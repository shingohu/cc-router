import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../reentrant_lifecycle_regression_test.dart' as routes;
import '../init_task_reentrancy/error_zone_repro.dart' show guardedZone;

class ReplayPolicy implements CCNavigationInterceptor {
  ReplayPolicy(this.deferrals, this.failure);
  final int deferrals;
  final String failure;
  int calls = 0;
  @override
  CCNavigationInterceptorDecision intercept(
    CCNavigationInterceptorContext context,
  ) {
    calls++;
    if (calls <= deferrals) return const CCNavigationDefer();
    if (calls == deferrals + 1) {
      if (failure == 'throw') throw StateError('probe replay failure');
      return const CCNavigationCancel(code: 'probe.denied');
    }
    return const CCNavigationProceed();
  }
}

class FailurePolicy implements CCNavigationFailurePolicy {
  FailurePolicy(this.recover);
  final bool recover;
  final List<CCNavigationFailureContext> contexts = [];
  @override
  CCNavigationFailureDecision onFailure(CCNavigationFailureContext context) {
    contexts.add(context);
    return recover
        ? const CCNavigationFailureRedirect.toIntent(routes.Intent())
        : const CCNavigationFailurePropagate();
  }
}

Future<Object?> observeInZone(Zone zone, Future<Object?> Function() work) {
  final outcome = Completer<Object?>();
  zone.run(() {
    unawaited(
      Future<Object?>.sync(work).then<void>(
        outcome.complete,
        onError: (Object error, StackTrace _) => outcome.complete(error),
      ),
    );
  });
  return outcome.future.timeout(const Duration(seconds: 2));
}

void main() {
  for (final separateErrorZones in [false, true]) {
    for (final deferrals in [1, 3]) {
      for (final recover in [false, true]) {
        for (final failure in ['deny', 'throw']) {
          test(
            'repeated replay failure: zones=$separateErrorZones, '
            'defers=$deferrals, recover=$recover, failure=$failure',
            () async {
              final policy = ReplayPolicy(deferrals, failure);
              final failurePolicy = FailurePolicy(recover);
              final runtime = CCRouterRuntime.forTesting(
                navigationAdapter: CCMemoryNavigationAdapter(),
                globalInterceptors: [
                  CCGlobalNavigationInterceptor(
                    id: 'probe.replay',
                    interceptor: policy,
                  ),
                ],
                navigationFailurePolicy: failurePolicy,
                components: [
                  CCComponentManifest(
                    id: 'probe',
                    version: '1.0.0',
                    registrar: routes.Registrar(),
                  ),
                ],
              );
              addTearDown(runtime.dispose);
              runtime.initialize();
              final uncaught = <Object>[];
              final firstZone = guardedZone(uncaught);
              final original = observeInZone(
                firstZone,
                () => runtime.goRoute(const routes.Intent()),
              );
              await Future<void>.delayed(Duration.zero);
              final id = runtime.pendingNavigations.single.navigationId;
              final resumers = <Future<Object?>>[];
              for (var replay = 0; replay < deferrals; replay++) {
                final zone = separateErrorZones
                    ? guardedZone(uncaught)
                    : firstZone.fork();
                resumers.add(
                  observeInZone(
                    zone,
                    () => runtime.resumePendingNavigation(id),
                  ),
                );
                // All callbacks are synchronous; one turn drains the async
                // pipeline to either the next defer or the terminal outcome.
                await Future<void>.delayed(Duration.zero);
                if (replay < deferrals - 1) {
                  expect(runtime.pendingNavigations.single.navigationId, id);
                }
              }
              final resumed = await Future.wait(resumers);
              final originalOutcome = await original;
              final error = resumed.first;
              expect(
                error,
                failure == 'deny'
                    ? isA<CCRouteCancelledError>()
                    : isA<CCNavigationInterceptorError>(),
              );
              expect(resumed.every((value) => identical(value, error)), isTrue);
              expect(originalOutcome, recover ? isNull : same(error));
              expect(failurePolicy.contexts, hasLength(1));
              expect(
                failurePolicy.contexts.single.attempt,
                CCNavigationFailureAttempt.pendingResume,
              );
              expect(runtime.recentNavigationFailures, hasLength(1));
              expect(
                runtime.recentNavigationFailures.single.recovered,
                recover,
              );
              expect(runtime.pendingNavigations, isEmpty);
              expect(runtime.activeRouteEntries.length, recover ? 1 : 0);
              expect(uncaught, isEmpty);
              // A subsequent fresh navigation must neither inherit replay
              // failure attribution nor trigger the recovery policy again.
              await runtime.goRoute(const routes.Intent());
              expect(failurePolicy.contexts, hasLength(1));
              expect(runtime.activeRouteEntries, hasLength(1));
            },
          );
        }
      }
    }
  }
}
