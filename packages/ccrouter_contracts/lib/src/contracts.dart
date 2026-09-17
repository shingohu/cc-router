import 'dart:async';

/// Marker interface for a command that performs work and returns [R].
abstract interface class CCCommand<R> {}

/// Marker interface for a side-effect-free query that returns [R].
abstract interface class CCQuery<R> {}

/// Marker interface for an action that may have multiple handlers.
abstract interface class CCAction {}

/// Marker interface for a fact published to independent subscribers.
abstract interface class CCEvent {}

/// Summarizes the handlers that processed an action.
final class CCActionReport {
  /// Creates an immutable action dispatch report.
  const CCActionReport({this.handled = 0, this.results = const []});

  /// Number of handlers that completed successfully.
  final int handled;

  /// Optional handler results retained by an action policy.
  final List<Object?> results;
}

/// Identifies one named implementation of service contract [T].
final class CCServiceKey<T> {
  /// Creates a typed service key with the stable [name].
  const CCServiceKey(this.name);

  /// Stable name used in registration and resolution.
  final String name;

  /// Compares both the service type and stable key name.
  @override
  bool operator ==(Object other) =>
      other is CCServiceKey<T> && other.name == name;

  /// Combines the service contract type and key name.
  @override
  int get hashCode => Object.hash(T, name);

  /// Returns a diagnostic representation of this key.
  @override
  String toString() => 'CCServiceKey<$T>($name)';
}

/// Defines the lifetime that owns a service instance.
enum CCServiceScope {
  /// Lives until the owning Runtime shuts down.
  app,

  /// Lives for one authenticated account Session.
  session,

  /// Lives while its declaring component remains enabled.
  component,

  /// Lives for one concrete route entry.
  route,

  /// Creates a fresh instance for every resolution.
  transient,
}

/// Propagates cooperative cancellation through an invocation chain.
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
final class CCInvocationContext {
  /// Creates the context propagated to a provider or message handler.
  CCInvocationContext({
    required this.invocationId,
    required this.traceId,
    required this.spanId,
    this.parentSpanId,
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

  /// Lifecycle Scope associated with this invocation.
  final String? scopeId;

  /// Latest time at which this invocation may complete.
  final DateTime? deadline;

  /// Cooperative cancellation signal for this invocation.
  final CCCancellationToken cancellation;
}

/// Base class for failures with stable CCRouter semantics.
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

/// Contract implemented by instances that release lifecycle-owned resources.
abstract interface class CCDisposable {
  /// Releases resources when the owning Scope closes.
  FutureOr<void> dispose();
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
