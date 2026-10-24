import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'review_repros/init_task_reentrancy/error_zone_repro.dart' as readiness;
import 'review_repros/init_task_reentrancy/host_shutdown_repro.dart' as host;
import 'review_repros/init_task_reentrancy/navigation_zone_repro.dart'
    as navigation;
import 'review_repros/init_task_reentrancy/repro.dart' as gate;

// Keep the original review fixtures executable while permanently discovering
// their expected contracts in the normal framework regression suite.
void main() {
  group('InitTask publication', gate.main);
  group('Shared readiness and cleanup Zones', readiness.main);
  group('Shared navigation Zones', navigation.main);
  group('Public Host shutdown', host.main);

  test(
    'shared readiness preserves original failure and stack in every Zone',
    () async {
      final runtime = CCRouterRuntime.forTesting();
      addTearDown(runtime.dispose);
      final uncaught = <Object>[];
      final started = Completer<void>();
      final release = Completer<void>();
      const failure = CCResolutionError('original-shared-failure');
      final stack = StackTrace.fromString('shared-initializer-origin-marker');
      var calls = 0;
      runtime.registerService(
        CCServiceProvider<readiness.Resource>(
          factory: (_) => readiness.Resource(),
          initializer: (_, _) async {
            calls++;
            started.complete();
            await release.future;
            Error.throwWithStackTrace(failure, stack);
          },
        ),
      );
      runtime.initialize();
      Future<(Object, String)> observe() {
        final done = Completer<(Object, String)>();
        readiness.guardedZone(uncaught).run(() {
          unawaited(
            runtime.serviceAsync<readiness.Resource>().then<void>(
              (value) => done.complete((value, '')),
              onError: (Object error, StackTrace trace) =>
                  done.complete((error, trace.toString())),
            ),
          );
        });
        return done.future;
      }

      final first = observe();
      await started.future;
      final second = observe();
      release.complete();
      final results = await Future.wait([first, second]);
      results.add(await observe());
      for (final result in results) {
        expect(result.$1, same(failure));
        expect(result.$2, contains('shared-initializer-origin-marker'));
      }
      expect(calls, 1);
      expect(uncaught, isEmpty);
    },
  );

  for (final shutdown in [false, true]) {
    test(
      'different error Zones join one Gate drain: shutdown=$shutdown',
      () async {
        final runtime = CCRouterRuntime.forTesting();
        addTearDown(runtime.dispose);
        final uncaught = <Object>[];
        final zones = [
          readiness.guardedZone(uncaught),
          readiness.guardedZone(uncaught),
        ];
        final release = Completer<void>();
        var startupRuns = 0;
        var privacyRuns = 0;
        runtime.registerInitTask(
          CCInitTaskDefinition(
            id: 'startup.owner',
            gate: CCInitTaskGate.appStarted,
            failurePolicy: CCInitTaskFailurePolicy.required,
            run: (context) {
              startupRuns++;
              return shutdown
                  ? context.cancellation.whenCancelled
                  : release.future;
            },
          ),
        );
        runtime.registerInitTask(
          CCInitTaskDefinition(
            id: 'startup.privacy',
            gate: CCInitTaskGate.privacyGranted,
            failurePolicy: CCInitTaskFailurePolicy.optional,
            run: (_) => privacyRuns++,
          ),
        );
        runtime.initialize();
        final outcomes = <Future<Object>>[];
        for (var index = 0; index < zones.length; index++) {
          final done = Completer<Object>();
          outcomes.add(done.future);
          zones[index].run(() {
            unawaited(
              runtime
                  .runInitTasks(
                    gate: index == 0
                        ? CCInitTaskGate.appStarted
                        : CCInitTaskGate.privacyGranted,
                  )
                  .then<void>(
                    done.complete,
                    onError: (Object error, StackTrace _) =>
                        done.complete(error),
                  ),
            );
          });
        }
        if (shutdown) {
          await runtime.dispose();
        } else {
          release.complete();
        }
        final results = await Future.wait(
          outcomes,
        ).timeout(const Duration(seconds: 2));
        expect(startupRuns, 1);
        expect(
          results.first,
          shutdown
              ? isA<CCInvocationCancelledError>()
              : isA<CCInitTaskRunResult>(),
        );
        expect(results.last, same(results.first));
        if (!shutdown) expect(privacyRuns, 1);
        expect(uncaught, isEmpty);
      },
    );
  }
}
