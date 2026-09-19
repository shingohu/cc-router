/// Marker interface for a command that performs work and returns [R].
///
/// Use a command for one-to-one operations with side effects, such as creating
/// an order. Use [CCQuery] for reads and [CCEvent] for fact notifications.
abstract interface class CCCommand<R> {}

/// Marker interface for a side-effect-free query that returns [R].
///
/// Use a query for one-to-one reads that must not intentionally mutate business
/// state. Use [CCCommand] when the operation performs a state change.
abstract interface class CCQuery<R> {}

/// Marker interface for an action that may have multiple handlers.
///
/// Use an action when multiple installed components may participate in an
/// explicitly requested operation and the caller awaits their completion.
abstract interface class CCAction {}

/// Marker interface for a fact published to independent subscribers.
///
/// Use an event after something has happened and publishers must not depend on
/// a subscriber result. Use [CCAction] for an awaited multi-handler request.
abstract interface class CCEvent {}

/// Summarizes the handlers that processed an action.
///
/// Callers use this report when they need to observe how many action handlers
/// completed. Actions intentionally do not expose handler result values.
final class CCActionReport {
  /// Creates an immutable action dispatch report.
  const CCActionReport({this.handled = 0});

  /// Number of handlers that completed successfully.
  final int handled;
}
