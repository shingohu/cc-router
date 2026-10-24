import 'dart:async';

import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

import 'review_repros/init_task_reentrancy/error_zone_repro.dart' as zones;
import 'review_repros/pending_work_retention/message_retention.dart'
    as messages;
import 'review_repros/pending_work_retention/multi_host_constructor.dart'
    as hosts;
import 'review_repros/pending_work_retention/repro.dart' as readiness;
import 'review_repros/runtime_round_trip/construction_retention.dart' as routes;

class _EqualAdapter extends hosts.CountingAdapter {
  @override
  bool operator ==(Object other) => other is _EqualAdapter;
  @override
  int get hashCode => 0;
}

// Create the error Future in the business execution's error Zone. A raw error
// Future created in the test Zone cannot cross into a guarded Dart error Zone.
class _ZoneGate extends messages.Gate {
  late final Completer<void> _completion;

  @override
  Completer<void> get release => _completion;

  @override
  Future<void> run(CCInvocationContext _) {
    _completion = Completer<void>();
    started.complete();
    return _completion.future;
  }
}

class _ReadinessRegistrar implements CCComponentRegistrar {
  _ReadinessRegistrar(this.scope, this.policy, this.resource, this.gate);

  final CCServiceScope scope;
  final CCServiceCreationPolicy policy;
  final readiness.Resource resource;
  final _ZoneGate gate;

  @override
  void register(CCRegistry registry) {
    routes.Registrar('none', (_) {}).register(registry);
    registry.registerService(
      CCServiceProvider<readiness.Resource>(
        scope: scope,
        creationPolicy: policy,
        factory: (_) => resource,
        initializer: (_, context) => gate.run(context),
      ),
    );
  }
}

Future<Object?> _observe(Future<Object?> work) => work.then<Object?>(
  (value) => value,
  onError: (Object error, StackTrace _) => error,
);

// Return only weak references from the setup frame before forcing GC.
Future<({WeakReference<Object> scope, WeakReference<routes.Payload>? payload})>
_endScope(
  CCRouterRuntime runtime,
  CCServiceScope scope,
  Completer<void> started,
) async {
  WeakReference<routes.Payload>? payload;
  late Future<Object?> outcome;
  late WeakReference<Object> reference;
  if (scope == CCServiceScope.session) {
    runtime.openSession(accountId: 'old');
    reference = WeakReference(runtime.sessionScope!);
    outcome = _observe(runtime.serviceAsync<readiness.Resource>());
    await started.future;
    await runtime.closeSession();
    runtime.openSession(accountId: 'new');
  } else {
    final arguments = routes.Payload();
    payload = WeakReference(arguments);
    await runtime.goRoute(routes.Intent(arguments));
    final entry = runtime.activeRouteEntries.single;
    // A weak payload is enough to detect a retained exact RouteEntry/Scope.
    reference = WeakReference(arguments);
    outcome = _observe(
      runtime.serviceForRouteAsync<readiness.Resource>(
        navigationId: entry.navigationId,
      ),
    );
    await started.future;
    expect(
      (await runtime.closeRoute(
        runtime.routeEntryHandleForNavigation(entry.navigationId)!,
      )).status,
      CCRouteCloseStatus.closed,
    );
  }
  expect(await outcome, isA<CCInvocationCancelledError>());
  return (scope: reference, payload: payload);
}

void main() {
  // These were previously opt-in review probes; keep them in the default suite.
  group('pending initializer GC', readiness.main);
  group('pending message GC', messages.main);
  group('Host constructor ownership', hosts.main);

  for (final scope in [CCServiceScope.session, CCServiceScope.route]) {
    for (final policy in CCServiceCreationPolicy.values) {
      test('ended $scope releases while Runtime lives, $policy', () async {
        final started = Completer<void>();
        final release = Completer<void>();
        final resource = readiness.Resource();
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: CCMemoryNavigationAdapter(),
          components: [
            CCComponentManifest(
              id: 'probe',
              version: '1.0.0',
              registrar: readiness.Registrar(
                scope,
                resource,
                started,
                release,
                policy,
              ),
            ),
          ],
        );
        addTearDown(runtime.dispose);
        runtime.initialize();
        final ended = await _endScope(runtime, scope, started);
        expect(resource.disposals, 1);
        await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
        final scopeRetained = readiness.targetIsAlive(ended.scope);
        final payloadRetained = readiness.targetIsAlive(ended.payload);
        release.completeError(StateError('late initializer failure'));
        await Future<void>.delayed(Duration.zero);
        expect(scopeRetained, isFalse);
        expect(payloadRetained, isFalse);
        expect(resource.disposals, 1);
        expect(runtime.isInitialized, isTrue);
      });
    }
  }

  for (final scope in CCServiceScope.values) {
    for (final policy in CCServiceCreationPolicy.values) {
      for (final lateError in [false, true]) {
        test('readiness owner end across error Zones: '
            '$scope $policy lateError=$lateError', () async {
          final gate = _ZoneGate();
          final resource = readiness.Resource();
          final runtime = CCRouterRuntime.forTesting(
            navigationAdapter: CCMemoryNavigationAdapter(),
            components: [
              CCComponentManifest(
                id: 'probe',
                version: '1.0.0',
                registrar: _ReadinessRegistrar(scope, policy, resource, gate),
              ),
            ],
          );
          addTearDown(runtime.dispose);
          runtime.initialize();
          if (scope == CCServiceScope.session) {
            runtime.openSession(accountId: 'old');
          }
          if (scope == CCServiceScope.route) {
            await runtime.goRoute(routes.Intent(routes.Payload()));
          }
          final uncaught = <Object>[];
          final outcomes = <Future<Object?>>[];
          for (var index = 0; index < 2; index++) {
            final done = Completer<Object?>();
            outcomes.add(done.future);
            zones.guardedZone(uncaught).run(() {
              final work = scope == CCServiceScope.route
                  ? runtime.serviceForRouteAsync<readiness.Resource>(
                      navigationId:
                          runtime.activeRouteEntries.single.navigationId,
                    )
                  : runtime.serviceAsync<readiness.Resource>();
              unawaited(_observe(work).then(done.complete));
            });
            // The fixture returns the same gate for new instances, but each
            // initializer must publish its own start signal only once.
            if (policy == CCServiceCreationPolicy.newInstance) break;
          }
          await gate.started.future;
          switch (scope) {
            case CCServiceScope.app:
              await runtime.dispose();
            case CCServiceScope.session:
              await runtime.closeSession();
            case CCServiceScope.route:
              await runtime.closeRoute(
                runtime.routeEntryHandleForNavigation(
                  runtime.activeRouteEntries.single.navigationId,
                )!,
              );
          }
          for (final outcome in outcomes) {
            expect(
              await outcome.timeout(const Duration(seconds: 2)),
              isA<CCInvocationCancelledError>(),
            );
          }
          final traceCount = runtime.recentTraces.length;
          if (lateError) {
            gate.release.completeError(StateError('late business error'));
          } else {
            gate.release.complete();
          }
          await Future<void>.delayed(Duration.zero);
          expect(resource.disposals, 1);
          expect(uncaught, isEmpty);
          expect(runtime.recentTraces.length, traceCount);
        });
      }
    }
  }

  for (final mode in ['event', 'typedEvent', 'generatedEvent']) {
    for (final terminal in ['cancel', 'timeout', 'shutdown']) {
      for (final lateError in [false, true]) {
        test('$mode $terminal consumes lateError=$lateError once', () async {
          final gate = _ZoneGate();
          final runtime = CCRouterRuntime.forTesting(
            components: mode == 'generatedEvent'
                ? [
                    CCComponentManifest(
                      id: 'probe',
                      version: '1.0.0',
                      registrar: messages.EventRegistrar(gate),
                    ),
                  ]
                : const [],
          );
          addTearDown(runtime.dispose);
          if (mode == 'event') {
            runtime.registerEvent<messages.Event>(
              'probe.event',
              (_, context) => gate.run(context),
            );
          } else if (mode == 'typedEvent') {
            runtime.registerEventSubscriber<messages.Event>(
              CCEventSubscriber<messages.Event>(
                id: const CCEventSubscriberId('probe.subscriber'),
                handler: (_, context) => gate.run(context),
              ),
            );
          }
          runtime.initialize();
          final cancellation = CCCancellationToken();
          final timeout = terminal == 'timeout'
              ? const Duration(milliseconds: 100)
              : null;
          final uncaught = <Object>[];
          final done = Completer<Object?>();
          zones.guardedZone(uncaught).run(() {
            final work = mode == 'generatedEvent'
                ? runtime.invokeGeneratedEvent(
                    messages.Event(),
                    eventId: 'probe.changed',
                    publisherComponentId: 'probe',
                    cancellation: cancellation,
                    timeout: timeout,
                  )
                : runtime.event(
                    messages.Event(),
                    cancellation: cancellation,
                    timeout: timeout,
                  );
            unawaited(_observe(work).then(done.complete));
          });
          await gate.started.future;
          if (terminal == 'cancel') cancellation.cancel();
          if (terminal == 'shutdown') await runtime.dispose();
          expect(
            await done.future.timeout(const Duration(seconds: 2)),
            terminal == 'timeout'
                ? isA<CCInvocationTimeoutError>()
                : isA<CCInvocationCancelledError>(),
          );
          await Future<void>.delayed(Duration.zero);
          final traceCount = runtime.recentTraces.length;
          if (lateError) {
            gate.release.completeError(StateError('late subscriber failure'));
          } else {
            gate.release.complete();
          }
          await Future<void>.delayed(Duration.zero);
          expect(runtime.subscriberErrors, isEmpty);
          expect(runtime.recentTraces.length, traceCount);
          expect(uncaught, isEmpty);
          if (terminal != 'shutdown') {
            final traces = runtime.recentTraces;
            expect(
              traces.where((trace) => trace.operation == 'event'),
              hasLength(1),
            );
            expect(
              traces.where((trace) => trace.operation == 'eventSubscriber'),
              hasLength(1),
            );
          }
        });
      }
    }
  }

  test(
    'constructor uniqueness uses identity rather than overloaded equality',
    () {
      final left = _EqualAdapter();
      final right = _EqualAdapter();
      final aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'left',
        adapters: {'left': left, 'right': right},
      );
      aggregate.initialize(const []);
      expect(left.initializations, 1);
      expect(right.initializations, 1);
      aggregate.dispose();
      expect(left.disposals, 1);
      expect(right.disposals, 1);
    },
  );

  test(
    'invalid later Host input never takes ownership of earlier children',
    () {
      final left = hosts.CountingAdapter();
      final right = hosts.CountingAdapter();
      expect(
        () => CCMultiHostNavigationAdapter(
          defaultHostId: 'left',
          adapters: {'left': left, '': right},
        ),
        throwsArgumentError,
      );
      expect(left.initializations, 0);
      expect(right.initializations, 0);
      expect(left.disposals, 0);
      expect(right.disposals, 0);
      // The caller can still transfer both rejected children to a valid owner.
      final aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'left',
        adapters: {'left': left, 'right': right},
      );
      aggregate.initialize(const []);
      aggregate.dispose();
      expect(left.disposals, 1);
      expect(right.disposals, 1);
    },
  );
}
