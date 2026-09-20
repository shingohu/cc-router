/// Immutable capability declaration for one navigation backend.
///
/// Hosts use this snapshot during composition and diagnostics to understand
/// which backend semantics are available. A capability does not grant access
/// to the adapter or change business navigation APIs; Runtime integration may
/// use it later to reject unsupported requests or select an explicit fallback.
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
