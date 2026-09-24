import 'package:ccrouter_analytics/ccrouter_analytics.dart';
import 'package:ccrouter_auto_track/ccrouter_auto_track.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _RecordingSink implements CCAnalyticsSink {
  final events = <CCAnalyticsEvent>[];

  @override
  void write(CCAnalyticsEvent event) => events.add(event);
}

void main() {
  testWidgets('exposure target emits once after the dwell threshold', (
    tester,
  ) async {
    final sink = _RecordingSink();
    final dispatcher = CCAnalyticsEventDispatcher(
      sinks: [sink],
      policy: CCAnalyticsPolicy(consentGranted: true),
    );
    final tracker = CCAnalyticsTracker(dispatcher: dispatcher);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CCAnalyticsExposureTarget(
          tracker: tracker,
          eventId: 'order.card.exposure',
          minimumVisibleDuration: const Duration(milliseconds: 500),
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 499));
    expect(sink.events, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(sink.events, hasLength(1));
    expect(sink.events.single.type, CCAnalyticsEventType.exposure);
    expect(sink.events.single.properties.values['visible_fraction'], 1.0);

    await tester.pump(const Duration(seconds: 1));
    expect(sink.events, hasLength(1));
    await dispatcher.close();
  });

  testWidgets('reusable exposure target deduplicates by visibility episode', (
    tester,
  ) async {
    final sink = _RecordingSink();
    final dispatcher = CCAnalyticsEventDispatcher(
      sinks: [sink],
      policy: CCAnalyticsPolicy(consentGranted: true),
    );
    final tracker = CCAnalyticsTracker(dispatcher: dispatcher);
    var visible = true;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              CCAnalyticsExposureTarget(
                tracker: tracker,
                eventId: 'order.card.exposure',
                minimumVisibleDuration: Duration.zero,
                once: false,
                child: SizedBox(width: 100, height: visible ? 100 : 0),
              ),
              GestureDetector(
                key: const ValueKey<String>('toggle'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => visible = !visible),
                child: const SizedBox(width: 40, height: 40),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(sink.events, hasLength(1));
    await tester.tap(find.byKey(const ValueKey<String>('toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('toggle')));
    await tester.pump();
    expect(sink.events, hasLength(2));
    await dispatcher.close();
  });

  testWidgets('backgrounding cancels the current exposure dwell timer', (
    tester,
  ) async {
    final sink = _RecordingSink();
    final dispatcher = CCAnalyticsEventDispatcher(
      sinks: [sink],
      policy: CCAnalyticsPolicy(consentGranted: true),
    );
    final tracker = CCAnalyticsTracker(dispatcher: dispatcher);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CCAnalyticsExposureTarget(
          tracker: tracker,
          eventId: 'order.card.exposure',
          minimumVisibleDuration: const Duration(seconds: 1),
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 1));
    expect(sink.events, isEmpty);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(sink.events, hasLength(1));
    await dispatcher.close();
  });

  testWidgets('scroll target emits bounded user session events', (
    tester,
  ) async {
    final sink = _RecordingSink();
    final dispatcher = CCAnalyticsEventDispatcher(
      sinks: [sink],
      policy: CCAnalyticsPolicy(consentGranted: true),
    );
    final tracker = CCAnalyticsTracker(dispatcher: dispatcher);
    late BuildContext notificationContext;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CCAnalyticsScrollable(
          tracker: tracker,
          eventId: 'list.scroll.end',
          startEventId: 'list.scroll.start',
          baseProperties: CCAnalyticsProperties.from([
            CCAnalyticsProperty('surface', 'orders'),
          ]),
          child: Builder(
            builder: (context) {
              notificationContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    _scrollStart(notificationContext, pixels: 0, user: true);
    _userScroll(
      notificationContext,
      pixels: 0,
      direction: ScrollDirection.reverse,
    );
    _scrollEnd(notificationContext, pixels: 180);
    await tester.pump();
    await dispatcher.close();

    expect(sink.events.map((event) => event.eventId), [
      'list.scroll.start',
      'list.scroll.end',
    ]);
    expect(sink.events.last.properties.values, {
      'surface': 'orders',
      'phase': 'end',
      'direction': 'reverse',
      'distance_bucket': '120-479',
      'duration_bucket': '0-249ms',
    });

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('programmatic scroll is ignored by default', (tester) async {
    final sink = _RecordingSink();
    final dispatcher = CCAnalyticsEventDispatcher(
      sinks: [sink],
      policy: CCAnalyticsPolicy(consentGranted: true),
    );
    final tracker = CCAnalyticsTracker(dispatcher: dispatcher);
    late BuildContext notificationContext;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CCAnalyticsScrollable(
          tracker: tracker,
          eventId: 'list.scroll.end',
          child: Builder(
            builder: (context) {
              notificationContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    _scrollStart(notificationContext, pixels: 0, user: false);
    _scrollEnd(notificationContext, pixels: 180);
    await tester.pump();
    await dispatcher.close();

    expect(sink.events, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}

FixedScrollMetrics _metrics(double pixels) => FixedScrollMetrics(
  minScrollExtent: 0,
  maxScrollExtent: 1000,
  pixels: pixels,
  viewportDimension: 300,
  axisDirection: AxisDirection.down,
  devicePixelRatio: 1,
);

void _scrollStart(
  BuildContext context, {
  required double pixels,
  required bool user,
}) {
  ScrollStartNotification(
    metrics: _metrics(pixels),
    dragDetails: user ? DragStartDetails() : null,
    context: context,
  ).dispatch(context);
}

void _userScroll(
  BuildContext context, {
  required double pixels,
  required ScrollDirection direction,
}) {
  UserScrollNotification(
    metrics: _metrics(pixels),
    direction: direction,
    context: context,
  ).dispatch(context);
}

void _scrollEnd(BuildContext context, {required double pixels}) {
  ScrollEndNotification(
    metrics: _metrics(pixels),
    context: context,
  ).dispatch(context);
}
