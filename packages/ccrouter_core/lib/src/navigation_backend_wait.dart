part of 'runtime.dart';

/// Detachable completion relay for one external Pop or targeted-close Future.
///
/// A late producer retains this small relay only. Terminal completion clears
/// the consumer Completer, owner subscriptions and deadline, so it retains no
/// Runtime, Entry, caller Zone or backend. Failure travels as data and is
/// restored in the consumer's error Zone, preserving its object and stack.
final class _NavigationBackendWait<T> {
  /// Creates a consumer relay before dispatch or synchronous owner teardown.
  _NavigationBackendWait();

  /// Consumer-owned completion, released at the first terminal outcome.
  Completer<_SharedOutcome<T>>? _completion = Completer<_SharedOutcome<T>>();

  /// Token subscriptions released on success, failure or owner retirement.
  final List<void Function()> _removers = [];

  /// One event-loop grace period for an already completing close transaction.
  Timer? _entryDeadline;

  /// Whether external work may still provide this operation's outcome.
  bool get isPending => _completion != null;

  /// Obtains the consumer Future before any reentrant owner notification.
  Future<T> get result => _restoreSharedOutcome(_completion!.future);

  /// Observes ownership without retaining an ended registration's listeners.
  ///
  /// Entry removal allows the dispatch's completing microtasks to deliver an
  /// exact close receipt first. Host and Runtime retirement have no grace period.
  void bind(
    CCCancellationToken token,
    T retired,
    Zone producerZone, {
    bool entry = false,
  }) {
    if (!isPending) return;
    final remove = token.addListener(() {
      if (entry) {
        producerZone.run(() => _retireEntry(retired));
      } else {
        _finish(_SharedOutcome.success(retired));
      }
    });
    if (isPending) {
      _removers.add(remove);
    } else {
      remove();
    }
  }

  /// Ends an orphaned close without racing synchronous backend removal events.
  void _retireEntry(T retired) {
    if (!isPending || _entryDeadline != null) return;
    try {
      _entryDeadline = Timer(
        Duration.zero,
        () => _finish(_SharedOutcome.success(retired)),
      );
    } catch (_) {
      // A Host scheduler failure must not prevent route cleanup or keep a wait.
      _finish(_SharedOutcome.success(retired));
    }
  }

  /// Consumes late completion while retaining no owner after cancellation.
  void follow(Future<T> work) {
    unawaited(work.then<void>(_succeed, onError: _fail));
  }

  /// Accepts producer success only while a consumer still owns this operation.
  void _succeed(T value) => _finish(_SharedOutcome.success(value));

  /// Consumes failures even when the consumer's owner has already ended.
  void _fail(Object error, StackTrace stack) =>
      _finish(_SharedOutcome.failure(error, stack));

  /// Clears every retaining edge before delivering a single terminal outcome.
  void _finish(_SharedOutcome<T> outcome) {
    final completion = _completion;
    if (completion == null) return;
    _completion = null;
    _entryDeadline?.cancel();
    _entryDeadline = null;
    for (final remove in _removers) {
      remove();
    }
    _removers.clear();
    completion.complete(outcome);
  }
}

/// Starts producer observation outside any Runtime-owning closure frame.
///
/// Calling and observing in the same Host Zone preserves Dart's error delivery
/// contract. External Future listeners retain only [wait], never [callback].
void _observeNavigationBackend<T>(
  _NavigationBackendWait<T> wait,
  Future<T> Function() callback,
) => wait.follow(Future<T>.sync(callback));

/// Coordinates external navigation results without exporting ownership internals.
extension _CCRouterRuntimeBackendWait on CCRouterRuntime {
  /// Bounds a Pop/close by its exact owners without cancelling application work.
  Future<T> _awaitNavigationBackend<T>(
    Future<T> Function() callback, {
    required CCCancellationToken registration,
    required T retired,
    CCCancellationToken? entryRemoval,
  }) {
    final wait = _NavigationBackendWait<T>();
    final result = wait.result;
    final producerZone = _hostZone;
    wait.bind(appScope.cancellation, retired, producerZone);
    wait.bind(registration, retired, producerZone);
    if (entryRemoval != null) {
      wait.bind(entryRemoval, retired, producerZone, entry: true);
    }
    if (wait.isPending) {
      producerZone.run(() => _observeNavigationBackend(wait, callback));
    }
    return result;
  }
}
