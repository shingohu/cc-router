import 'package:demo_analytics/demo_analytics.dart';
import 'package:demo_analytics_flutter/demo_analytics_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Sink implements AppAnalyticsSink {
  final events = <AppAnalyticsEvent>[];
  @override
  void write(AppAnalyticsEvent event) => events.add(event);
}

void main() {
  testWidgets(
    'a replaced ancestor position continues tracking the same target',
    (tester) async {
      final sink = _Sink();
      final dispatcher = AppAnalyticsEventDispatcher(
        sinks: [sink],
        policy: AppAnalyticsPolicy(consentGranted: true),
      );
      final controller = ScrollController();
      final target = _target(dispatcher);
      Widget layout(ScrollPhysics physics) => _surface(
        SizedBox(
          width: 200,
          height: 200,
          child: SingleChildScrollView(
            controller: controller,
            physics: physics,
            child: Column(
              children: [
                const SizedBox(height: 800),
                target,
                const SizedBox(height: 800),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(layout(const ClampingScrollPhysics()));
      final oldPosition = controller.position;
      await tester.pumpWidget(layout(const BouncingScrollPhysics()));
      expect(controller.position, isNot(same(oldPosition)));
      controller.jumpTo(800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(sink.events, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await dispatcher.close();
    },
  );

  for (final block in ['blacklist', 'throttle']) {
    testWidgets('$block rejection does not consume lifetime once', (
      tester,
    ) async {
      final sink = _Sink();
      final dispatcher = AppAnalyticsEventDispatcher(
        sinks: [sink],
        policy: AppAnalyticsPolicy(
          consentGranted: true,
          blockedEventIds: block == 'blacklist' ? {'card.exposure'} : {},
          throttleWindow: block == 'throttle' ? const Duration(hours: 1) : null,
        ),
      );
      final tracker = AppAnalyticsTracker(dispatcher: dispatcher);
      if (block == 'throttle') {
        tracker.exposure(eventId: 'card.exposure');
        await tester.pump(Duration.zero);
        sink.events.clear();
      }
      await tester.pumpWidget(_surface(_target(dispatcher)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(sink.events, isEmpty);
      expect(
        block == 'blacklist'
            ? dispatcher.blacklistedEventCount
            : dispatcher.throttledEventCount,
        1,
      );
      dispatcher.updatePolicy(AppAnalyticsPolicy(consentGranted: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 499));
      expect(sink.events, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(sink.events, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await dispatcher.close();
    });
  }

  testWidgets('revocation resets dwell and accepted once is never replayed', (
    tester,
  ) async {
    final sink = _Sink();
    final dispatcher = AppAnalyticsEventDispatcher(
      sinks: [sink],
      policy: AppAnalyticsPolicy(consentGranted: true),
    );
    await tester.pumpWidget(_surface(_target(dispatcher)));
    await tester.pump(const Duration(milliseconds: 400));
    dispatcher.updatePolicy(AppAnalyticsPolicy());
    dispatcher.updatePolicy(AppAnalyticsPolicy(consentGranted: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 499));
    expect(sink.events, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(sink.events, hasLength(1));
    dispatcher.updatePolicy(AppAnalyticsPolicy());
    dispatcher.updatePolicy(AppAnalyticsPolicy(consentGranted: true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(sink.events, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await dispatcher.close();
  });

  testWidgets('filtered attempts do not consume once or poll every frame', (
    tester,
  ) async {
    final sink = _Sink();
    var samples = 0;
    final dispatcher = AppAnalyticsEventDispatcher(
      sinks: [sink],
      randomSource: () {
        samples++;
        return 0.9;
      },
      policy: AppAnalyticsPolicy(consentGranted: true, sampleRate: 0.5),
    );
    final target = _target(dispatcher);
    await tester.pumpWidget(_surface(target));
    await tester.pump(const Duration(milliseconds: 500));
    for (var i = 0; i < 3; i++) {
      await tester.pumpWidget(_surface(target));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(samples, 1);
    expect(sink.events, isEmpty);
    dispatcher.updatePolicy(AppAnalyticsPolicy(consentGranted: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(sink.events, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await dispatcher.close();
  });

  testWidgets('background rebuild, close and detach cancel pending dwell', (
    tester,
  ) async {
    final sink = _Sink();
    final dispatcher = AppAnalyticsEventDispatcher(
      sinks: [sink],
      policy: AppAnalyticsPolicy(consentGranted: true),
    );
    final target = _target(dispatcher);
    await tester.pumpWidget(_surface(target));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpWidget(_surface(target));
    dispatcher.updatePolicy(AppAnalyticsPolicy(consentGranted: true));
    await tester.pump(const Duration(seconds: 1));
    expect(sink.events, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await dispatcher.close();
    await tester.pump(const Duration(seconds: 1));
    expect(sink.events, isEmpty);
    await tester.pumpWidget(const SizedBox());
    dispatcher.updatePolicy(AppAnalyticsPolicy(consentGranted: true));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('moving a target detaches old positions and resets dwell', (
    tester,
  ) async {
    final sink = _Sink();
    final dispatcher = AppAnalyticsEventDispatcher(
      sinks: [sink],
      policy: AppAnalyticsPolicy(consentGranted: true),
    );
    final first = ScrollController();
    final second = ScrollController();
    final target = _target(dispatcher, key: GlobalKey());
    Widget layout(bool moved) => _surface(
      Row(
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: SingleChildScrollView(
              controller: first,
              child: Column(
                children: [if (!moved) target, const SizedBox(height: 800)],
              ),
            ),
          ),
          SizedBox(
            width: 100,
            height: 100,
            child: SingleChildScrollView(
              controller: second,
              child: Column(
                children: [const SizedBox(height: 800), if (moved) target],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpWidget(layout(false));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpWidget(layout(true));
    await tester.pump(const Duration(seconds: 1));
    expect(sink.events, isEmpty);
    second.jumpTo(800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 499));
    expect(sink.events, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(sink.events, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    first.dispose();
    second.dispose();
    dispatcher.updatePolicy(AppAnalyticsPolicy());
    await dispatcher.close();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested scroll positions respect both viewport clips', (
    tester,
  ) async {
    final sink = _Sink();
    final dispatcher = AppAnalyticsEventDispatcher(
      sinks: [sink],
      policy: AppAnalyticsPolicy(consentGranted: true),
    );
    final outer = ScrollController();
    final inner = ScrollController();
    await tester.pumpWidget(
      _surface(
        SizedBox(
          width: 200,
          height: 200,
          child: SingleChildScrollView(
            controller: outer,
            child: Column(
              children: [
                const SizedBox(height: 800),
                SizedBox(
                  height: 200,
                  child: SingleChildScrollView(
                    controller: inner,
                    child: Column(
                      children: [
                        const SizedBox(height: 800),
                        _target(dispatcher),
                        const SizedBox(height: 800),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 800),
              ],
            ),
          ),
        ),
      ),
    );
    inner.jumpTo(800);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(sink.events, isEmpty);
    outer.jumpTo(800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    outer.jumpTo(0);
    await tester.pump();
    outer.jumpTo(800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 499));
    expect(sink.events, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(sink.events, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    inner.dispose();
    outer.dispose();
    await dispatcher.close();
  });

  testWidgets('ancestor scrolling starts a clipped visibility episode', (
    tester,
  ) async {
    final sink = _Sink();
    final dispatcher = AppAnalyticsEventDispatcher(
      sinks: [sink],
      policy: AppAnalyticsPolicy(consentGranted: true),
    );
    final controller = ScrollController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            height: 200,
            child: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: [
                  const SizedBox(height: 800),
                  AppAnalyticsExposureTarget(
                    tracker: AppAnalyticsTracker(dispatcher: dispatcher),
                    eventId: 'card.exposure',
                    once: false,
                    child: const SizedBox(width: 100, height: 100),
                  ),
                  const SizedBox(height: 800),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(sink.events, isEmpty);
    controller.jumpTo(650);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(sink.events, hasLength(1));
    expect(sink.events.single.properties.values['visible_fraction'], 0.5);
    controller.jumpTo(0);
    await tester.pump();
    controller.jumpTo(800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(sink.events, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await dispatcher.close();
  });

  testWidgets(
    'consent grant starts a fresh dwell without rebuilding the target',
    (tester) async {
      final sink = _Sink();
      final dispatcher = AppAnalyticsEventDispatcher(sinks: [sink]);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AppAnalyticsExposureTarget(
            tracker: AppAnalyticsTracker(dispatcher: dispatcher),
            eventId: 'card.exposure',
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(sink.events, isEmpty);
      dispatcher.updatePolicy(AppAnalyticsPolicy(consentGranted: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 499));
      expect(sink.events, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(sink.events, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await dispatcher.close();
    },
  );
}

Widget _surface(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(alignment: Alignment.topLeft, child: child),
);

AppAnalyticsExposureTarget _target(
  AppAnalyticsEventDispatcher dispatcher, {
  Key? key,
}) => AppAnalyticsExposureTarget(
  key: key,
  tracker: AppAnalyticsTracker(dispatcher: dispatcher),
  eventId: 'card.exposure',
  child: const SizedBox(width: 100, height: 100),
);
