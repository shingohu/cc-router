/// Non-sensitive identity for one managed route opening.
///
/// Runtime-issued handles are matched by object identity, never by route ID or
/// stack position. Retaining a handle retains no Runtime, Scope, payload,
/// Flutter Route, or BuildContext. Constructed or expired handles cannot close
/// another entry, including after Runtime replacement.
final class CCRouteEntryHandle {
  /// Creates an unbound identity; only Runtime-issued instances are accepted.
  CCRouteEntryHandle(this.routeEntryId);

  /// Sanitized identifier suitable for correlating entry diagnostics.
  final String routeEntryId;
}

/// Terminal outcome of a request to close one exact managed entry.
enum CCRouteCloseStatus {
  /// The exact backend entry was removed and its result channel completed.
  closed,

  /// The handle or its exact backend entry is no longer retained.
  notFound,

  /// This adapter or this backend entry cannot be removed safely in isolation.
  unsupported,

  /// A target-specific managed PopGuard rejected the close.
  guardDenied,
}

/// Reports targeted close without implying a change to the active stack.
final class CCRouteCloseOutcome {
  /// Creates an immutable outcome containing no business result or backend.
  const CCRouteCloseOutcome(this.status, {this.guardDeniedCode});

  /// Whether the exact requested entry was removed, missing, or rejected.
  final CCRouteCloseStatus status;

  /// Stable managed guard denial code; present only for [CCRouteCloseStatus.guardDenied].
  final String? guardDeniedCode;
}

/// Terminal status returned when an existing managed Entry is activated.
enum CCRouteActivationStatus {
  /// The target remained active and matching covering Entries were removed.
  activated,

  /// The exact target or one of the expected covering Entries is no longer active.
  notFound,

  /// The backend cannot remove the selected covering Entries atomically.
  unsupported,

  /// A PopGuard on a covering Entry rejected the activation.
  guardDenied,

  /// The backend observed a concurrent stack change and made no removal.
  conflict,
}

/// Reports activation of one exact existing Entry without recreating it.
final class CCRouteActivationOutcome {
  /// Creates an immutable activation receipt.
  const CCRouteActivationOutcome(this.status, {this.guardDeniedCode});

  /// Whether the target was activated, rejected, or unavailable.
  final CCRouteActivationStatus status;

  /// Stable managed guard denial code for [CCRouteActivationStatus.guardDenied].
  final String? guardDeniedCode;
}

/// Optional Host/Adapter SPI for removing one exact managed opening.
///
/// Runtime validates handle identity, target PopGuard, and result type first.
/// Implementations must atomically update their declarative and rendered state,
/// preserve covering entries and foreign Popups, and complete only the selected
/// result. Never fall back to Pop, a same-route entry, or an active Host. Return
/// unsupported if these guarantees cannot be upheld for this backend entry.
abstract interface class CCNavigationTargetedCloseAdapter {
  /// Closes the exact opening in its original Host and Navigator Outlet.
  /// Runtime dispatches and observes in its Host Zone. If the exact Entry,
  /// Host or Runtime ends while external work remains pending, the caller
  /// receives [CCRouteCloseStatus.notFound]; late completion is consumed.
  /// Completing exact transactions retain their actual receipt. This does not
  /// cancel Adapter-owned external tasks or wait for an outgoing Flutter frame.
  Future<CCRouteCloseOutcome> closeNavigation({
    required String navigationId,
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  });
}

/// Optional Host SPI for returning to one exact managed Entry.
///
/// Runtime supplies the exact covering identities after preflighting their
/// PopGuards. Implementations must verify that the target and every expected
/// covering identity still form the same partition, then remove exactly those
/// coverings as one backend transaction. They must not recreate the target,
/// infer a route by ID or stack position, or remove a concurrently inserted
/// Entry. Older adapters return [CCRouteActivationStatus.unsupported] through
/// Runtime.
abstract interface class CCNavigationActivateExistingAdapter {
  /// Removes the expected covering Entries while retaining the target Entry.
  Future<CCRouteActivationOutcome> activateExistingNavigation({
    required String targetNavigationId,
    required String hostId,
    required String navigatorOutlet,
    required List<String> expectedRemovalNavigationIds,
  });
}
