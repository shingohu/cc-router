import 'dart:async';

import 'navigation.dart';
import 'route.dart';

/// Classifies the stage at which one navigation attempt failed.
enum CCNavigationFailureStage {
  /// Route matching, availability, or Deep Link policy rejected the target.
  resolution,

  /// A generated route codec rejected typed or URI parameters.
  parameters,

  /// A navigation interceptor cancelled, timed out, or failed.
  interception,

  /// The navigation adapter rejected or failed the backend operation.
  dispatch,

  /// A page returned a value incompatible with its typed route contract.
  result,

  /// The failure did not match a more specific framework stage.
  unknown,
}

/// Sanitized Host-facing context for one failed navigation attempt.
///
/// The context intentionally omits URI values, Path and Query parameters,
/// typed arguments, Pop results, and `extra`. Use it to choose a stable error
/// destination without logging or persisting business payloads.
final class CCNavigationFailureContext {
  /// Creates an immutable failure context.
  const CCNavigationFailureContext({
    required this.navigationId,
    required this.operation,
    required this.origin,
    required this.openMode,
    required this.stage,
    required this.errorType,
    required this.recoveryDepth,
    this.routeId,
    this.source,
  });

  /// Runtime-unique identity preserved across failure recovery attempts.
  final String navigationId;

  /// Original stack operation requested by the caller.
  final CCNavigationOperation operation;

  /// Stable route ID when it was known without exposing route parameters.
  final String? routeId;

  /// Trusted ingress classification preserved from the original attempt.
  final CCNavigationOrigin origin;

  /// Original dynamic Open stack behavior, or null for typed operations.
  ///
  /// Failure policies may use this sanitized value to preserve the intended
  /// Host history when selecting a URI recovery destination.
  final CCDeepLinkOpenMode? openMode;

  /// Optional stable product attribution supplied by the caller.
  final CCNavigationSource? source;

  /// Framework stage that produced the failure.
  final CCNavigationFailureStage stage;

  /// Sanitized concrete error type without its arbitrary message.
  final String errorType;

  /// Number of previous Failure Policy recoveries in the same chain.
  final int recoveryDepth;
}

/// Decision returned by a [CCNavigationFailurePolicy].
sealed class CCNavigationFailureDecision {
  /// Creates a Host failure decision.
  const CCNavigationFailureDecision();
}

/// Propagates the original navigation failure to its caller.
final class CCNavigationFailurePropagate extends CCNavigationFailureDecision {
  /// Creates a propagate decision.
  const CCNavigationFailurePropagate();
}

/// Redirects the failed navigation to a new typed route or dynamic URI.
///
/// Redirect recovery completes with the replacement destination's result. Use
/// it only when that result remains compatible with the original typed call.
final class CCNavigationFailureRedirect extends CCNavigationFailureDecision {
  /// Redirects to a generated typed [intent].
  const CCNavigationFailureRedirect.toIntent(
    CCRouteIntent<Object?> intent, {
    this.operation,
    this.openMode,
  }) : intent = intent,
       uri = null;

  /// Redirects to a dynamically resolved [uri].
  const CCNavigationFailureRedirect.toUri(
    Uri uri, {
    this.operation,
    this.openMode,
  }) : intent = null,
       uri = uri;

  /// Typed recovery target, when supplied.
  final CCRouteIntent<Object?>? intent;

  /// Dynamic recovery target, when supplied.
  final Uri? uri;

  /// Optional stack operation override for the recovery destination.
  ///
  /// When omitted, Runtime preserves the original caller's operation. This
  /// prevents a failed Push from replacing an unrelated current page while
  /// retaining explicit Go, Reset, and Replace intent.
  final CCNavigationOperation? operation;

  /// Dynamic Open behavior when [operation] explicitly selects Open.
  ///
  /// An explicit Open defaults to Push when this is null. When [operation] is
  /// omitted and the original operation was Open, Runtime instead preserves
  /// the original request's Open mode.
  final CCDeepLinkOpenMode? openMode;
}

/// Opens a fallback destination and suppresses the original failure.
///
/// The original call completes with `null` after the fallback operation
/// completes. Use this for 404, unsupported-link, or unavailable-component UI
/// where callers do not consume a replacement page result.
final class CCNavigationFailureFallback extends CCNavigationFailureDecision {
  /// Falls back to a generated typed [intent].
  const CCNavigationFailureFallback.toIntent(
    CCRouteIntent<Object?> intent, {
    this.operation,
    this.openMode,
  }) : intent = intent,
       uri = null;

  /// Falls back to a dynamically resolved [uri].
  const CCNavigationFailureFallback.toUri(
    Uri uri, {
    this.operation,
    this.openMode,
  }) : intent = null,
       uri = uri;

  /// Typed fallback target, when supplied.
  final CCRouteIntent<Object?>? intent;

  /// Dynamic fallback target, when supplied.
  final Uri? uri;

  /// Optional stack operation override for the fallback destination.
  ///
  /// A null value inherits the original request operation so recovery does not
  /// introduce an unrelated destructive stack mutation.
  final CCNavigationOperation? operation;

  /// Dynamic Open behavior when [operation] explicitly selects Open.
  ///
  /// See [CCNavigationFailureRedirect.openMode] for inheritance semantics.
  final CCDeepLinkOpenMode? openMode;
}

/// Host policy that may recover one sanitized navigation failure.
///
/// Applications install at most one policy through their managed App options.
/// The policy must return a decision instead of navigating directly, which
/// keeps recovery inside Runtime loop detection, attribution, and interception.
abstract interface class CCNavigationFailurePolicy {
  /// Chooses whether to propagate, redirect, or fall back for [context].
  FutureOr<CCNavigationFailureDecision> onFailure(
    CCNavigationFailureContext context,
  );
}

/// Records one sanitized failure and its recovery outcome.
///
/// Runtime emits this event even when no [CCNavigationFailurePolicy] is
/// installed, so route resolution and parameter failures that happen before a
/// complete navigation request still have one terminal diagnostic envelope.
final class CCNavigationFailureEvent {
  /// Creates an immutable failure event.
  const CCNavigationFailureEvent({
    required this.context,
    required this.timestamp,
    required this.recovered,
  });

  /// Sanitized context optionally presented to the Host policy.
  final CCNavigationFailureContext context;

  /// Whether a policy selected redirect or fallback recovery.
  ///
  /// This remains false when no policy exists, the policy propagates, the
  /// policy fails, or the bounded recovery limit is reached.
  final bool recovered;

  /// Wall-clock time at which Runtime finalized the failure outcome.
  final DateTime timestamp;
}

/// Receives sanitized navigation failure outcomes.
///
/// Runtime delivers this terminal observation in FIFO order on a later
/// event-loop turn and preserves it during queue pressure. Listeners must
/// remain observational and must not start navigation. Use the Failure Policy
/// itself when the Host needs to select a redirect or fallback.
typedef CCNavigationFailureListener =
    void Function(CCNavigationFailureEvent event);
