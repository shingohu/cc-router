import 'dart:async';

import 'package:demo_analytics/demo_analytics.dart';

/// Application boundary used by [DemoFirebaseAnalyticsSink].
///
/// The callback is injected so the Demo does not force `firebase_analytics`
/// into CCRouter or applications using another provider.
typedef DemoFirebaseEventWriter =
    FutureOr<void> Function(String name, Map<String, Object> parameters);

/// Maps sanitized application analytics events to Firebase-style event calls.
///
/// This Adapter belongs to the application layer because event naming,
/// Firebase initialization, consent and upload policy are product decisions.
/// Only validated primitive properties and stable correlation identifiers
/// cross this boundary.
final class DemoFirebaseAnalyticsSink implements AppAnalyticsSink {
  /// Creates a sink backed by an application-owned Firebase writer.
  const DemoFirebaseAnalyticsSink({required this.writeEvent});

  /// Adapter callback, normally `FirebaseAnalytics.instance.logEvent`.
  final DemoFirebaseEventWriter writeEvent;

  /// Writes one sanitized event using Firebase's name and parameter shape.
  @override
  FutureOr<void> write(AppAnalyticsEvent event) {
    final parameters = <String, Object>{
      'type': event.type.name,
      'route_id': ?event.routeId,
      'component_id': ?event.componentId,
      'host_id': ?event.hostId,
      'outlet': ?event.outlet,
      'source': ?event.source,
      'navigation_id': ?event.navigationId,
      ...event.properties.values,
    };
    return writeEvent(event.eventId, parameters);
  }
}
