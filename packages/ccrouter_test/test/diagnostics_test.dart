import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:test/test.dart';

final class _RecordedEvent implements CCEvent {
  const _RecordedEvent();
}

final class _RecordedCommand implements CCCommand<String> {
  const _RecordedCommand();
}

final class _RecordingSink implements CCDiagnosticSink {
  final events = <CCDiagnosticEvent>[];

  @override
  void record(CCDiagnosticEvent event) => events.add(event);
}

final class _ThrowingSink implements CCDiagnosticSink {
  const _ThrowingSink();

  @override
  void record(CCDiagnosticEvent event) => throw StateError('sink failure');
}

final class _EmptyRegistrar implements CCComponentRegistrar {
  const _EmptyRegistrar();

  @override
  void register(CCRegistry registry) {}
}

final class _FailingRegistrar implements CCComponentRegistrar {
  const _FailingRegistrar();

  @override
  void register(CCRegistry registry) {
    throw StateError('registration failed');
  }
}

final class _InvalidInitializationRegistrar implements CCComponentRegistrar {
  const _InvalidInitializationRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerInitializationTask(
      CCInitializationTask(
        id: 'feature.prepare',
        dependsOn: const ['missing.prepare'],
        run: (_) {},
      ),
    );
  }
}

void main() {
  test(
    'component assembly and Runtime startup emit full diagnostics',
    () async {
      final sink = _RecordingSink();
      final runtime = CCRouterRuntime.forTesting(
        diagnostics: CCDiagnosticsConfig(
          sink: sink,
          defaultMinimumLevel: CCDiagnosticLevel.debug,
        ),
        components: const [
          CCComponentManifest(
            id: 'foundation',
            version: '1.0.0',
            registrar: _EmptyRegistrar(),
          ),
          CCComponentManifest(
            id: 'feature',
            version: '1.0.0',
            dependencies: ['foundation'],
            registrar: _EmptyRegistrar(),
          ),
        ],
      );

      runtime.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(
        sink.events
            .map(
              (event) => '${event.operation}:${event.status}:${event.target}',
            )
            .toList(),
        [
          'componentGraph:started:null',
          'componentRegistration:started:foundation',
          'componentRegistration:succeeded:foundation',
          'componentRegistration:started:feature',
          'componentRegistration:succeeded:feature',
          'componentGraph:succeeded:null',
          'runtimeInitialize:started:null',
          'runtimeInitialize:succeeded:null',
        ],
      );
      expect(
        sink.events.every(
          (event) => event.category == CCDiagnosticCategory.initialization,
        ),
        isTrue,
      );
      await runtime.dispose();
    },
  );

  test('component Registrar failure emits sanitized diagnostics', () async {
    final sink = _RecordingSink();

    expect(
      () => CCRouterRuntime.forTesting(
        diagnostics: CCDiagnosticsConfig(
          sink: sink,
          defaultMinimumLevel: CCDiagnosticLevel.debug,
        ),
        components: const [
          CCComponentManifest(
            id: 'broken',
            version: '1.0.0',
            registrar: _FailingRegistrar(),
          ),
        ],
      ),
      throwsStateError,
    );
    await Future<void>.delayed(Duration.zero);

    final registrationFailure = sink.events.singleWhere(
      (event) =>
          event.operation == 'componentRegistration' &&
          event.status == 'failed',
    );
    expect(registrationFailure.target, 'broken');
    expect(registrationFailure.targetComponentId, 'broken');
    expect(registrationFailure.failureStage, 'registrar');
    expect(registrationFailure.errorType, 'StateError');
    expect(registrationFailure.level, CCDiagnosticLevel.error);
    expect(
      sink.events.any(
        (event) =>
            event.operation == 'componentGraph' && event.status == 'failed',
      ),
      isTrue,
    );
  });

  test('Runtime validation failure identifies its startup stage', () async {
    final sink = _RecordingSink();
    final runtime = CCRouterRuntime.forTesting(
      diagnostics: CCDiagnosticsConfig(
        sink: sink,
        defaultMinimumLevel: CCDiagnosticLevel.debug,
      ),
      components: const [
        CCComponentManifest(
          id: 'feature',
          version: '1.0.0',
          registrar: _InvalidInitializationRegistrar(),
        ),
      ],
    );

    expect(runtime.initialize, throwsA(isA<CCRegistrationError>()));
    await Future<void>.delayed(Duration.zero);

    final failure = sink.events.singleWhere(
      (event) =>
          event.operation == 'runtimeInitialize' && event.status == 'failed',
    );
    expect(failure.failureStage, 'configurationValidation');
    expect(failure.errorType, 'CCRegistrationError');
    expect(failure.level, CCDiagnosticLevel.error);
    await runtime.dispose();
  });

  test(
    'typed Event subscriber keeps Event type and subscriber identity',
    () async {
      final sink = _RecordingSink();
      final runtime = CCRouterRuntime.forTesting(
        diagnostics: CCDiagnosticsConfig(sink: sink),
      );
      var received = 0;
      runtime.registerEventSubscriber<_RecordedEvent>(
        CCEventSubscriber<_RecordedEvent>(
          id: const CCEventSubscriberId<_RecordedEvent>('test.recorded'),
          handler: (_, _) {
            received++;
          },
        ),
      );
      runtime.initialize();

      await runtime.event(const _RecordedEvent());
      await Future<void>.delayed(Duration.zero);

      expect(received, 1);
      expect(
        sink.events.map((event) => event.operation),
        containsAll(<String>['event', 'eventSubscriber']),
      );
      expect(
        sink.events.any((event) => event.subscriberId == 'test.recorded'),
        isTrue,
      );
      await runtime.dispose();
    },
  );

  test('diagnostic category policy filters external delivery only', () async {
    final sink = _RecordingSink();
    final runtime = CCRouterRuntime.forTesting(
      diagnostics: CCDiagnosticsConfig(
        sink: sink,
        policies: const [
          CCDiagnosticCategoryPolicy(
            category: CCDiagnosticCategory.command,
            enabled: false,
          ),
        ],
      ),
    );
    runtime.registerCommand<_RecordedCommand, String>((_, _) => 'ok');
    runtime.initialize();

    expect(await runtime.command(const _RecordedCommand()), 'ok');
    await Future<void>.delayed(Duration.zero);

    expect(runtime.recentTraces, hasLength(1));
    expect(
      sink.events.where(
        (event) => event.category == CCDiagnosticCategory.command,
      ),
      isEmpty,
    );
    await runtime.dispose();
  });

  test('trace bundle groups retained nested invocation records', () async {
    final runtime = CCRouterRuntime.forTesting();
    runtime.registerCommand<_RecordedCommand, String>((_, context) {
      expect(context.traceId, isNotEmpty);
      return 'ok';
    });
    runtime.initialize();

    await runtime.command(const _RecordedCommand());
    final traceId = runtime.recentTraces.single.context.traceId;
    final bundle = runtime.traceBundle(traceId);

    expect(bundle.traceId, traceId);
    expect(bundle.records, hasLength(1));
    await runtime.dispose();
  });

  test('Sink failures do not change the framework result', () async {
    final runtime = CCRouterRuntime.forTesting(
      diagnostics: const CCDiagnosticsConfig(sink: _ThrowingSink()),
    );
    runtime.registerCommand<_RecordedCommand, String>((_, _) => 'ok');
    runtime.initialize();

    expect(await runtime.command(const _RecordedCommand()), 'ok');
    await Future<void>.delayed(Duration.zero);
    await runtime.dispose();
  });

  test('typed Event subscriber IDs use the stable identifier format', () {
    final runtime = CCRouterRuntime.forTesting();

    expect(
      () => runtime.registerEventSubscriber<_RecordedEvent>(
        const CCEventSubscriber<_RecordedEvent>(
          id: CCEventSubscriberId('invalid subscriber id'),
          handler: _noopEventHandler,
        ),
      ),
      throwsA(isA<CCRegistrationError>()),
    );
  });
}

Future<void> _noopEventHandler(
  _RecordedEvent event,
  CCInvocationContext context,
) async {}
