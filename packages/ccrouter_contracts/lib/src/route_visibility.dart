import 'route_entry.dart';

/// Identifies a visibility transition for one managed Route Entry.
///
/// Visibility is independent from RouteEntry disposal: a covered or hidden
/// entry remains mounted and keeps its Route Scope until it is removed.
enum CCRouteVisibilityPhase {
  /// The entry is about to become visible in its Navigator Outlet.
  willShow,

  /// The entry has become visible in its Navigator Outlet.
  didShow,

  /// The entry is about to stop being visible in its Navigator Outlet.
  willHide,

  /// The entry is no longer visible, either because it was covered or removed.
  didHide,
}

/// Immutable observation of one Managed Route Entry visibility transition.
///
/// The snapshot is safe for telemetry and UI coordination; it never exposes a
/// Widget, BuildContext, Navigator, or mutable Route Scope. A `willShow` or
/// `willHide` snapshot describes the state before the corresponding transition;
/// a `didShow` or `didHide` snapshot describes the state after it. RouteEntry
/// disposal remains observable through [CCRouteEntryLifecycleEvent] instead of
/// being inferred from `didHide`.
final class CCRouteVisibilityEvent {
  /// Creates one immutable visibility observation.
  const CCRouteVisibilityEvent({
    required this.entry,
    required this.phase,
    required this.timestamp,
    this.reason,
  });

  /// Route Entry snapshot at the observation boundary.
  final CCRouteEntrySnapshot entry;

  /// Visibility phase represented by this event.
  final CCRouteVisibilityPhase phase;

  /// Wall-clock time at which Runtime emitted this event.
  final DateTime timestamp;

  /// Sanitized operation that caused the visibility transition, when known.
  final String? reason;
}

/// Receives managed Route Entry visibility observations.
///
/// Listeners should perform short, observational work and must not synchronously
/// start another navigation from inside the callback. Listener failures are
/// isolated from Runtime transitions.
typedef CCRouteVisibilityListener = void Function(CCRouteVisibilityEvent event);
