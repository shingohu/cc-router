import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

// Original review fixture, also discovered by shared_execution_regression_test.
void main() {
  test('control: ordinary overlapping Gate calls share one drain', () async {
    final runtime = CCRouterRuntime.forTesting();
    addTearDown(runtime.dispose);
    final release = Completer<void>();
    var runs = 0;
    runtime.registerInitTask(
      CCInitTaskDefinition(
        id: 'startup.work',
        gate: CCInitTaskGate.appStarted,
        failurePolicy: CCInitTaskFailurePolicy.required,
        run: (_) {
          runs++;
          return release.future;
        },
      ),
    );
    runtime.initialize();
    final first = runtime.runInitTasks(gate: CCInitTaskGate.appStarted);
    final second = runtime.runInitTasks(gate: CCInitTaskGate.privacyGranted);
    release.complete();
    await Future.wait([first, second]);
    expect(second, same(first));
    expect(runs, 1);
  });

  for (final gate in [
    CCInitTaskGate.appStarted,
    CCInitTaskGate.privacyGranted,
  ]) {
    test(
      'synchronous Gate reentry runs each sibling once: ${gate.id}',
      () async {
        final runtime = CCRouterRuntime.forTesting();
        addTearDown(runtime.dispose);
        Future<CCInitTaskRunResult>? nested;
        var siblingRuns = 0;
        runtime.registerInitTask(
          CCInitTaskDefinition(
            id: 'startup.a',
            gate: CCInitTaskGate.appStarted,
            failurePolicy: CCInitTaskFailurePolicy.required,
            run: (_) {
              nested = runtime.runInitTasks(gate: gate);
            },
          ),
        );
        runtime.registerInitTask(
          CCInitTaskDefinition(
            id: 'startup.b',
            gate: CCInitTaskGate.appStarted,
            failurePolicy: CCInitTaskFailurePolicy.required,
            run: (_) => siblingRuns++,
          ),
        );
        runtime.initialize();
        final first = runtime.runInitTasks(gate: CCInitTaskGate.appStarted);
        await Future.wait([first, nested!]);
        expect(siblingRuns, 1);
        expect(nested, same(first));
      },
    );
  }

  test('first drain waits for synchronously opened Gate work', () async {
    final runtime = CCRouterRuntime.forTesting();
    addTearDown(runtime.dispose);
    final release = Completer<void>();
    Future<CCInitTaskRunResult>? nested;
    runtime.registerInitTask(
      CCInitTaskDefinition(
        id: 'startup.a',
        gate: CCInitTaskGate.appStarted,
        failurePolicy: CCInitTaskFailurePolicy.required,
        run: (_) {
          nested = runtime.runInitTasks(gate: CCInitTaskGate.privacyGranted);
        },
      ),
    );
    runtime.registerInitTask(
      CCInitTaskDefinition(
        id: 'startup.privacy',
        gate: CCInitTaskGate.privacyGranted,
        failurePolicy: CCInitTaskFailurePolicy.required,
        run: (_) => release.future,
      ),
    );
    runtime.initialize();
    var firstCompleted = false;
    final first = runtime.runInitTasks(gate: CCInitTaskGate.appStarted);
    unawaited(first.then((_) => firstCompleted = true));
    await Future<void>.delayed(Duration.zero);
    final completedBeforeRelease = firstCompleted;
    final third = runtime.runInitTasks(gate: CCInitTaskGate.privacyGranted);
    release.complete();
    await Future.wait([first, nested!, third]);
    expect(completedBeforeRelease, isFalse);
    expect(third, same(first));
  });
}
