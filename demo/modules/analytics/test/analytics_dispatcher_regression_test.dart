import 'dart:async';

import 'package:demo_analytics/demo_analytics.dart';
import 'package:test/test.dart';

void main() {
  test(
    'policy observers see committed state, isolate errors and detach',
    () async {
      final dispatcher = AppAnalyticsEventDispatcher(sinks: []);
      final states = <bool>[];
      dispatcher.addPolicyListener(() => throw StateError('observer'));
      final remove = dispatcher.addPolicyListener(() {
        states.add(dispatcher.policy.consentGranted);
        expect(
          () => dispatcher.updatePolicy(AppAnalyticsPolicy()),
          throwsStateError,
        );
      });
      expect(states, isEmpty);
      dispatcher.updatePolicy(AppAnalyticsPolicy(consentGranted: true));
      dispatcher.updatePolicy(AppAnalyticsPolicy());
      expect(states, [true, false]);
      remove();
      remove();
      dispatcher.updatePolicy(AppAnalyticsPolicy(consentGranted: true));
      await dispatcher.close();
      expect(states, [true, false]);
    },
  );

  test('close notifies terminal state once and releases observers', () async {
    final dispatcher = AppAnalyticsEventDispatcher(sinks: []);
    final states = <bool>[];
    dispatcher.addPolicyListener(() => states.add(dispatcher.isClosed));
    await dispatcher.close();
    await dispatcher.close();
    dispatcher.addPolicyListener(() => fail('closed listener retained'))();
    dispatcher.updatePolicy(AppAnalyticsPolicy(consentGranted: true));
    expect(states, [true]);
  });

  test('close during notification still reaches remaining observers', () async {
    final dispatcher = AppAnalyticsEventDispatcher(sinks: []);
    final states = <bool>[];
    late Future<void> closing;
    dispatcher.addPolicyListener(() {
      closing = dispatcher.close();
    });
    dispatcher.addPolicyListener(() => states.add(dispatcher.isClosed));
    dispatcher.updatePolicy(AppAnalyticsPolicy(consentGranted: true));
    await closing;
    dispatcher.updatePolicy(AppAnalyticsPolicy());
    expect(states, [true]);
  });

  test(
    'a synchronous burst respects capacity before the first write',
    () async {
      final received = <String>[];
      final dispatcher = AppAnalyticsEventDispatcher(
        capacity: 1,
        policy: AppAnalyticsPolicy(consentGranted: true),
        sinks: [_Sink((event) => received.add(event.eventId))],
      );
      for (final id in ['first.event', 'second.event', 'third.event']) {
        expect(dispatcher.dispatch(_event(id)), isTrue);
      }
      expect(received, isEmpty);
      expect(dispatcher.pendingEventCount, 1);
      expect(dispatcher.droppedEventCount, 2);
      expect(dispatcher.peakQueueDepth, 1);
      await dispatcher.close();
      expect(received, ['third.event']);
      expect(dispatcher.pendingEventCount, 0);
    },
  );

  for (final transition in ['revoke', 'revoke-grant', 'disable-enable']) {
    test(
      '$transition prevents remaining sinks from receiving old events',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        final first = <String>[];
        final second = <String>[];
        final dispatcher = AppAnalyticsEventDispatcher(
          policy: AppAnalyticsPolicy(consentGranted: true),
          sinks: [
            _Sink((event) async {
              first.add(event.eventId);
              if (event.eventId == 'old.event') {
                started.complete();
                await release.future;
              }
            }),
            _Sink((event) => second.add(event.eventId)),
          ],
        );
        dispatcher.dispatch(_event('old.event'));
        await started.future;
        dispatcher.dispatch(_event('old.pending'));
        dispatcher.updatePolicy(
          transition == 'disable-enable'
              ? AppAnalyticsPolicy(enabled: false, consentGranted: true)
              : AppAnalyticsPolicy(consentGranted: false),
        );
        expect(dispatcher.pendingEventCount, 0);
        final regrant = transition != 'revoke';
        if (regrant) {
          dispatcher.updatePolicy(AppAnalyticsPolicy(consentGranted: true));
          expect(dispatcher.dispatch(_event('new.event')), isTrue);
        }
        release.complete();
        await dispatcher.close();
        expect(first, ['old.event', if (regrant) 'new.event']);
        expect(second, [if (regrant) 'new.event']);
        expect(dispatcher.pendingEventCount, 0);
      },
    );
  }

  test('a sink error callback can revoke the remaining delivery', () async {
    final received = <String>[];
    late final AppAnalyticsEventDispatcher dispatcher;
    dispatcher = AppAnalyticsEventDispatcher(
      policy: AppAnalyticsPolicy(consentGranted: true),
      sinks: [
        _Sink((_) => throw StateError('failed sink')),
        _Sink((event) => received.add(event.eventId)),
      ],
      onSinkError: (_, _, _) {
        dispatcher.updatePolicy(AppAnalyticsPolicy(consentGranted: false));
        dispatcher.updatePolicy(AppAnalyticsPolicy(consentGranted: true));
      },
    );
    dispatcher.dispatch(_event('old.event'));
    await dispatcher.close();
    expect(received, isEmpty);
  });

  test(
    'delivery snapshot reports bounded per-sink health without payloads',
    () async {
      final good = <String>[];
      final dispatcher = AppAnalyticsEventDispatcher(
        policy: AppAnalyticsPolicy(consentGranted: true),
        sinks: [
          _Sink((event) => good.add(event.eventId)),
          _Sink((_) => throw StateError('private error detail')),
        ],
      );
      dispatcher.dispatch(_event('health.event'));
      await dispatcher.close();

      final snapshot = dispatcher.snapshot;
      expect(snapshot.acceptedEventCount, 1);
      expect(snapshot.pendingEventCount, 0);
      expect(snapshot.isClosed, isTrue);
      expect(snapshot.sinkHealth, hasLength(2));
      expect(snapshot.sinkHealth[0].sinkIndex, 0);
      expect(snapshot.sinkHealth[0].successfulWriteCount, 1);
      expect(snapshot.sinkHealth[0].failedWriteCount, 0);
      expect(snapshot.sinkHealth[1].sinkIndex, 1);
      expect(snapshot.sinkHealth[1].successfulWriteCount, 0);
      expect(snapshot.sinkHealth[1].failedWriteCount, 1);
      expect(
        snapshot.sinkHealth[1].totalWriteDuration,
        greaterThanOrEqualTo(Duration.zero),
      );
      expect(
        () => snapshot.sinkHealth.add(snapshot.sinkHealth.first),
        throwsUnsupportedError,
      );
      expect(good, ['health.event']);
    },
  );

  test('property snapshots lists before the caller can mutate them', () {
    final source = <Object?>['original', 7];
    final property = AppAnalyticsProperty('items', source);
    source[0] = Object();
    source.add('late');
    final properties = AppAnalyticsProperties.from([property]);
    expect(property.value, ['original', 7]);
    expect(properties.values['items'], ['original', 7]);
    expect(
      () => (property.value as List).add(Object()),
      throwsUnsupportedError,
    );
    expect(
      () => (properties.values['items'] as List).clear(),
      throwsUnsupportedError,
    );
    expect(
      () => properties.values['items'] = 'replacement',
      throwsUnsupportedError,
    );
    expect(() => AppAnalyticsProperty('items', [null]), throwsArgumentError);
    expect(
      () => AppAnalyticsProperty('items', [Object()]),
      throwsArgumentError,
    );
  });

  test('one sink cannot contaminate properties delivered to another', () async {
    final properties = AppAnalyticsProperties.from([
      AppAnalyticsProperty('items', <Object?>['safe', 3]),
    ]);
    final failures = <Object>[];
    final received = <Object?>[];
    final dispatcher = AppAnalyticsEventDispatcher(
      policy: AppAnalyticsPolicy(consentGranted: true),
      sinks: [
        _Sink(
          (event) => (event.properties.values['items'] as List).add(Object()),
        ),
        _Sink(
          (event) => received.addAll(event.properties.values['items'] as List),
        ),
      ],
      onSinkError: (error, _, _) => failures.add(error),
    );
    dispatcher.dispatch(_event('safe.event', properties: properties));
    await dispatcher.close();
    expect(failures.single, isA<UnsupportedError>());
    expect(received, ['safe', 3]);
  });

  test(
    'sink starts on a later event turn and close flushes scheduled work',
    () async {
      final received = <String>[];
      final dispatcher = AppAnalyticsEventDispatcher(
        policy: AppAnalyticsPolicy(consentGranted: true),
        sinks: [_Sink((event) => received.add(event.eventId))],
      );
      expect(dispatcher.dispatch(_event('queued.event')), isTrue);
      expect(received, isEmpty);
      expect(dispatcher.pendingEventCount, 1);
      await Future<void>.value();
      expect(received, isEmpty);
      await Future.wait([dispatcher.close(), dispatcher.close()]);
      expect(received, ['queued.event']);
      expect(dispatcher.pendingEventCount, 0);
      expect(dispatcher.dispatch(_event('closed.event')), isFalse);
    },
  );

  test(
    'revocation before the scheduled drain starts prevents all writes',
    () async {
      final received = <String>[];
      final dispatcher = AppAnalyticsEventDispatcher(
        policy: AppAnalyticsPolicy(consentGranted: true),
        sinks: [_Sink((event) => received.add(event.eventId))],
      );
      dispatcher.dispatch(_event('old.event'));
      dispatcher.updatePolicy(AppAnalyticsPolicy(consentGranted: false));
      dispatcher.updatePolicy(AppAnalyticsPolicy(consentGranted: true));
      dispatcher.dispatch(_event('new.event'));
      await dispatcher.close();
      expect(received, ['new.event']);
    },
  );

  test('synchronous sink reentry stays in a single FIFO drain', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final received = <String>[];
    late final AppAnalyticsEventDispatcher dispatcher;
    dispatcher = AppAnalyticsEventDispatcher(
      policy: AppAnalyticsPolicy(consentGranted: true),
      sinks: [
        _Sink((event) {
          received.add('first:${event.eventId}');
          if (event.eventId == 'outer.event') {
            dispatcher.dispatch(_event('inner.event'));
            started.complete();
            return release.future;
          }
        }),
        _Sink((event) => received.add('second:${event.eventId}')),
      ],
    );
    dispatcher.dispatch(_event('outer.event'));
    await started.future;
    release.complete();
    await dispatcher.close();
    expect(received, [
      'first:outer.event',
      'second:outer.event',
      'first:inner.event',
      'second:inner.event',
    ]);
  });

  test(
    'close called inside a sink waits for that write and remaining sinks',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final received = <String>[];
      var closeFinished = false;
      late Future<void> closing;
      late final AppAnalyticsEventDispatcher dispatcher;
      dispatcher = AppAnalyticsEventDispatcher(
        policy: AppAnalyticsPolicy(consentGranted: true),
        sinks: [
          _Sink((_) {
            closing = dispatcher.close().then((_) => closeFinished = true);
            started.complete();
            return release.future;
          }),
          _Sink((event) => received.add(event.eventId)),
        ],
      );
      dispatcher.dispatch(_event('closing.event'));
      await started.future;
      await Future<void>.value();
      final finishedBeforeRelease = closeFinished;
      release.complete();
      await closing;
      await dispatcher.close();
      expect(finishedBeforeRelease, isFalse);
      expect(received, ['closing.event']);
    },
  );

  test(
    'a timed out sink is quarantined and cannot block close forever',
    () async {
      final slow = _NeverCompletingSink();
      final received = <String>[];
      final dispatcher = AppAnalyticsEventDispatcher(
        policy: AppAnalyticsPolicy(consentGranted: true),
        sinkWriteTimeout: const Duration(milliseconds: 10),
        sinks: [slow, _Sink((event) => received.add(event.eventId))],
      );

      dispatcher.dispatch(_event('slow.event'));
      await slow.started.future;
      dispatcher.dispatch(_event('after.timeout'));
      await dispatcher.close().timeout(const Duration(seconds: 1));

      expect(dispatcher.timedOutSinkWriteCount, 1);
      expect(dispatcher.quarantinedSinkCount, 1);
      expect(dispatcher.snapshot.sinkHealth.first.timedOutWriteCount, 1);
      expect(dispatcher.snapshot.sinkHealth.first.quarantined, isTrue);
      expect(slow.events, ['slow.event']);
      expect(received, ['slow.event', 'after.timeout']);
    },
  );

  test('event admitted as the last sink completes is not stranded', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final received = <String>[];
    final dispatcher = AppAnalyticsEventDispatcher(
      policy: AppAnalyticsPolicy(consentGranted: true),
      sinks: [
        _Sink((event) {
          received.add(event.eventId);
          if (event.eventId == 'first.event') {
            started.complete();
            return release.future;
          }
        }),
      ],
    );
    dispatcher.dispatch(_event('first.event'));
    await started.future;
    final admitted = release.future.then((_) {
      expect(dispatcher.dispatch(_event('late.event')), isTrue);
    });
    release.complete();
    await admitted;
    await dispatcher.close();
    expect(received, ['first.event', 'late.event']);
    expect(dispatcher.pendingEventCount, 0);
  });
}

final class _Sink implements AppAnalyticsSink {
  _Sink(this.onWrite);
  final FutureOr<void> Function(AppAnalyticsEvent) onWrite;

  @override
  FutureOr<void> write(AppAnalyticsEvent event) => onWrite(event);
}

final class _NeverCompletingSink implements AppAnalyticsSink {
  final started = Completer<void>();
  final events = <String>[];

  @override
  Future<void> write(AppAnalyticsEvent event) {
    events.add(event.eventId);
    if (!started.isCompleted) started.complete();
    return Completer<void>().future;
  }
}

AppAnalyticsEvent _event(
  String id, {
  AppAnalyticsProperties properties = const AppAnalyticsProperties.empty(),
}) => AppAnalyticsEvent(
  eventId: id,
  type: AppAnalyticsEventType.custom,
  occurredAt: DateTime(2026),
  properties: properties,
);
