import 'service.dart';

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

/// Indicates that a registered route cannot serve the requested operation.
///
/// This covers operation-specific availability such as a typed external-origin
/// request targeting a route that disables Deep Links, or a deferred request
/// whose re-resolved target no longer matches its retained route identity.
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
class CCResolutionError extends CCRouterError {
  /// Creates a resolution error with a safe [message].
  const CCResolutionError(super.message);
}

/// Base class for deterministic Service provider resolution failures.
///
/// Service-specific failures remain catchable as [CCResolutionError] for
/// compatibility, while callers that need a precise recovery policy can match
/// the narrower subclasses below.
sealed class CCServiceError extends CCResolutionError {
  /// Creates a Service resolution failure with a safe [message].
  const CCServiceError(super.message);
}

/// Indicates that no Provider matches a requested Service identity.
final class CCServiceNotFoundError extends CCServiceError {
  /// Creates a missing-provider failure for the stable [identity].
  const CCServiceNotFoundError(this.identity, {this.key})
    : super(
        'No Service Provider is registered for "$identity"'
        '${key == null ? '' : ' with key "$key"'}.',
      );

  /// Stable Token ID or Dart type label used for the lookup.
  final String identity;

  /// Stable named implementation key, when the lookup requested one.
  final String? key;
}

/// Indicates that a Token was registered for a different Dart Service type.
final class CCServiceTypeMismatchError extends CCServiceError {
  /// Creates a type mismatch for [contractId] and [registeredType].
  const CCServiceTypeMismatchError(this.contractId, this.registeredType)
    : super(
        'Service contract "$contractId" is registered for $registeredType.',
      );

  /// Stable promoted Service Token ID.
  final String contractId;

  /// Safe diagnostic label of the type used during registration.
  final String registeredType;
}

/// Indicates that a Service Factory recursively requested its own Provider.
final class CCCircularServiceDependencyError extends CCServiceError {
  /// Creates a circular-construction failure for a sanitized [identity].
  const CCCircularServiceDependencyError(this.identity)
    : super('Circular Service construction was detected for "$identity".');

  /// Provider identity involved in the recursive construction.
  final String identity;
}

/// Indicates that a Service requires a lifecycle Scope that is not active.
///
/// The usual case is resolving a Session-scoped Service before a Session is
/// opened or after its close has started. Callers should open the required
/// Session or treat the capability as unavailable; retrying the same lookup
/// without a lifecycle transition cannot make it succeed.
final class CCServiceScopeUnavailableError extends CCServiceError {
  /// Creates a failure for the unavailable [scope].
  const CCServiceScopeUnavailableError(this.scope)
    : super('The required Service scope is not active.');

  /// Scope required by the Service Provider.
  final CCServiceScope scope;
}

/// Indicates that a lazily initialized Service is not ready for sync access.
///
/// Callers should await the corresponding asynchronous Service lookup or use a
/// generated asynchronous proxy. Repeating the same synchronous lookup cannot
/// start initialization and will produce the same error until readiness has
/// completed successfully.
final class CCServiceNotReadyError extends CCServiceError {
  /// Creates a not-ready failure for the stable [identity].
  const CCServiceNotReadyError(this.identity)
    : super('Service "$identity" is not ready for synchronous access.');

  /// Stable Token ID or Dart type label used for the lookup.
  final String identity;
}

/// Indicates that a Service's lazy readiness initializer failed.
///
/// The original error object and message are intentionally not retained. Use
/// [causeType] and the invocation trace for sanitized diagnostics; retry policy
/// belongs inside the initializer and is not inferred by Runtime.
final class CCServiceInitializationError extends CCServiceError {
  /// Creates an initialization failure for [identity] and safe [causeType].
  const CCServiceInitializationError(this.identity, this.causeType)
    : super('Service "$identity" failed to initialize ($causeType).');

  /// Stable Token ID or Dart type label identifying the Service.
  final String identity;

  /// Runtime type of the underlying failure without its message or payload.
  final String causeType;
}

/// Indicates that a critical Runtime initialization task failed.
///
/// The original exception and message are intentionally not retained. Hosts
/// use [taskId], [causeType], task snapshots, and Trace for safe diagnostics.
final class CCInitializationTaskError extends CCRouterError {
  /// Creates a sanitized failure for the critical initialization [taskId].
  const CCInitializationTaskError(this.taskId, this.causeType)
    : super('Initialization task "$taskId" failed ($causeType).');

  /// Stable identity of the failed task.
  final String taskId;

  /// Runtime type of the underlying failure without its message or payload.
  final String causeType;
}

/// Indicates that a Flutter `BuildContext` cannot be mapped to a bound Outlet.
///
/// This is returned by the optional call-site Outlet resolver when the Context
/// is outside a `CCRouterApp`, belongs to an unregistered Navigator, or is
/// evaluated before its Navigator is mounted. The resolver never falls back to
/// the root Outlet because doing so could silently target the wrong stack.
final class CCNavigationOutletResolutionError extends CCRouterError {
  /// Creates a sanitized call-site Outlet resolution failure.
  const CCNavigationOutletResolutionError()
    : super('The navigation Context is not inside a bound CCRouter Outlet.');
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
