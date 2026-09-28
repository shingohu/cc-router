import 'package:ccrouter/ccrouter.dart';

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
    List<CCComponentManifest> components = const [],
    List<CCRouteEntrySnapshot> routeEntries = const [],
    List<CCBackendEntrySnapshot> backendEntries = const [],
    List<CCTraceRecord> traces = const [],
    List<CCNavigationLifecycleEvent> navigationEvents = const [],
    List<CCNavigationFailureEvent> navigationFailures = const [],
    List<CCNavigationCapabilityFallbackEvent> capabilityFallbacks = const [],
    List<CCRouteVisibilityEvent> visibilityEvents = const [],
    List<CCNavigationBackendDiagnosticEvent> backendEvents = const [],
    List<CCInitializationTaskSnapshot> initializationTasks = const [],
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
       initializationTasks = List.unmodifiable(initializationTasks),
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
  final List<CCInitializationTaskSnapshot> initializationTasks;

  /// Navigation requests waiting for an external policy decision.
  final List<CCPendingNavigation> pendingNavigations;

  /// Bounded evidence of unsupported restoration demand.
  final List<CCRouteRestorationOpportunityEvent> restorationOpportunities;
}
