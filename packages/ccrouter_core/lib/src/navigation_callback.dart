part of 'runtime.dart';

/// Installs one callback identity and returns cleanup for that registration only.
///
/// Simultaneous duplicate adds keep the existing deduplication semantics. Once
/// removed, a later add gets a fresh token so old queued events and removers
/// cannot affect the new subscription. The closure retains only this registry.
void Function() _subscribeNavigationObserver<T>(
  Map<T, Object> registry,
  T listener,
) {
  final token = registry.putIfAbsent(listener, Object.new);
  return () {
    if (identical(registry[listener], token)) registry.remove(listener);
  };
}

/// One queued batch of observational callbacks for the same framework event.
final class _QueuedNavigationObservation {
  /// Captures callbacks with a cursor advanced before each external invocation.
  _QueuedNavigationObservation({
    required Iterable<void Function()> callbacks,
    required this.critical,
  }) : _remaining = callbacks.iterator;

  /// Remaining observers; nested backpressure can finish this batch once only.
  final Iterator<void Function()> _remaining;

  /// Finishes earlier callbacks before a reentrant batch can overtake them.
  void dispatch() {
    while (_remaining.moveNext()) {
      _remaining.current();
    }
  }

  /// Whether dropping this batch would lose a terminal lifecycle transition.
  final bool critical;
}

/// Centralizes navigation callback isolation and reentrancy enforcement.
extension CCRouterRuntimeNavigationCallbacks on CCRouterRuntime {
  /// Throws when a framework-owned callback attempts to start navigation.
  ///
  /// Decision callbacks and observers execute in a Runtime-specific Zone. The
  /// Zone also follows asynchronous work spawned by the callback, preventing a
  /// delayed recursive operation from bypassing the same ownership boundary.
  /// Its identity token cannot keep an ended Runtime reachable on its own.
  void _ensureNavigationCanStart() {
    if (identical(
      Zone.current[CCRouterRuntime._navigationCallbackZoneKey],
      _zoneIdentity,
    )) {
      throw const CCNavigationReentrancyError();
    }
  }

  /// Executes one synchronous framework decision inside the protected Zone.
  ///
  /// Errors remain visible to the owning policy pipeline, which decides
  /// whether to fail closed, wrap the failure, or propagate it.
  T _runNavigationDecisionCallback<T>(T Function() callback) => runZoned(
    callback,
    zoneValues: {CCRouterRuntime._navigationCallbackZoneKey: _zoneIdentity},
  );

  /// Executes one asynchronous framework decision inside the protected Zone.
  ///
  /// The returned Future preserves the callback result and error so timeout,
  /// cancellation, and recovery remain the responsibility of the caller.
  Future<T> _runAsyncNavigationDecisionCallback<T>(
    FutureOr<T> Function() callback,
  ) => runZoned(
    () => Future<T>.sync(callback),
    zoneValues: {CCRouterRuntime._navigationCallbackZoneKey: _zoneIdentity},
  );

  /// Bounds a decision wait by Runtime lifetime and an optional deadline.
  ///
  /// Cancellation finishes the framework wait even if user code never returns.
  /// Late values/errors are consumed without executing another pipeline step.
  /// Listeners and the deadline Timer are released on every terminal path.
  Future<T> _awaitNavigationDecision<T>(
    FutureOr<T> Function() callback, {
    CCCancellationToken? cancellation,
    CCCancellationToken? requestCancellation,
    Duration? timeout,
    CCRouterError? timeoutError,
  }) => _awaitRuntimeWork(
    () => _runAsyncNavigationDecisionCallback(callback),
    cancellation: cancellation,
    requestCancellation: requestCancellation,
    timeout: timeout,
    timeoutError: timeoutError,
  );

  /// Joins owned work until completion, timeout, or Runtime cancellation.
  ///
  /// Unlike policy callbacks, backend transactions run outside the decision
  /// Zone. Late results/errors are consumed and cannot resume the caller after
  /// shutdown; arbitrary Dart work itself remains owned by the Backend.
  Future<T> _awaitRuntimeWork<T>(
    FutureOr<T> Function() callback, {
    CCCancellationToken? cancellation,
    CCCancellationToken? requestCancellation,
    Duration? timeout,
    CCRouterError? timeoutError,
  }) async {
    _ensureNavigationRequestAlive(requestCancellation);
    final interrupted = Completer<T>();
    void interrupt(CCRouterError error) {
      if (interrupted.isCompleted) return;
      interrupted.completeError(error);
      try {
        cancellation?.cancel();
      } catch (error) {
        _recordNavigationCallbackFailure(
          'Navigation cancellation listener failed: ${error.runtimeType}.',
        );
      }
    }

    final remove = appScope.cancellation.addListener(
      () => interrupt(const CCRouteCancelledError('runtime_disposed')),
    );
    final removeRequest = requestCancellation?.addListener(
      () => interrupt(
        const CCRouteCancelledError('route_information_superseded'),
      ),
    );
    final removeHost = _navigationOperation?.cancellation.addListener(
      () => interrupt(const CCRouteCancelledError('host_detached')),
    );
    final timer = timeout == null
        ? null
        : Timer(timeout, () => interrupt(timeoutError!));
    try {
      final work = Future<T>.sync(callback);
      final value = await Future.any([work, interrupted.future]);
      _ensureNavigationRequestAlive(requestCancellation);
      return value;
    } catch (_) {
      _ensureNavigationAlive(cancellation);
      _ensureNavigationRequestAlive(requestCancellation);
      rethrow;
    } finally {
      timer?.cancel();
      remove();
      removeRequest?.call();
      removeHost?.call();
    }
  }

  /// Fences a Host-owned ingress before any late policy or mutation step.
  void _ensureNavigationRequestAlive(CCCancellationToken? cancellation) {
    _ensureNavigationAlive();
    _navigationOperation?.ensureAlive();
    if (cancellation?.isCancelled == true) {
      throw const CCRouteCancelledError('route_information_superseded');
    }
  }

  /// Rejects continuation after shutdown, including gaps between awaited steps.
  void _ensureNavigationAlive([CCCancellationToken? cancellation]) {
    if (!_disposed) return;
    try {
      cancellation?.cancel();
    } catch (error) {
      _recordNavigationCallbackFailure(
        'Navigation cancellation listener failed: ${error.runtimeType}.',
      );
    }
    throw const CCRouteCancelledError('runtime_disposed');
  }

  /// Enqueues cancellable callbacks bound to their exact registration tokens.
  ///
  /// Registration identity is checked immediately before each callback, so
  /// removing and re-adding the same listener cannot revive queued delivery.
  /// [critical] is reserved for terminal lifecycle transitions that must not
  /// be discarded during queue overflow.
  void _enqueueRegisteredNavigationObserverBatch<T>(
    Map<T, Object> observers,
    void Function(T observer) notify, {
    required String failureLabel,
    bool critical = false,
  }) {
    _enqueueNavigationObserverBatch(
      observers.entries,
      (registration) => notify(registration.key),
      isActive: (registration) =>
          identical(observers[registration.key], registration.value),
      failureLabel: failureLabel,
      critical: critical,
    );
  }

  /// Enqueues a snapshot, retaining duplicate static Aspect callbacks in order.
  ///
  /// [isActive] runs immediately before each delivery. Dynamic subscriptions
  /// supply registration-token checks through the registered wrapper above.
  void _enqueueNavigationObserverBatch<T>(
    Iterable<T> observers,
    void Function(T observer) notify, {
    required bool Function(T observer) isActive,
    required String failureLabel,
    bool critical = false,
  }) {
    final snapshot = observers.toList(growable: false);
    if (snapshot.isEmpty || !_acceptingNavigationObservations) return;
    _enqueueNavigationObservation(
      _QueuedNavigationObservation(
        critical: critical,
        callbacks: snapshot.map(
          (observer) => () {
            if (!isActive(observer)) return;
            _invokeNavigationObserver(
              () => notify(observer),
              failureLabel: failureLabel,
            );
          },
        ),
      ),
    );
  }

  /// Adds one observation batch while preserving the bounded queue invariant.
  ///
  /// Overflow removes the oldest non-critical batch first. If every retained
  /// batch is terminal, the oldest one is delivered synchronously as explicit
  /// backpressure so terminal state is never silently lost.
  /// The incoming terminal batch reserves its slot before synchronous delivery,
  /// so reentrant reports preserve FIFO and cannot exceed queue capacity.
  /// Every accepted batch invalidates health, including Aspect-only observations
  /// with no retained navigation diagnostic to advance the revision for them.
  void _enqueueNavigationObservation(_QueuedNavigationObservation observation) {
    if (!_acceptingNavigationObservations) return;
    if (_navigationObservationQueue.length >= _navigationObservationCapacity) {
      final droppable = _navigationObservationQueue
          .where((queued) => !queued.critical)
          .firstOrNull;
      if (droppable != null) {
        _navigationObservationQueue.remove(droppable);
        _recordNavigationObservationOverflow(
          'Navigation observation queue overflowed; the oldest '
          'non-terminal batch was dropped.',
        );
      } else if (!observation.critical) {
        _recordNavigationObservationOverflow(
          'Navigation observation queue overflowed; an incoming '
          'non-terminal batch was dropped.',
        );
        return;
      } else {
        final oldest = _navigationObservationQueue.removeFirst();
        // Commit the incoming batch before callbacks can enqueue more work.
        _navigationObservationQueue.addLast(observation);
        _diagnosticRevision++;
        _scheduleNavigationObservationDrain();
        _recordNavigationObservationOverflow(
          'Navigation observation queue reached capacity; the oldest '
          'terminal batch was delivered with backpressure.',
        );
        _dispatchNavigationObservations([oldest]);
        return;
      }
    }
    _navigationObservationQueue.addLast(observation);
    _diagnosticRevision++;
    _scheduleNavigationObservationDrain();
  }

  /// Schedules one event-loop drain without creating a task per observation.
  void _scheduleNavigationObservationDrain() {
    if (_navigationObservationTimer != null ||
        _drainingNavigationObservations ||
        !_acceptingNavigationObservations) {
      return;
    }
    _navigationObservationTimer = Timer(Duration.zero, () {
      _navigationObservationTimer = null;
      if (!_acceptingNavigationObservations) return;
      _drainNavigationObservations();
    });
  }

  /// Delivers all currently queued observations in FIFO order.
  void _drainNavigationObservations() {
    if (_drainingNavigationObservations) return;
    _drainingNavigationObservations = true;
    final pending = <_QueuedNavigationObservation>[];
    while (_navigationObservationQueue.isNotEmpty) {
      pending.add(_navigationObservationQueue.removeFirst());
    }
    if (pending.isNotEmpty) _diagnosticRevision++;
    try {
      _dispatchNavigationObservations(pending);
    } finally {
      _drainingNavigationObservations = false;
      _navigationObservationOverflowRecorded = false;
      if (_navigationObservationQueue.isNotEmpty) {
        _scheduleNavigationObservationDrain();
      }
    }
  }

  /// Delivers an admitted batch list, helping earlier fan-out on nested pressure.
  ///
  /// A callback cursor advances before invocation. Reentrant delivery finishes
  /// the older listeners and admitted batches first, preserving each listener's
  /// FIFO without duplicating callbacks or expanding the waiting queue.
  void _dispatchNavigationObservations(
    Iterable<_QueuedNavigationObservation> observations,
  ) {
    _navigationObservationDeliveries.addAll(observations);
    while (_navigationObservationDeliveries.isNotEmpty) {
      final oldest = _navigationObservationDeliveries.first;
      oldest.dispatch();
      if (identical(_navigationObservationDeliveries.firstOrNull, oldest)) {
        _navigationObservationDeliveries.removeFirst();
      }
    }
  }

  /// Flushes queued observations and releases Timer-owned closures.
  ///
  /// Runtime disposal calls this only after all event producers have stopped.
  /// New batches are rejected before the synchronous flush begins.
  void _disposeNavigationObservations() {
    _acceptingNavigationObservations = false;
    _navigationObservationTimer?.cancel();
    _navigationObservationTimer = null;
    _drainNavigationObservations();
    _navigationObservationQueue.clear();
  }

  /// Records at most one overflow diagnostic for each queue drain cycle.
  void _recordNavigationObservationOverflow(String message) {
    if (_navigationObservationOverflowRecorded) return;
    _navigationObservationOverflowRecorded = true;
    _recordNavigationCallbackFailure(message);
  }

  /// Delivers one observation without allowing it to alter navigation.
  ///
  /// Observer failures are converted to bounded sanitized diagnostics.
  /// Observer contracts return void and must not start unawaited asynchronous
  /// work; keeping the parent error Zone ensures a navigation Future rejected
  /// for reentrancy can still be observed by its caller.
  /// [failureLabel] must identify only the framework callback kind and must
  /// never contain business data.
  void _invokeNavigationObserver(
    void Function() callback, {
    required String failureLabel,
  }) {
    try {
      runZoned(
        callback,
        zoneValues: {CCRouterRuntime._navigationCallbackZoneKey: _zoneIdentity},
      );
    } catch (error) {
      _recordNavigationCallbackFailure(
        '$failureLabel failed: ${error.runtimeType}.',
      );
    }
  }
}
