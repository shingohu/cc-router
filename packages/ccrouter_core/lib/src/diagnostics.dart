part of 'runtime.dart';

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
