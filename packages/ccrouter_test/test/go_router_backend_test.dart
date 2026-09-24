import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(CCRouter.shutdown);

  testWidgets('CCGoRouterApp assembles a minimal Host from components', (
    tester,
  ) async {
    await tester.pumpWidget(
      CCGoRouterApp(
        components: const [],
        catalog: const CCFlutterRouteCatalog.empty(),
        title: 'Minimal Host',
        debugShowCheckedModeBanner: false,
        hostRoutes: [
          GoRoute(path: '/', builder: (_, _) => const Text('minimal host')),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(CCRouter.isInitialized, isTrue);
    expect(find.text('minimal host'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(CCRouter.isInitialized, isTrue);
  });

  testWidgets('CCGoRouterApp uses an explicitly initialized Runtime', (
    tester,
  ) async {
    CCRouter.initialize(components: const []);

    await tester.pumpWidget(
      CCGoRouterApp(
        catalog: const CCFlutterRouteCatalog.empty(),
        initialLocation: '/details',
        hostRoutes: [
          GoRoute(path: '/', builder: (_, _) => const Text('home')),
          GoRoute(path: '/details', builder: (_, _) => const Text('details')),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('details'), findsOneWidget);
    expect(CCRouter.registeredComponents, isEmpty);
  });

  test('managed backend assembles Router, Observer, and Adapter', () async {
    final catalog = CCFlutterRouteCatalog(const []);
    final backend = CCGoRouterBackend.managed(
      catalog: catalog,
      hostRoutes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
    );

    expect(backend.routeCatalog, same(catalog));
    expect(
      backend.router.routerDelegate.navigatorKey,
      same(backend.host.navigatorKey),
    );
    expect(backend.adapter.router, same(backend.router));
    expect(backend.adapter.observers, hasLength(1));
    expect(backend.adapter.observers.single.hostId, backend.host.id);
    expect(backend.adapter.observers.single.outlet, 'root');
    expect(backend.router.configuration.routes, hasLength(1));

    await backend.dispose();
    await backend.dispose();
  });

  test('attach backend leaves the application-owned Router usable', () async {
    final host = CCNavigationHost(id: 'attached');
    final router = GoRouter(
      navigatorKey: host.navigatorKey,
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/other', builder: (_, _) => const SizedBox()),
      ],
    );
    addTearDown(router.dispose);
    final backend = CCGoRouterBackend.attach(
      catalog: CCFlutterRouteCatalog(const []),
      router: router,
      host: host,
    );

    await backend.dispose();
    router.go('/other');

    expect(router.routeInformationProvider.value.uri.path, '/other');
  });

  test('managed backend rejects an empty Router assembly', () {
    expect(
      () => CCGoRouterBackend.managed(catalog: CCFlutterRouteCatalog(const [])),
      throwsA(isA<CCNavigationAdapterError>()),
    );
  });
}
