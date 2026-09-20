import 'navigation.dart';

/// Immutable capability declaration for one navigation backend.
///
/// Hosts use this snapshot during composition and diagnostics to understand
/// which backend semantics are available. A capability does not grant access
/// to the adapter or change business navigation APIs. Runtime rejects static
/// structures whose semantics cannot be preserved and records an explicit
/// fallback event when a documented safe behavior is selected.
final class CCNavigationAdapterCapabilities {
  /// Creates a capability snapshot with conservative false defaults.
  const CCNavigationAdapterCapabilities({
    this.supportsBackendVisibilityObservation = false,
    this.supportsNestedNavigators = false,
    this.supportsStatefulShell = false,
    this.supportsModalRoutes = false,
    this.supportsPredictiveBack = false,
    this.supportsManagedPopObservation = false,
  });

  /// Whether the Adapter confirms the current Entry for every managed Outlet.
  ///
  /// Runtime delays `visible` and `arrival` lifecycle events only when this is
  /// true. Adapters should declare it only when all registered managed routes
  /// are covered by a reliable top-route callback; partial observer coverage
  /// must remain false so unobserved pages do not stay indefinitely pending.
  final bool supportsBackendVisibilityObservation;

  /// Whether the adapter can target nested Navigator Outlets.
  final bool supportsNestedNavigators;

  /// Whether the adapter can retain and address stateful Shell branches.
  final bool supportsStatefulShell;

  /// Whether route presentation contracts for Dialog and BottomSheet are kept.
  final bool supportsModalRoutes;

  /// Whether the adapter participates in predictive-back coordination.
  final bool supportsPredictiveBack;

  /// Whether identity-bearing backend Pop events can close Managed RouteEntry.
  ///
  /// This is reserved for adapters that can distinguish an externally
  /// triggered Pop of a CCRouter-owned backend route from a Foreign Popup or
  /// LocalHistoryEntry. Without it, Runtime keeps backend events diagnostic.
  final bool supportsManagedPopObservation;
}

/// Optional adapter SPI exposing immutable backend capability metadata.
///
/// This interface is deliberately additive: older adapters may omit it and
/// are treated as having unknown or conservative capabilities. Hosts should
/// inspect it during setup or diagnostics rather than cast business-facing
/// navigation objects throughout application code.
abstract interface class CCNavigationAdapterCapabilitySource {
  /// Backend capabilities declared by the adapter implementation.
  CCNavigationAdapterCapabilities get capabilities;
}

/// Optional Adapter SPI exposing capabilities for one concrete Host.
///
/// Composite multi-Host adapters use this when child backends differ. Runtime prefers
/// this query for request-scoped behavior such as confirmed visibility, while
/// [CCNavigationAdapterCapabilitySource.capabilities] remains the conservative
/// aggregate used during static route-table validation.
abstract interface class CCNavigationHostCapabilitySource {
  /// Returns capabilities for [hostId], or null when that Host is unavailable.
  CCNavigationAdapterCapabilities? capabilitiesForHost(String hostId);
}

/// Identifies an optional backend capability whose absence selected a fallback.
///
/// These values describe behavior differences that preserve navigation safety;
/// unsupported route structures that cannot preserve semantics still fail
/// Adapter initialization instead of producing a fallback event.
enum CCNavigationCapabilityType {
  /// Exact backend callbacks cannot confirm the current managed Route Entry.
  backendVisibilityObservation,

  /// Exact backend callbacks cannot confirm managed Route Entry removals.
  managedPopObservation,
}

/// Identifies the safe Runtime behavior selected for a missing capability.
enum CCNavigationCapabilityFallbackBehavior {
  /// Runtime marks the committed managed Entry visible immediately.
  ///
  /// This preserves usable page lifecycle for adapters without complete
  /// Navigator observer coverage, but it cannot prove backend arrival timing.
  runtimeCommitVisibility,

  /// Runtime reconciles only the target Host and Outlet partition.
  ///
  /// This is used for declarative Go operations when the backend cannot report
  /// exact managed removals. Other Hosts, panes, and Shell Outlets are retained.
  partitionLocalReconciliation,
}

/// Sanitized record of one navigation that used a capability fallback.
///
/// Use this event to measure real fallback usage before requiring stronger
/// Adapter integration. It intentionally contains no URI, Path/Query values,
/// typed arguments, `extra`, backend Route object, or Pop result.
final class CCNavigationCapabilityFallbackEvent {
  /// Creates an immutable capability fallback observation.
  const CCNavigationCapabilityFallbackEvent({
    required this.navigationId,
    required this.operation,
    required this.routeId,
    required this.hostId,
    required this.navigatorOutlet,
    required this.capability,
    required this.behavior,
    required this.timestamp,
  });

  /// Runtime navigation identity shared with other sanitized diagnostics.
  final String navigationId;

  /// Stack operation whose execution required the fallback.
  final CCNavigationOperation operation;

  /// Stable route contract identity without concrete address values.
  final String routeId;

  /// Concrete Host whose backend capability was unavailable.
  final String hostId;

  /// Navigator Outlet isolated by the fallback behavior.
  final String navigatorOutlet;

  /// Optional backend capability that was unavailable.
  final CCNavigationCapabilityType capability;

  /// Safe behavior selected instead of the unavailable capability.
  final CCNavigationCapabilityFallbackBehavior behavior;

  /// Wall-clock time at which Runtime selected the fallback.
  final DateTime timestamp;
}

/// Receives sanitized capability fallback observations.
///
/// Runtime delivers callbacks in FIFO order on a later event-loop turn. These
/// non-terminal diagnostics may be dropped under observer queue pressure;
/// listeners must not start navigation or alter the selected fallback.
typedef CCNavigationCapabilityFallbackListener =
    void Function(CCNavigationCapabilityFallbackEvent event);
