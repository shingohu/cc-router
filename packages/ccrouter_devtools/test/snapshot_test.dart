import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_devtools/ccrouter_devtools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'snapshot copies collection boundaries and preserves read-only data',
    () {
      final components = <CCComponentManifest>[
        CCComponentManifest(
          id: 'orders',
          version: '1.0.0',
          registrar: _Registrar(),
          dependencies: ['account'],
        ),
      ];
      final snapshot = CCDevToolsSnapshot(
        capturedAt: DateTime.utc(2026, 1, 1),
        runtimeState: CCDevToolsRuntimeState.initialized,
        components: components,
      );

      components.clear();

      expect(snapshot.components, hasLength(1));
      expect(snapshot.components.single.id, 'orders');
      expect(
        () => snapshot.components.add(snapshot.components.single),
        throwsUnsupportedError,
      );
    },
  );

  test('static provider is deterministic and has no mutation surface', () {
    final snapshot = CCDevToolsSnapshot.empty(
      runtimeState: CCDevToolsRuntimeState.initialized,
    );
    final provider = CCStaticDevToolsSnapshotProvider(snapshot);
    var called = false;
    final remove = provider.addListener(() => called = true);

    expect(provider.snapshot(), same(snapshot));
    remove();
    expect(called, isFalse);
  });

  test('runtime snapshot conversion keeps stable IDs and omits payloads', () {
    final snapshot = CCDevToolsSnapshot(
      capturedAt: DateTime.utc(2026, 1, 1),
      runtimeState: CCDevToolsRuntimeState.initialized,
      components: [
        CCComponentManifest(
          id: 'orders',
          version: '1.0.0',
          registrar: _Registrar(),
        ),
      ],
      traces: [
        CCTraceRecord(
          context: _traceContext(),
          operation: 'service',
          target: 'orders.summary',
          startedAt: DateTime.utc(2026, 1, 1),
          duration: const Duration(microseconds: 12),
          status: 'succeeded',
        ),
      ],
    );

    final protocol = snapshot.toProtocolRuntimeSnapshot();
    expect(protocol.protocolVersion, ccRouterDevToolsProtocolVersion);
    expect(protocol.installedComponentIds, ['orders']);
    expect(protocol.traceEdges.single.targetId, 'orders.summary');
    expect(protocol.traceEdges.single.durationMicros, 12);
    expect(protocol.toJson().toString(), isNot(contains('secret')));
  });
}

CCTraceContextSnapshot _traceContext() => CCTraceContextSnapshot.from(
  CCInvocationContext(
    invocationId: 'invocation-1',
    traceId: 'trace-1',
    spanId: 'span-1',
    operation: 'service',
    target: 'orders.summary',
    callerComponentId: 'checkout',
    targetComponentId: 'orders',
    scopeId: 'app',
  ),
);

final class _Registrar implements CCComponentRegistrar {
  @override
  void register(CCRegistry registry) {}
}
