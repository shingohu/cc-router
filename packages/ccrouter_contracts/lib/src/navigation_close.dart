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

/// Optional Host/Adapter SPI for removing one exact managed opening.
///
/// Runtime validates handle identity, target PopGuard, and result type first.
/// Implementations must atomically update their declarative and rendered state,
/// preserve covering entries and foreign Popups, and complete only the selected
/// result. Never fall back to Pop, a same-route entry, or an active Host. Return
/// unsupported if these guarantees cannot be upheld for this backend entry.
abstract interface class CCNavigationTargetedCloseAdapter {
  /// Closes the exact opening in its original Host and Navigator Outlet.
  Future<CCRouteCloseOutcome> closeNavigation({
    required String navigationId,
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  });
}
