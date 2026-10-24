import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'navigation_test.dart'
    show
        TestIntent,
        RouteArgsCodec,
        RouteArgs,
        MissingPathCodec,
        FailingNavigationAdapter;

final class _Sink implements CCDiagnosticSink {
  final events = <CCDiagnosticEvent>[];

  @override
  void record(CCDiagnosticEvent event) => events.add(event);
}

void main() {
  test(
    'cancel diagnostics preserve exact placement without error alarms',
    () async {
      final sink = _Sink();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        diagnostics: CCDiagnosticsConfig(
          sink: sink,
          defaultMinimumLevel: CCDiagnosticLevel.debug,
        ),
        globalInterceptors: [
          CCGlobalNavigationInterceptor(
            id: 'test.cancel',
            interceptor: _Cancel(),
          ),
        ],
      );
      addTearDown(runtime.dispose);
      runtime.registerRoute<RouteArgs, void>(
        CCRouteDefinition(
          routeId: 'test.detail',
          patterns: const [CCPathPattern('/detail/:value', primary: true)],
          codec: const RouteArgsCodec(),
          placement: const CCRoutePlacement(
            hostId: 'right',
            navigatorOutlet: 'detail',
          ),
        ),
      );
      runtime.initialize();
      await expectLater(
        runtime.pushRoute(
          const TestIntent<void>('test.detail', RouteArgs('secret')),
        ),
        throwsA(isA<CCRouteCancelledError>()),
      );
      await Future<void>.delayed(Duration.zero);
      final events = sink.events.where(
        (e) => e.category == CCDiagnosticCategory.navigation,
      );
      expect(events.where((e) => e.level == CCDiagnosticLevel.error), isEmpty);
      final lifecycleFailure = events.singleWhere((e) => e.status == 'failed');
      expect(lifecycleFailure.level, CCDiagnosticLevel.warning);
      final failure = events.singleWhere((e) => e.failureReason != null);
      expect(failure.status, 'cancelled');
      expect(failure.level, CCDiagnosticLevel.warning);
      expect(failure.hostId, 'right');
      expect(failure.outlet, 'detail');
      expect(failure.failureReason, 'cancelled');
      expect(failure.failureAttempt, 'request');
      expect(failure.recoveryDepth, 0);
      expect(failure.errorType, 'CCRouteCancelledError');
      expect(failure.target, isNot(contains('secret')));
      final context = runtime.recentNavigationFailures.single.context;
      expect(context.hostId, 'right');
      expect(context.outlet, 'detail');
      expect(context.routeId, 'test.detail');
    },
  );

  test(
    'typed parameter failure uses declared placement without running codec twice',
    () async {
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
      );
      addTearDown(runtime.dispose);
      _route(
        runtime,
        'test.bad',
        host: 'right',
        codec: const MissingPathCodec(),
      );
      runtime.initialize();
      await expectLater(
        runtime.pushRoute(
          const TestIntent<void>('test.bad', RouteArgs('secret')),
        ),
        throwsA(isA<CCRouteParameterError>()),
      );
      final failure = runtime.recentNavigationFailures.single.context;
      expect(failure.hostId, 'right');
      expect(failure.outlet, 'detail');
      expect(failure.stage, CCNavigationFailureStage.parameters);
    },
  );

  test(
    'unresolved URI redirect does not inherit the previous route or outlet',
    () async {
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        globalInterceptors: [
          CCGlobalNavigationInterceptor(
            id: 'test.redirect',
            interceptor: _Interceptor(
              (_) => CCNavigationRedirect.toUri(Uri.parse('/missing/secret')),
            ),
          ),
        ],
      );
      addTearDown(runtime.dispose);
      _route(runtime, 'test.start', host: 'right');
      runtime.initialize();
      await expectLater(
        runtime.pushRoute(
          const TestIntent<void>('test.start', RouteArgs('secret')),
        ),
        throwsA(isA<CCRouteNotFoundError>()),
      );
      final failure = runtime.recentNavigationFailures.single.context;
      expect(failure.routeId, isNull);
      expect(failure.initialRouteId, 'test.start');
      expect(failure.hostId, 'right');
      expect(failure.outlet, isNull);
      expect(failure.attempt, CCNavigationFailureAttempt.interceptorRedirect);
    },
  );

  test(
    'failure recovery attributes the new target and preserves original identity',
    () async {
      final sink = _Sink();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: FailingNavigationAdapter(),
        diagnostics: CCDiagnosticsConfig(
          sink: sink,
          defaultMinimumLevel: CCDiagnosticLevel.debug,
        ),
        navigationFailurePolicy: _Policy(
          (context) => context.recoveryDepth == 0
              ? const CCNavigationFailureRedirect.toIntent(
                  TestIntent<void>('test.recovery', RouteArgs('secret')),
                )
              : const CCNavigationFailurePropagate(),
        ),
      );
      addTearDown(runtime.dispose);
      _route(runtime, 'test.start', host: 'left');
      _route(runtime, 'test.recovery', host: 'right');
      runtime.initialize();
      await expectLater(
        runtime.pushRoute(
          const TestIntent<void>('test.start', RouteArgs('secret')),
        ),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      await Future<void>.delayed(Duration.zero);
      final failures = runtime.recentNavigationFailures;
      expect(failures, hasLength(2));
      expect(failures.first.context.hostId, 'left');
      expect(failures.first.recovered, isTrue);
      expect(failures.last.context.hostId, 'right');
      expect(failures.last.context.outlet, 'detail');
      expect(failures.last.context.initialRouteId, 'test.start');
      expect(failures.last.context.routeId, 'test.recovery');
      expect(
        failures.last.context.navigationId,
        failures.first.context.navigationId,
      );
      expect(
        failures.last.context.attempt,
        CCNavigationFailureAttempt.failureRecovery,
      );
      expect(failures.last.context.recoveryDepth, 1);
      final exported = sink.events
          .where((e) => e.failureReason != null)
          .toList();
      expect(exported.last.hostId, 'right');
      expect(exported.last.failureAttempt, 'failureRecovery');
      expect(exported.last.recoveryDepth, 1);
    },
  );

  test(
    'pending replay redirect reports its actual attempted Host and Outlet',
    () async {
      var resumed = false;
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        globalInterceptors: [
          CCGlobalNavigationInterceptor(
            id: 'test.defer',
            interceptor: _Interceptor((context) {
              if (!resumed) return const CCNavigationDefer();
              if (context.request.routeId == 'test.start')
                return const CCNavigationRedirect.toIntent(
                  TestIntent<void>('test.end', RouteArgs('secret')),
                );
              return const CCNavigationCancel();
            }),
          ),
        ],
      );
      addTearDown(runtime.dispose);
      _route(runtime, 'test.start', host: 'left');
      _route(runtime, 'test.end', host: 'right');
      runtime.initialize();
      final original = expectLater(
        runtime.pushRoute(
          const TestIntent<void>('test.start', RouteArgs('secret')),
        ),
        throwsA(isA<CCRouteCancelledError>()),
      );
      await Future<void>.delayed(Duration.zero);
      final pending = runtime.pendingNavigations.single;
      expect(pending.hostId, 'left');
      expect(pending.outlet, 'detail');
      resumed = true;
      await expectLater(
        runtime.resumePendingNavigation(pending.navigationId),
        throwsA(isA<CCRouteCancelledError>()),
      );
      await original;
      final failure = runtime.recentNavigationFailures.single.context;
      expect(failure.hostId, 'right');
      expect(failure.outlet, 'detail');
      expect(failure.routeId, 'test.end');
      expect(failure.attempt, CCNavigationFailureAttempt.pendingResume);
    },
  );

  for (final capacity in [0, 1]) {
    test(
      'history completeness survives disabled Sink and capacity $capacity',
      () async {
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: CCMemoryNavigationAdapter(),
          navigationDiagnosticCapacity: capacity,
          traceCapacity: capacity,
          diagnostics: const CCDiagnosticsConfig(defaultEnabled: false),
        );
        addTearDown(runtime.dispose);
        runtime.initialize();
        final revision = runtime.diagnosticSnapshot.revision;
        for (var i = 0; i < 3; i++) {
          await expectLater(
            runtime.pushRoute(
              TestIntent<void>('unknown.$i', const RouteArgs('secret')),
            ),
            throwsA(isA<CCRouteNotFoundError>()),
          );
        }
        final health = runtime.diagnosticSnapshot;
        final failures = health.histories.singleWhere(
          (h) => h.name == 'failures',
        );
        expect(failures.retainedCount, capacity);
        expect(failures.omittedCount, 3 - capacity);
        expect(health.revision, greaterThan(revision));
        expect(health.sinkConfigured, isFalse);
        expect(health.delivery.deliveredEventCount, 0);
        expect(() => health.histories.clear(), throwsUnsupportedError);
      },
    );
  }
}

void _route(
  CCRouterRuntime runtime,
  String id, {
  required String host,
  CCRouteCodec<RouteArgs> codec = const RouteArgsCodec(),
}) => runtime.registerRoute<RouteArgs, void>(
  CCRouteDefinition(
    routeId: id,
    patterns: [CCPathPattern('/$id/:value', primary: true)],
    codec: codec,
    placement: CCRoutePlacement(hostId: host, navigatorOutlet: 'detail'),
  ),
);

final class _Interceptor implements CCNavigationInterceptor {
  _Interceptor(this.callback);
  final CCNavigationInterceptorDecision Function(CCNavigationInterceptorContext)
  callback;
  @override
  CCNavigationInterceptorDecision intercept(
    CCNavigationInterceptorContext context,
  ) => callback(context);
}

final class _Policy implements CCNavigationFailurePolicy {
  _Policy(this.callback);
  final CCNavigationFailureDecision Function(CCNavigationFailureContext)
  callback;
  @override
  CCNavigationFailureDecision onFailure(CCNavigationFailureContext context) =>
      callback(context);
}

final class _Cancel implements CCNavigationInterceptor {
  @override
  CCNavigationInterceptorDecision intercept(
    CCNavigationInterceptorContext context,
  ) => const CCNavigationCancel(code: 'private-reason');
}
