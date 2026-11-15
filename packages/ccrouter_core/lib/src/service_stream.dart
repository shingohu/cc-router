part of 'runtime.dart';

/// Creates Stream invocation state without entering or initializing a Service.
extension _CCRouterRuntimeServiceStream on CCRouterRuntime {
  /// Binds a Stream to its call-time owners rather than its later listener Zone.
  Stream<R> _createServiceStream<T extends Object, R>({
    CCServiceToken<T>? contractToken,
    CCServiceKey<T>? key,
    required String methodId,
    String? callerComponentId,
    String? navigationId,
    Duration? timeout,
    CCCancellationToken? cancellation,
    required Stream<R> Function(T, CCInvocationContext) call,
  }) {
    final invocation = _prepareServiceInvocation(
      contractToken: contractToken,
      key: key,
      methodId: methodId,
      callerComponentId: callerComponentId,
      navigationId: navigationId,
    );
    final parent = _parentContext;
    final now = DateTime.now();
    final requested = timeout == null ? null : now.add(timeout);
    final inherited = parent?.deadline;
    final deadline = requested == null
        ? inherited
        : inherited == null || requested.isBefore(inherited)
        ? requested
        : inherited;
    final context = _context(
      invocation.scope.id,
      operation: 'service',
      target: invocation.target,
      callerComponentId: callerComponentId,
      targetComponentId: invocation.provider.ownerComponentId,
      deadline: deadline,
      cancellation: _hostZone.run(CCCancellationToken.new),
    );
    final values = _invocationZoneValues(context, ownerScope: invocation.scope);
    final ownership =
        (values[CCRouterRuntime._invocationZoneKey] as _InvocationFrame)
            .ownership;
    final zone = Zone.current.fork(zoneValues: values);
    final execution = _hostZone.run(
      () => _ServiceStreamInvocation<R>(
        context: context,
        zone: zone,
        cleanupZone: _hostZone.fork(zoneValues: values),
        tokens: {
          ...ownership._tokens,
          if (parent != null) parent.cancellation,
          if (cancellation != null) cancellation,
        },
        scopes: ownership.scopes,
        start: () async {
          _ensureInvocationCanEnter(context, ownerScope: invocation.scope);
          final service =
              await _resolveReady(
                    invocation.provider,
                    context,
                    routeEntry: invocation.routeEntry,
                  )
                  as T;
          _ensureInvocationCanEnter(context, ownerScope: invocation.scope);
          return call(service, context);
        },
        reportCleanup: _serviceStreamCleanupReporter(
          WeakReference(this),
          context,
          invocation.target,
        ),
        record: _serviceStreamTrace(
          WeakReference(this),
          context,
          invocation.target,
          now,
        ),
      ),
    );
    return execution;
  }
}

/// Retains no Runtime, Provider or Scope while an external cancel Future waits.
void Function(Duration, String, String?) _serviceStreamTrace(
  WeakReference<CCRouterRuntime> runtime,
  CCInvocationContext context,
  String target,
  DateTime startedAt,
) =>
    (duration, status, errorType) => runtime.target?._recordTrace(
      context: context,
      operation: 'service',
      target: target,
      startedAt: startedAt,
      duration: duration,
      status: status,
      errorType: errorType,
    );

/// Observes cleanup in its cancellation Zone before crossing error Zones as data.
/// The pending source Future retains only this outcome relay, not a wait frame.
_SharedResult<void> _cancelServiceStreamSubscription(
  StreamSubscription<dynamic> subscription,
  Zone cancellationZone,
) {
  final result = _SharedResult<void>();
  cancellationZone.run(() {
    try {
      result.follow(subscription.cancel());
    } catch (error, stack) {
      result.fail(error, stack);
    }
  });
  return result;
}

/// Reports cleanup failures independently of the primary invocation outcome.
void Function(String) _serviceStreamCleanupReporter(
  WeakReference<CCRouterRuntime> runtime,
  CCInvocationContext context,
  String target,
) =>
    (errorType) => runtime.target?._emitDiagnostic(
      category: CCDiagnosticCategory.lifecycle,
      level: CCDiagnosticLevel.error,
      operation: 'serviceStreamCleanup',
      occurredAt: DateTime.now(),
      status: 'failed',
      duration: Duration.zero,
      invocationId: context.invocationId,
      traceId: context.traceId,
      spanId: context.spanId,
      target: target,
      scopeId: context.scopeId,
      callerComponentId: context.callerComponentId,
      targetComponentId: context.targetComponentId,
      errorType: errorType,
    );

/// Original terminal failure; a null stack means explicit consumer cancellation.
final class _ServiceStreamFailure {
  /// Preserves failure identity without formatting or logging its payload.
  const _ServiceStreamFailure(this.error, this.stack);

  /// Original failure delivered or returned to the appropriate consumer.
  final Object error;

  /// Original stack, absent when cancel must emit no terminal event.
  final StackTrace? stack;
}

/// Owns producer work separately from consumer delivery and its clearable queue.
final class _ServiceStreamInvocation<R> extends Stream<R> {
  /// Captures lazy startup and registers only weak references with live Scopes.
  _ServiceStreamInvocation({
    required this.context,
    required Zone zone,
    required Zone cleanupZone,
    required Set<CCCancellationToken> tokens,
    required List<WeakReference<CCScope>> scopes,
    required Future<Stream<R>> Function() start,
    required void Function(Duration, String, String?) record,
    required void Function(String) reportCleanup,
  }) : _zone = zone,
       _cleanupZone = cleanupZone,
       _tokens = tokens,
       _scopes = List.of(scopes),
       _start = start,
       _record = record,
       _reportCleanup = reportCleanup {
    _pending = WeakReference(this);
    for (final reference in _scopes) {
      final scope = reference.target;
      if (scope == null || scope.state != CCScopeState.active) {
        _cancelUnlistened();
        break;
      }
      scope._pendingServiceStreams.removeWhere((entry) => entry.target == null);
      scope._pendingServiceStreams.add(_pending);
    }
  }

  /// Payload-free invocation identity and cooperative cancellation signal.
  final CCInvocationContext context;

  /// Host context for retained outcome records, without short-lived callers.
  final Zone _ownerZone = Zone.current;

  /// Original producer context, released when producer work terminates.
  Zone? _zone;

  /// Host wait context preserving explicit invocation ownership signals.
  Zone? _cleanupZone;

  /// Lifetime signals retained until delivery ends or is interrupted.
  final Set<CCCancellationToken> _tokens;

  /// Concrete owners referenced weakly for cleanup barriers.
  final List<WeakReference<CCScope>> _scopes;

  /// Weak registration used before the first subscription exists.
  late final WeakReference<_ServiceStreamInvocation<R>> _pending;

  /// Consumer-owned delivery state, detached on cancellation or done.
  _ServiceStreamSubscription<R>? _consumer;

  /// Startup callback, never retained after entry or abandonment.
  Future<Stream<R>> Function()? _start;

  /// Weak Runtime observation retained until the invocation reaches its end.
  void Function(Duration, String, String?)? _record;

  /// Sanitized cleanup observation, independent of primary error precedence.
  void Function(String)? _reportCleanup;

  /// Actual upstream subscription, released before awaiting its cancel Future.
  StreamSubscription<R>? _subscription;

  /// Source cleanup outcome transferred to the consumer on listen.
  _SharedResult<void>? _cleanup = _SharedResult<void>();

  /// Joins cancellation reentry during startup or upstream listen.
  Completer<void>? _connecting;

  /// Removable original owner and invocation cancellation listeners.
  final List<void Function()> _removers = [];

  /// Whole-invocation deadline, including paused delivery.
  Timer? _timer;

  /// Call-time duration; unlistened calls never emit a method Trace.
  final Stopwatch _watch = Stopwatch()..start();

  /// Single-subscription admission flag.
  bool _listened = false;

  /// Whether producer work has reached its first terminal boundary.
  bool _stopped = false;

  /// Whether upstream done already includes native subscription cleanup.
  bool _sourceDone = false;

  /// Whether source cleanup has settled, independently of delivery pause.
  bool _cleanupFinished = false;

  /// Whether queued business events have been invalidated.
  bool _interrupted = false;

  /// Whether consumer done/cancel has released invocation observations.
  bool _deliveryEnded = false;

  /// Primary terminal cause, retained only until handed to the consumer.
  _ServiceStreamFailure? _terminalFailure;

  /// First notification failure to preserve in the cleanup receipt.
  _ServiceStreamFailure? _notificationFailure;

  /// Source failure type only; no business exception is retained in Trace state.
  String? _sourceErrorType;

  /// Validates callbacks before admitting one lazy subscription.
  @override
  StreamSubscription<R> listen(
    void Function(R)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (_listened) throw StateError('Stream has already been listened to.');
    final receipt =
        _cleanup ?? _ownerZone.run(() => _SharedResult<void>()..complete(null));
    final consumer = _ServiceStreamSubscription<R>(
      this,
      receipt,
      onData,
      onError,
      onDone,
      cancelOnError == true,
    );
    _listened = true;
    _consumer = consumer;
    _detachPending();
    if (_cleanupFinished) {
      // A discarded lazy call still delivers cancellation after listen returns.
      scheduleMicrotask(_publishTerminal);
    } else if (!_stopped) {
      _begin();
    }
    return consumer;
  }

  /// Installs cleanup ownership before entering any application callback.
  void _begin() {
    for (final scope in _scopes) {
      scope.target?._serviceStreams.add(_cleanup!);
    }
    for (final token in _tokens) {
      final remove = token.addListener(
        () => _stop(const CCInvocationCancelledError(), StackTrace.current),
      );
      if (_stopped) {
        remove();
        break;
      }
      _removers.add(remove);
    }
    if (_stopped) return;
    final deadline = context.deadline;
    if (deadline != null) {
      final micros = deadline.difference(DateTime.now()).inMicroseconds;
      if (micros <= 0) {
        _stop(const CCInvocationTimeoutError(), StackTrace.current);
        return;
      }
      _timer = Timer(
        Duration(milliseconds: (micros + 999) ~/ 1000),
        () => _stop(const CCInvocationTimeoutError(), StackTrace.current),
      );
    }
    _connecting = Completer<void>();
    _zone!.run(() => unawaited(_connect()));
  }

  /// Removes weak registrations on listen or any terminal boundary.
  void _detachPending() {
    for (final scope in _scopes) {
      scope.target?._pendingServiceStreams.remove(_pending);
    }
  }

  /// Releases unclaimed startup state without creating a Service or method Trace.
  void _cancelUnlistened() {
    if (_listened || _stopped) return;
    _record = null;
    _stop(const CCInvocationCancelledError(), StackTrace.current);
  }

  /// Attaches once and consumes late startup failures after cancellation.
  Future<void> _connect() async {
    try {
      final start = _start!;
      _start = null;
      final source = await start();
      _subscription = source.listen(_data, onError: _error, onDone: _done);
      if (_consumer?.isPaused == true) _subscription!.pause();
    } catch (error, stack) {
      if (!_stopped) _stop(error, stack);
    } finally {
      _connecting!.complete();
    }
  }

  /// Preserves invocation identity without replacing the control caller's error Zone.
  void _controlSource(void Function(StreamSubscription<R>) control) {
    final source = _subscription;
    if (source == null) return;
    final frame = _zone?[CCRouterRuntime._invocationZoneKey];
    if (frame == null) {
      control(source);
      return;
    }
    runZoned(
      () => control(source),
      zoneValues: {CCRouterRuntime._invocationZoneKey: frame},
    );
  }

  /// Applies consumer backpressure to the actual source.
  void _pauseSource() => _controlSource((source) => source.pause());

  /// Resumes the source; nested event callbacks are serialized by the consumer.
  void _resumeSource() => _controlSource((source) => source.resume());

  /// Admits ordered values only while the original invocation is live.
  void _data(R value) {
    if (!_stopped && _canDeliver())
      _consumer?._add(_ServiceStreamEvent<R>.data(value));
  }

  /// Retains only failure type in Trace while forwarding the original error/stack.
  void _error(Object error, StackTrace stack) {
    if (_stopped || !_canDeliver()) return;
    _sourceErrorType ??= error.runtimeType.toString();
    _consumer?._add(_ServiceStreamEvent<R>.error(error, stack, Zone.current));
  }

  /// Ends upstream work while preserving lifetime fences for pending delivery.
  void _done() {
    _sourceDone = true;
    if (_stopped || !_canDeliver()) return;
    if (_consumer?._hasPendingDelivery != true) _releaseSignals();
    _stop();
  }

  /// Checks wall-clock expiry even before its Timer callback is dispatched.
  bool _canDeliver() {
    if (_interrupted || _deliveryEnded) return false;
    final deadline = context.deadline;
    if (deadline != null && !deadline.isAfter(DateTime.now())) {
      _stop(const CCInvocationTimeoutError(), StackTrace.current);
      return false;
    }
    return true;
  }

  /// Consumer cancellation keeps the initiating error Zone and emits no event.
  void _cancelConsumer(_ServiceStreamSubscription<R> consumer, Zone origin) {
    if (identical(_consumer, consumer)) _consumer = null;
    if (!_deliveryEnded)
      _stop(const CCInvocationCancelledError(), null, origin);
    if (_cleanupFinished) _endDelivery();
  }

  /// Drops queued payloads immediately, before any asynchronous cleanup wait.
  void _interrupt(Object error, StackTrace? stack) {
    _interrupted = true;
    _terminalFailure = _ServiceStreamFailure(error, stack);
    _releaseSignals();
    _consumer?._interrupt();
    try {
      context.cancellation.cancel();
    } catch (failure, trace) {
      _notificationFailure ??= _ServiceStreamFailure(failure, trace);
      _reportCleanup?.call(failure.runtimeType.toString());
    }
  }

  /// Releases cancellation listeners and the deadline on interruption or delivery end.
  void _releaseSignals() {
    _timer?.cancel();
    _timer = null;
    for (final remove in _removers) {
      remove();
    }
    _removers.clear();
    _tokens.clear();
  }

  /// Starts cleanup once; an ended producer may still have interruptible delivery.
  void _stop([Object? error, StackTrace? stack, Zone? origin]) {
    if (_deliveryEnded) return;
    if (_stopped) {
      if (error != null && !_interrupted) {
        _interrupt(error, stack);
        if (_cleanupFinished) {
          _recordTerminal();
          _publishTerminal();
        }
      }
      return;
    }
    _stopped = true;
    _detachPending();
    _start = null;
    var cancellationZone = _zone;
    if (origin != null) {
      final frame = cancellationZone?[CCRouterRuntime._invocationZoneKey];
      cancellationZone = origin.fork(
        zoneValues: {
          if (frame != null) CCRouterRuntime._invocationZoneKey: frame,
        },
      );
    }
    if (error != null) {
      cancellationZone!.run(() => _interrupt(error, stack));
    }
    _zone = null;
    _cleanupZone!.run(() => unawaited(_finish(cancellationZone)));
  }

  /// Joins source cleanup as data, then releases producer and Scope references.
  Future<void> _finish(Zone? cancellationZone) async {
    var failure = _notificationFailure;
    final receipt = _cleanup!;
    try {
      await _connecting?.future;
      _connecting = null;
      final cancelling = _sourceDone || _subscription == null
          ? null
          : _cancelServiceStreamSubscription(_subscription!, cancellationZone!);
      _subscription = null;
      cancellationZone = null;
      if (cancelling != null) await cancelling.wait();
    } catch (error, stack) {
      failure ??= _ServiceStreamFailure(error, stack);
      _reportCleanup?.call(error.runtimeType.toString());
    }
    _subscription = null;
    _connecting = null;
    _cleanupZone = null;
    _notificationFailure = null;
    for (final scope in _scopes) {
      scope.target?._serviceStreams.remove(receipt);
    }
    _scopes.clear();
    _cleanupFinished = true;
    if (_terminalFailure == null && failure != null) _terminalFailure = failure;
    if (failure == null) {
      receipt.complete(null);
    } else {
      receipt.fail(failure.error, failure.stack!);
    }
    _cleanup = null;
    if (_interrupted || _consumer == null) _recordTerminal();
    _publishTerminal();
  }

  /// Transfers the final notification to consumer-owned storage, once per ending.
  void _publishTerminal() {
    final consumer = _consumer;
    if (consumer == null) {
      if (_listened) _endDelivery();
      return;
    }
    final failure = _terminalFailure;
    _terminalFailure = null;
    consumer._end(failure?.stack == null ? null : failure);
  }

  /// Records a single terminal observation without retaining exception payloads.
  void _recordTerminal() {
    final record = _record;
    _record = null;
    _watch.stop();
    final error = _terminalFailure?.error;
    record?.call(
      _watch.elapsed,
      error is CCInvocationCancelledError
          ? 'cancelled'
          : error is CCInvocationTimeoutError
          ? 'timedOut'
          : error != null || _sourceErrorType != null
          ? 'failed'
          : 'succeeded',
      error?.runtimeType.toString() ?? _sourceErrorType,
    );
  }

  /// Releases invocation observations when no more business payload can be delivered.
  void _endDelivery() {
    if (_deliveryEnded) return;
    _deliveryEnded = true;
    _releaseSignals();
    _recordTerminal();
    _terminalFailure = null;
    _notificationFailure = null;
    _reportCleanup = null;
    _consumer = null;
  }
}
