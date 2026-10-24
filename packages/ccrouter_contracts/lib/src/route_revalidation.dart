import 'dart:async';

import 'invocation.dart';
import 'route.dart';
import 'route_entry.dart';

/// Immutable input supplied while an active managed Route Entry is revalidated.
///
/// Policies may read application-owned authentication, permission, or feature
/// state, but must not retain this context or start navigation. [entry] contains
/// only sanitized identity and placement metadata; route arguments, results,
/// Scopes, Widgets, and backend Routes are never exposed.
final class CCRouteRevalidationContext {
  /// Creates one policy evaluation snapshot owned by the Runtime.
  const CCRouteRevalidationContext({
    required this.entry,
    required this.reason,
    required this.revision,
    required this.cancellation,
    this.deadline,
  });

  /// Exact managed Entry being evaluated.
  final CCRouteEntrySnapshot entry;

  /// Stable, non-sensitive application reason for this revalidation pass.
  final String reason;

  /// Monotonic Runtime-local pass revision.
  final int revision;

  /// Cooperative cancellation signal tied to Runtime lifetime and timeout.
  final CCCancellationToken cancellation;

  /// Absolute deadline for the current policy, when it has a timeout.
  final DateTime? deadline;
}

/// Decision returned for one retained managed Route Entry.
sealed class CCRouteRevalidationDecision {
  /// Creates an immutable revalidation decision.
  const CCRouteRevalidationDecision();
}

/// Keeps the exact Entry unchanged.
final class CCRouteRevalidationKeep extends CCRouteRevalidationDecision {
  /// Creates a keep decision.
  const CCRouteRevalidationKeep();
}

/// Removes the exact Entry because its active-state policy is no longer valid.
///
/// This is a Host policy transition rather than a user Pop, so Runtime does not
/// run PopGuard. The backend must support identity-based targeted close; it may
/// never fall back to the current route or a same-route instance.
final class CCRouteRevalidationClose extends CCRouteRevalidationDecision {
  /// Creates an exact close decision.
  const CCRouteRevalidationClose();
}

/// Replaces the exact current Entry with a generated typed destination.
///
/// Replacement is applied only when the Entry is still topmost in its original
/// Host and Outlet. A covered or stale Entry is reported without guessing.
/// The Backend must prove synchronous transaction acceptance through the
/// optional Host dispatch SPI; legacy Adapters report `unsupported` before
/// mutation. The report does not wait for the new page's eventual Pop result.
final class CCRouteRevalidationReplace extends CCRouteRevalidationDecision {
  /// Creates a replacement decision using a backend-neutral route intent.
  const CCRouteRevalidationReplace(this.intent);

  /// Generated destination that passes through normal route policy checks.
  final CCRouteIntent<Object?> intent;
}

/// Resets the Entry's complete Host to a generated typed destination.
///
/// The topmost reset decision in one Host supersedes every other decision for
/// that Host, providing deterministic logout or access-revocation behavior.
final class CCRouteRevalidationReset extends CCRouteRevalidationDecision {
  /// Creates a Host reset decision using a backend-neutral route intent.
  const CCRouteRevalidationReset(this.intent);

  /// Generated root destination that passes through normal route policy checks.
  final CCRouteIntent<Object?> intent;
}

/// Evaluates retained managed Route Entries after application policy changes.
///
/// Application Hosts register policies during Runtime initialization. State
/// owners explicitly trigger a pass after authentication, Session, permission,
/// or feature availability changes; Runtime never subscribes to an arbitrary
/// `Listenable`. Implementations must be side-effect-free and must not navigate.
abstract interface class CCRouteRevalidationPolicy {
  /// Returns the desired state for [context]'s exact Entry.
  FutureOr<CCRouteRevalidationDecision> evaluate(
    CCRouteRevalidationContext context,
  );
}

/// Stable Host registration for one active-route revalidation policy.
final class CCGlobalRouteRevalidationPolicy {
  /// Creates a named policy with an optional per-Entry evaluation timeout.
  const CCGlobalRouteRevalidationPolicy({
    required this.id,
    required this.policy,
    this.timeout,
  });

  /// Stable identifier used for deterministic policy ordering and errors.
  final String id;

  /// Application-owned policy implementation.
  final CCRouteRevalidationPolicy policy;

  /// Maximum duration allowed for each Entry evaluation.
  final Duration? timeout;
}

/// Terminal result for one Entry captured by a revalidation pass.
enum CCRouteRevalidationOutcome {
  /// Every policy kept the Entry.
  kept,

  /// The exact backend Entry was closed.
  closed,

  /// The topmost Entry was replaced and the replacement was accepted.
  replaced,

  /// The Entry's Host was reset to the selected destination.
  reset,

  /// A higher-priority reset decision owned reconciliation for this Host.
  ///
  /// This remains true when that selected reset later reports `stale` or
  /// `unsupported`; lower-priority actions never partially mutate the Host.
  superseded,

  /// The Entry changed after evaluation and was not mutated by this pass.
  stale,

  /// The backend could not safely perform the requested exact operation.
  unsupported,
}

/// Sanitized result for one Entry evaluated during a pass.
final class CCRouteRevalidationEntryResult {
  /// Creates an immutable result without route arguments or backend objects.
  const CCRouteRevalidationEntryResult({
    required this.routeEntryId,
    required this.routeId,
    required this.hostId,
    required this.navigatorOutlet,
    required this.outcome,
    this.policyId,
  });

  /// Exact Runtime Entry identity at evaluation time.
  final String routeEntryId;

  /// Stable route contract identity.
  final String routeId;

  /// Host that owned the evaluated Entry.
  final String hostId;

  /// Navigator partition that owned the evaluated Entry.
  final String navigatorOutlet;

  /// Terminal effect or safe fallback selected for the Entry.
  final CCRouteRevalidationOutcome outcome;

  /// Policy that selected a non-keep decision, when applicable.
  final String? policyId;
}

/// Immutable report returned after one serialized revalidation pass.
final class CCRouteRevalidationReport {
  /// Creates a report from sanitized per-Entry results.
  CCRouteRevalidationReport({
    required this.reason,
    required this.revision,
    required Iterable<CCRouteRevalidationEntryResult> entries,
  }) : entries = List.unmodifiable(entries);

  /// Stable application reason supplied by the trigger.
  final String reason;

  /// Monotonic Runtime-local pass revision.
  final int revision;

  /// Results in the original managed stack order.
  final List<CCRouteRevalidationEntryResult> entries;

  /// Whether the pass closed, replaced, or reset at least one Entry.
  bool get changed => entries.any(
    (entry) =>
        entry.outcome == CCRouteRevalidationOutcome.closed ||
        entry.outcome == CCRouteRevalidationOutcome.replaced ||
        entry.outcome == CCRouteRevalidationOutcome.reset,
  );
}
