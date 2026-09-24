import 'dart:async';

import 'package:ccrouter_analytics/ccrouter_analytics.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:test/test.dart';

final class _RecordingSink implements CCAnalyticsSink {
  _RecordingSink({this.fail = false});

  final bool fail;
  final events = <CCAnalyticsEvent>[];

  @override
  Future<void> write(CCAnalyticsEvent event) async {
    if (fail) throw StateError('sink failed');
    events.add(event);
  }
}

final class _BlockingSink implements CCAnalyticsSink {
  final ready = Completer<void>();
  final events = <CCAnalyticsEvent>[];

  @override
  Future<void> write(CCAnalyticsEvent event) async {
    events.add(event);
    await ready.future;
  }
}

void main() {
  group('analytics contracts', () {
    test('validates primitive properties and duplicate names', () {
      final properties = CCAnalyticsProperties.from([
        CCAnalyticsProperty('count', 2),
        CCAnalyticsProperty('labels', <Object?>['a', 'b']),
      ]);

      expect(properties.values['count'], 2);
      expect(
        () => CCAnalyticsProperty('payload', <String, Object>{'secret': 'x'}),
        throwsArgumentError,
      );
      expect(
        () => CCAnalyticsProperties.from([
          CCAnalyticsProperty('same', true),
          CCAnalyticsProperty('same', false),
        ]),
        throwsArgumentError,
      );
    });

    test('rejects unstable event identities', () {
      expect(
        () => CCAnalyticsEvent(
          eventId: 'Order Detail',
          type: CCAnalyticsEventType.custom,
          occurredAt: DateTime(2026),
        ),
        throwsArgumentError,
      );
    });
  });

  group('analytics dispatcher', () {
    test('filters events before queueing when consent or sampling rejects', () {
      final sink = _RecordingSink();
      final dispatcher = CCAnalyticsEventDispatcher(
        sinks: [sink],
        policy: CCAnalyticsPolicy(consentGranted: false),
      );

      expect(dispatcher.dispatch(_event('custom.blocked')), isFalse);
      expect(dispatcher.filteredEventCount, 1);
      dispatcher.updatePolicy(CCAnalyticsPolicy(sampleRate: 0));
      expect(dispatcher.dispatch(_event('custom.sampled')), isFalse);
      expect(dispatcher.filteredEventCount, 2);
    });

    test(
      'sampling uses the injected decision source deterministically',
      () async {
        final sink = _RecordingSink();
        final decisions = <double>[0.1, 0.9];
        final dispatcher = CCAnalyticsEventDispatcher(
          sinks: [sink],
          policy: CCAnalyticsPolicy(consentGranted: true, sampleRate: 0.5),
          randomSource: () => decisions.removeAt(0),
        );

        dispatcher.dispatch(_event('custom.accepted'));
        dispatcher.dispatch(_event('custom.filtered'));
        await dispatcher.close();

        expect(sink.events.map((event) => event.eventId), ['custom.accepted']);
        expect(dispatcher.filteredEventCount, 1);
      },
    );

    test('policy update clears events waiting for a sink', () async {
      final sink = _BlockingSink();
      final dispatcher = CCAnalyticsEventDispatcher(
        sinks: [sink],
        policy: CCAnalyticsPolicy(consentGranted: true),
      );

      dispatcher.dispatch(_event('custom.in_flight'));
      dispatcher.dispatch(_event('custom.pending'));
      dispatcher.updatePolicy(CCAnalyticsPolicy(consentGranted: false));
      sink.ready.complete();
      await dispatcher.close();

      expect(sink.events.map((event) => event.eventId), ['custom.in_flight']);
    });

    test('delivers FIFO events and isolates sink failures', () async {
      final good = _RecordingSink();
      final failed = _RecordingSink(fail: true);
      final failures = <Object>[];
      final dispatcher = CCAnalyticsEventDispatcher(
        sinks: [good, failed],
        policy: CCAnalyticsPolicy(consentGranted: true),
        onSinkError: (error, _, __) => failures.add(error),
      );

      dispatcher.dispatch(_event('custom.one'));
      dispatcher.dispatch(_event('custom.two'));
      await Future<void>.delayed(Duration.zero);

      expect(good.events.map((event) => event.eventId), [
        'custom.one',
        'custom.two',
      ]);
      expect(failures, hasLength(2));
      await dispatcher.close();
      expect(dispatcher.dispatch(_event('custom.three')), isFalse);
    });

    test('drops oldest queued event when capacity is reached', () async {
      final sink = _BlockingSink();
      final dispatcher = CCAnalyticsEventDispatcher(
        sinks: [sink],
        capacity: 1,
        policy: CCAnalyticsPolicy(consentGranted: true),
      );

      dispatcher.dispatch(_event('custom.one'));
      dispatcher.dispatch(_event('custom.two'));
      dispatcher.dispatch(_event('custom.three'));
      expect(dispatcher.droppedEventCount, 1);

      sink.ready.complete();
      await dispatcher.close();
      expect(sink.events.map((event) => event.eventId), [
        'custom.one',
        'custom.three',
      ]);
    });
  });

  test('navigation bridge emits page view and page leave events', () async {
    final sink = _RecordingSink();
    final dispatcher = CCAnalyticsEventDispatcher(
      sinks: [sink],
      policy: CCAnalyticsPolicy(consentGranted: true),
    );
    final bridge = CCRouterNavigationAnalytics(dispatcher: dispatcher);
    final aspect = bridge.createAspect();
    final request = CCNavigationAspectRequest(
      navigationId: 'runtime-navigation-1',
      operation: CCNavigationOperation.push,
      routeId: 'order.detail',
      routePattern: '/order/:id',
      resolvedHostId: 'default',
      navigatorOutlet: 'root',
      ownerComponentId: 'order',
      placement: const CCRoutePlacement.root(),
      origin: CCNavigationOrigin.internal,
      openMode: null,
      source: const CCNavigationSource.feature('order.list'),
      presentation: const CCPagePresentation(),
      telemetryContext: const CCNavigationTelemetryContext(
        anonymousVisitorId: 'visitor-1',
        applicationSessionId: 'session-1',
      ),
    );
    final arrival = CCNavigationAspectEvent(
      phase: CCNavigationAspectPhase.arrival,
      request: request,
      timestamp: DateTime(2026),
    );
    final hide = CCNavigationAspectEvent(
      phase: CCNavigationAspectPhase.hide,
      request: request,
      timestamp: DateTime(2026, 1, 1, 0, 0, 1),
    );

    aspect.onArrival!(arrival);
    aspect.onHide!(hide);
    await dispatcher.close();

    expect(sink.events.map((event) => event.eventId), [
      'page.view.order.detail',
      'page.leave.order.detail',
    ]);
    expect(sink.events.first.routeId, 'order.detail');
    expect(sink.events.first.anonymousVisitorId, 'visitor-1');
  });

  test(
    'explicit target records before running the business callback',
    () async {
      final sink = _RecordingSink();
      final dispatcher = CCAnalyticsEventDispatcher(
        sinks: [sink],
        policy: CCAnalyticsPolicy(consentGranted: true),
      );
      final tracker = CCAnalyticsTracker(
        dispatcher: dispatcher,
        context: const CCAnalyticsContext(routeId: 'order.detail'),
      );
      final target = CCAnalyticsTarget(
        tracker: tracker,
        eventId: 'order.detail.confirm',
      );
      final calls = <String>[];

      target.run<void>(() => calls.add('business'));
      await dispatcher.close();

      expect(calls, ['business']);
      expect(sink.events.single.type, CCAnalyticsEventType.click);
      expect(sink.events.single.routeId, 'order.detail');
    },
  );
}

CCAnalyticsEvent _event(String eventId) => CCAnalyticsEvent(
  eventId: eventId,
  type: CCAnalyticsEventType.custom,
  occurredAt: DateTime(2026),
);
