import 'dart:async';

/// Propagates cooperative cancellation through an invocation chain.
///
/// Pass a token when a caller needs to cancel pending Command or Query work;
/// handlers should observe it instead of assuming cancellation stops Dart code.
final class CCCancellationToken {
  /// Creates a token in the non-cancelled state.
  CCCancellationToken();

  /// Completes when cancellation is requested.
  final Completer<void> _completer = Completer<void>();

  /// Callbacks notified exactly once when cancellation is requested.
  final Set<void Function()> _listeners = {};

  /// Whether cancellation has already been requested.
  bool get isCancelled => _completer.isCompleted;

  /// Completes when cancellation is first requested.
  Future<void> get whenCancelled => _completer.future;

  /// Requests cancellation and synchronously notifies registered listeners.
  void cancel() {
    if (isCancelled) return;
    _completer.complete();
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }

  /// Registers [listener] and returns a callback that removes it.
  ///
  /// If this token is already cancelled, [listener] runs immediately.
  void Function() addListener(void Function() listener) {
    if (isCancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }
}

/// Carries trace, lifecycle, deadline, and cancellation data for one invocation.
///
/// Provider factories and message handlers use this context to cooperate with
/// Runtime deadlines and cancellation and to correlate nested diagnostics.
final class CCInvocationContext {
  /// Creates the context propagated to a provider or message handler.
  CCInvocationContext({
    required this.invocationId,
    required this.traceId,
    required this.spanId,
    this.parentSpanId,
    this.operation,
    this.target,
    this.callerComponentId,
    this.targetComponentId,
    this.scopeId,
    this.deadline,
    CCCancellationToken? cancellation,
  }) : cancellation = cancellation ?? CCCancellationToken();

  /// Identity unique to this invocation.
  final String invocationId;

  /// Identity shared by all spans in one call chain.
  final String traceId;

  /// Identity of this invocation span.
  final String spanId;

  /// Parent span identity, or null for a root invocation.
  final String? parentSpanId;

  /// Framework operation category for this invocation, when applicable.
  ///
  /// Generated Service proxies use `service`; provider construction contexts
  /// may use a narrower internal category. Callers must not use this value as
  /// authorization input.
  final String? operation;

  /// Sanitized capability identity targeted by this invocation.
  ///
  /// The value contains only stable framework identifiers and intentionally
  /// excludes method arguments, return values, URIs, and arbitrary metadata.
  final String? target;

  /// Component that initiated the invocation when generated code knows it.
  ///
  /// Null means the caller could not be attributed safely; Runtime never
  /// guesses ownership from the current route or service construction Zone.
  final String? callerComponentId;

  /// Component that registered the invoked capability, when known.
  final String? targetComponentId;

  /// Lifecycle Scope associated with this invocation.
  final String? scopeId;

  /// Latest time at which this invocation may complete.
  final DateTime? deadline;

  /// Cooperative cancellation signal for this invocation.
  final CCCancellationToken cancellation;
}
