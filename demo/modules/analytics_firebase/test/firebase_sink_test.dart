import 'package:ccrouter_analytics/ccrouter_analytics.dart';
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
      CCAnalyticsEvent(
        eventId: 'page.view.orders',
        type: CCAnalyticsEventType.pageView,
        occurredAt: DateTime(2026),
        routeId: 'orders.detail',
        properties: CCAnalyticsProperties.from([
          CCAnalyticsProperty('tab', 'summary'),
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
