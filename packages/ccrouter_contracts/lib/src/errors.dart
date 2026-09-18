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
  /// Creates a route-not-found error without retaining the full URI.
  const CCRouteNotFoundError(String path)
    : super('No route matches path "$path".');
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
  const CCRouteUnavailableError(String routeId)
    : super('Route "$routeId" is unavailable.');
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

/// Indicates that an Aspect callback attempted synchronous navigation reentry.
final class CCNavigationReentrancyError extends CCRouterError {
  /// Creates a reentrancy error that leaves the active navigation unchanged.
  const CCNavigationReentrancyError()
    : super('Navigation cannot be started from an active Aspect callback.');
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
