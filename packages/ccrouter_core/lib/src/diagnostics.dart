part of 'runtime.dart';

/// Capacity and completeness of one named, payload-free diagnostic history.
final class CCDiagnosticHistorySnapshot {
  /// Captures counts since this Runtime was constructed.
  const CCDiagnosticHistorySnapshot({
    required this.name,
    required this.capacity,
    required this.retainedCount,
    required this.omittedCount,
  });

  /// Framework-defined history name, not a caller-supplied label.
  final String name;

  /// Per-history retention limit; zero disables retention.
  final int capacity;

  /// Records currently retained; this is not a lifetime success count.
  final int retainedCount;

  /// Observations not retained because of zero capacity or capacity rotation.
  /// Independent of external Sink filtering/sampling; queue losses have their
  /// own delivery counter, while filtering/sampling counts are not exposed.
  final int omittedCount;
}

/// Lightweight diagnostic health without copying event or Trace histories.
///
/// This read-only business/tooling value contains no Runtime back-reference.
/// Use it to explain incomplete histories and detect changes before reading
/// full snapshots. It is not a replay, audit, or delivery acknowledgement.
final class CCDiagnosticSnapshot {
  /// Captures one Runtime's revision, history limits and external delivery.
  CCDiagnosticSnapshot({
    required this.runtimeId,
    required this.revision,
    required this.sinkConfigured,
    required this.delivery,
    required Iterable<CCDiagnosticHistorySnapshot> histories,
  }) : histories = List.unmodifiable(histories);

  /// Non-reusable Runtime identity distinguishing shutdown/reinitialization.
  final String runtimeId;

  /// Monotonic in-Runtime observation revision, independent of Sink policies.
  /// Delivery completion counters may change without advancing this revision.
  final int revision;

  /// Whether the Host configured an external Sink, independent of filtering.
  final bool sinkConfigured;

  /// Bounded external queue/write health, including losses and Sink failures.
  final CCDiagnosticDeliverySnapshot delivery;

  /// Completeness of invocation, navigation, Entry, visibility and backend rings.
  /// Live state and removed backend ledger retention are not event histories.
  final List<CCDiagnosticHistorySnapshot> histories;
}

/// Collects payload-free history counts without adding timers or listeners.
extension CCRouterRuntimeDiagnosticHealth on CCRouterRuntime {
  /// Returns lightweight health suitable for an optional mounted debug panel.
  /// Reuses an immutable value while both observations and delivery are stable.
  CCDiagnosticSnapshot get diagnosticSnapshot {
    final delivery = diagnosticDeliverySnapshot;
    final cached = _diagnosticSnapshot;
    if (cached != null &&
        cached.revision == _diagnosticRevision &&
        identical(cached.delivery, delivery)) {
      return cached;
    }
    return _diagnosticSnapshot = CCDiagnosticSnapshot(
      runtimeId: _runtimeId,
      revision: _diagnosticRevision,
      sinkConfigured: diagnostics.sink != null,
      delivery: delivery,
      histories: [
        _historySnapshot('traces', traceCapacity, _traces.length, _traceTotal),
        _historySnapshot(
          'navigation',
          navigationDiagnosticCapacity,
          _navigationEvents.length,
          _navigationEventTotal,
        ),
        _historySnapshot(
          'failures',
          navigationDiagnosticCapacity,
          _navigationFailures.length,
          _navigationFailureTotal,
        ),
        _historySnapshot(
          'fallbacks',
          navigationDiagnosticCapacity,
          _navigationCapabilityFallbacks.length,
          _navigationFallbackTotal,
        ),
        _historySnapshot(
          'entries',
          navigationDiagnosticCapacity,
          _routeEntryEvents.length,
          _routeEntryEventTotal,
        ),
        _historySnapshot(
          'visibility',
          navigationDiagnosticCapacity,
          _routeVisibilityEvents.length,
          _routeVisibilityEventTotal,
        ),
        _historySnapshot(
          'backend',
          navigationDiagnosticCapacity,
          _backendNavigationEvents.length,
          _backendNavigationEventTotal,
        ),
      ],
    );
  }

  /// Advances health and retains a record after its fixed counter is updated.
  /// A zero capacity still advances the revision and lifetime observation count.
  void _retainDiagnostic<T>(Queue<T> history, T record, int capacity) {
    _diagnosticRevision++;
    if (capacity == 0) return;
    if (history.length == capacity) history.removeFirst();
    history.addLast(record);
  }

  /// Copies one history's counts without enumerating its retained records.
  CCDiagnosticHistorySnapshot _historySnapshot(
    String name,
    int capacity,
    int retained,
    int total,
  ) => CCDiagnosticHistorySnapshot(
    name: name,
    capacity: capacity,
    retainedCount: retained,
    omittedCount: total - retained,
  );
}

/// Immutable invocation identity retained by a completed trace record.
///
/// Use this snapshot to correlate completed framework work without retaining
/// the live cancellation token or its listeners. It intentionally contains no
/// handler arguments, service instances, or arbitrary business values.
final class CCTraceContextSnapshot {
  /// Copies safe scalar fields from one live invocation [context].
  CCTraceContextSnapshot.from(CCInvocationContext context)
    : invocationId = context.invocationId,
      traceId = context.traceId,
      spanId = context.spanId,
      parentSpanId = context.parentSpanId,
      operation = context.operation,
      target = context.target,
      callerComponentId = context.callerComponentId,
      targetComponentId = context.targetComponentId,
      scopeId = context.scopeId,
      deadline = context.deadline,
      cancellationRequested = context.cancellation.isCancelled;

  /// Identity unique to the completed invocation.
  final String invocationId;

  /// Identity shared by every span in the completed call chain.
  final String traceId;

  /// Identity of this completed invocation span.
  final String spanId;

  /// Parent span identity, or null for a root invocation.
  final String? parentSpanId;

  /// Framework operation category captured from the live context.
  final String? operation;

  /// Sanitized capability identity captured from the live context.
  final String? target;

  /// Explicitly attributed calling component, when one was supplied.
  final String? callerComponentId;

  /// Component that registered the invoked capability, when known.
  final String? targetComponentId;

  /// Lifecycle Scope associated with the invocation, when one existed.
  final String? scopeId;

  /// Deadline used by the invocation, when configured.
  final DateTime? deadline;

  /// Whether cancellation had been requested when tracing completed.
  final bool cancellationRequested;
}

/// Immutable diagnostic outcome for one framework invocation.
///
/// Use trace records for development diagnostics, latency inspection, and
/// sanitized failure reporting. They are not a replacement for business
/// analytics and intentionally omit arbitrary payload data.
final class CCTraceRecord {
  /// Creates a completed trace record.
  const CCTraceRecord({
    required this.context,
    required this.operation,
    required this.target,
    required this.startedAt,
    required this.duration,
    required this.status,
    this.errorType,
  });

  /// Safe identity snapshot captured after the invocation completed.
  final CCTraceContextSnapshot context;

  /// Operation category such as command, query, action, or event.
  final String operation;

  /// Sanitized target type or capability identifier.
  final String target;

  /// Wall-clock time when execution began.
  final DateTime startedAt;

  /// Elapsed execution time observed by the Runtime.
  final Duration duration;

  /// Terminal status such as succeeded, failed, cancelled, or timedOut.
  final String status;

  /// Concrete error type without the potentially sensitive error message.
  final String? errorType;
}

/// Bounded trace records associated with one stable [traceId].
///
/// A bundle is a local troubleshooting view, not a replayable request log.
/// Records may be incomplete when the Runtime history capacity was exceeded;
/// callers should use the bundle to correlate failure context before exporting
/// a sanitized report to an application observability system.
final class CCTraceBundle {
  /// Creates one immutable trace bundle.
  const CCTraceBundle({required this.traceId, required this.records});

  /// Trace identity shared by the records in this bundle.
  final String traceId;

  /// Records in completion order, copied from the bounded Runtime history.
  final List<CCTraceRecord> records;
}
