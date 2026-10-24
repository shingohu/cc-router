import 'dart:async';

import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reentrant_lifecycle_regression_test.dart' as routes;
import 'review_repros/init_task_reentrancy/error_zone_repro.dart'
    show guardedZone;

class _Policy implements CCNavigationInterceptor {
  _Policy(this.callback);
  final FutureOr<CCNavigationInterceptorDecision> Function(
    CCNavigationInterceptorContext,
  )
  callback;
  @override
  FutureOr<CCNavigationInterceptorDecision> intercept(
    CCNavigationInterceptorContext context,
  ) => callback(context);
}

class _Observed {
  _Observed(this.value, [this.stack]);
  final Object? value;
  final StackTrace? stack;
}

Future<_Observed> _inZone(Zone zone, Future<Object?> Function() work) {
  final done = Completer<_Observed>();
  zone.run(() {
    unawaited(
      Future<Object?>.sync(work).then<void>(
        (value) => done.complete(_Observed(value)),
        onError: (Object error, StackTrace stack) =>
            done.complete(_Observed(error, stack)),
      ),
    );
  });
  return done.future.timeout(const Duration(seconds: 2));
}

class _Recovery implements CCNavigationFailurePolicy {
  int calls = 0;
  @override
  CCNavigationFailureDecision onFailure(CCNavigationFailureContext context) {
    calls++;
    expect(context.attempt, CCNavigationFailureAttempt.pendingResume);
    return const CCNavigationFailureRedirect.toIntent(routes.Intent());
  }
}

class _StringIntent implements CCRouteIntent<String> {
  const _StringIntent();
  @override
  String get routeId => 'probe.result';
  @override
  String get arguments => 'value';
}

CCRouterRuntime _runtime(
  CCNavigationInterceptor policy, {
  CCNavigationAdapter? adapter,
  CCNavigationFailurePolicy? failurePolicy,
  List<CCNavigationAspect> aspects = const [],
  Duration? policyTimeout,
}) {
  final runtime = CCRouterRuntime.forTesting(
    navigationAdapter: adapter ?? CCMemoryNavigationAdapter(),
    globalInterceptors: [
      CCGlobalNavigationInterceptor(
        id: 'probe.resume',
        interceptor: policy,
        timeout: policyTimeout,
      ),
    ],
    navigationFailurePolicy: failurePolicy,
    navigationAspects: aspects,
    components: [
      CCComponentManifest(
        id: 'probe',
        version: '1.0.0',
        registrar: routes.Registrar(
          extra: (registry) => registry.registerRoute(
            CCRouteDefinition<String, String>(
              routeId: 'probe.result',
              patterns: [CCPathPattern('/result/:id', primary: true)],
              codec: const routes.Codec(),
            ),
          ),
        ),
      ),
    ],
  );
  addTearDown(runtime.dispose);
  runtime.initialize();
  return runtime;
}

void main() {
  for (final terminal in [
    'proceed',
    'cancel',
    'timeout',
    'session',
    'shutdown',
  ]) {
    test('three error Zones join repeated defer then $terminal', () async {
      var calls = 0;
      final after = <CCNavigationAspectEvent>[];
      final runtime = _runtime(
        _Policy((_) {
          calls++;
          return calls <= 2
              ? CCNavigationDefer(
                  timeout: calls == 2 && terminal == 'timeout'
                      ? const Duration(milliseconds: 100)
                      : null,
                )
              : const CCNavigationProceed();
        }),
        aspects: [CCNavigationAspect(id: 'probe.observe', onAfter: after.add)],
      );
      runtime.openSession(accountId: 'live');
      final uncaught = <Object>[];
      final zones = List.generate(3, (_) => guardedZone(uncaught));
      final original = _inZone(
        zones[0],
        () => runtime.goRoute(const routes.Intent()),
      );
      await Future<void>.delayed(Duration.zero);
      final id = runtime.pendingNavigations.single.navigationId;
      final firstResume = _inZone(
        zones[1],
        () => runtime.resumePendingNavigation(id),
      );
      await Future<void>.delayed(Duration.zero);
      expect(runtime.pendingNavigations.single.navigationId, id);
      Future<_Observed>? finalResume;
      if (terminal == 'proceed') {
        finalResume = _inZone(
          zones[2],
          () => runtime.resumePendingNavigation(id),
        );
      } else if (terminal == 'cancel') {
        zones[2].run(() => expect(runtime.cancelPendingNavigation(id), isTrue));
      } else if (terminal == 'session') {
        await runtime.closeSession();
      } else if (terminal == 'shutdown') {
        await runtime.dispose();
      }
      final results = await Future.wait([
        original,
        firstResume,
        if (finalResume != null) finalResume,
      ]);
      for (final result in results) {
        expect(
          result.value,
          terminal == 'proceed' ? isNull : isA<CCRouteCancelledError>(),
        );
        expect(result.value, same(results.first.value));
      }
      if (terminal != 'proceed') {
        final code = (results.first.value as CCRouteCancelledError).code;
        expect(code, switch (terminal) {
          'cancel' => 'pending_cancelled',
          'timeout' => 'pending_timeout',
          'session' => 'session_closed',
          _ => 'runtime_disposed',
        });
      }
      await Future<void>.delayed(Duration.zero);
      expect(runtime.pendingNavigations, isEmpty);
      expect(uncaught, isEmpty);
      if (terminal != 'shutdown') expect(after, hasLength(1));
    });
  }

  for (final terminal in ['host', 'shutdown', 'timeout']) {
    test(
      'cross-Zone resumed policy wait ends on $terminal and fences late error',
      () async {
        late Completer<CCNavigationInterceptorDecision> gate;
        final started = Completer<void>();
        var calls = 0;
        final aggregate = CCMultiHostNavigationAdapter(
          defaultHostId: 'primary',
          adapters: {
            'primary': CCMemoryNavigationAdapter(),
            'secondary': CCMemoryNavigationAdapter(),
          },
        );
        final runtime = _runtime(
          _Policy((_) {
            calls++;
            if (calls == 1) return const CCNavigationDefer();
            if (calls == 2) {
              // The producer Future belongs to the resumed policy's Zone.
              // A foreign error Future supplied by application code is not
              // a framework-shared result and cannot cross error Zones.
              gate = Completer<CCNavigationInterceptorDecision>();
              started.complete();
              return gate.future;
            }
            return const CCNavigationProceed();
          }),
          adapter: aggregate,
          policyTimeout: terminal == 'timeout'
              ? const Duration(milliseconds: 100)
              : null,
        );
        final uncaught = <Object>[];
        final original = _inZone(
          guardedZone(uncaught),
          () => runtime.goRoute(const routes.Intent()),
        );
        await Future<void>.delayed(Duration.zero);
        final id = runtime.pendingNavigations.single.navigationId;
        final resumed = _inZone(
          guardedZone(uncaught),
          () => runtime.resumePendingNavigation(id),
        );
        await started.future;
        if (terminal == 'host') {
          aggregate.unregisterHost(
            'primary',
            replacementActiveHostId: 'secondary',
          );
          aggregate.registerHost('primary', CCMemoryNavigationAdapter());
          aggregate.activateHost('primary');
        } else if (terminal == 'shutdown') {
          await runtime.dispose();
        }
        final results = await Future.wait([original, resumed]);
        expect(
          results.first.value,
          terminal == 'timeout'
              ? isA<CCNavigationInterceptorTimeoutError>()
              : isA<CCRouteCancelledError>(),
        );
        expect(results.last.value, same(results.first.value));
        gate.completeError(StateError('late business failure'));
        await Future<void>.delayed(Duration.zero);
        if (terminal != 'shutdown') {
          await runtime.goRoute(const routes.Intent());
          expect(runtime.activeRouteEntries, hasLength(1));
          expect(runtime.activeRouteEntries.single.hostId, 'primary');
        }
        expect(uncaught, isEmpty);
      },
    );
  }

  test(
    'resume preserves original failure identity and stack in both Zones',
    () async {
      var calls = 0;
      const error = CCRouteCancelledError('probe.original');
      final stack = StackTrace.fromString('resumed-policy-stack-marker');
      final runtime = _runtime(
        _Policy((_) {
          if (++calls == 1) return const CCNavigationDefer();
          Error.throwWithStackTrace(error, stack);
        }),
      );
      final uncaught = <Object>[];
      final original = _inZone(
        guardedZone(uncaught),
        () => runtime.goRoute(const routes.Intent()),
      );
      await Future<void>.delayed(Duration.zero);
      final resumed = _inZone(
        guardedZone(uncaught),
        () => runtime.resumePendingNavigation(
          runtime.pendingNavigations.single.navigationId,
        ),
      );
      for (final result in await Future.wait([original, resumed])) {
        expect(result.value, same(error));
        expect(
          result.stack.toString(),
          contains('resumed-policy-stack-marker'),
        );
      }
      expect(runtime.recentNavigationFailures, hasLength(1));
      expect(
        runtime.recentNavigationFailures.single.context.attempt,
        CCNavigationFailureAttempt.pendingResume,
      );
      expect(uncaught, isEmpty);
    },
  );

  test(
    'only original pipeline invokes Failure Policy after a failed resume',
    () async {
      var calls = 0;
      final recovery = _Recovery();
      final runtime = _runtime(
        _Policy((_) {
          calls++;
          if (calls == 1) return const CCNavigationDefer();
          if (calls == 2) throw StateError('policy rejected');
          return const CCNavigationProceed();
        }),
        failurePolicy: recovery,
      );
      final uncaught = <Object>[];
      final original = _inZone(
        guardedZone(uncaught),
        () => runtime.goRoute(const routes.Intent()),
      );
      await Future<void>.delayed(Duration.zero);
      final resumed = _inZone(
        guardedZone(uncaught),
        () => runtime.resumePendingNavigation(
          runtime.pendingNavigations.single.navigationId,
        ),
      );
      expect((await original).value, isNull);
      expect((await resumed).value, isA<CCNavigationInterceptorError>());
      expect(recovery.calls, 1);
      expect(runtime.activeRouteEntries, hasLength(1));
      expect(uncaught, isEmpty);
    },
  );

  for (final replace in [false, true]) {
    for (final wrongType in [false, true]) {
      test(
        'cross-Zone ${replace ? 'replace' : 'push'} result, wrongType=$wrongType',
        () async {
          var authorized = false;
          final runtime = _runtime(
            _Policy(
              (_) => authorized
                  ? const CCNavigationProceed()
                  : const CCNavigationDefer(),
            ),
          );
          final uncaught = <Object>[];
          final original = _inZone(
            guardedZone(uncaught),
            () => replace
                ? runtime.replaceRoute<String>(const _StringIntent())
                : runtime.pushRoute<String>(const _StringIntent()),
          );
          await Future<void>.delayed(Duration.zero);
          final id = runtime.pendingNavigations.single.navigationId;
          authorized = true;
          final resumed = _inZone(
            guardedZone(uncaught),
            () => runtime.resumePendingNavigation(id),
          );
          await Future<void>.delayed(Duration.zero);
          expect(runtime.activeRouteEntries.single.navigationId, id);
          runtime.popRoute<Object>(result: wrongType ? 42 : 'done');
          final results = await Future.wait([original, resumed]);
          expect(
            results.first.value,
            wrongType ? isA<CCRouteResultTypeError>() : 'done',
          );
          expect(results.last.value, same(results.first.value));
          expect(runtime.activeRouteEntries, isEmpty);
          expect(uncaught, isEmpty);
        },
      );
    }
  }
}
