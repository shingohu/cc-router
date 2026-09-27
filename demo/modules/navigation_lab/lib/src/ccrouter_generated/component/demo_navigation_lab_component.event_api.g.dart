// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

import 'package:ccrouter/ccrouter_generated.dart';
import 'package:demo_navigation_lab/src/component_capabilities.dart'
    as event_type_0;

/// Typed Event publication entry points for component `demo_navigation_lab_component`.
abstract final class DemoNavigationLabEvents {
  /// Publishes `demo_navigation_lab.order_completed` to its static subscribers.
  static Future<void> publishDemoOrderCompleted(
    event_type_0.DemoOrderCompletedEvent event, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => CCRouterGeneratedEventBinding.publish(
    event,
    eventId: "demo_navigation_lab.order_completed",
    publisherComponentId: "demo_navigation_lab_component",
    timeout: timeout,
    cancellation: cancellation,
  );

  /// Publishes `demo_navigation_lab.slow` to its static subscribers.
  static Future<void> publishDemoSlow(
    event_type_0.DemoSlowEvent event, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => CCRouterGeneratedEventBinding.publish(
    event,
    eventId: "demo_navigation_lab.slow",
    publisherComponentId: "demo_navigation_lab_component",
    timeout: timeout,
    cancellation: cancellation,
  );

  /// Publishes `demo_navigation_lab.unobserved` to its static subscribers.
  static Future<void> publishDemoUnobserved(
    event_type_0.DemoUnobservedEvent event, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => CCRouterGeneratedEventBinding.publish(
    event,
    eventId: "demo_navigation_lab.unobserved",
    publisherComponentId: "demo_navigation_lab_component",
    timeout: timeout,
    cancellation: cancellation,
  );
}
