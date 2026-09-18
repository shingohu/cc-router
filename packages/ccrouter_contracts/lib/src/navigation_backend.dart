import 'navigation.dart';
import 'route_placement.dart';

/// Identifies who owns one backend navigation entry.
enum CCBackendEntryOwner {
  /// Entry created by CCRouter and associated with a managed RouteEntry.
  managed,

  /// Entry created by application or third-party navigation code.
  foreign,

  /// Entry identity exists, but ownership cannot be established reliably.
  opaque,
}

/// Describes the retained backend lifecycle state of one entry.
enum CCBackendEntryLifecycleState {
  /// Entry is currently present in the observed backend stack.
  active,

  /// Backend reported that the entry left its stack.
  removed,

  /// Backend identity was observed without a reliable lifecycle conclusion.
  unknown,
}

/// Identifies a stack transition observed from a navigation backend.
///
/// Backend events include transitions caused by user gestures, system back,
/// or application code that bypasses `CCRouter.navigator`.
enum CCNavigationBackendEventKind {
  /// A backend route was pushed.
  push,

  /// A backend route was popped.
  pop,

  /// A backend route was replaced.
  replace,

  /// A backend route was removed without becoming active.
  remove,
}

/// Immutable ledger entry for one backend Navigator route.
///
/// Runtime keeps this record separate from [CCRouteEntrySnapshot]. Foreign and
/// opaque entries can therefore be diagnosed without acquiring a Route Scope
/// or changing the CCRouter-managed navigation stack.
final class CCBackendEntry {
  /// Creates one immutable backend ledger entry.
  const CCBackendEntry({
    required this.backendEntryId,
    required this.owner,
    required this.lifecycleState,
    required this.navigatorOutlet,
    this.routeEntryId,
    this.routeId,
    this.hostId,
    this.location,
    this.lastSequence,
  });

  /// Stable identity assigned by the navigation adapter.
  final String backendEntryId;

  /// Ownership classification used to protect Managed Route Entries.
  final CCBackendEntryOwner owner;

  /// CCRouter RouteEntry identity when [owner] is [managed].
  final String? routeEntryId;

  /// Stable route contract ID when the backend supplied one.
  final String? routeId;

  /// Host or Window identity, when the adapter supports multiple hosts.
  final String? hostId;

  /// Navigator Outlet containing this backend entry.
  final String navigatorOutlet;

  /// Backend location or settings name, when available.
  final String? location;

  /// Current state in the backend ledger.
  final CCBackendEntryLifecycleState lifecycleState;

  /// Last adapter sequence observed for this entry.
  final int? lastSequence;
}

/// Immutable, backend-neutral observation of one Navigator stack transition.
///
/// Route metadata is nullable because an application may mutate its own
/// backend stack without first creating a CCRouter request. When the adapter
/// can correlate the transition, it supplies [navigationId], [routeId], URI,
/// placement, origin, and source from its internal RouteEntry.
final class CCNavigationBackendEvent {
  /// Creates one immutable backend lifecycle event.
  const CCNavigationBackendEvent({
    required this.kind,
    required this.timestamp,
    this.backendEntryId,
    this.backendOperationId,
    this.previousBackendEntryId,
    this.hostId,
    this.navigatorOutlet,
    this.sequence,
    this.owner,
    this.navigationId,
    this.routeId,
    this.uri,
    this.placement = const CCRoutePlacement.root(),
    this.location,
    this.origin,
    this.source,
  });

  /// Backend stack transition observed by the adapter.
  final CCNavigationBackendEventKind kind;

  /// Backend route identity affected by this transition, when available.
  final String? backendEntryId;

  /// Adapter operation identity used for duplicate-event suppression.
  final String? backendOperationId;

  /// Backend entry that preceded the affected entry, when known.
  final String? previousBackendEntryId;

  /// Host or Window identity associated with this event, when supported.
  final String? hostId;

  /// Navigator Outlet that emitted this event.
  final String? navigatorOutlet;

  /// Monotonic adapter sequence for this backend event.
  final int? sequence;

  /// Adapter ownership classification, when it can be established.
  final CCBackendEntryOwner? owner;

  /// Runtime navigation ID when this transition matched a tracked request.
  final String? navigationId;

  /// CCRouter route ID when this transition matched a tracked request.
  final String? routeId;

  /// Request URI when this transition matched a tracked request.
  final Uri? uri;

  /// Shell and Navigator outlet associated with the transition.
  final CCRoutePlacement placement;

  /// Backend route settings location, when the backend exposes one.
  final String? location;

  /// Trusted request origin when the transition matched a tracked request.
  final CCNavigationOrigin? origin;

  /// Product source when the transition matched a tracked request.
  final CCNavigationSource? source;

  /// Wall-clock time at which the adapter observed the transition.
  final DateTime timestamp;
}

/// Receives backend Navigator transition events from a navigation adapter.
///
/// Runtime hosts subscribe to this optional adapter capability. Implementations
/// should invoke listeners after the backend observer callback and must not
/// allow listener failures to alter backend navigation.
typedef CCNavigationBackendEventListener =
    void Function(CCNavigationBackendEvent event);

/// Optional adapter capability that exposes backend stack observations.
///
/// Core uses this interface without importing Flutter or another navigation
/// library. Adapters that cannot observe backend transitions may omit it.
abstract interface class CCNavigationBackendEventSource {
  /// Subscribes to backend stack events and returns a removal callback.
  void Function() addBackendEventListener(
    CCNavigationBackendEventListener listener,
  );
}
