import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/managed_test_home.dart';

void main() {
  tearDown(CCRouterHost.shutdown);
  for (final capacity in [0, 1, 2, 3, 1000]) {
    testWidgets(
      'Runtime history capacity $capacity preserves order and delivery',
      (tester) async {
        CCRouterHost.initialize(
          navigationDiagnosticCapacity: capacity,
          hostAssembly: CCHostAssembly.fromComponents(
            components: const [
              CCComponentManifest(
                id: 'fixture',
                version: '1.0.0',
                registrar: TestHomeRegistrar(),
              ),
            ],
          ),
        );
        final backend = CCManagedRouterBackend(
          routeCatalog: CCFlutterRouteCatalog(
            [testHomeDestination()],
            componentVersions: const {'fixture': '1.0.0'},
          ),
        );
        await tester.pumpWidget(
          CCRouterApp.managed(
            backend: backend,
            child: MaterialApp.router(routerConfig: backend.routerConfig),
          ),
        );
        await tester.pumpAndSettle();
        final delivered = <CCNavigationBackendEvent>[];
        backend.adapter.addBackendEventListener(delivered.add);
        final before = CCRouter.recentBackendNavigationEvents.toList();
        final frozen = CCRouter.recentBackendNavigationEvents;
        final expected = before.map((event) => event.kind).toList();
        // Fill and wrap odd as well as even capacities using real Navigator events.
        for (
          var index = 0;
          index < (capacity < 10 ? capacity * 3 + 7 : 4);
          index++
        ) {
          final start = delivered.length;
          final result = backend.host.navigatorKey.currentState!.push<void>(
            MaterialPageRoute<void>(builder: (_) => const Text('foreign')),
          );
          await tester.pumpAndSettle();
          backend.host.navigatorKey.currentState!.pop();
          await tester.pumpAndSettle();
          await result;
          expected.addAll(delivered.skip(start).map((event) => event.kind));
        }
        final history = CCRouter.recentBackendNavigationEvents;
        expect(history.length, capacity == 0 ? 0 : lessThanOrEqualTo(capacity));
        expect(
          history.map((event) => event.kind),
          expected.skip(
            expected.length > capacity ? expected.length - capacity : 0,
          ),
        );
        expect(frozen, before);
        expect(() => history.clear(), throwsUnsupportedError);
        expect(
          delivered.where(
            (event) => event.kind == CCNavigationBackendEventKind.pop,
          ),
          isNotEmpty,
        );
        expect(
          delivered.every((event) => event.hostId == backend.host.id),
          isTrue,
        );
        expect(CCRouter.activeRouteEntries.single.routeId, 'fixture.home');
        expect(backend.host.navigatorKey.currentState!.canPop(), isFalse);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
