import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:demo_analytics/demo_analytics.dart';
import 'package:test/test.dart';

final class _Sink implements AppAnalyticsSink {
  final events = <AppAnalyticsEvent>[];
  @override
  Future<void> write(AppAnalyticsEvent event) async => events.add(event);
}

CCNavigationAspectEvent _event(String id, CCNavigationAspectPhase phase) =>
    CCNavigationAspectEvent(
      phase: phase,
      timestamp: DateTime.utc(2026, 10, 23),
      outcome: phase == CCNavigationAspectPhase.after
          ? CCNavigationAspectOutcome.succeeded
          : null,
      request: CCNavigationAspectRequest(
        navigationId: id,
        operation: CCNavigationOperation.push,
        routeId: 'order.detail',
        routePattern: '/orders/:id',
        resolvedHostId: 'host.primary',
        navigatorOutlet: 'detail',
        ownerComponentId: 'order',
        placement: const CCRoutePlacement.root(),
        origin: CCNavigationOrigin.internal,
        openMode: null,
        source: null,
        presentation: const CCPagePresentation(),
      ),
    );

void main() {
  for (final action in ['dispose', 'reset', 'revoke']) {
    test(
      'provider $action cannot resurrect identity or publish a visit',
      () async {
        final sink = _Sink();
        final dispatcher = AppAnalyticsEventDispatcher(
          sinks: [sink],
          policy: AppAnalyticsPolicy(consentGranted: true),
        );
        late final AppNavigationAnalyticsBridge bridge;
        bridge = AppNavigationAnalyticsBridge(
          dispatcher: dispatcher,
          identityProvider: () {
            switch (action) {
              case 'dispose':
                bridge.dispose();
              case 'reset':
                bridge.resetTracking();
              case 'revoke':
                dispatcher.updatePolicy(
                  dispatcher.policy.copyWith(consentGranted: false),
                );
            }
            return const AppAnalyticsIdentity(
              anonymousVisitorId: 'retired-identity',
            );
          },
        );
        bridge.createAspect().onArrival!(
          _event('retired.navigation', CCNavigationAspectPhase.arrival),
        );
        expect(bridge.retainedIdentityCount, 0);
        await dispatcher.close();
        expect(sink.events, isEmpty);
        bridge.dispose();
      },
    );
  }

  test(
    'accepts opaque UUID visitor and application Session identities',
    () async {
      final sink = _Sink();
      final dispatcher = AppAnalyticsEventDispatcher(
        sinks: [sink],
        policy: AppAnalyticsPolicy(consentGranted: true),
      );
      final bridge = AppNavigationAnalyticsBridge(
        dispatcher: dispatcher,
        identityProvider: () => const AppAnalyticsIdentity(
          anonymousVisitorId: '123e4567-e89b-12d3-a456-426614174000',
          applicationSessionId: 'run_2026.09-20',
        ),
      );
      bridge.createAspect().onArrival!(
        _event('uuid.navigation', CCNavigationAspectPhase.arrival),
      );
      await dispatcher.close();
      expect(
        sink.events.single.anonymousVisitorId,
        '123e4567-e89b-12d3-a456-426614174000',
      );
      expect(sink.events.single.applicationSessionId, 'run_2026.09-20');
      bridge.dispose();
    },
  );

  test(
    'snapshots first observation across redirects, async wait and concurrent entries',
    () async {
      final sink = _Sink();
      final dispatcher = AppAnalyticsEventDispatcher(
        sinks: [sink],
        policy: AppAnalyticsPolicy(consentGranted: true),
      );
      var identity = const AppAnalyticsIdentity(
        anonymousVisitorId: 'visitor-1',
      );
      var reads = 0;
      final bridge = AppNavigationAnalyticsBridge(
        dispatcher: dispatcher,
        identityProvider: () {
          reads++;
          return identity;
        },
      );
      final aspect = bridge.createAspect();
      aspect.onFound!(_event('first', CCNavigationAspectPhase.found));
      identity = const AppAnalyticsIdentity(anonymousVisitorId: 'visitor-2');
      aspect.onFound!(_event('first', CCNavigationAspectPhase.found));
      aspect.onFound!(_event('second', CCNavigationAspectPhase.found));
      await Future<void>.delayed(Duration.zero);
      aspect.onArrival!(_event('first', CCNavigationAspectPhase.arrival));
      aspect.onAfter!(_event('first', CCNavigationAspectPhase.after));
      aspect.onArrival!(_event('second', CCNavigationAspectPhase.arrival));
      aspect.onHide!(_event('first', CCNavigationAspectPhase.hide));
      aspect.onShow!(_event('first', CCNavigationAspectPhase.show));
      expect(reads, 2);
      expect(bridge.retainedIdentityCount, 2);
      aspect.onRemoved!(_event('first', CCNavigationAspectPhase.removed));
      aspect.onDisposed!(_event('first', CCNavigationAspectPhase.disposed));
      aspect.onLost!(_event('second', CCNavigationAspectPhase.lost));
      expect(bridge.retainedIdentityCount, 0);
      await dispatcher.close();
      expect(sink.events.map((event) => event.anonymousVisitorId), [
        'visitor-1',
        'visitor-2',
        'visitor-1',
        'visitor-1',
      ]);
      bridge.dispose();
    },
  );

  test(
    'Consent reset and disposal release snapshots and fence late observations',
    () async {
      final sink = _Sink();
      final dispatcher = AppAnalyticsEventDispatcher(
        sinks: [sink],
        policy: AppAnalyticsPolicy(consentGranted: false),
      );
      var reads = 0;
      final bridge = AppNavigationAnalyticsBridge(
        dispatcher: dispatcher,
        identityProvider: () {
          reads++;
          return const AppAnalyticsIdentity(anonymousVisitorId: 'visitor-1');
        },
      );
      final aspect = bridge.createAspect();
      aspect.onFound!(_event('first', CCNavigationAspectPhase.found));
      aspect.onArrival!(_event('first', CCNavigationAspectPhase.arrival));
      expect(reads, 0);
      dispatcher.updatePolicy(dispatcher.policy.copyWith(consentGranted: true));
      aspect.onShow!(_event('first', CCNavigationAspectPhase.show));
      expect(bridge.retainedIdentityCount, 1);
      bridge.resetTracking();
      dispatcher.updatePolicy(
        dispatcher.policy.copyWith(consentGranted: false),
      );
      expect(bridge.retainedIdentityCount, 0);
      aspect.onHide!(_event('first', CCNavigationAspectPhase.hide));
      bridge.dispose();
      bridge.dispose();
      dispatcher.updatePolicy(dispatcher.policy.copyWith(consentGranted: true));
      aspect.onFound!(_event('late', CCNavigationAspectPhase.found));
      aspect.onArrival!(_event('late', CCNavigationAspectPhase.arrival));
      expect(reads, 1);
      expect(bridge.retainedIdentityCount, 0);
      await dispatcher.close();
      expect(dispatcher.acceptedEventCount, 1);
      expect(sink.events, isEmpty); // Revocation discards the queued visit.
    },
  );

  test(
    'invalid identity and provider errors are isolated in the application',
    () async {
      final sink = _Sink();
      final dispatcher = AppAnalyticsEventDispatcher(
        sinks: [sink],
        policy: AppAnalyticsPolicy(consentGranted: true),
      );
      final candidates = <AppAnalyticsIdentity?>[
        const AppAnalyticsIdentity(anonymousVisitorId: 'account@example.com'),
        const AppAnalyticsIdentity(
          anonymousVisitorId: 'visitor',
          applicationSessionId: 'https://example.com',
        ),
        AppAnalyticsIdentity(anonymousVisitorId: 'v${'x' * 64}'),
        null,
      ];
      var index = 0;
      final bridge = AppNavigationAnalyticsBridge(
        dispatcher: dispatcher,
        identityProvider: () {
          if (index == candidates.length) {
            throw StateError('identity unavailable');
          }
          return candidates[index];
        },
      );
      final aspect = bridge.createAspect();
      for (; index <= candidates.length; index++) {
        aspect.onFound!(_event('nav.$index', CCNavigationAspectPhase.found));
        aspect.onArrival!(
          _event('nav.$index', CCNavigationAspectPhase.arrival),
        );
        aspect.onDisposed!(
          _event('nav.$index', CCNavigationAspectPhase.disposed),
        );
      }
      expect(bridge.retainedIdentityCount, 0);
      await dispatcher.close();
      expect(sink.events, hasLength(5));
      expect(
        sink.events.every(
          (event) =>
              event.anonymousVisitorId == null &&
              event.applicationSessionId == null,
        ),
        isTrue,
      );
      bridge.dispose();
    },
  );

  test(
    'bounds identity snapshots for incomplete application observations',
    () async {
      final dispatcher = AppAnalyticsEventDispatcher(
        sinks: const [],
        policy: AppAnalyticsPolicy(consentGranted: true),
      );
      final bridge = AppNavigationAnalyticsBridge(dispatcher: dispatcher);
      final aspect = bridge.createAspect();
      for (var index = 0; index < 1100; index++) {
        aspect.onFound!(_event('nav.$index', CCNavigationAspectPhase.found));
      }
      expect(bridge.retainedIdentityCount, 1024);
      bridge.dispose();
      expect(bridge.retainedIdentityCount, 0);
      await dispatcher.close();
    },
  );
}
