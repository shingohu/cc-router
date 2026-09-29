import 'dart:async';

import 'component.dart';
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

/// Declares one stable typed Command contract for generated registration.
///
/// Use this annotation on a public, concrete, immutable `CCCommand<R>` class.
/// A component-internal Command may omit [componentId], allowing the generator
/// to infer the Package's sole [CCComponent]. A Command moved into a shared
/// contracts Package must declare its owning component explicitly.
final class CCCommandContract {
  /// Creates one generated Command contract declaration.
  const CCCommandContract({
    this.componentId,
    required this.id,
    this.alias,
    this.version = '0.1.0',
    this.description = '',
  });

  /// Component that owns the single Command handler.
  final CCComponentId? componentId;

  /// Globally stable identity used by generated clients and diagnostics.
  final String id;

  /// Default generated Client method shared by the owner and consumers.
  ///
  /// Use a public lower-camel identifier when the Command type name does not
  /// express the preferred operation name. `CCCommandDependency.alias` may
  /// override it for one consuming component. Changing this value changes the
  /// generated source API but does not change dispatch, ownership, or result
  /// semantics.
  final String? alias;

  /// Independent Command Contract SemVer used by generated clients.
  final String version;

  /// Human-readable usage scenario exported to generated documentation.
  final String description;
}

/// Marks one public top-level function as a generated Command handler.
///
/// The function accepts the annotated Command and optionally an
/// [CCInvocationContext]. Its synchronous or asynchronous result must match the
/// Command's `R`. The generator assigns the handler to the Contract owner and
/// installs it through the component Registrar.
final class CCCommandHandler {
  /// Creates a stateless generated Command handler marker.
  const CCCommandHandler();
}

/// Declares that one component consumes a cross-component Command contract.
///
/// Add this value to `CCComponent.commandDependencies`. The generator validates
/// the owning component dependency and emits a typed component-specific client.
/// Owner components receive clients for their own Commands automatically and
/// do not declare a self dependency.
final class CCCommandDependency<C extends CCCommand<Object?>> {
  /// Creates one typed Command dependency.
  const CCCommandDependency({this.alias});

  /// Overrides the Contract default method for this consuming component.
  ///
  /// When absent, generation uses `CCCommandContract.alias` and then the
  /// Command type name. The value must be a public lower-camel Dart identifier.
  final String? alias;
}

/// Marker interface for a fact published to independent subscribers.
///
/// Use an event after something has happened and publishers must not depend on
/// a subscriber result. Use [CCCommand] when one owner must perform requested
/// work and report completion or a typed result.
abstract interface class CCEvent {}

/// Declares one stable typed Event contract for generated publication.
///
/// Apply this annotation to a public, concrete, immutable [CCEvent] class. A
/// component-internal Event may omit [componentId], while a shared contracts
/// Package declares its owning publisher component explicitly.
final class CCEventContract {
  /// Creates one generated Event contract declaration.
  const CCEventContract({
    this.componentId,
    required this.id,
    this.version = '0.1.0',
    this.description = '',
  });

  /// Component that owns the generated publication API.
  final CCComponentId? componentId;

  /// Globally stable Event identity used by Trace and metadata.
  final String id;

  /// Independent Event Contract SemVer used by generated publication APIs.
  final String version;

  /// Human-readable fact and usage scenario exported to documentation.
  final String description;
}

/// Marks one public top-level function as a static Event subscription.
///
/// The function accepts the annotated Event and optionally an
/// [CCInvocationContext], returning `void` or `Future<void>`. Omit [id] only
/// when this component has exactly one subscriber for the Event; generation
/// then derives `<componentId>.<eventId>` deterministically.
final class CCEventSubscription {
  /// Creates one generated static subscription declaration.
  const CCEventSubscription({this.id});

  /// Globally stable Subscriber identity, or null for the single default.
  final String? id;
}

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
  const CCEventSubscriber({
    required this.id,
    required this.handler,
    this.eventId,
  });

  /// Typed stable identity used for ordering and diagnostics.
  final CCEventSubscriberId<E> id;

  /// Handler invoked after the Event has been published.
  final CCEventHandler<E> handler;

  /// Stable generated Event identity associated with [E].
  ///
  /// Generated subscriptions always provide this value. Handwritten 1.x
  /// registrations may omit it and retain Dart-type-only dispatch semantics.
  final String? eventId;
}
