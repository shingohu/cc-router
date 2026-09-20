import 'navigation.dart';
import 'navigation_telemetry.dart';
import 'route_entry.dart';
import 'route_placement.dart';
import 'route_presentation.dart';

/// Identifies the observation hook reached by a navigation request.
enum CCNavigationAspectPhase {
  /// The route matched and passed the Runtime's basic request validation.
  found,

  /// A managed Route Entry became the visible destination in its Outlet.
  arrival,

  /// A previously hidden managed Route Entry became current again.
  show,

  /// A managed Route Entry remained mounted but stopped being current.
  hide,

  /// A managed Route Entry left its backend navigation structure.
  removed,

  /// Runtime finished disposing the managed Route Entry Scope.
  disposed,

  /// Navigation did not reach its requested destination.
  lost,

  /// The navigation operation reached a terminal success or failure state.
  after,
}

/// Describes the terminal result reported by the [after] aspect hook.
enum CCNavigationAspectOutcome {
  /// The Adapter operation and, for result-bearing navigation, its result
  /// channel completed successfully.
  succeeded,

  /// Runtime or the Adapter rejected the operation.
  failed,

  /// A navigation interceptor deliberately stopped the operation.
  cancelled,
}

/// Sanitized request data supplied to a [CCNavigationAspect].
///
/// This snapshot intentionally omits typed arguments and `extra` payloads.
/// Use it for routing policy, diagnostics, and telemetry without retaining
/// application objects or sensitive navigation data.
final class CCNavigationAspectRequest {
  /// Creates an immutable aspect request snapshot.
  CCNavigationAspectRequest({
    required this.navigationId,
    required this.operation,
    required this.routeId,
    required this.routePattern,
    required this.resolvedHostId,
    required this.navigatorOutlet,
    required this.ownerComponentId,
    required this.placement,
    required this.origin,
    required this.openMode,
    required this.source,
    required this.presentation,
    this.referrerRouteId,
    this.telemetryContext,
    List<String> redirectChain = const [],
  }) : redirectChain = List.unmodifiable(redirectChain);

  /// Runtime-unique identity shared by all hooks for one navigation.
  final String navigationId;

  /// Stack operation requested by the caller.
  final CCNavigationOperation operation;

  /// Stable route contract selected by Runtime resolution.
  final String routeId;

  /// Canonical route template with parameter names but no parameter values.
  final String routePattern;

  /// Concrete navigation Host selected for this request.
  ///
  /// Unlike [placement], this value never contains the unresolved `default`
  /// alias after Runtime request construction.
  final String resolvedHostId;

  /// Navigator Outlet selected inside [resolvedHostId].
  final String navigatorOutlet;

  /// Trusted component that registered the resolved route definition.
  final String ownerComponentId;

  /// Best-known managed route that referred into this navigation.
  ///
  /// Runtime derives this from the current visible managed Entry. The value is
  /// null when navigation originated outside an observed managed stack or when
  /// no deterministic referrer exists.
  final String? referrerRouteId;

  /// Route IDs visited by interceptor redirects and failure recovery.
  ///
  /// Values contain contract identities only and never URI parameters.
  final List<String> redirectChain;

  /// Shell, parent, and Navigator Outlet placement for the route.
  final CCRoutePlacement placement;

  /// Trusted ingress origin attached by framework infrastructure.
  final CCNavigationOrigin origin;

  /// Stack behavior selected for a dynamic Open request.
  ///
  /// This is null for typed Push, Replace, Go, and Reset operations. Use it to
  /// distinguish an external link layered above the current page from one that
  /// rebuilt the Host's declarative location without inspecting URI payloads.
  final CCDeepLinkOpenMode? openMode;

  /// Product attribution supplied by the caller, when available.
  final CCNavigationSource? source;

  /// Adapter-neutral presentation contract of the destination.
  final CCRoutePresentation presentation;

  /// Anonymous Host telemetry captured when this navigation started.
  final CCNavigationTelemetryContext? telemetryContext;
}

/// Cumulative stage durations captured for one navigation observation.
///
/// A null stage has not happened or cannot be observed reliably. Durations are
/// monotonic within one Runtime process and never include route parameters or
/// arbitrary application payloads.
final class CCNavigationAspectTiming {
  /// Creates one immutable timing snapshot.
  const CCNavigationAspectTiming({
    this.resolve,
    this.intercept,
    this.dispatch,
    this.arrival,
    this.stay,
    this.total,
  });

  /// Time spent synchronously resolving and decoding route targets.
  final Duration? resolve;

  /// Cumulative time spent awaiting global and route interceptors.
  final Duration? intercept;

  /// Time spent entering the Adapter until synchronous acceptance returned.
  final Duration? dispatch;

  /// Time from navigation start until the first confirmed visible state.
  final Duration? arrival;

  /// Cumulative time for which the managed Entry was current in its Outlet.
  final Duration? stay;

  /// Time from navigation start until this observation was created.
  final Duration? total;
}

/// Immutable event delivered to one navigation aspect hook.
///
/// [entry] is present for managed Entry phases from Arrival through Disposed.
/// [outcome] is present for Lost and After. Errors contain only a stable runtime
/// type, never an arbitrary exception message or payload.
final class CCNavigationAspectEvent {
  /// Creates one sanitized aspect event.
  const CCNavigationAspectEvent({
    required this.phase,
    required this.request,
    required this.timestamp,
    this.entry,
    this.outcome,
    this.errorType,
    this.elapsed,
    this.timing,
  });

  /// Hook phase represented by this event.
  final CCNavigationAspectPhase phase;

  /// Sanitized request identity and route metadata.
  final CCNavigationAspectRequest request;

  /// Managed Route Entry associated with an Entry lifecycle observation.
  final CCRouteEntrySnapshot? entry;

  /// Terminal operation outcome, when this is an after event.
  final CCNavigationAspectOutcome? outcome;

  /// Sanitized error type for lost or failed navigation.
  final String? errorType;

  /// Time spent from the first route match until this observation.
  ///
  /// This value is suitable for local performance metrics and is not a Widget
  /// lifetime measurement.
  final Duration? elapsed;

  /// Stage-specific performance snapshot for this observation.
  ///
  /// Prefer this field over [elapsed] when distinguishing framework work from
  /// page stay time. [elapsed] remains the total duration for compatibility.
  final CCNavigationAspectTiming? timing;

  /// Wall-clock time at which Runtime dispatched this event.
  final DateTime timestamp;
}

/// Observation callback used by the non-decision aspect hooks.
typedef CCNavigationAspectObserver =
    void Function(CCNavigationAspectEvent event);

/// One named global navigation observation registration.
///
/// Use this for diagnostics, exposure tracking, performance metrics, and
/// failure observation. Aspects never influence navigation decisions; use a
/// [CCGlobalNavigationInterceptor] or route interceptor for cancellation and
/// redirection. Runtime dispatches hooks in FIFO order on a later event-loop
/// turn; non-terminal hooks may be dropped under queue pressure while terminal
/// hooks remain lossless through explicit backpressure. Observation callbacks
/// must return quickly and must not start navigation directly or from
/// asynchronous work spawned by the callback.
final class CCNavigationAspect {
  /// Creates a named aspect with optional observation hooks.
  const CCNavigationAspect({
    required this.id,
    this.onFound,
    this.onArrival,
    this.onShow,
    this.onHide,
    this.onRemoved,
    this.onDisposed,
    this.onLost,
    this.onAfter,
  });

  /// Stable identifier used for deterministic aspect ordering.
  final String id;

  /// Called after a route has matched and before Adapter dispatch.
  final CCNavigationAspectObserver? onFound;

  /// Called when a managed Route Entry enters the visible state.
  final CCNavigationAspectObserver? onArrival;

  /// Called when a hidden managed Entry becomes current again.
  ///
  /// Analytics integrations normally count both Arrival and Show as page-view
  /// opportunities, while deduplicating according to their own product rules.
  final CCNavigationAspectObserver? onShow;

  /// Called when a managed Entry becomes hidden but remains alive.
  final CCNavigationAspectObserver? onHide;

  /// Called when a managed Entry permanently leaves navigation structure.
  final CCNavigationAspectObserver? onRemoved;

  /// Called after Runtime finishes disposing the Entry's Route Scope.
  final CCNavigationAspectObserver? onDisposed;

  /// Called when a request is cancelled or fails before reaching its target.
  final CCNavigationAspectObserver? onLost;

  /// Called after a request reaches a terminal success, failure, or cancel.
  final CCNavigationAspectObserver? onAfter;
}
