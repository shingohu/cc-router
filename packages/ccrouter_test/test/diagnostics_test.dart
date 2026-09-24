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

void main() {
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
