/// Marker interface for a command that performs work and returns [R].
///
/// Use a command for one-to-one operations with a single owning handler, such
/// as creating an order, submitting a payment, or refreshing remote data.
/// Choose `CCCommand<void>` when callers only need completion or failure, and
/// use a Service method for repeatable capability access or state reads. A
/// command still participates in timeout, cancellation, and tracing when its
/// result type is `void`.
abstract interface class CCCommand<R> {}

/// Marker interface for a fact published to independent subscribers.
///
/// Use an event after something has happened and publishers must not depend on
/// a subscriber result. Use [CCCommand] when one owner must perform requested
/// work and report completion or a typed result.
abstract interface class CCEvent {}
