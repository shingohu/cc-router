part of 'runtime.dart';

/// Immutable diagnostic outcome for one framework invocation.
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

  /// Context used by the invocation.
  final CCInvocationContext context;

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
