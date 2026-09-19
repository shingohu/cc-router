import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

final class _TelemetryProvider implements CCNavigationTelemetryContextProvider {
  const _TelemetryProvider();

  @override
  CCNavigationTelemetryContext currentContext() =>
      const CCNavigationTelemetryContext(
        anonymousVisitorId: 'anonymous-visitor',
        applicationSessionId: 'application-session',
      );
}

void main() {
  test('bounds restoration signals reported before Runtime subscribes', () {
    final source = CCRouteRestorationOpportunityController(pendingCapacity: 2);
    final occurredAt = DateTime.utc(2026, 9, 19, 8);
    for (var index = 0; index < 3; index++) {
      source.report(
        CCRouteRestorationOpportunitySignal(
          reason: CCRouteRestorationOpportunityReason.unknown,
          occurredAt: occurredAt.add(Duration(minutes: index)),
          previousTopRouteId: 'route.$index',
        ),
      );
    }

    expect(
      source.takeInitialSignals().map((signal) => signal.previousTopRouteId),
      ['route.1', 'route.2'],
    );
    expect(source.takeInitialSignals(), isEmpty);
  });

  test(
    'records initial and runtime restoration opportunities safely',
    () async {
      final occurredAt = DateTime.utc(2026, 9, 19, 8);
      final source = CCRouteRestorationOpportunityController(
        initialSignals: [
          CCRouteRestorationOpportunitySignal(
            reason:
                CCRouteRestorationOpportunityReason.androidActivityRecreated,
            occurredAt: occurredAt,
            previousTopRouteId: 'orders.detail',
            previousHostCount: 2,
            previousOutletCount: 3,
            previousComponentCatalogFingerprint: 'catalog.previous',
            applicationVersion: '1.2.3+45',
          ),
        ],
      );
      final runtime = CCRouterRuntime.forTesting(
        navigationDiagnosticCapacity: 2,
        restorationOpportunitySource: source,
        telemetryContextProvider: const _TelemetryProvider(),
        components: const [
          CCComponentManifest(
            id: 'orders',
            version: '1.0.0',
            registrar: _EmptyRegistrar(),
          ),
        ],
      );
      runtime.initialize();

      final initial = runtime.recentRouteRestorationOpportunities.single;
      expect(initial.reason, isNotNull);
      expect(initial.occurredAt, occurredAt);
      expect(initial.outcome, CCRouteRestorationOpportunityOutcome.unsupported);
      expect(initial.previousTopRouteId, 'orders.detail');
      expect(initial.previousHostCount, 2);
      expect(initial.previousOutletCount, 3);
      expect(initial.currentComponentCatalogFingerprint, hasLength(8));
      expect(initial.telemetryContext?.anonymousVisitorId, 'anonymous-visitor');

      final observed = <CCRouteRestorationOpportunityEvent>[];
      runtime.addRouteRestorationOpportunityListener(observed.add);
      source.report(
        CCRouteRestorationOpportunitySignal(
          reason: CCRouteRestorationOpportunityReason.uncleanPreviousSession,
          occurredAt: occurredAt.add(const Duration(minutes: 1)),
          previousTopRouteId: '/orders/secret?account=123',
          previousHostCount: -1,
        ),
      );

      expect(observed, hasLength(1));
      expect(observed.single.previousTopRouteId, isNull);
      expect(observed.single.previousHostCount, isNull);
      expect(runtime.subscriberErrors, hasLength(2));
      expect(runtime.recentRouteRestorationOpportunities, hasLength(2));

      await runtime.dispose();
      source.report(
        CCRouteRestorationOpportunitySignal(
          reason: CCRouteRestorationOpportunityReason.desktopWindowReopened,
          occurredAt: occurredAt.add(const Duration(minutes: 2)),
        ),
      );
      expect(observed, hasLength(1));
    },
  );
}

final class _EmptyRegistrar implements CCComponentRegistrar {
  const _EmptyRegistrar();

  @override
  void register(CCRegistry registry) {}
}
