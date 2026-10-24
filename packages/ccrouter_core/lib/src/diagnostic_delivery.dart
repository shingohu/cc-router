part of 'runtime.dart';

/// Owns bounded diagnostic delivery independently of Runtime and its Scopes.
///
/// Pending application Futures retain only this delivery state through their
/// completion callbacks. Delivery runs in the creating Host Zone so nested
/// invocation Zones cannot retain the Runtime through Timer/Future callbacks.
/// Close releases the Sink and waiting payloads even if a write never completes.
final class _DiagnosticDelivery {
  /// Creates a per-Runtime FIFO using an already validated positive capacity.
  _DiagnosticDelivery({required CCDiagnosticSink? sink, required this.capacity})
    : _sink = sink,
      _zone = Zone.current;

  /// Maximum waiting events, excluding the one unfinished asynchronous write.
  final int capacity;

  /// Preserves Host context without inheriting later invocation Zone values.
  final Zone _zone;

  /// Host-owned destination, detached on close; Runtime never disposes it.
  CCDiagnosticSink? _sink;

  /// Waiting sanitized events, never detached into an additional batch buffer.
  final Queue<CCDiagnosticEvent> _queue = Queue();

  /// Deferred delivery, batch continuation, or terminal construction cleanup.
  Timer? _timer;

  /// Guards synchronous Sink reentrancy during a bounded drain batch.
  bool _draining = false;

  /// Writes left in this batch, shared across synchronous and Future completion.
  int _remaining = 0;

  /// Whether the current Sink Future still occupies the sole write slot.
  bool _writing = false;

  /// Prevents queued or late-completing work from starting after shutdown.
  bool _closed = false;

  /// Rejects reentrant acceptance while the final best-effort batch is drained.
  bool _closing = false;

  /// High-water mark for the waiting queue only.
  int _peakQueueDepth = 0;

  /// Successfully completed Sink writes.
  int _delivered = 0;

  /// Isolated synchronous and asynchronous Sink failures.
  int _failed = 0;

  /// Waiting events discarded on overflow or close.
  int _dropped = 0;

  /// Cached scalar health without Sink, event, Future or Runtime references.
  CCDiagnosticDeliverySnapshot? _snapshot;

  /// Copies changed state without exposing live queue ownership.
  /// Comparing scalars also detects late write completion after close, without
  /// adding cache invalidation work to the enqueue/drain hot path.
  CCDiagnosticDeliverySnapshot get snapshot {
    final cached = _snapshot;
    final queued = _queue.length;
    final inFlight = _writing ? 1 : 0;
    if (cached != null &&
        cached.queuedEventCount == queued &&
        cached.inFlightWriteCount == inFlight &&
        cached.peakQueueDepth == _peakQueueDepth &&
        cached.deliveredEventCount == _delivered &&
        cached.failedEventCount == _failed &&
        cached.droppedEventCount == _dropped &&
        cached.isClosed == _closed) {
      return cached;
    }
    return _snapshot = CCDiagnosticDeliverySnapshot(
      queueCapacity: capacity,
      queuedEventCount: queued,
      inFlightWriteCount: inFlight,
      peakQueueDepth: _peakQueueDepth,
      deliveredEventCount: _delivered,
      failedEventCount: _failed,
      droppedEventCount: _dropped,
      isClosed: _closed,
    );
  }

  /// Accepts a sanitized event without waiting for the external Sink.
  void enqueue(CCDiagnosticEvent event) {
    if (_closed || _closing || _sink == null) return;
    if (_queue.length == capacity) {
      _queue.removeFirst();
      _dropped++;
    }
    _queue.addLast(event);
    if (_queue.length > _peakQueueDepth) _peakQueueDepth = _queue.length;
    _schedule();
  }

  /// Schedules an event-loop boundary only when no write already owns progress.
  void _schedule() {
    if (_closed ||
        _closing ||
        _draining ||
        _writing ||
        _timer != null ||
        _queue.isEmpty) {
      return;
    }
    _zone.run(_scheduleBatch);
  }

  /// Creates the Timer in Host context, never in an enqueue caller's Zone.
  void _scheduleBatch() => _timer = Timer(Duration.zero, _startBatch);

  /// Starts a finite budget from a Timer or the idle shutdown's final attempt.
  void _startBatch() {
    _timer = null;
    if (_closed || _draining || _writing) return;
    _remaining = _queue.length;
    _drain();
  }

  /// Consumes this batch's budget or hands its remaining progress to one Future.
  void _drain() {
    if (_closed || _draining || _writing) return;
    _draining = true;
    // Future completions must share this budget too: resetting it here could
    // let reentrant Future.value/error writes starve the event loop indefinitely.
    try {
      while (!_closed && _queue.isNotEmpty && _remaining > 0) {
        _remaining--;
        final event = _queue.removeFirst();
        try {
          final result = _sink!.record(event);
          if (result is Future<void>) {
            _writing = true;
            unawaited(
              result.then<void>(_writeSucceeded, onError: _writeFailed),
            );
            if (_writing) return;
            // SynchronousFuture may release the slot inside then(). Keep the
            // current bounded batch moving without a timer for every event.
            continue;
          }
          _delivered++;
        } catch (_) {
          _failed++;
        }
      }
    } finally {
      _draining = false;
      _schedule();
    }
  }

  /// Releases the write slot and continues FIFO delivery after success.
  void _writeSucceeded(void _) {
    _delivered++;
    _writing = false;
    _drain();
  }

  /// Absorbs late errors too; diagnostic failures never re-enter the Runtime.
  void _writeFailed(Object _, StackTrace __) {
    _failed++;
    _writing = false;
    _drain();
  }

  /// Stops acceptance and makes one final best-effort drain if the slot is free.
  ///
  /// Synchronous Sinks keep their legacy shutdown delivery. An unfinished
  /// Future stops the final drain; all remaining queued events are discarded.
  /// Reentrant close during a write clears waiting data without recursive drain.
  void close() {
    if (_closed || _closing) return;
    _closing = true;
    _finishClose();
  }

  /// Stops acceptance after construction failure, preserving deferred logging.
  ///
  /// No Runtime was returned to the caller, so this delivery owner schedules
  /// its own final drain and cleanup without capturing the failed Runtime.
  /// Scheduling failures discard waiting data rather than mask startup errors.
  void closeDeferred() {
    if (_closed || _closing) return;
    _closing = true;
    try {
      _timer?.cancel();
      _timer = null;
      if (_queue.isEmpty) {
        _release();
      } else {
        _zone.run(_scheduleClose);
      }
    } catch (_) {
      _release();
    }
  }

  /// Creates the sole terminal Timer in Host context, never in a caller Zone.
  void _scheduleClose() => _timer = Timer(Duration.zero, _finishClose);

  /// Makes the final drain attempt and releases ownership even if it throws.
  void _finishClose() {
    if (_closed) return;
    try {
      _timer?.cancel();
      _timer = null;
      _zone.run(_startBatch);
    } finally {
      _release();
    }
  }

  /// Detaches the Host Sink and drops waiting payloads without cancelling writes.
  void _release() {
    _closed = true;
    _timer = null;
    _sink = null;
    _dropped += _queue.length;
    _queue.clear();
  }
}
