import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_devtools/ccrouter_devtools.dart';
import 'package:flutter_test/flutter_test.dart';

const _tick = Duration(milliseconds: 250);

final class _Command implements CCCommand<void> {}

final class _Registrar implements CCComponentRegistrar {
  _Registrar(this.task);
  final Completer<void> task;
  @override
  void register(CCRegistry registry) {
    registry.registerCommand<_Command, void>((_, _) {});
    registry.registerInitTask(
      CCInitTaskDefinition(
        id: 'fixture.prepare',
        gate: CCInitTaskGate.appStarted,
        failurePolicy: CCInitTaskFailurePolicy.required,
        run: (_) => task.future,
      ),
    );
  }
}

final class _SlowSink implements CCDiagnosticSink {
  final firstWrite = Completer<void>();
  var writes = 0;
  @override
  Future<void> record(CCDiagnosticEvent event) {
    writes++;
    return writes == 1 ? firstWrite.future : Future.value();
  }
}

void _initialize({Completer<void>? task, CCDiagnosticSink? sink}) {
  CCRouterHost.initialize(
    hostAssembly: CCHostAssembly.fromComponents(
      components: [
        CCComponentManifest(
          id: 'fixture',
          version: '1.0.0',
          registrar: _Registrar(task ?? Completer<void>()),
        ),
      ],
    ),
    diagnostics: CCDiagnosticsConfig(
      sink: sink,
      defaultMinimumLevel: CCDiagnosticLevel.debug,
    ),
  );
}

void main() {
  tearDown(CCRouterHost.shutdown);

  testWidgets(
    'burst invocation changes are coalesced into one refresh interval',
    (tester) async {
      _initialize();
      var calls = 0;
      final remove = const CCRouterDevToolsSnapshotProvider().addListener(
        () => calls++,
      );
      addTearDown(remove);
      for (var i = 0; i < 100; i++) {
        await CCRouter.command(_Command());
      }
      expect(calls, 0);
      await tester.pump(_tick);
      expect(calls, 1);
      expect(
        const CCRouterDevToolsSnapshotProvider().snapshot().traces,
        hasLength(100),
      );
      await tester.pump(_tick * 3);
      expect(calls, 1);
      remove();
      await CCRouterHost.shutdown();
    },
  );

  testWidgets(
    'provider follows startup, non-navigation calls, tasks and replacement',
    (tester) async {
      const provider = CCRouterDevToolsSnapshotProvider();
      var notifications = 0;
      final remove = provider.addListener(() => notifications++);
      addTearDown(remove);
      await tester.pump(_tick);
      expect(notifications, 0);
      final task = Completer<void>();
      _initialize(task: task);
      await tester.pump(_tick);
      expect(notifications, 1);
      final firstId = provider.snapshot().diagnosticHealth!.runtimeId;
      await tester.pump(_tick);
      expect(notifications, 1);
      await CCRouter.command(_Command());
      await tester.pump(_tick);
      expect(notifications, 2);
      expect(provider.snapshot().traces.single.operation, 'command');
      final running = CCRouterHost.runInitTasks(
        gate: CCInitTaskGate.appStarted,
      );
      await tester.pump(_tick);
      expect(notifications, 3);
      expect(
        provider.snapshot().initTasks.single.state,
        CCInitTaskState.running,
      );
      task.complete();
      await running;
      await tester.pump(_tick);
      expect(notifications, 4);
      expect(
        provider.snapshot().initTasks.single.state,
        CCInitTaskState.succeeded,
      );
      await CCRouterHost.shutdown();
      _initialize();
      await tester.pump(_tick);
      expect(notifications, 5);
      expect(provider.snapshot().diagnosticHealth!.runtimeId, isNot(firstId));
      await CCRouterHost.shutdown();
      await tester.pump(_tick);
      expect(notifications, 6);
      expect(
        provider.snapshot().runtimeState,
        CCDevToolsRuntimeState.uninitialized,
      );
      remove();
      remove();
      _initialize();
      await tester.pump(_tick * 2);
      expect(notifications, 6);
    },
  );

  testWidgets(
    'Sink completion refreshes even without another Runtime observation',
    (tester) async {
      final sink = _SlowSink();
      _initialize(sink: sink);
      await tester.pump(const Duration(milliseconds: 1));
      var notifications = 0;
      const provider = CCRouterDevToolsSnapshotProvider();
      final remove = provider.addListener(() => notifications++);
      addTearDown(remove);
      final revision = provider.snapshot().diagnosticHealth!.revision;
      expect(provider.snapshot().diagnosticHealth!.sinkConfigured, isTrue);
      expect(
        provider.snapshot().diagnosticHealth!.delivery.inFlightWriteCount,
        1,
        reason:
            'writes=${sink.writes}, queued=${provider.snapshot().diagnosticHealth!.delivery.queuedEventCount}',
      );
      await tester.pump(_tick);
      expect(notifications, 0);
      sink.firstWrite.complete();
      await tester.pump();
      await tester.pump(_tick);
      expect(notifications, 1);
      final health = provider.snapshot().diagnosticHealth!;
      expect(health.revision, revision);
      expect(health.delivery.inFlightWriteCount, 0);
      expect(health.delivery.deliveredEventCount, greaterThan(0));
      await tester.pump(_tick);
      expect(notifications, 1);
      remove();
      await CCRouterHost.shutdown();
    },
  );

  testWidgets('a throwing listener is isolated and removal cancels its Timer', (
    tester,
  ) async {
    var calls = 0;
    final remove = const CCRouterDevToolsSnapshotProvider().addListener(() {
      calls++;
      throw StateError('private visualization failure');
    });
    _initialize();
    await tester.pump(_tick);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
    remove();
    await CCRouterHost.shutdown();
    await tester.pump(_tick);
    expect(calls, 1);
  });
}
