// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _EventGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter_generated.dart';
import 'package:demo_navigation_lab/src/navigation_lab_component_registrar.dart'
    as event_source;
import 'package:demo_navigation_lab/src/component_capabilities.dart'
    as event_type_0;

/// Registers one generated subscriber for `demo_navigation_lab.order_completed`.
void ccrouterRegisterFailDemoOrderCompletedEventSubscription(
  CCRegistry registry, {
  required String subscriberId,
}) {
  registry.registerEventSubscriber<event_type_0.DemoOrderCompletedEvent>(
    CCEventSubscriber<event_type_0.DemoOrderCompletedEvent>(
      id: CCEventSubscriberId<event_type_0.DemoOrderCompletedEvent>(
        subscriberId,
      ),
      eventId: "demo_navigation_lab.order_completed",
      handler: (event, _) => event_source.failDemoOrderCompleted(event),
    ),
  );
}

/// Registers one generated subscriber for `demo_navigation_lab.order_completed`.
void ccrouterRegisterTrackDemoOrderCompletedEventSubscription(
  CCRegistry registry, {
  required String subscriberId,
}) {
  registry.registerEventSubscriber<event_type_0.DemoOrderCompletedEvent>(
    CCEventSubscriber<event_type_0.DemoOrderCompletedEvent>(
      id: CCEventSubscriberId<event_type_0.DemoOrderCompletedEvent>(
        subscriberId,
      ),
      eventId: "demo_navigation_lab.order_completed",
      handler: (event, _) => event_source.trackDemoOrderCompleted(event),
    ),
  );
}

/// Registers one generated subscriber for `demo_navigation_lab.slow`.
void ccrouterRegisterWaitForDemoSlowEventEventSubscription(
  CCRegistry registry, {
  required String subscriberId,
}) {
  registry.registerEventSubscriber<event_type_0.DemoSlowEvent>(
    CCEventSubscriber<event_type_0.DemoSlowEvent>(
      id: CCEventSubscriberId<event_type_0.DemoSlowEvent>(subscriberId),
      eventId: "demo_navigation_lab.slow",
      handler: event_source.waitForDemoSlowEvent,
    ),
  );
}
