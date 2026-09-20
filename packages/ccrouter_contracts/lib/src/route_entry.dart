import 'navigation.dart';
import 'route_placement.dart';

/// Describes the lifecycle of one concrete navigation entry.
///
/// A Route ID identifies a destination contract; this state belongs to one
/// individual opening of that destination and therefore has its own result and
/// Route Scope. Hidden entries remain alive until they leave the navigation
/// structure permanently.
enum CCRouteEntryLifecycleState {
  /// Entry identity has been allocated but resolution has not started.
  created,

  /// Runtime is resolving and validating the destination.
  resolving,

  /// Adapter accepted the entry into a navigation structure.
  pushed,

  /// Entry is the active visible destination in its Outlet.
  visible,

  /// Entry remains mounted but is not the active destination.
  hidden,

  /// Entry removal has started and its result channel is closing.
  popping,

  /// Entry has left the navigation structure.
  removed,

  /// Route Scope disposal has completed.
  disposed,
}

/// Immutable adapter-neutral snapshot of one concrete Route Entry.
///
/// This value is suitable for diagnostics, predicates, and Adapter SPI
/// integrations. It does not expose the mutable Route Scope or a backend
/// `Route`/`Navigator` object.
final class CCRouteEntrySnapshot {
  /// Creates a snapshot for one Route Entry state.
  const CCRouteEntrySnapshot({
    required this.routeEntryId,
    required this.navigationId,
    required this.routeId,
    required this.ownerComponentId,
    required this.hostId,
    required this.normalizedUri,
    required this.placement,
    required this.origin,
    required this.lifecycleState,
  });

  /// Stable identity for this one opening of a route.
  final String routeEntryId;

  /// Navigation request identity that created this entry.
  final String navigationId;

  /// Stable destination contract ID.
  final String routeId;

  /// Trusted component that owns the destination contract.
  final String ownerComponentId;

  /// Concrete navigation Host that owns this Entry instance.
  ///
  /// Unlike [placement], this value has already resolved the `default` alias
  /// and is therefore safe for multi-Host isolation and diagnostics.
  final String hostId;

  /// Canonical or normalized URI used to create this entry.
  final Uri normalizedUri;

  /// Shell, parent, and Navigator Outlet placement for this entry.
  final CCRoutePlacement placement;

  /// Trusted ingress origin attached to the navigation request.
  final CCNavigationOrigin origin;

  /// Current lifecycle state of this entry.
  final CCRouteEntryLifecycleState lifecycleState;
}

/// Records one Route Entry lifecycle transition.
///
/// Use this for diagnostics, test assertions, and sanitized telemetry. Scope
/// disposal failures remain isolated from navigation and are represented by
/// the final `disposed` transition rather than exposing service instances.
final class CCRouteEntryLifecycleEvent {
  /// Creates one immutable lifecycle transition event.
  const CCRouteEntryLifecycleEvent({
    required this.entry,
    required this.previousState,
    required this.timestamp,
    this.reason,
  });

  /// Entry snapshot after this transition.
  final CCRouteEntrySnapshot entry;

  /// State before the transition, or null for the first `created` event.
  final CCRouteEntryLifecycleState? previousState;

  /// Wall-clock time at which Runtime recorded this transition.
  final DateTime timestamp;

  /// Sanitized lifecycle reason, when the transition was caused by an
  /// operation such as `pop`, `replace`, `reset`, or Runtime disposal.
  final String? reason;
}

/// Receives Route Entry lifecycle transitions.
typedef CCRouteEntryLifecycleListener =
    void Function(CCRouteEntryLifecycleEvent event);
