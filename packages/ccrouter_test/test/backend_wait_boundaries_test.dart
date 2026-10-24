import 'dart:async';

import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

import 'reentrant_lifecycle_regression_test.dart' as fixture;
import 'review_repros/init_task_reentrancy/error_zone_repro.dart' as zones;
import 'review_repros/pop_wait_lifecycle/repro.dart' as waits;
import 'review_repros/runtime_round_trip/construction_retention.dart' as routes;
import 'review_repros/shared_waiter_lifetime/repro.dart' show alive, observe;

CCRouterRuntime runtimeFor(CCNavigationAdapter adapter) {
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
  runtime.initialize();
  return runtime;
}

Future<Object?> invoke(CCRouterRuntime runtime, String mode) => mode == 'close'
    ? runtime.closeRoute(runtime.activeRouteEntries.single.handle!)
    : mode == 'boolean'
    ? runtime.maybePopRoute<void>()
    : runtime.maybePopOutcomeRoute<void>(
        trigger: CCPopTrigger.gesture,
        placementOverride: mode == 'scoped'
            ? const CCRoutePlacement(hostId: 'right')
            : null,
      );

final callerKey = Object();

class ReadyResource {}

class Guard implements CCPopGuard {
  Guard(this.onEvaluate);
  final void Function() onEvaluate;
  @override
  CCPopGuardDecision evaluate(CCPopGuardContext context) {
    onEvaluate();
    return const CCPopAllow();
  }
}

Future<(WeakReference<Object>, WeakReference<Object>)> replaceWhileClosing(
  CCRouterRuntime runtime,
) async {
  final original = routes.Payload();
  final caller = Object();
  await runtime.goRoute(routes.Intent(original));
  final closing = runZoned(
    () => runtime.closeRoute(runtime.activeRouteEntries.single.handle!),
    zoneValues: {callerKey: caller},
  );
  await runtime.goRoute(routes.Intent(routes.Payload()));
  expect((await closing).status, CCRouteCloseStatus.notFound);
  return (WeakReference(original), WeakReference(caller));
}

Future<WeakReference<Object>> firstReadiness(
  CCRouterRuntime runtime, {
  CCCancellationToken? cancellation,
}) async {
  final payload = Object();
  final work = runZoned(
    () => observe(
      runtime.serviceAsync<ReadyResource>(cancellation: cancellation),
    ),
    zoneValues: {callerKey: payload},
  );
  if (cancellation != null) cancellation.cancel();
  await work;
  return WeakReference(payload);
}

WeakReference<Object> firstFactory(CCRouterRuntime runtime) {
  final payload = Object();
  runZoned(runtime.service<ReadyResource>, zoneValues: {callerKey: payload});
  return WeakReference(payload);
}

Future<WeakReference<Object>> firstCall(
  CCRouterRuntime runtime,
  String mode,
) async {
  final payload = Object();
  await runZoned(() {
    if (mode == 'session') {
      runtime.openSession(accountId: 'live');
      return Future<void>.value();
    }
    return mode == 'navigate'
        ? runtime.goRoute(const fixture.Intent())
        : runtime.maybePopOutcomeRoute<void>();
  }, zoneValues: {callerKey: payload});
  return WeakReference(payload);
}

class ReentrantAdapter extends waits.Coordinator {
  ReentrantAdapter(super.hostId, super.gate);
  void Function()? onPop;
  void Function()? onClose;
  void Function()? onSyncPop;

  @override
  Future<CCPopOutcome> maybePopOutcome({Object? result}) {
    onPop?.call();
    return super.maybePopOutcome(result: result);
  }

  @override
  CCPopOutcome popOutcome({Object? result}) {
    onSyncPop?.call();
    return CCPopOutcome(
      handled: true,
      hostId: hostId,
      removedEntryOwner: CCPopRemovedEntryOwner.managed,
      removedBackendEntryId: 'old-unregistered-entry',
    );
  }

  @override
  Future<CCRouteCloseOutcome> closeNavigation({
    required String navigationId,
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) {
    onClose?.call();
    return super.closeNavigation(
      navigationId: navigationId,
      hostId: hostId,
      navigatorOutlet: navigatorOutlet,
      result: result,
    );
  }
}

void main() {
  for (final asynchronous in [false, true]) {
    test(
      'PopGuard Host replacement cannot receive the old Back async=$asynchronous',
      () async {
        final gate = waits.Gate();
        gate.finish(false);
        final original = ReentrantAdapter('right', gate);
        final replacement = ReentrantAdapter('right', gate);
        var replacementPops = 0;
        replacement.onPop = () => replacementPops++;
        replacement.onSyncPop = () => replacementPops++;
        final aggregate = CCMultiHostNavigationAdapter(
          defaultHostId: 'right',
          adapters: {'left': fixture.ProbeAdapter('left'), 'right': original},
        );
        var replaced = false;
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: aggregate,
          globalPopGuards: [
            CCGlobalPopGuard(
              id: 'replace.host',
              guard: Guard(() {
                if (replaced) return;
                replaced = true;
                aggregate.unregisterHost(
                  'right',
                  replacementActiveHostId: 'left',
                );
                aggregate.registerHost('right', replacement);
                aggregate.activateHost('right');
              }),
            ),
          ],
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
        await runtime.goRoute(const fixture.Intent());
        if (asynchronous) {
          final outcome = await runtime.maybePopOutcomeRoute<void>();
          expect(outcome.handled, isTrue);
          expect(outcome.removedEntryOwner, CCPopRemovedEntryOwner.none);
        } else {
          runtime.popRoute();
        }
        expect(replaced, isTrue);
        expect(replacementPops, 0);
        expect(runtime.desynchronizedBackendHosts, isEmpty);
        await runtime.maybePopOutcomeRoute<void>();
        expect(
          replacementPops,
          1,
          reason: 'A fresh Back may reach the replacement',
        );
      },
    );
  }

  test(
    'replacing an Entry releases a pending close while Runtime remains live',
    () async {
      final gate = waits.Gate();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: waits.Coordinator('right', gate),
        components: [
          CCComponentManifest(
            id: 'probe',
            version: '1.0.0',
            registrar: routes.Registrar('none', (_) {}),
          ),
        ],
      );
      addTearDown(runtime.dispose);
      runtime.initialize();
      final weak = await replaceWhileClosing(runtime);
      await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
      expect(alive(weak.$1), isFalse);
      expect(alive(weak.$2), isFalse);
      expect(runtime.activeRouteEntries, hasLength(1));
      gate.finish(true);
      await Future<void>.delayed(Duration.zero);
      expect(runtime.activeRouteEntries, hasLength(1));
    },
  );

  for (final phase in ['factory', 'initializer']) {
    test('Host-context $phase preserves PopGuard reentrancy fence', () async {
      final outcome = Completer<Object?>();
      final factoryNavigation = Completer<Object?>();
      final gate = waits.Gate();
      gate.finish(false);
      late CCRouterRuntime runtime;
      var evaluated = false;
      runtime = CCRouterRuntime.forTesting(
        navigationAdapter: waits.Coordinator('right', gate),
        globalPopGuards: [
          CCGlobalPopGuard(
            id: 'probe.guard',
            guard: Guard(() {
              if (evaluated) return;
              evaluated = true;
              unawaited(
                observe(
                  runtime.serviceAsync<ReadyResource>(),
                ).then(outcome.complete),
              );
            }),
          ),
        ],
        components: [
          CCComponentManifest(
            id: 'probe',
            version: '1.0.0',
            registrar: fixture.Registrar(),
          ),
        ],
      );
      addTearDown(runtime.dispose);
      Future<void> navigate() => runtime.goRoute(const fixture.Intent());
      runtime.registerService(
        CCServiceProvider<ReadyResource>(
          factory: (_) {
            if (phase == 'factory') {
              unawaited(observe(navigate()).then(factoryNavigation.complete));
            }
            return ReadyResource();
          },
          initializer: phase == 'initializer' ? (_, _) => navigate() : null,
        ),
      );
      runtime.initialize();
      await runtime.goRoute(const fixture.Intent());
      await runtime.maybePopOutcomeRoute<void>();
      expect(
        await outcome.future.timeout(const Duration(seconds: 2)),
        phase == 'initializer'
            ? isA<CCNavigationReentrancyError>()
            : isA<ReadyResource>(),
      );
      expect(evaluated, isTrue);
      if (phase == 'factory') {
        expect(
          await factoryNavigation.future.timeout(const Duration(seconds: 2)),
          isA<CCNavigationReentrancyError>(),
        );
      }
      expect(runtime.activeRouteEntries, hasLength(1));
    });
  }

  test(
    'Scope-owned factory callbacks do not inherit the first caller Zone',
    () async {
      final gate = Completer<void>();
      final runtime = CCRouterRuntime.forTesting();
      addTearDown(runtime.dispose);
      runtime.registerService(
        CCServiceProvider<ReadyResource>(
          factory: (_) {
            unawaited(gate.future.then((_) {}));
            return ReadyResource();
          },
        ),
      );
      runtime.initialize();
      final weak = firstFactory(runtime);
      await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
      final retained = alive(weak);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(retained, isFalse);
    },
  );

  for (final terminal in ['success', 'failure', 'cancel']) {
    test(
      'shared producer does not adopt its first readiness caller $terminal',
      () async {
        final gate = Completer<void>();
        final runtime = CCRouterRuntime.forTesting();
        addTearDown(runtime.dispose);
        var runs = 0;
        runtime.registerService(
          CCServiceProvider<ReadyResource>(
            factory: (_) => ReadyResource(),
            initializer: (_, _) {
              runs++;
              if (terminal == 'failure')
                throw const CCResolutionError('shared-failure');
              return terminal == 'cancel' ? gate.future : Future<void>.value();
            },
          ),
        );
        runtime.initialize();
        final weak = await firstReadiness(
          runtime,
          cancellation: terminal == 'cancel' ? CCCancellationToken() : null,
        );
        await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
        final retained = alive(weak);
        if (terminal == 'cancel') gate.complete();
        final result = await observe(runtime.serviceAsync<ReadyResource>());
        expect(
          result,
          terminal == 'failure'
              ? isA<CCResolutionError>()
              : isA<ReadyResource>(),
        );
        expect(runs, 1);
        expect(retained, isFalse);
      },
    );
  }

  for (final mode in ['navigate', 'pop', 'session']) {
    test('live Host does not retain its first $mode caller Zone', () async {
      final gate = waits.Gate();
      gate.finish(false);
      final runtime = runtimeFor(waits.Coordinator('right', gate));
      addTearDown(runtime.dispose);
      final weak = await firstCall(runtime, mode);
      await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
      expect(alive(weak), isFalse);
      // Host remains operational after the first caller has disappeared.
      await runtime.goRoute(const fixture.Intent());
      expect(runtime.activeRouteEntries, hasLength(1));
    });
  }

  for (final mode in ['legacy', 'coordinator', 'scoped', 'boolean', 'close']) {
    for (final terminal in ['live', 'dispose', 'detach']) {
      for (final error in [false, true]) {
        test(
          '$mode independent error Zone $terminal lateError=$error',
          () async {
            final gate = waits.Gate();
            final child = switch (mode) {
              'legacy' => waits.LegacyAdapter('right', gate),
              'scoped' => waits.ScopedCoordinator('right', gate),
              _ => waits.Coordinator('right', gate),
            };
            final aggregate = CCMultiHostNavigationAdapter(
              defaultHostId: 'right',
              adapters: {'left': fixture.ProbeAdapter('left'), 'right': child},
            );
            final runtime = runtimeFor(aggregate);
            addTearDown(runtime.dispose);
            if (mode == 'close') await runtime.goRoute(const fixture.Intent());
            final uncaught = <Object>[];
            final caller = zones.guardedZone(uncaught);
            var settled = false;
            final pending = caller.run(() => observe(invoke(runtime, mode)));
            unawaited(pending.then((_) => settled = true));
            await Future<void>.delayed(Duration.zero);
            expect(settled, isFalse);
            if (terminal == 'dispose') await runtime.dispose();
            if (terminal == 'detach') {
              aggregate.unregisterHost(
                'right',
                replacementActiveHostId: 'left',
              );
              aggregate.registerHost('right', fixture.ProbeAdapter('right'));
              aggregate.activateHost('right');
              await runtime.goRoute(const fixture.Intent());
            }
            if (terminal == 'live') gate.finish(error);
            final outcome = await pending.timeout(const Duration(seconds: 2));
            if (terminal == 'live' && error) {
              expect(outcome, isA<CCNavigationAdapterError>());
            } else if (mode == 'close') {
              expect(
                (outcome as CCRouteCloseOutcome).status,
                CCRouteCloseStatus.notFound,
              );
            } else if (mode == 'boolean') {
              expect(outcome, terminal != 'live');
            } else {
              final pop = outcome as CCPopOutcome;
              expect(pop.handled, terminal != 'live');
              expect(pop.removedEntryOwner, CCPopRemovedEntryOwner.none);
              expect(pop.trigger, CCPopTrigger.gesture);
              expect(pop.hostId, 'right');
            }
            if (terminal != 'live') gate.finish(error);
            await Future<void>.delayed(Duration.zero);
            expect(uncaught, isEmpty);
            expect(runtime.desynchronizedBackendHosts, isEmpty);
            if (terminal == 'detach') {
              expect(runtime.activeRouteEntries.single.hostId, 'right');
            }
            expect(gate.calls, 1);
          },
        );
      }
    }
  }

  for (final mode in ['pop', 'close']) {
    for (final terminal in ['dispose', 'detach']) {
      for (final error in [false, true]) {
        test('synchronous $mode $terminal reentry lateError=$error', () async {
          final gate = waits.Gate();
          final child = ReentrantAdapter('right', gate);
          final aggregate = CCMultiHostNavigationAdapter(
            defaultHostId: 'right',
            adapters: {'left': fixture.ProbeAdapter('left'), 'right': child},
          );
          final runtime = runtimeFor(aggregate);
          addTearDown(runtime.dispose);
          await runtime.goRoute(const fixture.Intent());
          Future<void>? shutdown;
          void retire() {
            if (terminal == 'dispose') {
              shutdown = runtime.dispose();
            } else {
              aggregate.unregisterHost(
                'right',
                replacementActiveHostId: 'left',
              );
              aggregate.registerHost('right', fixture.ProbeAdapter('right'));
              aggregate.activateHost('right');
            }
          }

          if (mode == 'pop') child.onPop = retire;
          if (mode == 'close') child.onClose = retire;
          final outcome = await invoke(
            runtime,
            mode,
          ).timeout(const Duration(seconds: 2));
          if (mode == 'pop') {
            expect((outcome as CCPopOutcome).handled, isTrue);
          } else {
            expect(
              (outcome as CCRouteCloseOutcome).status,
              CCRouteCloseStatus.notFound,
            );
          }
          if (shutdown != null) await shutdown;
          if (terminal == 'detach')
            await runtime.goRoute(const fixture.Intent());
          gate.finish(error);
          await Future<void>.delayed(Duration.zero);
          expect(runtime.desynchronizedBackendHosts, isEmpty);
          expect(child.disposeCalls, 1);
          expect(gate.calls, 1);
        });
      }
    }
  }

  test(
    'initial-stack synchronous business Pop fences reentrant Host reuse',
    () async {
      final gate = waits.Gate();
      final child = ReentrantAdapter('right', gate);
      final aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'right',
        adapters: {'left': fixture.ProbeAdapter('left'), 'right': child},
      );
      final runtime = runtimeFor(aggregate);
      addTearDown(runtime.dispose);
      child.onSyncPop = () {
        aggregate.unregisterHost('right', replacementActiveHostId: 'left');
        aggregate.registerHost('right', fixture.ProbeAdapter('right'));
        aggregate.activateHost('right');
      };
      runtime.popRoute();
      await runtime.goRoute(const fixture.Intent());
      expect(runtime.desynchronizedBackendHosts, isEmpty);
      expect(runtime.activeRouteEntries, hasLength(1));
    },
  );

  test(
    'original CCRouterError and stack reach the independent caller Zone',
    () async {
      final gate = waits.Gate();
      final runtime = runtimeFor(waits.Coordinator('right', gate));
      addTearDown(runtime.dispose);
      final uncaught = <Object>[];
      const failure = CCResolutionError('original-backend-error');
      final stack = StackTrace.fromString('backend-original-stack-marker');
      final result = zones
          .guardedZone(uncaught)
          .run(
            () => runtime.maybePopOutcomeRoute<void>().then<Object?>(
              (value) => value,
              onError: (Object error, StackTrace trace) =>
                  (error, trace.toString()),
            ),
          );
      gate.completion.completeError(failure, stack);
      final outcome =
          await result.timeout(const Duration(seconds: 2)) as (Object, String);
      expect(outcome.$1, same(failure));
      expect(outcome.$2, contains('backend-original-stack-marker'));
      expect(uncaught, isEmpty);
    },
  );
}
