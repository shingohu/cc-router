import 'dart:async';

import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

import 'review_repros/init_task_reentrancy/error_zone_repro.dart' as zones;
import 'review_repros/shared_waiter_lifetime/host_identity.dart' as identity;
import 'review_repros/shared_waiter_lifetime/navigation_retention.dart'
    as retention;
import 'review_repros/shared_waiter_lifetime/repro.dart' as waiter;
import 'review_repros/runtime_round_trip/construction_retention.dart' as routes;
import 'reentrant_lifecycle_regression_test.dart' as fixture;

class _Caller implements CCDisposable {
  int disposals = 0;
  @override
  void dispose() => disposals++;
}

const _callerToken = CCServiceToken<_Caller>('probe.scoped-caller');

class _ScopedRegistrar implements CCComponentRegistrar {
  _ScopedRegistrar(this.scope, this.callers);
  final CCServiceScope scope;
  final List<_Caller> callers;
  @override
  void register(CCRegistry registry) {
    routes.Registrar('none', (_) {}).register(registry);
    registry.registerService(
      CCServiceProvider<_Caller>(
        contractToken: _callerToken,
        scope: scope,
        factory: (_) {
          final caller = _Caller();
          callers.add(caller);
          return caller;
        },
      ),
    );
  }
}

class _ReceiptAdapter extends identity.Adapter {
  _ReceiptAdapter({required this.wrongHost}) : super('left');
  final bool wrongHost;
  @override
  CCPopOutcome popOutcome({Object? result}) => CCPopOutcome(
    handled: true,
    removedEntryOwner: CCPopRemovedEntryOwner.managed,
    removedBackendEntryId: backendId,
    hostId: wrongHost ? 'right' : 'left',
    navigatorOutlet: wrongHost ? 'root' : 'sibling',
  );
}

class _PredictiveAdapter extends identity.Adapter
    implements CCNavigationAdapterCapabilitySource {
  _PredictiveAdapter(super.hostId);
  @override
  CCNavigationAdapterCapabilities get capabilities =>
      const CCNavigationAdapterCapabilities(
        supportsPredictiveBack: true,
        supportsManagedPopObservation: true,
      );
}

class _IdentityAdapter extends identity.Adapter
    implements
        CCNavigationBackendSnapshotSource,
        CCNavigationPopTargetSource,
        CCNavigationScopedPopTargetSource,
        CCNavigationScopedPopCoordinator,
        CCNavigationScopedPopGuardBinding {
  _IdentityAdapter(super.hostId);
  CCScopedPopGuardEvaluator? guard;
  Completer<CCPopOutcome>? pendingPop;
  void Function()? onTarget;

  @override
  CCNavigationPopTarget get activePopTarget {
    onTarget?.call();
    return CCNavigationPopTarget(
      hostId: hostId,
      navigatorOutlet: 'detail',
      backendEntryId: backendId,
      owner: CCBackendEntryOwner.managed,
      handlesPopInternally: true,
    );
  }

  @override
  CCNavigationPopTarget? popTargetAt({
    required String hostId,
    required String navigatorOutlet,
  }) => activePopTarget;

  CCPopOutcome get receipt => CCPopOutcome(
    handled: true,
    removedBackendEntryId: backendId,
    removedEntryOwner: CCPopRemovedEntryOwner.managed,
    trigger: CCPopTrigger.gesture,
    hostId: hostId,
    navigatorOutlet: 'detail',
  );

  @override
  CCPopOutcome popOutcome({Object? result}) => receipt;
  @override
  Future<CCPopOutcome> maybePopOutcome({Object? result}) =>
      pendingPop?.future ?? Future.value(receipt);
  @override
  CCPopOutcome popOutcomeAt({
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) => receipt;
  @override
  Future<CCPopOutcome> maybePopOutcomeAt({
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) => maybePopOutcome(result: result);
  @override
  bool canPopAt({required String hostId, required String navigatorOutlet}) =>
      true;
  @override
  void bindScopedPopGuardEvaluator(CCScopedPopGuardEvaluator? evaluator) =>
      guard = evaluator;
  @override
  List<CCInitialBackendEntrySnapshot> readInitialBackendEntries() => [
    CCInitialBackendEntrySnapshot(
      backendEntryId: backendId,
      owner: CCBackendEntryOwner.foreign,
      navigatorOutlet: 'detail',
    ),
  ];
}

class _Gate {
  final started = Completer<void>();
  late Completer<void> release;
  int starts = 0;
  Future<void> run(Object _, CCInvocationContext context) {
    starts++;
    // Create the producer Future in its own error Zone.
    release = Completer<void>();
    started.complete();
    return release.future;
  }
}

class _RuntimeIdentityAdapter extends _IdentityAdapter
    implements CCNavigationAdapterCapabilitySource {
  _RuntimeIdentityAdapter(super.hostId);
  @override
  CCNavigationAdapterCapabilities get capabilities =>
      const CCNavigationAdapterCapabilities(
        supportsManagedPopObservation: true,
      );
  @override
  CCNavigationPopTarget get activePopTarget => CCNavigationPopTarget(
    hostId: hostId,
    navigatorOutlet: 'root',
    backendEntryId: backendId,
    owner: CCBackendEntryOwner.managed,
  );
  @override
  CCPopOutcome get receipt => CCPopOutcome(
    handled: true,
    hostId: hostId,
    navigatorOutlet: 'root',
    removedBackendEntryId: backendId,
    removedEntryOwner: CCPopRemovedEntryOwner.managed,
  );
  @override
  List<CCInitialBackendEntrySnapshot> readInitialBackendEntries() => const [];
}

Future<(Object, String)> _observeInZone(
  CCRouterRuntime runtime,
  Zone zone, {
  CCCancellationToken? cancellation,
  Duration? timeout,
}) {
  final done = Completer<(Object, String)>();
  zone.run(() {
    unawaited(
      runtime
          .serviceAsync<waiter.SharedResource>(
            cancellation: cancellation,
            timeout: timeout,
          )
          .then<void>(
            (value) => done.complete((value, '')),
            onError: (Object error, StackTrace stack) =>
                done.complete((error, stack.toString())),
          ),
    );
  });
  return done.future;
}

Future<WeakReference<waiter.CallerPayload>> _endZoneWaiter(
  CCRouterRuntime runtime,
  String terminal,
  bool separateErrorZone,
  List<Object> uncaught,
) async {
  final payload = waiter.CallerPayload();
  final weak = WeakReference(payload);
  final token = CCCancellationToken();
  final zone = (separateErrorZone ? zones.guardedZone(uncaught) : Zone.current)
      .fork(zoneValues: {waiter.callerPayloadKey: payload});
  final work = _observeInZone(
    runtime,
    zone,
    cancellation: token,
    timeout: terminal == 'timeout' ? const Duration(milliseconds: 50) : null,
  );
  if (terminal == 'cancel') token.cancel();
  expect(
    (await work).$1,
    terminal == 'cancel'
        ? isA<CCInvocationCancelledError>()
        : isA<CCInvocationTimeoutError>(),
  );
  return weak;
}

Future<
  ({
    WeakReference<waiter.CallerPayload> caller,
    WeakReference<routes.Payload>? route,
  })
>
_endScopedCaller(CCRouterRuntime runtime, CCServiceScope scope) async {
  final payload = waiter.CallerPayload();
  WeakReference<routes.Payload>? route;
  String? navigationId;
  if (scope == CCServiceScope.session)
    runtime.openSession(accountId: 'old');
  else {
    final arguments = routes.Payload();
    route = WeakReference(arguments);
    await runtime.goRoute(routes.Intent(arguments));
    navigationId = runtime.activeRouteEntries.single.navigationId;
  }
  final entered = Completer<void>();
  final work = Zone.current
      .fork(zoneValues: {waiter.callerPayloadKey: payload})
      .run(
        () => waiter.observe(
          runtime.invokeService<_Caller, Object>(
            contractToken: _callerToken,
            methodId: 'join',
            navigationId: navigationId,
            call: (_, _) {
              final waiting = runtime.serviceAsync<waiter.SharedResource>();
              entered.complete();
              return waiting;
            },
          ),
        ),
      );
  await entered.future;
  if (scope == CCServiceScope.session) {
    await runtime.closeSession();
    runtime.openSession(accountId: 'new');
  } else {
    expect(
      (await runtime.closeRoute(
        runtime.routeEntryHandleForNavigation(
          runtime.activeRouteEntries.single.navigationId,
        )!,
      )).status,
      CCRouteCloseStatus.closed,
    );
  }
  expect(await work, isA<CCInvocationCancelledError>());
  return (caller: WeakReference(payload), route: route);
}

void main() {
  // Preserve review evidence and discover all original probes by default.
  group('independent waiter GC', waiter.main);
  group('child identity and observer isolation', identity.main);
  group('navigation callback GC controls', retention.main);

  for (final scope in [CCServiceScope.session, CCServiceScope.route]) {
    for (final fails in [false, true]) {
      test(
        'ended $scope caller releases while shared App initializer lives, fails=$fails',
        () async {
          final gate = _Gate();
          final callers = <_Caller>[];
          final runtime = CCRouterRuntime.forTesting(
            navigationAdapter: CCMemoryNavigationAdapter(),
            components: [
              CCComponentManifest(
                id: 'probe',
                version: '1.0.0',
                registrar: _ScopedRegistrar(scope, callers),
              ),
            ],
          );
          addTearDown(runtime.dispose);
          final resource = waiter.SharedResource();
          runtime.registerService(
            CCServiceProvider<waiter.SharedResource>(
              factory: (_) => resource,
              initializer: gate.run,
            ),
          );
          runtime.initialize();
          final uncaught = <Object>[];
          final first = _observeInZone(runtime, zones.guardedZone(uncaught));
          await gate.started.future;
          final references = await _endScopedCaller(runtime, scope);
          await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
          final callerRetained = waiter.alive(references.caller);
          final routeRetained =
              references.route != null && waiter.alive(references.route!);
          const failure = CCResolutionError(
            'shared setup failed after caller closed',
          );
          if (fails)
            gate.release.completeError(failure);
          else
            gate.release.complete();
          expect((await first).$1, same(fails ? failure : resource));
          expect(callerRetained, isFalse);
          expect(routeRetained, isFalse);
          expect(callers.single.disposals, 1);
          if (scope == CCServiceScope.session) {
            expect(runtime.service<_Caller>(), isNot(same(callers.first)));
            expect(callers.last.disposals, 0);
          }
          expect(gate.starts, 1);
          expect(uncaught, isEmpty);
        },
      );
    }
  }

  for (final terminal in ['cancel', 'timeout']) {
    for (final separateErrorZone in [false, true]) {
      for (final fails in [false, true]) {
        test(
          '$terminal shared waiter: separate error Zone=$separateErrorZone failure=$fails',
          () async {
            final gate = _Gate();
            final runtime = CCRouterRuntime.forTesting();
            addTearDown(runtime.dispose);
            final resource = waiter.SharedResource();
            runtime.registerService(
              CCServiceProvider<waiter.SharedResource>(
                factory: (_) => resource,
                initializer: gate.run,
              ),
            );
            runtime.initialize();
            final uncaught = <Object>[];
            final first = _observeInZone(runtime, zones.guardedZone(uncaught));
            await gate.started.future;
            final live = _observeInZone(runtime, zones.guardedZone(uncaught));
            final weak = await _endZoneWaiter(
              runtime,
              terminal,
              separateErrorZone,
              uncaught,
            );
            await forceGC(
              fullGcCycles: 3,
              timeout: const Duration(seconds: 20),
            );
            final retained = waiter.alive(weak);
            const failure = CCResolutionError('original readiness failure');
            final stack = StackTrace.fromString('independent-waiter-origin');
            if (fails)
              gate.release.completeError(failure, stack);
            else
              gate.release.complete();
            final results = [
              await first,
              await live,
              await _observeInZone(runtime, zones.guardedZone(uncaught)),
            ];
            for (final result in results) {
              expect(result.$1, same(fails ? failure : resource));
              if (fails)
                expect(result.$2, contains('independent-waiter-origin'));
            }
            expect(retained, isFalse);
            expect(gate.starts, 1);
            expect(uncaught, isEmpty);
          },
        );
      }
    }
  }

  test(
    'every MultiHost identity-bearing SPI uses one registration domain',
    () async {
      final children = [_IdentityAdapter('left'), _IdentityAdapter('right')];
      final aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'left',
        adapters: {for (final child in children) child.hostId: child},
      );
      addTearDown(aggregate.dispose);
      aggregate.initialize(const []);
      final snapshots = aggregate.readInitialBackendEntries();
      final ids = {
        for (final snapshot in snapshots)
          snapshot.hostId!: snapshot.backendEntryId,
      };
      expect(ids.values.toSet(), hasLength(2));
      final events = <CCNavigationBackendEvent>[];
      final gestures = <CCPredictiveBackEvent>[];
      final targets = <CCNavigationPopTarget>[];
      aggregate.addBackendEventListener(events.add);
      aggregate.addPredictiveBackListener(gestures.add);
      aggregate.bindScopedPopGuardEvaluator((trigger, {required target}) {
        targets.add(target);
        return const CCPopAllow();
      });
      for (final child in children) {
        aggregate.activateHost(child.hostId);
        final id = ids[child.hostId];
        expect(id, isNot(child.backendId));
        expect(aggregate.activePopTarget.backendEntryId, id);
        expect(aggregate.activePopTarget.handlesPopInternally, isTrue);
        expect(
          aggregate
              .popTargetAt(hostId: child.hostId, navigatorOutlet: 'detail')!
              .backendEntryId,
          id,
        );
        child.guard!(CCPopTrigger.gesture, target: child.activePopTarget);
        expect(targets.last.backendEntryId, id);
        expect(targets.last.hostId, child.hostId);
        expect(targets.last.handlesPopInternally, isTrue);
        for (final kind in [
          CCNavigationBackendEventKind.push,
          CCNavigationBackendEventKind.replace,
        ]) {
          child.emit(
            CCNavigationBackendEvent(
              kind: kind,
              timestamp: DateTime.now(),
              backendEntryId: child.backendId,
              previousBackendEntryId: child.backendId,
              owner: CCBackendEntryOwner.foreign,
              navigatorOutlet: 'detail',
            ),
          );
          expect(events.last.backendEntryId, id);
          expect(events.last.previousBackendEntryId, id);
          expect(events.last.hostId, child.hostId);
        }
        final outcomes = [
          aggregate.popOutcome(),
          await aggregate.maybePopOutcome(),
          aggregate.popOutcomeAt(
            hostId: child.hostId,
            navigatorOutlet: 'detail',
          ),
          await aggregate.maybePopOutcomeAt(
            hostId: child.hostId,
            navigatorOutlet: 'detail',
          ),
        ];
        for (final outcome in outcomes) {
          expect(outcome.removedBackendEntryId, id);
          expect(outcome.hostId, child.hostId);
          expect(outcome.navigatorOutlet, 'detail');
          expect(outcome.trigger, CCPopTrigger.gesture);
          expect(outcome.removedEntryOwner, CCPopRemovedEntryOwner.managed);
        }
        final timestamp = DateTime.now();
        child.emitPredictive(
          CCPredictiveBackEvent(
            phase: CCPredictiveBackPhase.committed,
            timestamp: timestamp,
            progress: 0.8,
            outcome: child.receipt,
          ),
        );
        expect(gestures.last.outcome!.removedBackendEntryId, id);
        expect(gestures.last.outcome!.hostId, child.hostId);
        expect(gestures.last.progress, 0.8);
        expect(gestures.last.timestamp, timestamp);
      }
    },
  );

  for (final operation in ['target', 'pop', 'maybePop']) {
    test(
      'reentrant focus change keeps target registration, operation=$operation',
      () async {
        final left = _IdentityAdapter('left');
        final aggregate = CCMultiHostNavigationAdapter(
          defaultHostId: 'left',
          adapters: {'left': left, 'right': _IdentityAdapter('right')},
        );
        addTearDown(aggregate.dispose);
        aggregate.initialize(const []);
        final leftId = aggregate
            .readInitialBackendEntries()
            .first
            .backendEntryId;
        left.onTarget = () => aggregate.activateHost('right');
        if (operation == 'target') {
          final target = aggregate.activePopTarget;
          expect(target.hostId, 'left');
          expect(target.backendEntryId, leftId);
        } else {
          final outcome = operation == 'pop'
              ? aggregate.popOutcome()
              : await aggregate.maybePopOutcome();
          expect(outcome.hostId, 'left');
          expect(outcome.removedBackendEntryId, leftId);
        }
        expect(aggregate.activeHostId, 'right');
      },
    );
  }

  for (final scoped in [false, true]) {
    test(
      'pending Pop keeps old registration identity after same-Host replacement, scoped=$scoped',
      () async {
        final left = _IdentityAdapter('left');
        final old = _IdentityAdapter('right');
        final aggregate = CCMultiHostNavigationAdapter(
          defaultHostId: 'left',
          adapters: {'left': left, 'right': old},
        );
        addTearDown(aggregate.dispose);
        aggregate.initialize(const []);
        aggregate.activateHost('right');
        final oldId = aggregate.activePopTarget.backendEntryId;
        old.pendingPop = Completer<CCPopOutcome>();
        final pending = scoped
            ? aggregate.maybePopOutcomeAt(
                hostId: 'right',
                navigatorOutlet: 'detail',
              )
            : aggregate.maybePopOutcome();
        aggregate.unregisterHost('right', replacementActiveHostId: 'left');
        aggregate.registerHost('right', _IdentityAdapter('right'));
        aggregate.activateHost('right');
        final replacementId = aggregate.activePopTarget.backendEntryId;
        old.pendingPop!.complete(old.receipt);
        expect((await pending).removedBackendEntryId, oldId);
        expect(replacementId, isNot(oldId));
      },
    );
  }

  for (final wrongHost in [false, true]) {
    test(
      'Core rejects managed receipt in wrong partition, wrongHost=$wrongHost',
      () async {
        final adapter = _ReceiptAdapter(wrongHost: wrongHost);
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: adapter,
          components: [
            CCComponentManifest(
              id: 'probe',
              version: '1.0.0',
              registrar: fixture.Registrar(),
            ),
          ],
        );
        addTearDown(runtime.dispose);
        runtime.initialize();
        final result = runtime.pushRoute(const fixture.Intent());
        await Future<void>.delayed(Duration.zero);
        final entry = runtime.activeRouteEntries.single;
        runtime.popRoute();
        expect(
          runtime.activeRouteEntries.single.routeEntryId,
          entry.routeEntryId,
        );
        expect(
          runtime.desynchronizedBackendHosts,
          contains(wrongHost ? 'right' : 'left'),
        );
        expect(adapter.delegate.stack, hasLength(1));
        await runtime.dispose();
        await result;
      },
    );
  }

  for (final capacity in [0, 4]) {
    for (final scoped in [false, true]) {
      test(
        'old pending Runtime Pop cannot desynchronize replacement, history=$capacity scoped=$scoped',
        () async {
          final old = _RuntimeIdentityAdapter('right');
          final aggregate = CCMultiHostNavigationAdapter(
            defaultHostId: 'right',
            adapters: {'left': _RuntimeIdentityAdapter('left'), 'right': old},
          );
          final runtime = CCRouterRuntime.forTesting(
            navigationAdapter: aggregate,
            navigationDiagnosticCapacity: capacity,
            components: [
              CCComponentManifest(
                id: 'probe',
                version: '1.0.0',
                registrar: fixture.Registrar(),
              ),
            ],
          );
          addTearDown(runtime.dispose);
          runtime.initialize();
          final oldResult = waiter.observe(
            runtime
                .pushRoute(const fixture.Intent())
                .then<Object?>((_) => null),
          );
          await Future<void>.delayed(Duration.zero);
          old.pendingPop = Completer<CCPopOutcome>();
          final pending = runtime.maybePopOutcomeRoute<void>(
            placementOverride: scoped
                ? const CCRoutePlacement(hostId: 'right')
                : null,
          );
          aggregate.unregisterHost('right', replacementActiveHostId: 'left');
          aggregate.registerHost('right', _RuntimeIdentityAdapter('right'));
          aggregate.activateHost('right');
          final newResult = waiter.observe(
            runtime
                .pushRoute(const fixture.Intent())
                .then<Object?>((_) => null),
          );
          await Future<void>.delayed(Duration.zero);
          final replacement = runtime.activeRouteEntries.single;
          old.pendingPop!.complete(old.receipt);
          expect((await pending).handled, isTrue);
          expect(
            runtime.activeRouteEntries.single.routeEntryId,
            replacement.routeEntryId,
          );
          expect(runtime.desynchronizedBackendHosts, isEmpty);
          await runtime.dispose();
          await Future.wait([oldResult, newResult]);
        },
      );
    }
  }

  test(
    'throwing Host observer does not block Runtime predictive reconciliation',
    () async {
      final child = _PredictiveAdapter('left');
      final aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'left',
        adapters: {'left': child},
      );
      aggregate.addPredictiveBackListener(
        (_) => throw StateError('Host observer failure'),
      );
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: aggregate,
        components: [
          CCComponentManifest(
            id: 'probe',
            version: '1.0.0',
            registrar: fixture.Registrar(),
          ),
        ],
      );
      addTearDown(runtime.dispose);
      runtime.initialize();
      final result = runtime.pushRoute(const fixture.Intent());
      await Future<void>.delayed(Duration.zero);
      expect(runtime.activeRouteEntries, hasLength(1));
      child.delegate.pop();
      final event = CCPredictiveBackEvent(
        phase: CCPredictiveBackPhase.committed,
        timestamp: DateTime.now(),
        outcome: CCPopOutcome(
          handled: true,
          removedEntryOwner: CCPopRemovedEntryOwner.managed,
          removedBackendEntryId: child.backendId,
          hostId: child.hostId,
          navigatorOutlet: 'root',
        ),
      );
      child.emitPredictive(event);
      // Check synchronously before the original result Future can reconcile.
      expect(runtime.activeRouteEntries, isEmpty);
      child.emitPredictive(event);
      await result;
      expect(runtime.desynchronizedBackendHosts, isEmpty);
    },
  );
}
