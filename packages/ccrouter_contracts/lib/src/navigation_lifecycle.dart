import 'navigation.dart';
import 'route_placement.dart';

/// Describes the Runtime phase reached by one navigation request.
///
/// Telemetry consumers can pair a [requested] event with a later [completed]
/// or [failed] event through [CCNavigationLifecycleEvent.navigationId].
enum CCNavigationLifecyclePhase {
  /// Runtime accepted the request for interception, coordination, or dispatch.
  ///
  /// A single-flight follower emits this phase while awaiting the admitted
  /// request and does not perform a second Adapter operation.
  requested,

  /// The requested operation or its shared single-flight result succeeded.
  completed,

  /// Runtime policy, an interceptor, the adapter, or the backend rejected it.
  failed,
}

/// Immutable, adapter-neutral lifecycle data for one Runtime navigation.
///
/// Use this contract for navigation telemetry, diagnostics, and latency
/// measurement. It describes the Runtime request boundary and does not expose
/// widget instances, backend Route objects, typed arguments, or Pop results.
final class CCNavigationLifecycleEvent {
  /// Creates one immutable lifecycle event.
  const CCNavigationLifecycleEvent({
    required this.navigationId,
    required this.phase,
    required this.operation,
    required this.routeId,
    required this.routePattern,
    required this.placement,
    required this.origin,
    required this.openMode,
    required this.timestamp,
    this.source,
    this.errorType,
  });

  /// Runtime-unique identifier shared by all phases of one request.
  final String navigationId;

  /// Request phase represented by this event.
  final CCNavigationLifecyclePhase phase;

  /// Stack operation dispatched to the navigation adapter.
  final CCNavigationOperation operation;

  /// Stable route contract ID selected by Runtime resolution.
  final String routeId;

  /// Canonical route template with parameter names but no parameter values.
  ///
  /// Use this for aggregation without exposing actual Path, Query, Fragment,
  /// or user-info values supplied to the navigation request.
  final String routePattern;

  /// Structural parent, Shell, and Navigator outlet for the route.
  final CCRoutePlacement placement;

  /// Trusted ingress classification attached by framework infrastructure.
  final CCNavigationOrigin origin;

  /// Stack behavior used by a dynamic Open request, or null otherwise.
  ///
  /// Telemetry can use this to compare Push and Go ingress outcomes without
  /// retaining the incoming URI or its parameters.
  final CCDeepLinkOpenMode? openMode;

  /// Product attribution used by telemetry, when supplied by the caller.
  final CCNavigationSource? source;

  /// Wall-clock time at which Runtime emitted this event.
  final DateTime timestamp;

  /// Sanitized adapter error type for a [CCNavigationLifecyclePhase.failed]
  /// event. The error message and arbitrary payload are intentionally omitted.
  final String? errorType;
}

/// Receives Runtime navigation lifecycle events.
///
/// Runtime delivers listeners in FIFO order on a later event-loop turn so
/// telemetry cannot block the accepted navigation call stack. Non-terminal
/// events may be dropped under queue pressure; `completed` and `failed` remain
/// lossless through explicit backpressure. Removing a listener before delivery
/// cancels its queued callbacks. Listeners must not start navigation from the
/// callback or asynchronous work spawned there; Runtime rejects both as
/// reentrant.
typedef CCNavigationLifecycleListener =
    void Function(CCNavigationLifecycleEvent event);
