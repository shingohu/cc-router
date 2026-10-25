import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_devtools_protocol/ccrouter_devtools_protocol.dart';

/// Describes whether the snapshot was captured from an initialized Runtime.
enum CCDevToolsRuntimeState {
  /// No production Runtime is initialized in the current isolate.
  uninitialized,

  /// Snapshot data was read from the active initialized Runtime.
  initialized,
}

/// Immutable, read-only view of the CCRouter diagnostics surface.
///
/// The source values are already bounded and sanitized by CCRouter. This type
/// only groups them for visualization; it does not retain mutable framework
/// objects or provide operations that can change navigation or lifecycle.
final class CCRouterDevToolsSnapshot {
  /// Creates a diagnostics snapshot from safe CCRouter values.
  CCRouterDevToolsSnapshot({
    required this.capturedAt,
    required this.runtimeState,
    this.catalog,
    this.diagnosticHealth,
    List<CCComponentManifest> components = const [],
    List<CCRouteEntrySnapshot> routeEntries = const [],
    List<CCBackendEntrySnapshot> backendEntries = const [],
    List<CCTraceRecord> traces = const [],
    List<CCNavigationLifecycleEvent> navigationEvents = const [],
    List<CCNavigationFailureEvent> navigationFailures = const [],
    List<CCNavigationCapabilityFallbackEvent> capabilityFallbacks = const [],
    List<CCRouteVisibilityEvent> visibilityEvents = const [],
    List<CCNavigationBackendDiagnosticEvent> backendEvents = const [],
    List<CCInitTaskSnapshot> initTasks = const [],
    List<CCPendingNavigation> pendingNavigations = const [],
  }) : components = List.unmodifiable(components),
       routeEntries = List.unmodifiable(routeEntries),
       backendEntries = List.unmodifiable(backendEntries),
       traces = List.unmodifiable(traces),
       navigationEvents = List.unmodifiable(navigationEvents),
       navigationFailures = List.unmodifiable(navigationFailures),
       capabilityFallbacks = List.unmodifiable(capabilityFallbacks),
       visibilityEvents = List.unmodifiable(visibilityEvents),
       backendEvents = List.unmodifiable(backendEvents),
       initTasks = List.unmodifiable(initTasks),
       pendingNavigations = List.unmodifiable(pendingNavigations);

  /// Creates an empty snapshot used when a Host has no active Runtime.
  factory CCRouterDevToolsSnapshot.empty({
    CCDevToolsRuntimeState runtimeState = CCDevToolsRuntimeState.uninitialized,
  }) => CCRouterDevToolsSnapshot(
    capturedAt: DateTime.now(),
    runtimeState: runtimeState,
  );

  /// Wall-clock time at which this immutable view was assembled.
  final DateTime capturedAt;

  /// Runtime availability at capture time.
  final CCDevToolsRuntimeState runtimeState;

  /// Optional generated static source index linked by stable capability IDs.
  final CCDevToolsStaticCatalogSnapshot? catalog;

  /// Lightweight history completeness and external Sink delivery counters.
  /// Null means that the producer did not provide health, not zero losses.
  final CCDiagnosticSnapshot? diagnosticHealth;

  /// Installed component manifests in dependency order.
  final List<CCComponentManifest> components;

  /// Currently retained managed Route Entries in navigation order.
  final List<CCRouteEntrySnapshot> routeEntries;

  /// Adapter-neutral managed, foreign, and opaque backend entries.
  final List<CCBackendEntrySnapshot> backendEntries;

  /// Bounded invocation trace records.
  final List<CCTraceRecord> traces;

  /// Bounded navigation lifecycle events.
  final List<CCNavigationLifecycleEvent> navigationEvents;

  /// Bounded terminal navigation failures.
  final List<CCNavigationFailureEvent> navigationFailures;

  /// Bounded Adapter capability fallbacks.
  final List<CCNavigationCapabilityFallbackEvent> capabilityFallbacks;

  /// Bounded managed Route visibility events.
  final List<CCRouteVisibilityEvent> visibilityEvents;

  /// Bounded backend transitions observed by the Adapter.
  final List<CCNavigationBackendDiagnosticEvent> backendEvents;

  /// Current initialization task states and dependency edges.
  final List<CCInitTaskSnapshot> initTasks;

  /// Navigation requests waiting for an external policy decision.
  final List<CCPendingNavigation> pendingNavigations;

  /// Converts this widget-facing view into the versioned tooling protocol.
  ///
  /// The conversion copies only stable identities, lifecycle states, Host and
  /// Outlet placement, fixed diagnostic states, health counts and trace timing.
  /// It intentionally omits route
  /// addresses, arguments, results, Widget instances, and backend objects.
  CCDevToolsRuntimeSnapshot toProtocolRuntimeSnapshot({
    String hostId = 'default',
  }) => CCDevToolsRuntimeSnapshot(
    capturedAt: capturedAt,
    runtimeState: runtimeState.name,
    installedComponentIds: components.map((component) => component.id),
    entries: [
      for (final entry in routeEntries)
        CCDevToolsRuntimeEntry(
          kind: 'route',
          id: entry.routeEntryId,
          state: entry.lifecycleState.name,
          ownerComponentId: entry.ownerComponentId,
          hostId: entry.hostId,
          outlet: entry.placement.navigatorOutlet,
          routeId: entry.routeId,
          traceId: entry.navigationId,
        ),
      for (final entry in backendEntries)
        CCDevToolsRuntimeEntry(
          kind: 'backend',
          id: entry.backendEntryId,
          state: entry.lifecycleState.name,
          ownerComponentId: entry.owner.name,
          hostId: entry.hostId ?? hostId,
          outlet: entry.navigatorOutlet,
          routeId: entry.routeId,
          traceId: entry.navigationId,
        ),
    ],
    traceEdges: [
      for (final trace in traces)
        CCDevToolsTraceEdge(
          traceId: trace.context.traceId,
          spanId: trace.context.spanId,
          parentSpanId: trace.context.parentSpanId,
          sourceId: trace.context.parentSpanId ?? trace.context.traceId,
          targetId: trace.target,
          kind: trace.operation,
          status: trace.status,
          startedAt: trace.startedAt,
          durationMicros: trace.duration.inMicroseconds,
          ownerComponentId: trace.context.targetComponentId,
        ),
    ],
    diagnostics: [
      for (final event in navigationFailures)
        CCDevToolsDiagnosticRecord(
          kind: 'failure',
          id: event.context.navigationId,
          status: event.recovered
              ? 'recoverySelected'
              : event.context.reason == CCNavigationFailureReason.cancelled
              ? 'cancelled'
              : 'failed',
          timestamp: event.timestamp,
          routeId: event.context.routeId,
          initialRouteId: event.context.initialRouteId,
          hostId: event.context.hostId,
          outlet: event.context.outlet,
          operation: event.context.operation.name,
          stage: event.context.stage.name,
          reason: event.context.reason.name,
          attempt: event.context.attempt.name,
          errorType: event.context.errorType,
          recoveryDepth: event.context.recoveryDepth,
          recoverySelected: event.recovered,
        ),
      for (final event in capabilityFallbacks)
        CCDevToolsDiagnosticRecord(
          kind: 'fallback',
          id: event.navigationId,
          status: 'fallbackSelected',
          timestamp: event.timestamp,
          routeId: event.routeId,
          hostId: event.hostId,
          outlet: event.navigatorOutlet,
          operation: event.operation.name,
          capability: event.capability.name,
          behavior: event.behavior.name,
        ),
      for (final pending in pendingNavigations)
        CCDevToolsDiagnosticRecord(
          kind: 'pending',
          id: pending.navigationId,
          status: 'pending',
          timestamp: pending.createdAt,
          expiresAt: pending.expiresAt,
          routeId: pending.routeId,
          hostId: pending.hostId,
          outlet: pending.outlet,
          operation: pending.operation.name,
          origin: pending.origin.name,
        ),
      for (final task in initTasks)
        CCDevToolsDiagnosticRecord(
          kind: 'initTask',
          id: task.id,
          status: task.state.name,
          ownerComponentId: task.ownerComponentId,
          gateId: task.gateId,
          failurePolicy: task.failurePolicy.name,
          blockedByTaskId: task.blockedByTaskId,
          errorType: task.errorType,
          durationMicros: task.duration?.inMicroseconds,
          dependsOn: task.dependsOn,
        ),
    ],
    diagnosticHealth: diagnosticHealth == null
        ? null
        : _protocolHealth(diagnosticHealth!),
  );
}

/// Copies fixed counters without leaking a Runtime, Sink, queue or payload.
CCDevToolsDiagnosticHealth _protocolHealth(CCDiagnosticSnapshot health) {
  final delivery = health.delivery;
  return CCDevToolsDiagnosticHealth(
    runtimeId: health.runtimeId,
    revision: health.revision,
    sinkConfigured: health.sinkConfigured,
    queueCapacity: delivery.queueCapacity,
    queued: delivery.queuedEventCount,
    inFlight: delivery.inFlightWriteCount,
    peakQueued: delivery.peakQueueDepth,
    delivered: delivery.deliveredEventCount,
    failed: delivery.failedEventCount,
    dropped: delivery.droppedEventCount,
    closed: delivery.isClosed,
    runtimeHealth: health.runtimeHealth == null
        ? null
        : CCDevToolsRuntimeHealth(
            activeRouteEntries: health.runtimeHealth!.activeRouteEntryCount,
            exitingRouteEntries: health.runtimeHealth!.exitingRouteEntryCount,
            pendingNavigations: health.runtimeHealth!.pendingNavigationCount,
            inFlightNavigations: health.runtimeHealth!.inFlightNavigationCount,
            trackedNavigationHosts:
                health.runtimeHealth!.trackedNavigationHostCount,
            activeBackendEntries: health.runtimeHealth!.activeBackendEntryCount,
            backendEntries: health.runtimeHealth!.backendEntryCount,
            desynchronizedBackendHosts:
                health.runtimeHealth!.desynchronizedBackendHostCount,
            observerQueueDepth: health.runtimeHealth!.observerQueueDepth,
            observerQueueCapacity: health.runtimeHealth!.observerQueueCapacity,
            navigationEvents: health.runtimeHealth!.navigationEventCount,
            routeEntryTransitions:
                health.runtimeHealth!.routeEntryTransitionCount,
            backendEvents: health.runtimeHealth!.backendEventCount,
            unattributedBackendEvents:
                health.runtimeHealth!.unattributedBackendEventCount,
          ),
    histories: health.histories.map(
      (history) => CCDevToolsHistoryStatus(
        name: history.name,
        capacity: history.capacity,
        retainedCount: history.retainedCount,
        omittedCount: history.omittedCount,
      ),
    ),
  );
}
