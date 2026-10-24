import 'package:ccrouter_demo/restoration_demand.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final time = DateTime.utc(2026, 10, 23);
  DemoRestorationSignal signal(int index) => DemoRestorationSignal(
    reason: DemoRestorationReason.androidActivityRecreated,
    occurredAt: time.add(Duration(minutes: index)),
    previousTopRouteId: 'route.$index',
  );

  test(
    'application bounds initial/runtime evidence without starting CCRouter',
    () {
      final observed = <DemoRestorationDemand>[];
      final recorder = DemoRestorationDemandRecorder(
        capacity: 2,
        initialSignals: [signal(0), signal(1), signal(2)],
        onRecorded: observed.add,
      );
      expect(recorder.events.map((event) => event.signal.previousTopRouteId), [
        'route.1',
        'route.2',
      ]);
      expect(recorder.events.first.outcome, 'unsupported');
      expect(
        recorder.events.first.signal.occurredAt,
        time.add(const Duration(minutes: 1)),
      );
      recorder.record(signal(3));
      expect(observed, hasLength(4));
      expect(recorder.events, hasLength(2));
      expect(() => recorder.events.clear(), throwsUnsupportedError);
      recorder.dispose();
      recorder.dispose();
      expect(recorder.events, isEmpty);
      expect(recorder.record(signal(4)), isFalse);
      expect(observed, hasLength(4));
    },
  );

  test('sanitizes evidence and isolates application exporter failures', () {
    final recorder = DemoRestorationDemandRecorder(
      onRecorded: (_) => throw StateError('application exporter failed'),
    );
    expect(
      recorder.record(
        DemoRestorationSignal(
          reason: DemoRestorationReason.uncleanPreviousSession,
          occurredAt: time,
          previousTopRouteId: '/orders/secret?account=123',
          previousHostCount: -1,
          previousOutletCount: 3,
          previousComponentCatalogFingerprint: 'catalog.previous',
          applicationVersion: '1.2.3+45',
        ),
      ),
      isTrue,
    );
    final event = recorder.events.single;
    expect(event.signal.previousTopRouteId, isNull);
    expect(event.signal.previousHostCount, isNull);
    expect(event.signal.previousOutletCount, 3);
    expect(event.signal.applicationVersion, '1.2.3+45');
    expect(
      event.signal.previousComponentCatalogFingerprint,
      'catalog.previous',
    );
    recorder.dispose();
    expect(
      () => DemoRestorationDemandRecorder(capacity: 0),
      throwsArgumentError,
    );
  });
}
