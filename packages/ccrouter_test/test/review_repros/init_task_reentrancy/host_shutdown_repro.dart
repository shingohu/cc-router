import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter_test/flutter_test.dart';

import 'error_zone_repro.dart' show Disposable, NoOutcome, guardedZone;

class Registrar implements CCComponentRegistrar {
  Registrar(this.started, this.resource);
  final Completer<void> started;
  final Disposable resource;

  @override
  void register(CCRegistry registry) {
    registry.registerService(
      CCServiceProvider<Disposable>(factory: (_) => resource),
    );
    registry.registerInitTask(
      CCInitTaskDefinition(
        id: 'fixture.startup',
        gate: CCInitTaskGate.appStarted,
        failurePolicy: CCInitTaskFailurePolicy.required,
        run: (context) {
          started.complete();
          return context.cancellation.whenCancelled;
        },
      ),
    );
  }
}

void main() {
  test('public Host shutdown in another error Zone finishes cleanup', () async {
    final started = Completer<void>();
    final resource = Disposable();
    final uncaught = <Object>[];
    final taskZone = guardedZone(uncaught);
    final stopZone = guardedZone(uncaught);
    CCRouterHost.initialize(
      hostAssembly: CCHostAssembly.fromComponents(
        components: [
          CCComponentManifest(
            id: 'fixture',
            version: '1.0.0',
            registrar: Registrar(started, resource),
          ),
        ],
      ),
    );
    CCRouter.service<Disposable>();
    final taskOutcome = Completer<Object?>();
    taskZone.run(() {
      unawaited(
        CCRouterHost.runInitTasks(gate: CCInitTaskGate.appStarted).then<void>(
          taskOutcome.complete,
          onError: (Object error, StackTrace _) => taskOutcome.complete(error),
        ),
      );
    });
    await started.future;
    final shutdownOutcome = Completer<Object?>();
    stopZone.run(() {
      unawaited(
        CCRouterHost.shutdown().then<void>(
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
    Object? restartError;
    try {
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(components: const []),
      );
    } catch (error) {
      restartError = error;
    }
    // The original regression blocked cleanup and subsequent initialization.
    expect(task, isA<CCInvocationCancelledError>());
    expect(
      {
        'shutdownCompleted': shutdown == null,
        'serviceDisposals': resource.disposalCount,
        'restartError': restartError?.runtimeType.toString(),
        'uncaught': uncaught.map((e) => e.runtimeType.toString()).toList(),
      },
      {
        'shutdownCompleted': true,
        'serviceDisposals': 1,
        'restartError': null,
        'uncaught': <String>[],
      },
    );
    await CCRouterHost.shutdown();
  });
}
