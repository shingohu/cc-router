import 'dart:async';

import 'invocation.dart';
import 'navigation.dart';
import 'navigation_interceptor.dart';
import 'route_entry.dart';
import 'route_placement.dart';
import 'route_presentation.dart';

/// Identifies the observation hook reached by a navigation request.
enum CCNavigationAspectPhase {
  /// The route matched and passed the Runtime's basic request validation.
  found,

  /// A managed Route Entry became the visible destination in its Outlet.
  arrival,

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
  const CCNavigationAspectRequest({
    required this.navigationId,
    required this.operation,
    required this.routeId,
    required this.uri,
    required this.placement,
    required this.origin,
    required this.source,
    required this.presentation,
  });

  /// Runtime-unique identity shared by all hooks for one navigation.
  final String navigationId;

  /// Stack operation requested by the caller.
  final CCNavigationOperation operation;

  /// Stable route contract selected by Runtime resolution.
  final String routeId;

  /// Canonical or normalized URI selected by Runtime resolution.
  final Uri uri;

  /// Shell, parent, and Navigator Outlet placement for the route.
  final CCRoutePlacement placement;

  /// Trusted ingress origin attached by framework infrastructure.
  final CCNavigationOrigin origin;

  /// Product attribution supplied by the caller, when available.
  final CCNavigationSource? source;

  /// Adapter-neutral presentation contract of the destination.
  final CCRoutePresentation presentation;
}

/// Immutable event delivered to one navigation aspect hook.
///
/// [entry] is present for [CCNavigationAspectPhase.arrival]. [outcome] is
/// present for [CCNavigationAspectPhase.after]. Errors contain only a stable
/// runtime type, never an arbitrary exception message or payload.
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
  });

  /// Hook phase represented by this event.
  final CCNavigationAspectPhase phase;

  /// Sanitized request identity and route metadata.
  final CCNavigationAspectRequest request;

  /// Managed Route Entry that became visible, when this is an arrival event.
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

  /// Wall-clock time at which Runtime dispatched this event.
  final DateTime timestamp;
}

/// Context supplied to the decision-capable [CCNavigationAspect.before] hook.
///
/// Aspects may return a normal, cancel, or redirect interception. The context
/// omits typed arguments and must not be retained after the callback returns.
final class CCNavigationAspectContext {
  /// Creates one before-hook context.
  const CCNavigationAspectContext({
    required this.request,
    required this.cancellation,
    required this.redirectDepth,
  });

  /// Sanitized request being considered.
  final CCNavigationAspectRequest request;

  /// Cooperative cancellation signal for asynchronous policy work.
  final CCCancellationToken cancellation;

  /// Number of redirects already followed for this navigation identity.
  final int redirectDepth;
}

/// Decision callback for the [CCNavigationAspect.before] hook.
typedef CCNavigationAspectBefore =
    FutureOr<CCNavigationInterception> Function(
      CCNavigationAspectContext context,
    );

/// Observation callback used by the non-decision aspect hooks.
typedef CCNavigationAspectObserver =
    void Function(CCNavigationAspectEvent event);

/// One named global navigation AOP policy and observation registration.
///
/// Use [before] for cross-cutting cancellation or redirection such as login,
/// maintenance mode, or forced upgrade. Use [onFound], [onArrival], [onLost],
/// and [onAfter] for diagnostics, exposure tracking, performance metrics, and
/// failure handling. Observation callbacks must return quickly and must not
/// synchronously start another navigation.
final class CCNavigationAspect {
  /// Creates a named aspect with optional decision and observation hooks.
  const CCNavigationAspect({
    required this.id,
    this.before,
    this.onFound,
    this.onArrival,
    this.onLost,
    this.onAfter,
  });

  /// Stable identifier used for deterministic aspect ordering.
  final String id;

  /// Optional cross-cutting decision hook executed before route interceptors.
  final CCNavigationAspectBefore? before;

  /// Called after a route has matched and before Adapter dispatch.
  final CCNavigationAspectObserver? onFound;

  /// Called when a managed Route Entry enters the visible state.
  final CCNavigationAspectObserver? onArrival;

  /// Called when a request is cancelled or fails before reaching its target.
  final CCNavigationAspectObserver? onLost;

  /// Called after a request reaches a terminal success, failure, or cancel.
  final CCNavigationAspectObserver? onAfter;
}
