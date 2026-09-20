part of 'runtime.dart';

/// One queued batch of observational callbacks for the same framework event.
final class _QueuedNavigationObservation {
  /// Creates a batch whose callbacks share one priority and diagnostic label.
  const _QueuedNavigationObservation({
    required this.dispatch,
    required this.critical,
  });

  /// Delivers the snapshot of observers retained by this batch.
  final void Function() dispatch;

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
  void _ensureNavigationCanStart() {
    if (identical(
      Zone.current[CCRouterRuntime._navigationCallbackZoneKey],
      this,
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
    zoneValues: {CCRouterRuntime._navigationCallbackZoneKey: this},
  );

  /// Executes one asynchronous framework decision inside the protected Zone.
  ///
  /// The returned Future preserves the callback result and error so timeout,
  /// cancellation, and recovery remain the responsibility of the caller.
  Future<T> _runAsyncNavigationDecisionCallback<T>(
    FutureOr<T> Function() callback,
  ) => runZoned(
    () => Future<T>.sync(callback),
    zoneValues: {CCRouterRuntime._navigationCallbackZoneKey: this},
  );

  /// Enqueues one event for a snapshot of observational subscribers.
  ///
  /// [isActive] is evaluated immediately before each callback, so removing a
  /// listener before the next event-loop turn also cancels queued delivery.
  /// [critical] is reserved for terminal lifecycle transitions that must not
  /// be discarded during queue overflow.
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
        dispatch: () {
          for (final observer in snapshot) {
            if (!isActive(observer)) continue;
            _invokeNavigationObserver(
              () => notify(observer),
              failureLabel: failureLabel,
            );
          }
        },
      ),
    );
  }

  /// Adds one observation batch while preserving the bounded queue invariant.
  ///
  /// Overflow removes the oldest non-critical batch first. If every retained
  /// batch is terminal, the oldest one is delivered synchronously as explicit
  /// backpressure so terminal state is never silently lost.
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
        _recordNavigationObservationOverflow(
          'Navigation observation queue reached capacity; the oldest '
          'terminal batch was delivered with backpressure.',
        );
        oldest.dispatch();
      }
    }
    _navigationObservationQueue.addLast(observation);
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
    try {
      for (final observation in pending) {
        observation.dispatch();
      }
    } finally {
      _drainingNavigationObservations = false;
      _navigationObservationOverflowRecorded = false;
      if (_navigationObservationQueue.isNotEmpty) {
        _scheduleNavigationObservationDrain();
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
        zoneValues: {CCRouterRuntime._navigationCallbackZoneKey: this},
      );
    } catch (error) {
      _recordNavigationCallbackFailure(
        '$failureLabel failed: ${error.runtimeType}.',
      );
    }
  }
}
