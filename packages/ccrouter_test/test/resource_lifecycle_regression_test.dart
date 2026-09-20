import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

final class _LifecycleArguments {
  const _LifecycleArguments(this.id);

  final int id;
}

final class _LifecycleCodec implements CCRouteCodec<_LifecycleArguments> {
  const _LifecycleCodec();

  @override
  _LifecycleArguments decode(CCEncodedRouteArguments input) =>
      _LifecycleArguments(int.parse(input.path['id']!));

  @override
  CCEncodedRouteArguments encode(_LifecycleArguments arguments) =>
      CCEncodedRouteArguments(path: {'id': '${arguments.id}'});
}

final class _LifecycleIntent implements CCRouteIntent<int> {
  const _LifecycleIntent(this.id);

  final int id;

  @override
  String get routeId => 'lifecycle.detail';

  @override
  Object get arguments => _LifecycleArguments(id);
}

final class _LifecycleRegistrar implements CCComponentRegistrar {
  const _LifecycleRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerRoute<_LifecycleArguments, int>(
      CCRouteDefinition<_LifecycleArguments, int>(
        routeId: 'lifecycle.detail',
        patterns: const [CCPathPattern('/lifecycle/:id', primary: true)],
        codec: const _LifecycleCodec(),
      ),
    );
  }
}

void main() {
  LeakTesting.enable();
  LeakTracking.warnForUnsupportedPlatforms = false;
  final leakSettings = LeakTesting.settings.withTrackedAll().withIgnored(
    createdByTestHelpers: true,
  );

  test(
    'repeated navigation releases live entries and bounds diagnostics',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        traceCapacity: 16,
        navigationDiagnosticCapacity: 16,
        navigationAdapter: adapter,
        components: const [
          CCComponentManifest(
            id: 'lifecycle',
            version: '1.0.0',
            registrar: _LifecycleRegistrar(),
          ),
        ],
      );
      runtime.initialize();

      for (var index = 0; index < 250; index++) {
        final result = runtime.pushRoute<int>(_LifecycleIntent(index));
        expect(runtime.activeRouteEntries, hasLength(1));
        runtime.popRoute(result: index);
        expect(await result, index);
        expect(runtime.activeRouteEntries, isEmpty);
        expect(runtime.activeBackendEntries, isEmpty);
        expect(runtime.pendingNavigations, isEmpty);
      }

      expect(runtime.recentTraces.length, lessThanOrEqualTo(16));
      expect(runtime.recentNavigationEvents.length, lessThanOrEqualTo(16));
      expect(runtime.recentRouteEntryEvents.length, lessThanOrEqualTo(16));
      expect(
        runtime.recentBackendNavigationEvents.length,
        lessThanOrEqualTo(16),
      );

      await runtime.dispose();
      expect(adapter.stack, isEmpty);
      expect(adapter.routes, isEmpty);
    },
  );

  testWidgets(
    'Host lifecycle and Navigator resources are disposed after unmount',
    experimentalLeakTesting: leakSettings,
    (tester) async {
      final host = CCNavigationHost(id: 'lifecycle.leak');
      final observer = CCGoRouterNavigationObserver(
        hostId: host.id,
        outlet: 'root',
      );

      await tester.pumpWidget(
        CCRouterApp(
          host: host,
          child: MaterialApp(
            navigatorKey: host.navigatorKey,
            navigatorObservers: [observer],
            home: const CCPageLifecycleListener(child: Text('root')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final route = host.navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const CCPageLifecycleListener(child: Text('detail')),
        ),
      );
      await tester.pumpAndSettle();
      host.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await route;

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
