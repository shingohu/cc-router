import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

class Resource {}

class NoOutcome {}

class Disposable implements CCDisposable {
  int disposalCount = 0;
  @override
  void dispose() => disposalCount++;
}

Zone guardedZone(List<Object> uncaught) {
  late Zone zone;
  runZonedGuarded(() => zone = Zone.current, (error, _) => uncaught.add(error));
  return zone;
}

void main() {
  for (final sharedErrorZone in [true, false]) {
    for (final initializationFails in [false, true]) {
      for (final lateJoin in [false, true]) {
        test('shared readiness: same error Zone=$sharedErrorZone, '
            'initialization fails=$initializationFails, late join=$lateJoin', () async {
          final runtime = CCRouterRuntime.forTesting();
          addTearDown(runtime.dispose);
          final uncaught = <Object>[];
          final owner = guardedZone(uncaught);
          final other = sharedErrorZone ? owner.fork() : guardedZone(uncaught);
          final started = Completer<void>();
          final release = Completer<void>();
          var initializations = 0;
          final resource = Resource();
          runtime.registerService(
            CCServiceProvider<Resource>(
              factory: (_) => resource,
              initializer: (_, _) async {
                initializations++;
                started.complete();
                await release.future;
                if (initializationFails)
                  throw StateError('fixture init failure');
              },
            ),
          );
          runtime.initialize();

          // Observe each Future in its own caller Zone. Only successful outcome
          // values cross into the test Zone; the fixture does not await an error
          // Future from another error Zone itself.
          void observe(Zone zone, Completer<Object> outcome) => zone.run(() {
            unawaited(
              runtime.serviceAsync<Resource>().then<void>(
                outcome.complete,
                onError: (Object error, StackTrace _) =>
                    outcome.complete(error),
              ),
            );
          });

          final first = Completer<Object>();
          final second = Completer<Object>();
          observe(owner, first);
          await started.future;
          if (lateJoin) {
            release.complete();
            await first.future;
            observe(other, second);
          } else {
            observe(other, second);
            release.complete();
          }
          final firstOutcome = await first.future;
          final secondOutcome = await second.future.timeout(
            const Duration(seconds: 2),
            onTimeout: NoOutcome.new,
          );
          // Cancellation lets a broken waiter terminate after the probe records
          // whether the actual readiness failure reached it.
          await runtime.dispose();

          expect(initializations, 1);
          expect(
            firstOutcome,
            initializationFails
                ? isA<CCServiceInitializationError>()
                : same(resource),
          );
          expect(
            secondOutcome,
            initializationFails
                ? isA<CCServiceInitializationError>()
                : same(resource),
            reason:
                'uncaught errors: ${uncaught.map((e) => e.runtimeType).toList()}',
          );
          if (initializationFails) {
            expect(
              secondOutcome,
              same(firstOutcome),
              reason: 'Concurrent and late callers preserve failure identity',
            );
          }
          expect(uncaught, isEmpty);
        });
      }
    }

    test('shutdown joins cancelled InitTask: '
        'same error Zone=$sharedErrorZone', () async {
      final runtime = CCRouterRuntime.forTesting();
      final uncaught = <Object>[];
      final owner = guardedZone(uncaught);
      final stopper = sharedErrorZone ? owner.fork() : guardedZone(uncaught);
      final started = Completer<void>();
      final resource = Disposable();
      runtime.registerService(
        CCServiceProvider<Disposable>(factory: (_) => resource),
      );
      runtime.registerInitTask(
        CCInitTaskDefinition(
          id: 'startup.pending',
          gate: CCInitTaskGate.appStarted,
          failurePolicy: CCInitTaskFailurePolicy.required,
          run: (context) {
            started.complete();
            return context.cancellation.whenCancelled;
          },
        ),
      );
      runtime.initialize();
      runtime.service<Disposable>();
      final taskOutcome = Completer<Object?>();
      owner.run(() {
        unawaited(
          runtime
              .runInitTasks(gate: CCInitTaskGate.appStarted)
              .then<void>(
                taskOutcome.complete,
                onError: (Object error, StackTrace _) =>
                    taskOutcome.complete(error),
              ),
        );
      });
      await started.future;
      final shutdownOutcome = Completer<Object?>();
      stopper.run(() {
        unawaited(
          runtime.dispose().then<void>(
            (_) => shutdownOutcome.complete(),
            onError: (Object error, StackTrace _) =>
                shutdownOutcome.complete(error),
          ),
        );
      });
      final task = await taskOutcome.future.timeout(const Duration(seconds: 1));
      final shutdown = await shutdownOutcome.future.timeout(
        const Duration(seconds: 2),
        onTimeout: NoOutcome.new,
      );
      // The watchdog makes an internal cross-Zone cleanup hang fail boundedly.
      expect(task, isA<CCInvocationCancelledError>());
      expect(
        shutdown,
        isNull,
        reason:
            'task=${task.runtimeType}, disposals=${resource.disposalCount}, '
            'uncaught=${uncaught.map((e) => e.runtimeType).toList()}',
      );
      expect(resource.disposalCount, 1);
      expect(uncaught, isEmpty);
    });
  }
}
