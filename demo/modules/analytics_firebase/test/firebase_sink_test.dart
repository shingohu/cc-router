import 'package:demo_analytics/demo_analytics.dart';
import 'package:demo_analytics_firebase/demo_analytics_firebase.dart';
import 'package:test/test.dart';

void main() {
  test('Firebase sink maps only sanitized event data', () async {
    String? name;
    Map<String, Object>? parameters;
    final sink = DemoFirebaseAnalyticsSink(
      writeEvent: (eventName, eventParameters) {
        name = eventName;
        parameters = eventParameters;
      },
    );
    await sink.write(
      AppAnalyticsEvent(
        eventId: 'page.view.orders',
        type: AppAnalyticsEventType.pageView,
        occurredAt: DateTime(2026),
        routeId: 'orders.detail',
        properties: AppAnalyticsProperties.from([
          AppAnalyticsProperty('tab', 'summary'),
        ]),
      ),
    );

    expect(name, 'page.view.orders');
    expect(parameters, {
      'type': 'pageView',
      'route_id': 'orders.detail',
      'tab': 'summary',
    });
  });
}
