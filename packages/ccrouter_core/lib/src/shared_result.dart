part of 'runtime.dart';

/// Completion data that can cross Dart error Zones without losing failures.
final class _SharedOutcome<T> {
  /// Stores a successful value without creating an error Future.
  const _SharedOutcome.success(T value)
    : _value = value,
      _error = null,
      _stack = null;

  /// Stores the original failure identity and stack for each caller to restore.
  const _SharedOutcome.failure(Object error, StackTrace stack)
    : _value = null,
      _error = error,
      _stack = stack;

  /// Successful value; nullable only to represent a failed completion.
  final T? _value;

  /// Original failure, rather than a wrapper or sanitized diagnostic.
  final Object? _error;

  /// Throw site retained for a failed completion.
  final StackTrace? _stack;

  /// Restores the result in the waiting caller's error Zone.
  T unwrap() {
    final error = _error;
    if (error != null) Error.throwWithStackTrace(error, _stack!);
    return _value as T;
  }
}

/// Private single-execution completion shared as data, never as an error Future.
///
/// Create and publish this record before invoking reentrant user code. Attach
/// [follow] in the producer's Zone; call [wait] in each consumer's Zone. The
/// record owns no Runtime, Scope or timer. Cancellable consumers are retained
/// only until their own cancellation or the shared producer's terminal state.
final class _SharedResult<T> {
  /// Completion always succeeds with either value or failure data.
  final Completer<_SharedOutcome<T>> _completion =
      Completer<_SharedOutcome<T>>();

  /// Stable terminal data for late subscribers, independent of error Zones.
  _SharedOutcome<T>? _outcome;

  /// Removable per-consumer relays, never listeners on the shared Future.
  final Set<Completer<_SharedOutcome<T>>> _waiters = {};

  /// Joins execution without restoring a failure, suitable for cleanup barriers.
  Future<_SharedOutcome<T>> get settled => _completion.future;

  /// Delivers the original result or failure inside the caller's error Zone.
  ///
  /// Cancellation drops only this consumer's relay. Attaching Future.any or
  /// then in the caller Zone to [settled] would instead retain that Zone until
  /// the shared producer finishes, even after the consumer has ended.
  Future<T> wait({CCCancellationToken? cancellation}) {
    if (cancellation == null) return _restoreSharedOutcome(settled);
    if (cancellation.isCancelled) {
      return Future<T>.error(const CCInvocationCancelledError());
    }
    final outcome = _outcome;
    if (outcome != null) {
      return _restoreSharedOutcome(Future.value(outcome));
    }
    final relay = Completer<_SharedOutcome<T>>();
    _waiters.add(relay);
    final remove = cancellation.addListener(() {
      if (!_waiters.remove(relay)) return;
      relay.complete(
        _SharedOutcome.failure(
          const CCInvocationCancelledError(),
          StackTrace.current,
        ),
      );
    });
    return _restoreSharedOutcome(relay.future, remove: remove);
  }

  /// Publishes one successful terminal outcome.
  void complete(T value) => _publish(_SharedOutcome.success(value));

  /// Publishes one failed terminal outcome without an internal unhandled error.
  void fail(Object error, StackTrace stack) =>
      _publish(_SharedOutcome.failure(error, stack));

  /// Releases all relays before publishing one shared success or failure.
  void _publish(_SharedOutcome<T> outcome) {
    if (_outcome != null) throw StateError('Shared result already completed.');
    _outcome = outcome;
    final waiters = _waiters.toList();
    _waiters.clear();
    _completion.complete(outcome);
    for (final relay in waiters) {
      relay.complete(outcome);
    }
  }

  /// Observes producer completion in the producer's error Zone exactly once.
  void follow(Future<T> work) {
    unawaited(work.then<void>(complete, onError: fail));
  }
}

/// Unwraps in the consumer Zone without capturing the shared producer record.
Future<T> _restoreSharedOutcome<T>(
  Future<_SharedOutcome<T>> future, {
  void Function()? remove,
}) async {
  try {
    return (await future).unwrap();
  } finally {
    remove?.call();
  }
}
