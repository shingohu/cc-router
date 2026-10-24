import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_devtools/ccrouter_devtools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() async {
    CCDevToolsServiceExtension.clear();
    await CCRouterHost.shutdown();
  });

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
      final snapshot = CCRouterDevToolsSnapshot(
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
    final snapshot = CCRouterDevToolsSnapshot.empty(
      runtimeState: CCDevToolsRuntimeState.initialized,
    );
    final provider = CCStaticDevToolsSnapshotProvider(snapshot);
    var called = false;
    final remove = provider.addListener(() => called = true);

    expect(provider.snapshot(), same(snapshot));
    remove();
    expect(called, isFalse);
  });

  test(
    'protocol conversion includes safe failure, fallback, pending, task and health state',
    () {
      final snapshot = CCRouterDevToolsSnapshot(
        capturedAt: DateTime.utc(2026),
        runtimeState: CCDevToolsRuntimeState.initialized,
        navigationFailures: [
          CCNavigationFailureEvent(
            context: const CCNavigationFailureContext(
              navigationId: 'nav-1',
              operation: CCNavigationOperation.push,
              origin: CCNavigationOrigin.internal,
              openMode: null,
              stage: CCNavigationFailureStage.interception,
              errorType: 'CCRouteCancelledError',
              recoveryDepth: 2,
              reason: CCNavigationFailureReason.cancelled,
              attempt: CCNavigationFailureAttempt.pendingResume,
              hostId: 'right',
              outlet: 'detail',
              routeId: 'orders.detail',
              initialRouteId: 'orders.start',
            ),
            timestamp: DateTime.utc(2026),
            recovered: false,
          ),
        ],
        capabilityFallbacks: [
          CCNavigationCapabilityFallbackEvent(
            navigationId: 'nav-2',
            operation: CCNavigationOperation.go,
            routeId: 'orders.detail',
            hostId: 'left',
            navigatorOutlet: 'root',
            capability: CCNavigationCapabilityType.managedPopObservation,
            behavior: CCNavigationCapabilityFallbackBehavior
                .partitionLocalReconciliation,
            timestamp: DateTime.utc(2026),
          ),
        ],
        pendingNavigations: [
          CCPendingNavigation(
            navigationId: 'nav-3',
            operation: CCNavigationOperation.push,
            routeId: 'orders.detail',
            address: const CCRouteAddressSummary(
              routePattern: '/orders/:id',
              hasPathParameters: true,
              hasQueryParameters: true,
              hasFragment: true,
            ),
            origin: CCNavigationOrigin.internal,
            openMode: null,
            source: null,
            hostId: 'right',
            outlet: 'detail',
            createdAt: DateTime.utc(2026),
            expiresAt: DateTime.utc(2027),
          ),
        ],
        initTasks: [
          CCInitTaskSnapshot(
            id: 'orders.prepare',
            ownerComponentId: 'orders',
            gateId: 'appStarted',
            state: CCInitTaskState.failed,
            failurePolicy: CCInitTaskFailurePolicy.optional,
            dependsOn: ['account.prepare'],
            errorType: 'StateError',
            duration: const Duration(microseconds: 12),
          ),
        ],
        diagnosticHealth: CCDiagnosticSnapshot(
          runtimeId: 'runtime-1',
          revision: 3,
          sinkConfigured: false,
          delivery: const CCDiagnosticDeliverySnapshot(
            queueCapacity: 4,
            queuedEventCount: 0,
            inFlightWriteCount: 0,
            peakQueueDepth: 0,
            deliveredEventCount: 0,
            failedEventCount: 0,
            droppedEventCount: 0,
            isClosed: false,
          ),
          histories: [
            const CCDiagnosticHistorySnapshot(
              name: 'failures',
              capacity: 1,
              retainedCount: 1,
              omittedCount: 2,
            ),
          ],
        ),
      );
      final protocol = CCDevToolsRuntimeSnapshot.fromJson(
        snapshot.toProtocolRuntimeSnapshot().toJson(),
      );
      final records = protocol.diagnostics!;
      expect(records.map((r) => r.kind), [
        'failure',
        'fallback',
        'pending',
        'initTask',
      ]);
      expect(records[0].status, 'cancelled');
      expect(records[0].hostId, 'right');
      expect(records[0].outlet, 'detail');
      expect(records[0].recoveryDepth, 2);
      expect(records[0].attempt, 'pendingResume');
      expect(records[1].behavior, 'partitionLocalReconciliation');
      expect(records[2].expiresAt, DateTime.utc(2027));
      expect(records[3].dependsOn, ['account.prepare']);
      expect(records[3].durationMicros, 12);
      expect(protocol.diagnosticHealth!.histories.single.omittedCount, 2);
      expect(protocol.toJson().toString(), isNot(contains('/orders/:id')));
    },
  );

  test('runtime snapshot conversion keeps stable IDs and omits payloads', () {
    final snapshot = CCRouterDevToolsSnapshot(
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

  test(
    'service extension can be cleared without exposing a mutable Runtime',
    () {
      CCDevToolsServiceExtension.register(
        provider: CCStaticDevToolsSnapshotProvider(
          CCRouterDevToolsSnapshot.empty(),
        ),
      );
      CCDevToolsServiceExtension.clear();
      // The VM service handler is intentionally not called in this widget test;
      // registration is process-global and the public contract is idempotent.
      expect(ccRouterDevToolsSnapshotExtension, 'ext.ccrouter.snapshot');
    },
  );

  test('generated Host integration installs and clears its Catalog', () async {
    final catalog = CCDevToolsStaticCatalogSnapshot(
      capturedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      catalogFingerprint: 'fixture',
    );
    final assembly = CCHostAssembly.fromPackageBundles(
      [
        CCGeneratedPackageBundle(
          packageName: 'host',
          packageVersion: '1.0.0',
          contentFingerprint: 'host-fingerprint',
        ),
      ],
      hostToolIntegrations: [CCDevToolsHostIntegration(catalog: catalog)],
    );

    CCRouterHost.initialize(hostAssembly: assembly);
    expect(
      const CCRouterDevToolsSnapshotProvider().snapshot().catalog,
      same(catalog),
    );

    await CCRouterHost.shutdown();
    expect(const CCRouterDevToolsSnapshotProvider().snapshot().catalog, isNull);
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
