part of 'runtime.dart';

/// One consumer-owned event; the entire queue can be cleared at an Owner boundary.
final class _ServiceStreamEvent<R> {
  /// Holds an admitted value only until synchronous delivery or cancellation.
  const _ServiceStreamEvent.data(R value)
    : value = value,
      error = null,
      stack = null,
      origin = null,
      done = false,
      terminal = false;

  /// Preserves source errors and their cancellation context without string wrapping.
  const _ServiceStreamEvent.error(
    this.error,
    this.stack,
    this.origin, {
    this.terminal = false,
  }) : value = null,
       done = false;

  /// Marks completion after every previously admitted event.
  const _ServiceStreamEvent.done()
    : value = null,
      error = null,
      stack = null,
      origin = null,
      done = true,
      terminal = true;

  /// Typed data, including legitimate null values.
  final R? value;

  /// Original error for an error event.
  final Object? error;

  /// Original stack accompanying an error.
  final StackTrace? stack;

  /// Source event Zone used for automatic cancelOnError.
  final Zone? origin;

  /// Whether this is the final done notification.
  final bool done;

  /// Whether this error belongs to the already-completed cleanup boundary.
  final bool terminal;
}

/// Implements Dart subscription callbacks over a queue with explicit payload ownership.
final class _ServiceStreamSubscription<R> implements StreamSubscription<R> {
  /// Registers callbacks before acquiring the invocation's single subscription.
  _ServiceStreamSubscription(
    this._owner,
    this._receipt,
    void Function(R)? data,
    Function? error,
    void Function()? done,
    this._cancelOnError,
  ) {
    onData(data);
    onError(error);
    onDone(done);
  }

  /// Invocation reference, released immediately on explicit cancel or done.
  _ServiceStreamInvocation<R>? _owner;

  /// Shared cleanup outcome, owned here rather than by a retained completed Stream.
  _SharedResult<void>? _receipt;

  /// Memoized cancellation outcome as data, safe for joining error Zones.
  _SharedResult<void>? _cancelReceipt;

  /// Consumer callback context, never substituted with the producer error Zone.
  final Zone _zone = Zone.current;

  /// Pending payloads, cleared synchronously on cancellation or Owner interruption.
  final Queue<_ServiceStreamEvent<R>> _queue = Queue();

  /// Registered data handler in the original listener Zone.
  void Function(R)? _onData;

  /// Registered one- or two-argument error handler in the listener Zone.
  Function? _onError;

  /// Registered done handler in the listener Zone.
  void Function()? _onDone;

  /// Original listener's cancelOnError policy.
  final bool _cancelOnError;

  /// Native pause count; signals and explicit resumes are interchangeable.
  int _pauses = 0;

  /// Prevents overlapping event callbacks during synchronous source reentry.
  bool _draining = false;

  /// At most one queued delivery microtask exists per subscription.
  bool _scheduled = false;

  /// Explicit or automatic cancellation suppresses future done notifications.
  bool _cancelled = false;

  /// Whether the done notification has been accepted.
  bool _done = false;

  /// Whether terminal notifications have been queued.
  bool _ending = false;

  /// Weak signal leases preserve pause context without owning abandoned Futures.
  final Set<WeakReference<_ServiceStreamResumeWait>> _resumeWaits = {};

  /// Accepted cancelOnError event; explicit cancel can still suppress delivery.
  _ServiceStreamEvent<R>? _errorAfterCancel;

  /// Pending resume-hook events still need original Owner and deadline fences.
  bool get _hasPendingDelivery => _queue.isNotEmpty || _draining;

  /// Replaces the data handler without changing its original callback Zone.
  @override
  void onData(void Function(R)? handleData) => _onData = handleData == null
      ? null
      : _zone.registerUnaryCallback<void, R>(handleData);

  /// Validates native Dart error-handler arity before registering it.
  @override
  void onError(Function? handleError) {
    if (handleError == null) {
      _onError = null;
    } else if (handleError is void Function(Object, StackTrace)) {
      _onError = _zone.registerBinaryCallback<void, Object, StackTrace>(
        handleError,
      );
    } else if (handleError is void Function(Object)) {
      _onError = _zone.registerUnaryCallback<void, Object>(handleError);
    } else {
      throw ArgumentError(
        'Error handler must accept Object or Object and StackTrace.',
      );
    }
  }

  /// Replaces the done callback in the original listener Zone.
  @override
  void onDone(void Function()? handleDone) => _onDone = handleDone == null
      ? null
      : _zone.registerCallback<void>(handleDone);

  /// Cancels once and restores each joining caller's original cleanup failure.
  @override
  Future<void> cancel() => _cancelInZone(Zone.current);

  /// Chooses the native cancellation origin while releasing callbacks immediately.
  Future<void> _cancelInZone(Zone origin, {bool fromError = false}) {
    if (!fromError) {
      _errorAfterCancel = null;
      _onError = null;
    }
    _onData = null;
    _onDone = null;
    final previous = _cancelReceipt;
    if (previous != null) return previous.wait();
    if (_done) return Future<void>.value();
    _cancelled = true;
    _releaseResumeWaits();
    _queue.clear();
    final receipt = _receipt!;
    _cancelReceipt = receipt;
    _receipt = null;
    final owner = _owner;
    _owner = null;
    if (!fromError) _onError = null;
    owner?._cancelConsumer(this, origin);
    return receipt.wait();
  }

  /// Pauses upstream once on the transition from flowing to paused.
  @override
  void pause([Future<void>? resumeSignal]) {
    if (_done || _cancelled) return;
    _pauses++;
    if (resumeSignal != null) {
      final wait = _ServiceStreamResumeWait(
        this,
        Zone.current,
        _zone.errorZone,
      );
      _resumeWaits.removeWhere((entry) => entry.target == null);
      _resumeWaits.add(WeakReference(wait));
      _observeServiceStreamResumeSignal(
        resumeSignal,
        wait,
        Zone.current.errorZone,
      );
    }
    if (_pauses == 1) _owner?._pauseSource();
  }

  /// Cancels caller-context retention even when a signal Future never settles.
  void _releaseResumeWaits() {
    for (final wait in _resumeWaits) {
      wait.target?.release();
    }
    _resumeWaits.clear();
  }

  /// Resumes upstream with native synchronous hook timing and serialized callbacks.
  @override
  void resume() {
    if (_done || _cancelled || _pauses == 0) return;
    _pauses--;
    if (_pauses != 0) return;
    _owner?._resumeSource();
    _schedule();
  }

  /// Cancelled and completed subscriptions are never considered paused.
  @override
  bool get isPaused => !_done && !_cancelled && _pauses > 0;

  /// Implements native asFuture replacement and waits for error cancellation cleanup.
  @override
  Future<E> asFuture<E>([E? futureValue]) {
    if (futureValue == null && null is! E)
      throw ArgumentError.notNull('futureValue');
    final value = futureValue as E;
    final completion = Completer<E>();
    onDone(() => completion.complete(value));
    onError((Object error, StackTrace stack) {
      unawaited(
        cancel().then<void>(
          (_) => completion.completeError(error, stack),
          onError: (Object _, StackTrace __) =>
              completion.completeError(error, stack),
        ),
      );
    });
    return completion.future;
  }

  /// Accepts source events without adding any opaque SDK payload queue.
  void _add(_ServiceStreamEvent<R> event) {
    if (_cancelled || _done) return;
    _queue.addLast(event);
    if (!isPaused && !_draining) _drain();
  }

  /// Owner interruption discards both queued values and queued business errors.
  void _interrupt() {
    _queue.clear();
    _ending = false;
  }

  /// Appends the terminal error, if any, followed by native done semantics.
  void _end(_ServiceStreamFailure? failure) {
    if (_cancelled || _done || _ending) return;
    _ending = true;
    if (failure != null)
      _queue.addLast(
        _ServiceStreamEvent<R>.error(
          failure.error,
          failure.stack!,
          null,
          terminal: true,
        ),
      );
    _queue.addLast(_ServiceStreamEvent<R>.done());
    if (!isPaused && !_draining) _drain();
  }

  /// Schedules pending resumed events in the listener's original scheduler.
  void _schedule() {
    if (_scheduled || _queue.isEmpty || isPaused || _done || _cancelled) return;
    _scheduled = true;
    _zone.scheduleMicrotask(() {
      _scheduled = false;
      _drain();
    });
  }

  /// Serializes callbacks while rechecking ownership at each business event.
  void _drain() {
    if (_draining || isPaused || _done || _cancelled) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty && !isPaused && !_done && !_cancelled) {
        final event = _queue.removeFirst();
        if (!event.terminal && _owner?._canDeliver() != true) continue;
        if (event.done) {
          _done = true;
          _releaseResumeWaits();
          final handler = _onDone;
          final owner = _owner;
          _owner = null;
          _receipt = null;
          _onData = null;
          _onError = null;
          _onDone = null;
          owner?._endDelivery();
          if (handler != null) _zone.runGuarded(handler);
        } else if (event.error != null) {
          final handler = _onError;
          if (_cancelOnError) {
            _errorAfterCancel = event;
            final work = _zone.run(
              () => _cancelInZone(event.origin ?? _zone, fromError: true),
            );
            _zone.run(
              () => unawaited(_reportServiceStreamErrorAfterCancel(work, this)),
            );
          } else {
            _dispatchServiceStreamError(
              _zone,
              handler,
              event.error!,
              event.stack!,
            );
          }
        } else {
          final handler = _onData;
          if (handler != null) _zone.runUnaryGuarded(handler, event.value as R);
        }
      }
    } finally {
      _draining = false;
    }
  }

  /// Reads the latest handler, matching Dart changes made during async cancel.
  void _completeErrorAfterCancel() {
    final event = _errorAfterCancel;
    _errorAfterCancel = null;
    if (event == null) return;
    final handler = _onError;
    _onData = null;
    _onError = null;
    _onDone = null;
    _dispatchServiceStreamError(_zone, handler, event.error!, event.stack!);
  }
}

/// Dispatches original errors through the same callback arity rules as Dart streams.
void _dispatchServiceStreamError(
  Zone zone,
  Function? handler,
  Object error,
  StackTrace stack,
) {
  if (handler == null) {
    zone.handleUncaughtError(error, stack);
  } else if (handler is void Function(Object, StackTrace)) {
    zone.runBinaryGuarded(handler, error, stack);
  } else {
    zone.runUnaryGuarded(handler as void Function(Object), error);
  }
}

/// Keeps the source error primary after cancelOnError, with cleanup diagnosed separately.
Future<void> _reportServiceStreamErrorAfterCancel(
  Future<void> cleanup,
  _ServiceStreamSubscription<dynamic> consumer,
) async {
  try {
    await cleanup;
  } catch (_) {
    /* Already reported independently. */
  }
  consumer._completeErrorAfterCancel();
}

/// One pause signal retains its caller context only while the consumer is live.
final class _ServiceStreamResumeWait {
  /// Captures native resume context separately from its final error destination.
  _ServiceStreamResumeWait(this._consumer, this._caller, this._errorZone);

  /// Cleared on cancel/done so pending caller Futures cannot retain the consumer.
  _ServiceStreamSubscription<dynamic>? _consumer;

  /// Original pause scheduler and values, released at either terminal boundary.
  Zone? _caller;

  /// Native unhandled-error domain, without short-lived child Zone values.
  final Zone _errorZone;

  /// Releases both strong references before invoking potentially reentrant resume.
  void complete() {
    final consumer = _consumer;
    final caller = _caller;
    release();
    if (consumer != null && caller != null) caller.run(consumer.resume);
  }

  /// Resume still occurs for failed signals; errors remain unhandled as in Dart.
  void fail(Object error, StackTrace stack) {
    complete();
    _errorZone.handleUncaughtError(error, stack);
  }

  /// Detaches an unfinished signal without suppressing its future error reporting.
  void release() {
    _consumer = null;
    _caller = null;
  }
}

/// Keeps Future callbacks outside the subscription method's captured frame.
void _observeServiceStreamResumeSignal(
  Future<void> signal,
  _ServiceStreamResumeWait wait,
  Zone observationZone,
) {
  observationZone.run(
    () => unawaited(
      signal.then<void>((_) => wait.complete(), onError: wait.fail),
    ),
  );
}
