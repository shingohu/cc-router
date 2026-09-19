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

/// Identifies which kind of backend entry consumed a Pop request.
enum CCPopRemovedOwner {
  /// No backend entry was confirmed as removed.
  none,

  /// A CCRouter-managed backend entry was removed.
  managed,

  /// An application-owned or third-party backend entry was removed.
  foreign,

  /// An entry was removed but its ownership could not be established.
  opaque,
}

/// Identifies the trigger that entered the ownership-aware Pop pipeline.
///
/// System back and ordinary gestures use [system] or [gesture] respectively;
/// platform predictive back uses [predictiveBack]; direct business calls use
/// [business]. [unknown] is retained for legacy adapters that only return a
/// Boolean or an untagged [CCPopOutcome].
enum CCPopTrigger {
  /// The operating system requested a normal back operation.
  system,

  /// A non-predictive interactive gesture requested a back operation.
  gesture,

  /// A committed platform predictive-back gesture removed the backend entry.
  predictiveBack,

  /// Business code explicitly called `CCRouter.navigator.pop`.
  business,

  /// The adapter did not identify the source of the Pop.
  unknown,
}

/// Adapter-neutral result of one coordinated Pop request.
///
/// A handled Pop can still represent a `LocalHistoryEntry` or foreign Popup;
/// callers must only close a CCRouter Route Scope when [removedOwner] is
/// [CCPopRemovedOwner.managed]. [resultAvailable] is true only when the
/// adapter can associate the Pop with a managed result channel; it does not
/// embed or expose the result value itself.
final class CCPopOutcome {
  /// Creates a Pop result with explicit ownership and result-channel state.
  const CCPopOutcome({
    required this.handled,
    this.removedBackendEntryId,
    this.removedOwner = CCPopRemovedOwner.none,
    this.resultAvailable = false,
    this.trigger = CCPopTrigger.unknown,
  });

  /// Whether the backend accepted or consumed the Pop request.
  final bool handled;

  /// Backend identity removed by the Pop, when the adapter could correlate it.
  final String? removedBackendEntryId;

  /// Ownership of the backend entry removed by the Pop.
  final CCPopRemovedOwner removedOwner;

  /// Whether the adapter can provide a result for the removed entry.
  final bool resultAvailable;

  /// Trigger that entered the Pop coordination pipeline.
  final CCPopTrigger trigger;

  /// Returns this outcome with selected diagnostic fields replaced.
  ///
  /// Runtime uses this to attach a trusted trigger when an older Adapter
  /// returns an otherwise complete outcome without source metadata.
  CCPopOutcome copyWith({CCPopTrigger? trigger}) => CCPopOutcome(
    handled: handled,
    removedBackendEntryId: removedBackendEntryId,
    removedOwner: removedOwner,
    resultAvailable: resultAvailable,
    trigger: trigger ?? this.trigger,
  );
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

/// Immutable active backend entry reported during adapter initialization.
///
/// A snapshot describes entries that already exist before Runtime starts
/// observing transitions. It is diagnostic state only: even a `managed`
/// snapshot does not create a CCRouter RouteEntry or Route Scope without a
/// matching Runtime navigation identity.
final class CCNavigationBackendEntrySnapshot {
  /// Creates one active backend snapshot entry.
  const CCNavigationBackendEntrySnapshot({
    required this.backendEntryId,
    required this.owner,
    required this.navigatorOutlet,
    this.routeEntryId,
    this.routeId,
    this.hostId,
    this.location,
    this.sequence,
  });

  /// Stable identity assigned by the backend before Runtime initialization.
  final String backendEntryId;

  /// Backend ownership classification known at snapshot time.
  final CCBackendEntryOwner owner;

  /// Navigator Outlet containing this backend entry.
  final String navigatorOutlet;

  /// Optional matching CCRouter RouteEntry identity from state restoration.
  final String? routeEntryId;

  /// Optional stable CCRouter route ID supplied by the backend.
  final String? routeId;

  /// Optional Window or display host identity.
  final String? hostId;

  /// Optional backend location or settings name.
  final String? location;

  /// Backend sequence associated with this snapshot, when available.
  final int? sequence;
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

/// Identifies one phase of a platform predictive-back gesture.
enum CCPredictiveBackPhase {
  /// The platform began an interactive back gesture.
  started,

  /// The platform updated the gesture progress without committing a Pop.
  updated,

  /// The platform committed the Pop after the gesture crossed its threshold.
  committed,

  /// The platform cancelled the gesture and restored the current route.
  cancelled,
}

/// Adapter-neutral observation of one predictive-back gesture phase.
final class CCPredictiveBackEvent {
  /// Creates an immutable predictive-back phase event.
  const CCPredictiveBackEvent({
    required this.phase,
    required this.timestamp,
    this.progress = 0,
    this.outcome,
  }) : assert(progress >= 0 && progress <= 1);

  /// Gesture phase reported by the platform adapter.
  final CCPredictiveBackPhase phase;

  /// Normalized gesture progress in the inclusive range 0..1.
  final double progress;

  /// Ownership-aware result supplied when [phase] is [committed].
  final CCPopOutcome? outcome;

  /// Wall-clock time at which the adapter observed this phase.
  final DateTime timestamp;
}

/// Receives predictive-back phase events from a navigation adapter.
typedef CCPredictiveBackEventListener =
    void Function(CCPredictiveBackEvent event);

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

/// Optional Adapter SPI for platform predictive-back coordination.
///
/// Implementations must emit a committed event only after the backend has
/// removed the route and can provide a [CCPopOutcome]. Runtime deliberately
/// ignores started, updated, and cancelled phases for Route Scope teardown.
abstract interface class CCNavigationPredictiveBackSource {
  /// Subscribes to predictive-back phases and returns a removal callback.
  void Function() addPredictiveBackListener(
    CCPredictiveBackEventListener listener,
  );
}

/// Optional Adapter SPI that exposes a predictive-back source only when the
/// host explicitly enables platform integration.
///
/// This provider keeps adapters that cannot participate in predictive back
/// conservative by default while allowing a composition root to opt in to a
/// host-owned bridge.
abstract interface class CCNavigationPredictiveBackSourceProvider {
  /// Active predictive-back source, or null when the feature is disabled.
  CCNavigationPredictiveBackSource? get predictiveBackSource;
}

/// Optional Adapter SPI exposing the initial backend stack.
///
/// Implementations call this after [CCNavigationAdapter.initialize] has
/// accepted route metadata. Runtime records the result in its Backend Entry
/// ledger before accepting navigation, while keeping the snapshot separate
/// from transition events and managed RouteEntry lifecycle.
abstract interface class CCNavigationBackendSnapshotSource {
  /// Reads active backend entries that predate Runtime event observation.
  Future<List<CCNavigationBackendEntrySnapshot>> readInitialBackendSnapshot();
}

/// Optional Adapter SPI that provides ownership-aware Pop outcomes.
///
/// Older adapters may implement only [CCNavigationAdapter.maybePop]; Runtime
/// then preserves compatibility by converting its Boolean result into an
/// outcome whose removed owner is [CCPopRemovedOwner.none].
abstract interface class CCNavigationPopCoordinator {
  /// Coordinates one Pop and returns the removed backend Entry ownership.
  Future<CCPopOutcome> maybePopOutcome({Object? result});

  /// Executes an explicit business Pop and returns the removed ownership.
  ///
  /// Unlike [maybePopOutcome], this operation is initiated by
  /// `CCRouter.navigator.pop`. Adapters must report a foreign or opaque entry
  /// without allowing Runtime to close the underlying managed Route Entry.
  /// Returning `handled: false` preserves the adapter's normal root-Pop
  /// rejection semantics.
  CCPopOutcome popOutcome({Object? result});
}

/// Optional Adapter SPI for exact removal of CCRouter-managed backend Entries.
///
/// Runtime calls this only after validating a [CCRouteEntryHandle] against its
/// own live Entry ledger. Implementations must use [navigationId] and the
/// optional [backendEntryId] as identity, never stack position. A backend that
/// cannot preserve this contract must omit the SPI and report the corresponding
/// capability as unsupported; Runtime will then fail explicitly instead of
/// guessing which page to remove.
abstract interface class CCNavigationExactEntryRemoval {
  /// Removes exactly the managed Entry identified by [navigationId].
  ///
  /// [backendEntryId] is supplied when the backend ledger has a stable identity.
  /// The operation must complete only after the backend accepted the removal.
  /// It must not remove foreign, opaque, or unrelated backend Entries.
  Future<void> removeManagedEntry({
    required String navigationId,
    String? backendEntryId,
  });

  /// Removes managed Entries below the exact target identified by [navigationId].
  ///
  /// The target itself remains in the backend. Entries owned by foreign or
  /// opaque navigation systems must remain untouched even when they appear
  /// between managed Entries.
  Future<void> removeManagedEntriesBelow({
    required String navigationId,
    String? backendEntryId,
  });
}
