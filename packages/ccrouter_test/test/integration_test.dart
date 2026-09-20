// ignore_for_file: deprecated_member_use

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  void initialize(
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
  void pop({Object? result}) => delegate.pop(result: result);

  @override
  bool canPop() => delegate.canPop();

  @override
  void dispose() => delegate.dispose();
}

void main() {
  tearDown(CCRouter.shutdown);

  testWidgets(
    'foreign routes and local history never remove a managed Route Entry',
    (tester) async {
      final host = CCNavigationHost(id: 'window.main');
      final observer = CCGoRouterNavigationObserver(
        hostId: host.id,
        outlet: 'root',
      );
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
        navigatorKey: host.navigatorKey,
        initialLocation: '/',
        observers: [observer],
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('home')),
          detailRoute,
        ],
      );
      final adapter = CCGoRouterAdapter(
        router: router,
        host: host,
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

      runtime.initialize();
      await tester.pumpWidget(
        CCRouterApp(
          host: host,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      final managedResult = runtime.pushRoute<String>(
        const _OrderIntent<String>(_OrderArguments('42')),
      );
      await tester.pumpAndSettle();
      final managedEntryId = runtime.activeRouteEntries.single.routeEntryId;
      final managedBackendEntries = runtime.activeBackendEntries.where(
        (entry) => entry.owner == CCBackendEntryOwner.managed,
      );
      expect(managedBackendEntries, isNotEmpty);
      expect(
        managedBackendEntries.every((entry) => entry.hostId == host.id),
        isTrue,
      );
      final managedPushEvent = runtime.recentBackendNavigationEvents.lastWhere(
        (event) => event.routeId == 'orders.detail',
      );
      expect(managedPushEvent.hostId, host.id);
      expect(managedPushEvent.placement.hostId, host.id);
      final managedContext = tester.element(
        find.byKey(const ValueKey('managed-order')),
      );

      void expectManagedEntryAlive({
        CCRouteEntryLifecycleState state = CCRouteEntryLifecycleState.visible,
      }) {
        expect(runtime.activeRouteEntries, hasLength(1));
        expect(runtime.activeRouteEntries.single.routeEntryId, managedEntryId);
        expect(runtime.activeRouteEntries.single.lifecycleState, state);
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
      expectManagedEntryAlive(state: CCRouteEntryLifecycleState.hidden);
      await tester.tap(find.text('close-dialog'));
      await tester.pumpAndSettle();
      await dialog;
      expectManagedEntryAlive();

      final modal = showModalBottomSheet<void>(
        context: managedContext,
        builder: (context) => TextButton(
          key: const ValueKey('foreign-modal'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('close-modal'),
        ),
      );
      await tester.pumpAndSettle();
      expectManagedEntryAlive(state: CCRouteEntryLifecycleState.hidden);
      await tester.tap(find.text('close-modal'));
      await tester.pumpAndSettle();
      await modal;
      expectManagedEntryAlive();

      final bottomSheet = scaffoldKey.currentState!.showBottomSheet(
        (_) =>
            const SizedBox(key: ValueKey('foreign-local-history'), height: 80),
      );
      await tester.pumpAndSettle();
      expectManagedEntryAlive();
      final localHistoryPop = await runtime.maybePopOutcomeRoute();
      expect(localHistoryPop.handled, isTrue);
      expect(localHistoryPop.removedOwner, CCPopRemovedOwner.none);
      await tester.pumpAndSettle();
      await bottomSheet.closed;
      expect(find.byKey(const ValueKey('foreign-local-history')), findsNothing);
      expectManagedEntryAlive();

      final foreignRoute = Navigator.of(managedContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Text('foreign-page', key: ValueKey('foreign-page')),
        ),
      );
      await tester.pumpAndSettle();
      expectManagedEntryAlive(state: CCRouteEntryLifecycleState.hidden);
      Navigator.of(
        tester.element(find.byKey(const ValueKey('foreign-page'))),
      ).pop();
      await tester.pumpAndSettle();
      await foreignRoute;
      expectManagedEntryAlive();

      final secondForeignRoute = Navigator.of(managedContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Text('foreign-page-2', key: ValueKey('foreign-page-2')),
        ),
      );
      await tester.pumpAndSettle();
      expectManagedEntryAlive(state: CCRouteEntryLifecycleState.hidden);
      runtime.popRoute();
      await tester.pumpAndSettle();
      await secondForeignRoute;
      expectManagedEntryAlive();

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
    'a rejected Pop keeps the managed Route Entry and pending result alive',
    (tester) async {
      final observer = CCGoRouterNavigationObserver(outlet: 'root');
      final allowPop = ValueNotifier(false);
      final detailRoute = GoRoute(
        path: '/orders/:id',
        builder: (_, state) => ValueListenableBuilder<bool>(
          valueListenable: allowPop,
          builder: (_, canPop, _) => PopScope<void>(
            canPop: canPop,
            child: Text(
              'order:${state.pathParameters['id']}',
              key: const ValueKey('guarded-order'),
            ),
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
      addTearDown(allowPop.dispose);
      addTearDown(runtime.dispose);
      addTearDown(router.dispose);

      runtime.initialize();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final managedResult = runtime.pushRoute<String>(
        const _OrderIntent<String>(_OrderArguments('guarded')),
      );
      await tester.pumpAndSettle();
      final managedEntryId = runtime.activeRouteEntries.single.routeEntryId;
      expect(find.byKey(const ValueKey('guarded-order')), findsOneWidget);

      final declined = await runtime.maybePopOutcomeRoute<String>(
        result: 'rejected',
      );
      // PopScope consumes the request even though it refuses to remove the
      // route. Ownership and result availability carry the rejection detail.
      expect(declined.handled, isTrue);
      expect(declined.removedOwner, CCPopRemovedOwner.none);
      expect(runtime.activeRouteEntries, hasLength(1));
      expect(runtime.activeRouteEntries.single.routeEntryId, managedEntryId);
      expect(
        runtime.activeRouteEntries.single.lifecycleState,
        CCRouteEntryLifecycleState.visible,
      );
      expect(find.byKey(const ValueKey('guarded-order')), findsOneWidget);

      allowPop.value = true;
      await tester.pump();
      final accepted = await runtime.maybePopOutcomeRoute<String>(
        result: 'accepted',
      );
      await tester.pumpAndSettle();
      expect(accepted.handled, isTrue);
      expect(accepted.removedOwner, CCPopRemovedOwner.managed);
      expect(accepted.removedOwner, CCPopRemovedOwner.managed);
      expect(await managedResult, 'accepted');
      expect(runtime.activeRouteEntries, isEmpty);
    },
  );

  testWidgets('an external system Pop closes a managed go route entry', (
    tester,
  ) async {
    final observer = CCGoRouterNavigationObserver(outlet: 'root');
    final detailRoute = GoRoute(
      path: ':id',
      builder: (_, state) => Text(
        'order:${state.pathParameters['id']}',
        key: const ValueKey('go-managed-order'),
      ),
    );
    final ordersRoute = GoRoute(
      path: '/orders',
      builder: (_, _) => const Text('orders-parent'),
      routes: [detailRoute],
    );
    final router = GoRouter(
      initialLocation: '/',
      observers: [observer],
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        ordersRoute,
      ],
    );
    final adapter = CCGoRouterAdapter(
      router: router,
      observers: [observer],
      bindings: [
        CCGoRouterRouteBinding(routeId: 'orders.detail', goRoute: detailRoute),
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

    runtime.initialize();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await runtime.goRoute(const _OrderIntent<void>(_OrderArguments('42')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('go-managed-order')), findsOneWidget);
    expect(runtime.activeRouteEntries, hasLength(1));

    final context = tester.element(
      find.byKey(const ValueKey('go-managed-order')),
    );
    Navigator.of(context).pop<void>();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('go-managed-order')), findsNothing);
    expect(runtime.activeRouteEntries, isEmpty);
  });

  testWidgets(
    'dynamic open pushes on GoRouter and completes before its later Pop',
    (tester) async {
      final observer = CCGoRouterNavigationObserver(outlet: 'root');
      final detailRoute = GoRoute(
        path: '/orders/:id',
        builder: (_, state) => Text(
          'open-order:${state.pathParameters['id']}',
          key: const ValueKey('open-managed-order'),
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

      runtime.initialize();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(runtime.activeBackendEntries, hasLength(1));

      await runtime.openRoute(Uri.parse('/orders/42'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('open-managed-order')), findsOneWidget);
      expect(runtime.canPopRoute(), isTrue);
      expect(runtime.activeRouteEntries, hasLength(1));
      expect(
        runtime.activeRouteEntries.single.lifecycleState,
        CCRouteEntryLifecycleState.visible,
      );

      runtime.popRoute();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(runtime.activeRouteEntries, isEmpty);
    },
  );

  testWidgets('replace recreates the same route with updated parameters', (
    tester,
  ) async {
    final observer = CCGoRouterNavigationObserver(outlet: 'root');
    final detailRoute = GoRoute(
      path: '/orders/:id',
      pageBuilder: (_, state) => ccGoRouterPage(
        child: Text(
          'replace-order:${state.pathParameters['id']}',
          key: ValueKey('replace-order-${state.pathParameters['id']}'),
        ),
        presentation: const CCPagePresentation(),
        key: state.pageKey,
        name: 'orders.detail',
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
        CCGoRouterRouteBinding(routeId: 'orders.detail', goRoute: detailRoute),
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

    runtime.initialize();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final firstResult = runtime.pushRoute<String>(
      const _OrderIntent<String>(_OrderArguments('1')),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('replace-order-1')), findsOneWidget);

    final replacementResult = runtime.replaceRoute<String>(
      const _OrderIntent<String>(_OrderArguments('2')),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const ValueKey('replace-order-1')), findsNothing);
    expect(find.byKey(const ValueKey('replace-order-2')), findsOneWidget);
    expect(runtime.activeRouteEntries, hasLength(1));
    expect(runtime.activeRouteEntries.single.normalizedUri.path, '/orders/2');

    runtime.popRoute(result: 'done');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(await firstResult.timeout(const Duration(seconds: 2)), isNull);
    expect(await replacementResult.timeout(const Duration(seconds: 2)), 'done');
    expect(runtime.activeRouteEntries, isEmpty);
  });

  testWidgets('Runtime dispose terminates a pending typed Push result', (
    tester,
  ) async {
    final detailRoute = GoRoute(
      path: '/orders/:id',
      builder: (_, state) => Text(
        'dispose-order:${state.pathParameters['id']}',
        key: const ValueKey('dispose-order'),
      ),
    );
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        detailRoute,
      ],
    );
    final adapter = CCGoRouterAdapter(
      router: router,
      bindings: [
        CCGoRouterRouteBinding(routeId: 'orders.detail', goRoute: detailRoute),
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

    runtime.initialize();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final pending = runtime.pushRoute<String>(
      const _OrderIntent<String>(_OrderArguments('42')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dispose-order')), findsOneWidget);

    final completion = expectLater(
      pending,
      throwsA(
        isA<CCNavigationAdapterError>().having(
          (error) => error.message,
          'message',
          contains('disposed before navigation completed'),
        ),
      ),
    );
    await tester.runAsync(
      () => runtime.dispose().timeout(const Duration(seconds: 2)),
    );

    await tester.runAsync(() => completion.timeout(const Duration(seconds: 2)));
    expect(runtime.activeRouteEntries, isEmpty);
    expect(adapter.isInitialized, isFalse);
  });

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

      CCRouter.initialize(
        deepLinkIngressPolicy: CCDeepLinkIngressPolicy(
          allowedAuthorities: [
            CCDeepLinkAuthorityRule(scheme: 'https', host: 'example.com'),
          ],
        ),
        components: const [
          CCComponentManifest(
            id: 'orders',
            version: '1.0.0',
            registrar: _OrdersRegistrar(),
          ),
        ],
      );
      CCRouterHostBinding.attachNavigationAdapter(adapter);
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
    CCRouter.initialize(
      deepLinkIngressPolicy: CCDeepLinkIngressPolicy(allowRelativePaths: true),
      components: [
        CCComponentManifest(
          id: 'internal',
          version: '1.0.0',
          registrar: registrar,
        ),
      ],
    );
    CCRouterHostBinding.attachNavigationAdapter(adapter);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await expectLater(
      CCDeepLinkIngress.fromNotification(
        Uri.parse('/internal/7'),
        source: const CCNavigationSource.notification('order_ready'),
      ),
      throwsA(isA<CCDeepLinkRejectedError>()),
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
