part of 'runtime.dart';

/// Builds a Subscriber body outside the Runtime-owning fan-out closure frame.
///
/// Cancellation ends the traced invocation, while an uncooperative Subscriber
/// can finish later. Its await must retain only the registered callback, Event
/// and invocation context, not the fan-out's Runtime or sibling invocations.
Future<void> Function(CCInvocationContext) _eventSubscriberBody(
  _RegisteredEventSubscriber subscriber,
  CCEvent event,
) => (context) async {
  await subscriber.callback(event, context);
};
