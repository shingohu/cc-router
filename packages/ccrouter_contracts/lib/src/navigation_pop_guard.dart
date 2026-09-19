import 'navigation_backend.dart';
import 'route_entry.dart';

/// Immutable context supplied when a managed route is about to be popped.
///
/// Pop guards use this snapshot for synchronous decisions such as protecting a
/// dirty form, mandatory onboarding step, or payment confirmation. The context
/// deliberately excludes Pop result values and mutable backend objects so a
/// guard cannot retain sensitive data or manipulate a Navigator directly.
final class CCPopGuardContext {
  /// Creates a context for one managed-entry Pop attempt.
  const CCPopGuardContext({required this.entry, required this.trigger});

  /// Managed route entry that would be removed when the Pop succeeds.
  final CCRouteEntrySnapshot entry;

  /// Trusted source that initiated the Pop attempt.
  final CCPopTrigger trigger;
}

/// Result returned by a [CCPopGuard].
///
/// Decisions are synchronous because system gestures and predictive back need
/// an immediate answer. Use Flutter `PopScope` for workflows that must display
/// an asynchronous confirmation dialog before retrying navigation.
sealed class CCPopGuardDecision {
  /// Creates a Pop guard decision.
  const CCPopGuardDecision();
}

/// Allows the Pop pipeline to continue to the next guard or adapter.
final class CCPopAllow extends CCPopGuardDecision {
  /// Creates an allow decision.
  const CCPopAllow();
}

/// Consumes a Pop attempt without removing the managed route entry.
final class CCPopDeny extends CCPopGuardDecision {
  /// Creates a denial with a stable, non-sensitive diagnostic [code].
  const CCPopDeny({this.code = 'pop_denied'});

  /// Stable reason suitable for diagnostics and application handling.
  final String code;
}

/// Synchronously decides whether one managed route entry may be popped.
///
/// Implementations must be fast, side-effect free, and must not navigate. Use
/// this contract for state already available in memory. Network checks and UI
/// confirmation belong outside this callback because platform back handling
/// cannot safely wait for them.
abstract interface class CCPopGuard {
  /// Evaluates one managed Pop attempt.
  CCPopGuardDecision evaluate(CCPopGuardContext context);
}

/// Stable application-host registration for one global Pop guard.
///
/// Global guards run in stable ID order before the route owner's guards. Use
/// them for application-wide constraints such as a mandatory security flow;
/// ordinary dirty-page protection should remain route-local or use `PopScope`.
final class CCGlobalPopGuard {
  /// Creates a named global Pop guard registration.
  const CCGlobalPopGuard({required this.id, required this.guard});

  /// Stable identity used for deterministic ordering and diagnostics.
  final String id;

  /// Guard implementation invoked for managed entries only.
  final CCPopGuard guard;
}

/// Callback installed into an Adapter-owned platform back bridge.
///
/// Host integrations use this before committing a system gesture or predictive
/// back transition. Normal business code must use `CCRouter.navigator` rather
/// than retaining or invoking this callback.
typedef CCPopGuardEvaluator = CCPopGuardDecision Function(CCPopTrigger trigger);

/// Optional Adapter SPI for binding Runtime Pop guard evaluation.
///
/// Adapters implement this only when platform back can bypass
/// `CCRouter.navigator.maybePop`, such as Android predictive back. The Runtime
/// installs the evaluator during initialization and clears it during disposal.
abstract interface class CCNavigationPopGuardBinding {
  /// Installs [evaluator], or clears the previous binding when it is null.
  void bindPopGuardEvaluator(CCPopGuardEvaluator? evaluator);
}
