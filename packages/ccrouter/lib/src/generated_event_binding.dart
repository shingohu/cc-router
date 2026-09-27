part of 'facade.dart';

/// Generated-code-only bridge for typed Event publication.
///
/// Owner component Clients call this bridge with build-time validated Event and
/// publisher identities. Business code uses the generated Client.
abstract final class CCRouterGeneratedEventBinding {
  /// Publishes [event] to every statically registered subscriber.
  static Future<void> publish<E extends CCEvent>(
    E event, {
    required String eventId,
    required String publisherComponentId,
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => CCRouter._runtime.invokeGeneratedEvent(
    event,
    eventId: eventId,
    publisherComponentId: publisherComponentId,
    timeout: timeout,
    cancellation: cancellation,
  );
}
