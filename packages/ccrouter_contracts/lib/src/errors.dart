/// Base class for failures with stable CCRouter semantics.
///
/// Business callers may catch this type when they need one framework-level
/// fallback while still matching concrete subclasses for recoverable cases.
sealed class CCRouterError implements Exception {
  /// Creates a framework error with a safe diagnostic [message].
  const CCRouterError(this.message);

  /// Human-readable message that must not expose sensitive business data.
  final String message;

  /// Formats the concrete error type and message.
  @override
  String toString() => '$runtimeType: $message';
}

/// Indicates that a static API was used before initialization.
final class CCRouterNotInitializedError extends CCRouterError {
  /// Creates the not-initialized error.
  const CCRouterNotInitializedError()
    : super('CCRouter has not been initialized.');
}

/// Indicates that initialization was requested while a Runtime is active.
final class CCRouterAlreadyInitializedError extends CCRouterError {
  /// Creates the already-initialized error.
  const CCRouterAlreadyInitializedError()
    : super('CCRouter already owns an active Runtime.');
}

/// Indicates an invalid or conflicting capability registration.
final class CCRegistrationError extends CCRouterError {
  /// Creates a registration error with a safe [message].
  const CCRegistrationError(super.message);
}

/// Indicates an invalid or conflicting route definition.
final class CCRouteRegistrationError extends CCRouterError {
  /// Creates a route registration error with a safe [message].
  const CCRouteRegistrationError(super.message);
}

/// Indicates an invalid or conflicting Shell definition.
final class CCShellRegistrationError extends CCRouterError {
  /// Creates a Shell registration error with a safe [message].
  const CCShellRegistrationError(super.message);
}

/// Indicates that a URI does not match an installed route.
final class CCRouteNotFoundError extends CCRouterError {
  /// Creates a route-not-found error without retaining the supplied location.
  const CCRouteNotFoundError(String _)
    : super('No route matches the supplied location.');
}

/// Indicates that multiple equally specific routes match one location.
///
/// This error exposes only stable route IDs so diagnostics can identify
/// conflicting definitions without retaining a potentially sensitive URI.
final class CCRouteAmbiguityError extends CCRouterError {
  /// Creates an ambiguity error from the tied [routeIds].
  CCRouteAmbiguityError(Iterable<String> routeIds)
    : super(
        'Route resolution has equally specific matches for route IDs: '
        '${(routeIds.toSet().toList()..sort()).join(', ')}.',
      );
}

/// Indicates that a route was found but its owning component is unavailable.
final class CCRouteUnavailableError extends CCRouterError {
  /// Creates an unavailable-route error for [routeId].
  const CCRouteUnavailableError(this.routeId)
    : super('Route "$routeId" is unavailable.');

  /// Stable unavailable route identity suitable for failure policy matching.
  final String routeId;
}

/// Indicates that external ingress matched a route that forbids Deep Links.
///
/// The error exposes only the stable route ID and never retains the rejected
/// URI or its query values. Host Failure Policies can use it to show an
/// unsupported-link destination without weakening the route's security policy.
final class CCDeepLinkRejectedError extends CCRouterError {
  /// Creates a rejection for the matched but externally disabled [routeId].
  const CCDeepLinkRejectedError(this.routeId)
    : super('Route "$routeId" does not accept external navigation.');

  /// Stable matched route identity without rejected URI values.
  final String routeId;
}

/// Identifies why the Host rejected an external location before route matching.
enum CCDeepLinkIngressRejectionReason {
  /// A Path-only external location was supplied while the Host forbids it.
  relativePathNotAllowed,

  /// The location has a malformed or unsafe Scheme/authority shape.
  invalidAuthority,

  /// No exact Host rule accepts the location's Scheme, Host, and effective Port.
  authorityNotAllowed,
}

/// Indicates that external input failed the application Host trust policy.
///
/// The error intentionally retains no URI, Host, query value, or path value.
/// Diagnostics can use [reason] to distinguish configuration and trust failures
/// without exposing the rejected input.
final class CCDeepLinkIngressRejectedError extends CCRouterError {
  /// Creates a sanitized ingress rejection for the stable [reason].
  const CCDeepLinkIngressRejectedError(this.reason)
    : super('External navigation was rejected by the Host ingress policy.');

  /// Stable rejection category safe for failure handling and telemetry.
  final CCDeepLinkIngressRejectionReason reason;
}

/// Indicates that navigation failure recovery exceeded its loop limit.
final class CCNavigationFailureRecoveryLoopError extends CCRouterError {
  /// Creates a bounded failure-recovery loop error.
  const CCNavigationFailureRecoveryLoopError()
    : super('Navigation failure recovery exceeded the limit.');
}

/// Indicates invalid values at a route codec boundary.
final class CCRouteParameterError extends CCRouterError {
  /// Creates a parameter error with a sanitized [message].
  const CCRouteParameterError(super.message);
}

/// Indicates that a navigation adapter failed or is not configured.
///
/// Business callers may handle this as an unavailable navigation backend;
/// application hosts use its message to diagnose adapter setup or execution.
final class CCNavigationAdapterError extends CCRouterError {
  /// Creates an adapter error with a sanitized [message].
  const CCNavigationAdapterError(super.message);
}

/// Indicates that an identical navigation is already in flight.
final class CCNavigationDuplicateError extends CCRouterError {
  /// Creates a duplicate-navigation error for [routeId].
  const CCNavigationDuplicateError(String routeId)
    : super('Navigation for route "$routeId" is already in flight.');
}

/// Indicates that a requested pending-navigation continuation is unavailable.
final class CCNavigationPendingNotFoundError extends CCRouterError {
  /// Creates a pending-navigation lookup error without retaining user input.
  const CCNavigationPendingNotFoundError()
    : super('The pending navigation is no longer available.');
}

/// Indicates that a framework policy or observer attempted navigation reentry.
final class CCNavigationReentrancyError extends CCRouterError {
  /// Creates a reentrancy error that leaves the active operation unchanged.
  const CCNavigationReentrancyError()
    : super('Navigation cannot start from an active framework callback.');
}

/// Indicates that an adapter returned a value incompatible with a typed route.
///
/// Generated typed navigation may surface this when page code Pops a value that
/// does not conform to the route contract's declared result type.
final class CCRouteResultTypeError extends CCRouterError {
  /// Creates a result-type error for the affected [routeId].
  const CCRouteResultTypeError(String routeId)
    : super('Route "$routeId" returned an incompatible result type.');
}

/// Indicates that a navigation interceptor intentionally stopped a request.
final class CCRouteCancelledError extends CCRouterError {
  /// Creates a cancellation error with a stable non-sensitive [code].
  const CCRouteCancelledError(this.code) : super('Navigation was cancelled.');

  /// Stable cancellation reason for policy-specific handling and telemetry.
  final String code;
}

/// Indicates that redirects exceeded the Runtime safety limit.
final class CCRouteRedirectLoopError extends CCRouterError {
  /// Creates a redirect-loop error for the affected [routeId].
  const CCRouteRedirectLoopError(String routeId)
    : super('Navigation redirects exceeded the limit near route "$routeId".');
}

/// Indicates that a navigation interceptor failed unexpectedly.
///
/// The original exception object and message are intentionally omitted so
/// diagnostics cannot retain business payloads or credentials.
final class CCNavigationInterceptorError extends CCRouterError {
  /// Creates a sanitized failure for [interceptorId] and [causeType].
  const CCNavigationInterceptorError(this.interceptorId, this.causeType)
    : super('Navigation interceptor "$interceptorId" failed as $causeType.');

  /// Stable interceptor identity used for diagnostics.
  final String interceptorId;

  /// Runtime type of the isolated failure without its arbitrary message.
  final String causeType;
}

/// Indicates that a navigation interceptor exceeded its configured timeout.
final class CCNavigationInterceptorTimeoutError extends CCRouterError {
  /// Creates a timeout failure for [interceptorId].
  const CCNavigationInterceptorTimeoutError(this.interceptorId)
    : super('Navigation interceptor "$interceptorId" timed out.');

  /// Stable interceptor identity used for diagnostics.
  final String interceptorId;
}

/// Indicates that a managed route Pop was rejected by a Pop guard.
///
/// Direct business `pop` calls surface this error because their `void` API has
/// no outcome channel. System and gesture handling should use
/// `maybePopOutcome`, which reports the same code without throwing.
final class CCPopGuardDeniedError extends CCRouterError {
  /// Creates a denial error with a stable, non-sensitive [code].
  const CCPopGuardDeniedError(this.code)
    : super('The managed route rejected the Pop request.');

  /// Stable reason supplied by the guard that stopped the Pop.
  final String code;
}

/// Indicates that a requested capability or lifecycle owner cannot be resolved.
final class CCResolutionError extends CCRouterError {
  /// Creates a resolution error with a safe [message].
  const CCResolutionError(super.message);
}

/// Indicates access to a Scope that is closing or closed.
final class CCScopeClosedError extends CCRouterError {
  /// Creates an error for the closed Scope identified by [scopeId].
  const CCScopeClosedError(String scopeId)
    : super('Scope "$scopeId" is closed.');
}

/// Indicates a generic invocation failure recorded by diagnostics.
final class CCInvocationError extends CCRouterError {
  /// Creates an invocation error with a sanitized [message].
  const CCInvocationError(super.message);
}

/// Indicates that cooperative cancellation ended an invocation.
final class CCInvocationCancelledError extends CCRouterError {
  /// Creates an invocation-cancelled error.
  const CCInvocationCancelledError() : super('Invocation was cancelled.');
}

/// Indicates that an invocation exceeded its effective deadline.
final class CCInvocationTimeoutError extends CCRouterError {
  /// Creates an invocation-timeout error.
  const CCInvocationTimeoutError() : super('Invocation exceeded its deadline.');
}
