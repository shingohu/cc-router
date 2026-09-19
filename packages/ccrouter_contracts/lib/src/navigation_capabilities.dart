/// Immutable capability declaration for one navigation backend.
///
/// Hosts use this snapshot during composition and diagnostics to understand
/// which backend semantics are available. A capability does not grant access
/// to the adapter or change business navigation APIs; Runtime integration may
/// use it later to reject unsupported requests or select an explicit fallback.
final class CCNavigationAdapterCapabilities {
  /// Creates a capability snapshot with conservative false defaults.
  const CCNavigationAdapterCapabilities({
    this.supportsForeignEntryObservation = false,
    this.supportsBackendEntryIdentity = false,
    this.supportsInitialStackSnapshot = false,
    this.supportsAtomicPopAndPush = false,
    this.supportsPushAndRemoveUntil = false,
    this.supportsNestedNavigators = false,
    this.supportsStatefulShell = false,
    this.supportsModalRoutes = false,
    this.supportsOpaqueUiObservation = false,
    this.supportsPredictiveBack = false,
    this.supportsManagedPopObservation = false,
    this.supportsExactEntryRemoval = false,
    this.supportsExactEntryReplacement = false,
  });

  /// Whether application-owned foreign Navigator Routes can be observed.
  ///
  /// This does not include arbitrary overlays or independent Navigators unless
  /// the adapter explicitly provides a corresponding bridge.
  final bool supportsForeignEntryObservation;

  /// Whether backend entries receive stable identities for lifecycle events.
  ///
  /// Without this capability, Runtime must not infer ownership from stack
  /// position after an uncorrelated backend event.
  final bool supportsBackendEntryIdentity;

  /// Whether the adapter can report its complete initial backend stack.
  ///
  /// A false value means pre-existing backend entries remain isolated until
  /// later events identify them.
  final bool supportsInitialStackSnapshot;

  /// Whether Pop and Push can preserve one composite operation contract.
  ///
  /// This includes the removed result and the new entry's result Future.
  final bool supportsAtomicPopAndPush;

  /// Whether Push followed by predicate-based removal preserves stack order.
  final bool supportsPushAndRemoveUntil;

  /// Whether the adapter can target nested Navigator Outlets.
  final bool supportsNestedNavigators;

  /// Whether the adapter can retain and address stateful Shell branches.
  final bool supportsStatefulShell;

  /// Whether route presentation contracts for Dialog and BottomSheet are kept.
  final bool supportsModalRoutes;

  /// Whether non-Route UI can be explicitly reported as opaque diagnostics.
  ///
  /// This does not turn an OverlayEntry, MenuAnchor, or LocalHistoryEntry into
  /// a CCRouter route or give it a typed result channel.
  final bool supportsOpaqueUiObservation;

  /// Whether the adapter participates in predictive-back coordination.
  final bool supportsPredictiveBack;

  /// Whether identity-bearing backend Pop events can close Managed RouteEntry.
  ///
  /// This is reserved for adapters that can distinguish an externally
  /// triggered Pop of a CCRouter-owned backend route from a Foreign Popup or
  /// LocalHistoryEntry. Without it, Runtime keeps backend events diagnostic.
  final bool supportsManagedPopObservation;

  /// Whether the Adapter can remove a managed backend Entry by stable identity.
  ///
  /// This is required for `CCRouter.navigator.removeRoute` and
  /// `removeRouteBelow`. False means Runtime must report a capability error;
  /// it must not emulate the operation by removing the stack top or by index.
  final bool supportsExactEntryRemoval;

  /// Whether the Adapter can replace an Entry below a stable anchor identity.
  ///
  /// False means Runtime must report a capability error instead of silently
  /// replacing a positionally guessed backend Entry.
  final bool supportsExactEntryReplacement;
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
