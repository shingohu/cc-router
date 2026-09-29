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
final class CCDevToolsSnapshot {
  /// Creates a diagnostics snapshot from safe CCRouter values.
  CCDevToolsSnapshot({
    required this.capturedAt,
    required this.runtimeState,
    this.catalog,
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
    List<CCRouteRestorationOpportunityEvent> restorationOpportunities =
        const [],
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
       pendingNavigations = List.unmodifiable(pendingNavigations),
       restorationOpportunities = List.unmodifiable(restorationOpportunities);

  /// Creates an empty snapshot used when a Host has no active Runtime.
  factory CCDevToolsSnapshot.empty({
    CCDevToolsRuntimeState runtimeState = CCDevToolsRuntimeState.uninitialized,
  }) => CCDevToolsSnapshot(
    capturedAt: DateTime.now(),
    runtimeState: runtimeState,
  );

  /// Wall-clock time at which this immutable view was assembled.
  final DateTime capturedAt;

  /// Runtime availability at capture time.
  final CCDevToolsRuntimeState runtimeState;

  /// Optional generated static source index linked by stable capability IDs.
  final CCDevToolsStaticCatalogSnapshot? catalog;

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

  /// Bounded evidence of unsupported restoration demand.
  final List<CCRouteRestorationOpportunityEvent> restorationOpportunities;

  /// Converts this widget-facing view into the versioned tooling protocol.
  ///
  /// The conversion copies only stable identities, lifecycle states, Host and
  /// Outlet placement, and bounded trace timing. It intentionally omits route
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
  );
}
