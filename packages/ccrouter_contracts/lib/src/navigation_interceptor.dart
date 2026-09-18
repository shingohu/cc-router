import 'dart:async';

import 'invocation.dart';
import 'navigation.dart';
import 'route.dart';

/// Provides the immutable request context seen by one navigation interceptor.
///
/// Interceptors use this context for access checks, feature gates, and
/// redirect decisions. They must not retain it or call a navigation adapter.
final class CCNavigationInterceptorContext {
  /// Creates a context for one interception pass.
  const CCNavigationInterceptorContext({
    required this.request,
    required this.cancellation,
    required this.redirectDepth,
    this.deadline,
  });

  /// Runtime-validated request currently being considered.
  final CCNavigationRequest request;

  /// Cooperative cancellation signal for asynchronous interceptor work.
  final CCCancellationToken cancellation;

  /// Number of redirects already followed for this navigation.
  final int redirectDepth;

  /// Optional deadline reserved for host-provided navigation policies.
  final DateTime? deadline;
}

/// Result returned by a navigation interceptor.
sealed class CCNavigationInterception {
  /// Creates an interception result.
  const CCNavigationInterception();
}

/// Allows the current request to continue to the next interceptor or Adapter.
final class CCNavigationProceed extends CCNavigationInterception {
  /// Creates a continue result.
  const CCNavigationProceed();
}

/// Stops navigation with a stable cancellation reason.
final class CCNavigationCancel extends CCNavigationInterception {
  /// Creates a cancellation result with a non-sensitive [code].
  const CCNavigationCancel({this.code = 'cancelled'});

  /// Stable reason code suitable for diagnostics and telemetry.
  final String code;
}

/// Redirects the current request to another typed route intent.
final class CCNavigationRedirect extends CCNavigationInterception {
  /// Redirects to a generated [intent] while preserving navigation context.
  const CCNavigationRedirect.toIntent(CCRouteIntent<Object?> intent)
    : intent = intent,
      uri = null;

  /// Redirects to a dynamically resolved [uri] while preserving its origin.
  const CCNavigationRedirect.toUri(Uri uri) : intent = null, uri = uri;

  /// Typed target used by generated access-control flows.
  final CCRouteIntent<Object?>? intent;

  /// URI target used by dynamic or host-owned redirect policies.
  final Uri? uri;
}

/// Pauses navigation until an external application policy resumes or cancels it.
///
/// Authentication, onboarding, consent, and device-unlock components can use
/// this result when they need to show UI outside the interceptor. Runtime
/// stores the validated request and exposes a [CCPendingNavigation] snapshot;
/// it does not know which business screen will satisfy the policy.
final class CCNavigationDefer extends CCNavigationInterception {
  /// Creates a deferred decision with an optional stable reason and timeout.
  const CCNavigationDefer({this.code = 'deferred', this.timeout});

  /// Stable reason used in diagnostics and cancellation events.
  final String code;

  /// Optional maximum time to retain the continuation.
  final Duration? timeout;
}

/// Executes one global or route-specific navigation policy.
///
/// Implementations may perform asynchronous authorization or feature checks,
/// then return [CCNavigationProceed], [CCNavigationCancel], or a redirect.
/// Calling `CCRouter.navigator` or an Adapter from inside an interceptor is not
/// supported because it would create re-entrant navigation.
abstract interface class CCNavigationInterceptor {
  /// Evaluates [context] and returns the next navigation decision.
  FutureOr<CCNavigationInterception> intercept(
    CCNavigationInterceptorContext context,
  );
}

/// Stable registration for one global navigation interceptor.
///
/// Hosts use this value when configuring `CCRouter.initialize`; IDs determine
/// deterministic global execution order and diagnostic identity.
final class CCGlobalNavigationInterceptor {
  /// Creates a named global interceptor registration.
  const CCGlobalNavigationInterceptor({
    required this.id,
    required this.interceptor,
  });

  /// Stable identifier used for deterministic ordering.
  final String id;

  /// Interceptor implementation invoked for every navigation request.
  final CCNavigationInterceptor interceptor;
}
