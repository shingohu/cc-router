import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final class _OrderArguments {
  const _OrderArguments(this.id);

  final String id;
}

final class _OrderCodec implements CCRouteCodec<_OrderArguments> {
  const _OrderCodec();

  @override
  _OrderArguments decode(CCEncodedRouteArguments input) =>
      _OrderArguments(input.path['id']!);

  @override
  CCEncodedRouteArguments encode(_OrderArguments arguments) =>
      CCEncodedRouteArguments(path: {'id': arguments.id});
}

final class _OrderIntent<R> implements CCRouteIntent<R> {
  const _OrderIntent(this.arguments);

  @override
  String get routeId => 'orders.detail';

  @override
  final _OrderArguments arguments;
}

final class _SimpleOrdersRegistrar implements CCComponentRegistrar {
  const _SimpleOrdersRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerRoute<_OrderArguments, String>(
      CCRouteDefinition<_OrderArguments, String>(
        routeId: 'orders.detail',
        patterns: [const CCPathPattern('/orders/:id', primary: true)],
        codec: const _OrderCodec(),
      ),
    );
  }
}

final class _OrdersRegistrar implements CCComponentRegistrar {
  const _OrdersRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerShell(
      CCShellDefinition(
        shellId: 'tabs',
        type: CCShellType.statefulBranches,
        outlets: const ['home', 'settings'],
        initialOutlet: 'home',
      ),
    );
    registry.registerRoute<_OrderArguments, void>(
      CCRouteDefinition<_OrderArguments, void>(
        routeId: 'orders.detail',
        patterns: [
          const CCPathPattern('/settings/orders/:id', primary: true),
          const CCUriPattern('https://example.com/settings/orders/:id'),
        ],
        codec: const _OrderCodec(),
        deepLink: CCDeepLinkPolicy.enabled,
        placement: const CCRoutePlacement(
          shellId: 'tabs',
          navigatorOutlet: 'settings',
        ),
      ),
    );
  }
}

final class _RecordingNavigationAdapter
    implements CCNavigationAdapter, CCNavigationBackendEventSource {
  _RecordingNavigationAdapter(this.delegate);

  final CCNavigationAdapter delegate;
  final List<CCNavigationRequest> requests = [];

  @override
  Future<void> initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) => delegate.initialize(routes, shells: shells);

  @override
  void Function() addBackendEventListener(
    CCNavigationBackendEventListener listener,
  ) {
    final source = delegate;
    if (source is CCNavigationBackendEventSource) {
      return (source as CCNavigationBackendEventSource).addBackendEventListener(
        listener,
      );
    }
    return () {};
  }

  @override
  Future<Object?> navigate(CCNavigationRequest request) {
    requests.add(request);
    return delegate.navigate(request);
  }

  @override
  Future<bool> maybePop({Object? result}) => delegate.maybePop(result: result);

  @override
  Future<Object?> popAndPush(
    CCNavigationRequest request, {
    Object? popResult,
  }) => delegate.popAndPush(request, popResult: popResult);

  @override
  Future<void> popUntil(CCNavigationStackPredicate predicate) =>
      delegate.popUntil(predicate);

  @override
  Future<Object?> pushAndRemoveUntil(
    CCNavigationRequest request,
    CCNavigationStackPredicate predicate,
  ) => delegate.pushAndRemoveUntil(request, predicate);

  @override
  void pop({Object? result}) => delegate.pop(result: result);

  @override
  bool canPop() => delegate.canPop();

  @override
  Future<void> dispose() => delegate.dispose();
}

void main() {
  tearDown(CCRouter.shutdown);

  testWidgets(
    'foreign routes and local history never remove a managed Route Entry',
    (tester) async {
      final observer = CCGoRouterNavigationObserver(outlet: 'root');
      final scaffoldKey = GlobalKey<ScaffoldState>();
      final detailRoute = GoRoute(
        path: '/orders/:id',
        builder: (_, state) => Scaffold(
          key: scaffoldKey,
          body: Text(
            'order:${state.pathParameters['id']}',
            key: const ValueKey('managed-order'),
          ),
        ),
      );
      final router = GoRouter(
        initialLocation: '/',
        observers: [observer],
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('home')),
          detailRoute,
        ],
      );
      final adapter = CCGoRouterAdapter(
        router: router,
        observers: [observer],
        bindings: [
          CCGoRouterRouteBinding(
            routeId: 'orders.detail',
            goRoute: detailRoute,
          ),
        ],
      );
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: const [
          CCComponentManifest(
            id: 'orders',
            version: '1.0.0',
            registrar: _SimpleOrdersRegistrar(),
          ),
        ],
      );
      addTearDown(runtime.dispose);
      addTearDown(router.dispose);

      await runtime.initialize();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final managedResult = runtime.pushRoute<String>(
        const _OrderIntent<String>(_OrderArguments('42')),
      );
      await tester.pumpAndSettle();
      final managedEntryId = runtime.activeRouteEntries.single.routeEntryId;
      final managedContext = tester.element(
        find.byKey(const ValueKey('managed-order')),
      );

      void expectManagedEntryUnchanged() {
        expect(runtime.activeRouteEntries, hasLength(1));
        expect(runtime.activeRouteEntries.single.routeEntryId, managedEntryId);
        expect(
          runtime.activeRouteEntries.single.lifecycleState,
          CCRouteEntryLifecycleState.visible,
        );
      }

      final dialog = showDialog<void>(
        context: managedContext,
        builder: (context) => AlertDialog(
          key: const ValueKey('foreign-dialog'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('close-dialog'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expectManagedEntryUnchanged();
      await tester.tap(find.text('close-dialog'));
      await tester.pumpAndSettle();
      await dialog;
      expectManagedEntryUnchanged();

      final modal = showModalBottomSheet<void>(
        context: managedContext,
        builder: (context) => TextButton(
          key: const ValueKey('foreign-modal'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('close-modal'),
        ),
      );
      await tester.pumpAndSettle();
      expectManagedEntryUnchanged();
      await tester.tap(find.text('close-modal'));
      await tester.pumpAndSettle();
      await modal;
      expectManagedEntryUnchanged();

      final bottomSheet = scaffoldKey.currentState!.showBottomSheet(
        (_) =>
            const SizedBox(key: ValueKey('foreign-local-history'), height: 80),
      );
      await tester.pumpAndSettle();
      expectManagedEntryUnchanged();
      final localHistoryPop = await runtime.maybePopOutcomeRoute();
      expect(localHistoryPop.handled, isTrue);
      expect(localHistoryPop.removedOwner, CCPopRemovedOwner.none);
      await tester.pumpAndSettle();
      await bottomSheet.closed;
      expect(find.byKey(const ValueKey('foreign-local-history')), findsNothing);
      expectManagedEntryUnchanged();

      final foreignRoute = Navigator.of(managedContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Text('foreign-page', key: ValueKey('foreign-page')),
        ),
      );
      await tester.pumpAndSettle();
      expectManagedEntryUnchanged();
      Navigator.of(
        tester.element(find.byKey(const ValueKey('foreign-page'))),
      ).pop();
      await tester.pumpAndSettle();
      await foreignRoute;
      expectManagedEntryUnchanged();

      Navigator.of(managedContext).pop<String>('managed-result');
      await tester.pumpAndSettle();
      expect(await managedResult, 'managed-result');
      expect(runtime.activeRouteEntries, isEmpty);
      expect(
        runtime.recentBackendNavigationEvents.where(
          (event) => event.routeId == null,
        ),
        isNotEmpty,
      );
    },
  );

  testWidgets(
    'external ingress reaches the bound StatefulShell branch with metadata',
    (tester) async {
      final homeKey = GlobalKey<NavigatorState>();
      final settingsKey = GlobalKey<NavigatorState>();
      final observedEvents = <CCGoRouterNavigationEvent>[];
      final observer = CCGoRouterNavigationObserver(
        outlet: 'settings',
        onEvent: observedEvents.add,
      );
      final detailRoute = GoRoute(
        path: 'orders/:id',
        builder: (_, state) => Text(
          'order:${state.pathParameters['id']}',
          key: const ValueKey('order-detail'),
        ),
      );
      final homeRoute = GoRoute(
        path: '/home',
        builder: (_, _) => const Text('home'),
      );
      final settingsRoute = GoRoute(
        path: '/settings',
        builder: (_, _) => const Text('settings'),
        routes: [detailRoute],
      );
      final shellRoute = StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) => Scaffold(body: navigationShell),
        branches: [
          StatefulShellBranch(navigatorKey: homeKey, routes: [homeRoute]),
          StatefulShellBranch(
            navigatorKey: settingsKey,
            observers: [observer],
            routes: [settingsRoute],
          ),
        ],
      );
      final router = GoRouter(initialLocation: '/home', routes: [shellRoute]);
      final goRouterAdapter = CCGoRouterAdapter(
        router: router,
        observers: [observer],
        shells: [
          CCGoRouterShellBinding(
            shellId: 'tabs',
            route: shellRoute,
            initialOutlet: 'home',
            outlets: {'home': homeKey, 'settings': settingsKey},
          ),
        ],
        bindings: [
          CCGoRouterRouteBinding(
            routeId: 'orders.detail',
            goRoute: detailRoute,
          ),
        ],
      );
      final adapter = _RecordingNavigationAdapter(goRouterAdapter);
      addTearDown(router.dispose);

      await CCRouter.initialize(
        components: const [
          CCComponentManifest(
            id: 'orders',
            version: '1.0.0',
            registrar: _OrdersRegistrar(),
          ),
        ],
        navigationAdapter: adapter,
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      const source = CCNavigationSource.deepLink('universal_link.orders');
      await CCDeepLinkIngress.fromPlatform(
        Uri.parse('https://example.com/settings/orders/42'),
        source: source,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('order-detail')), findsOneWidget);
      expect(find.text('order:42'), findsOneWidget);
      expect(router.state.uri.path, '/settings/orders/42');
      expect(adapter.requests, hasLength(1));
      expect(
        adapter.requests.single.origin,
        CCNavigationOrigin.externalPlatform,
      );
      expect(adapter.requests.single.source, same(source));
      expect(adapter.requests.single.routeId, 'orders.detail');
      expect(adapter.requests.single.placement.navigatorOutlet, 'settings');
      expect(observedEvents, isNotEmpty);
      expect(observedEvents.last.outlet, 'settings');
      expect(observedEvents.last.location, 'orders/:id');
      expect(settingsKey.currentState, isNotNull);
      expect(homeKey.currentState, isNotNull);
      final backendEvents = CCRouter.recentBackendNavigationEvents;
      expect(backendEvents, isNotEmpty);
      expect(
        backendEvents.any(
          (event) =>
              event.routeId == 'orders.detail' &&
              event.origin == CCNavigationOrigin.externalPlatform &&
              event.source == source,
        ),
        isTrue,
      );
    },
  );

  testWidgets('external ingress rejects a route disabled for deep links', (
    tester,
  ) async {
    final route = GoRoute(
      path: '/internal/:id',
      builder: (_, state) => Text('internal:${state.pathParameters['id']}'),
    );
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        route,
      ],
    );
    final adapter = CCGoRouterAdapter(
      router: router,
      bindings: [CCGoRouterRouteBinding(routeId: 'internal', goRoute: route)],
    );
    addTearDown(router.dispose);

    final registrar = _DisabledRouteRegistrar();
    await CCRouter.initialize(
      components: [
        CCComponentManifest(
          id: 'internal',
          version: '1.0.0',
          registrar: registrar,
        ),
      ],
      navigationAdapter: adapter,
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await expectLater(
      CCDeepLinkIngress.fromNotification(
        Uri.parse('/internal/7'),
        source: const CCNavigationSource.notification('order_ready'),
      ),
      throwsA(isA<CCRouteNotFoundError>()),
    );
    expect(router.state.uri.path, '/');
    expect(find.text('home'), findsOneWidget);
  });
}

final class _DisabledRouteRegistrar implements CCComponentRegistrar {
  @override
  void register(CCRegistry registry) {
    registry.registerRoute<_OrderArguments, void>(
      CCRouteDefinition<_OrderArguments, void>(
        routeId: 'internal',
        patterns: [const CCPathPattern('/internal/:id', primary: true)],
        codec: const _OrderCodec(),
      ),
    );
  }
}
