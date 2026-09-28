import 'dart:async';

import 'package:ccrouter_analytics/ccrouter_analytics.dart';

/// Vendor boundary used by [CCFirebaseAnalyticsSink].
///
/// The callback is injected so this optional package does not force
/// `firebase_analytics` into Core or applications using another provider.
typedef CCFirebaseEventWriter =
    FutureOr<void> Function(String name, Map<String, Object> parameters);

/// Maps sanitized CCRouter analytics events to Firebase-style event calls.
///
/// Only validated primitive properties and stable correlation identifiers cross
/// this boundary. Route arguments, URI values and arbitrary objects never do.
final class CCFirebaseAnalyticsSink implements CCAnalyticsSink {
  /// Creates a sink backed by an application-owned Firebase writer.
  const CCFirebaseAnalyticsSink({required this.writeEvent});

  /// Adapter callback, normally `FirebaseAnalytics.instance.logEvent`.
  final CCFirebaseEventWriter writeEvent;

  /// Writes one sanitized event using Firebase's name and parameter shape.
  @override
  FutureOr<void> write(CCAnalyticsEvent event) {
    final parameters = <String, Object>{
      'type': event.type.name,
      if (event.routeId case final value?) 'route_id': value,
      if (event.componentId case final value?) 'component_id': value,
      if (event.hostId case final value?) 'host_id': value,
      if (event.outlet case final value?) 'outlet': value,
      if (event.source case final value?) 'source': value,
      if (event.navigationId case final value?) 'navigation_id': value,
      ...event.properties.values,
    };
    return writeEvent(event.eventId, parameters);
  }
}
