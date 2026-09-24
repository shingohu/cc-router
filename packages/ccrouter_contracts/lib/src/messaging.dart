import 'dart:async';

import 'invocation.dart';

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

/// Handles one typed Event without depending on the Core registration package.
typedef CCEventHandler<E extends CCEvent> =
    FutureOr<void> Function(E event, CCInvocationContext context);

/// Binds a stable subscriber identity to one [CCEvent] type.
///
/// The event type remains the dispatch key, while this typed identity
/// distinguishes multiple independent subscribers of the same event. Generated
/// Contract packages should expose these values so component authors do not
/// repeat free-form strings in registrars. The value must be stable for the
/// Runtime lifetime and must not contain payload or account data.
final class CCEventSubscriberId<E extends CCEvent> {
  /// Creates a typed subscriber identity.
  const CCEventSubscriberId(this.value);

  /// Stable diagnostic identity of the subscriber.
  final String value;
}

/// Describes one typed Event subscriber for component registration.
///
/// Use this form when a generated Contract package provides a
/// [CCEventSubscriberId]. The legacy `(String, handler)` registration remains
/// available for handwritten 1.x registrars and low-level tests.
final class CCEventSubscriber<E extends CCEvent> {
  /// Creates a typed Event subscriber descriptor.
  const CCEventSubscriber({required this.id, required this.handler});

  /// Typed stable identity used for ordering and diagnostics.
  final CCEventSubscriberId<E> id;

  /// Handler invoked after the Event has been published.
  final CCEventHandler<E> handler;
}
