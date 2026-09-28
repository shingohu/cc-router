import 'package:ccrouter_devtools_protocol/ccrouter_devtools_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('envelope round trips static catalog and runtime edges', () {
    final capturedAt = DateTime.utc(2026, 1, 1, 2, 3, 4);
    final envelope = CCDevToolsSnapshotEnvelope(
      capturedAt: capturedAt,
      catalog: CCDevToolsStaticCatalogSnapshot(
        capturedAt: capturedAt,
        catalogFingerprint: 'catalog-v1',
        components: [
          CCDevToolsCatalogComponent(
            id: 'orders',
            version: '1.0.0',
            dependencies: ['account'],
          ),
        ],
        relations: [
          const CCDevToolsCatalogRelation(
            sourceId: 'checkout.submit',
            targetId: 'orders.summary',
            kind: 'calls',
          ),
        ],
        records: [
          CCDevToolsCatalogRecord(
            kind: 'route',
            id: 'orders.detail',
            ownerComponentId: 'orders',
            packageName: 'orders',
            source: const CCDevToolsSourceLocation(
              packageName: 'orders',
              packageUri: 'package:orders/src/detail.dart',
              line: 10,
              column: 3,
            ),
          ),
        ],
      ),
      runtime: CCDevToolsRuntimeSnapshot(
        capturedAt: capturedAt,
        runtimeState: 'initialized',
        installedComponentIds: ['orders'],
        traceEdges: [
          CCDevToolsTraceEdge(
            traceId: 'trace-1',
            spanId: 'span-1',
            sourceId: 'navigation',
            targetId: 'orders.detail',
            kind: 'route',
            status: 'completed',
            startedAt: capturedAt,
            durationMicros: 42,
          ),
        ],
      ),
    );

    final decoded = CCDevToolsSnapshotEnvelope.decode(envelope.encode());
    expect(decoded.protocolVersion, 1);
    expect(decoded.catalog!.records.single.id, 'orders.detail');
    expect(decoded.catalog!.components.single.dependencies, ['account']);
    expect(decoded.catalog!.relations.single.kind, 'calls');
    expect(decoded.runtime.traceEdges.single.durationMicros, 42);
  });

  test('decoder rejects malformed required fields', () {
    expect(
      () => CCDevToolsSnapshotEnvelope.fromJson(const <String, Object?>{}),
      throwsFormatException,
    );
  });

  test('decoder rejects unsupported protocol versions', () {
    expect(
      () => CCDevToolsRuntimeSnapshot.fromJson({
        'protocolVersion': 99,
        'capturedAt': '2026-01-01T00:00:00.000Z',
        'runtimeState': 'initialized',
        'installedComponentIds': <Object?>[],
        'entries': <Object?>[],
        'traceEdges': <Object?>[],
      }),
      throwsFormatException,
    );
  });

  test('protocol collections are immutable', () {
    final snapshot = CCDevToolsRuntimeSnapshot(
      capturedAt: DateTime.utc(2026),
      runtimeState: 'initialized',
      installedComponentIds: ['orders'],
    );
    expect(
      () => snapshot.installedComponentIds.add('payments'),
      throwsUnsupportedError,
    );
  });
}
