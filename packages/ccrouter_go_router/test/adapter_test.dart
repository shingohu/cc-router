import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

CCNavigationRoute route(String id, {String path = '/detail/:value'}) =>
    CCNavigationRoute(
      routeId: id,
      patterns: [CCPathPattern(path, primary: true)],
      presentation: const CCPagePresentation(),
      deepLink: CCDeepLinkPolicy.disabled,
    );

CCNavigationRequest request({
  required String id,
  required CCNavigationOperation operation,
  required Uri uri,
  CCRoutePlacement placement = const CCRoutePlacement.root(),
  CCNavigationOrigin origin = CCNavigationOrigin.internal,
}) => CCNavigationRequest(
  navigationId: 'test-$id-${operation.name}',
  operation: operation,
  routeId: id,
  uri: uri,
  arguments: const Object(),
  presentation: const CCPagePresentation(),
  placement: placement,
  origin: origin,
);

void main() {
  testWidgets('maps typed Push and Pop through the supplied GoRouter', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(
          path: '/detail/:value',
          builder: (_, state) =>
              Text('detail:${state.pathParameters['value']}'),
        ),
      ],
    );
    final adapter = CCGoRouterAdapter(router: router);
    addTearDown(router.dispose);

    await adapter.initialize([route('detail')]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final result = adapter.navigate(
      request(
        id: 'detail',
        operation: CCNavigationOperation.push,
        uri: Uri.parse('/detail/42'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('detail:42'), findsOneWidget);
    adapter.pop(result: 'done');
    await tester.pumpAndSettle();
    expect(await result, 'done');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('Adapter retains bounded Navigator lifecycle events', (
    tester,
  ) async {
    final observer = CCGoRouterNavigationObserver(outlet: 'root');
    final router = GoRouter(
      initialLocation: '/',
      observers: [observer],
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(path: '/detail', builder: (_, _) => const Text('detail')),
      ],
    );
    final adapter = CCGoRouterAdapter(
      router: router,
      observers: [observer],
      lifecycleEventCapacity: 2,
    );
    addTearDown(router.dispose);
    await adapter.initialize([route('detail', path: '/detail')]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await adapter.navigate(
      request(
        id: 'detail',
        operation: CCNavigationOperation.go,
        uri: Uri.parse('/detail'),
      ),
    );
    await tester.pumpAndSettle();

    expect(adapter.lifecycleEvents, hasLength(2));
    expect(
      adapter.lifecycleEvents.map((event) => event.kind),
      containsAll([
        CCGoRouterNavigationEventKind.push,
        CCGoRouterNavigationEventKind.remove,
      ]),
    );
    await adapter.dispose();
    expect(adapter.lifecycleEvents, isEmpty);
  });

  testWidgets('normalizes absolute URI requests to GoRouter paths', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(
          path: '/detail/:value',
          builder: (_, state) => Text(
            'detail:${state.pathParameters['value']}:${state.uri.queryParameters['tab']}',
          ),
        ),
      ],
    );
    final adapter = CCGoRouterAdapter(router: router);
    addTearDown(router.dispose);

    await adapter.initialize([route('detail')]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await adapter.navigate(
      request(
        id: 'detail',
        operation: CCNavigationOperation.go,
        uri: Uri.parse('https://example.com/detail/42?tab=items'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('detail:42:items'), findsOneWidget);
  });

  test(
    'rejects modal presentations until their backend semantics are ready',
    () async {
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
      );
      final adapter = CCGoRouterAdapter(router: router);
      addTearDown(router.dispose);

      final modal = CCNavigationRoute(
        routeId: 'filters',
        patterns: [const CCPathPattern('/filters', primary: true)],
        presentation: const CCModalBottomSheetPresentation(),
        deepLink: CCDeepLinkPolicy.disabled,
      );

      await expectLater(
        adapter.initialize([modal]),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      expect(adapter.isInitialized, isFalse);
    },
  );

  testWidgets('presents a bound modal bottom sheet and returns its result', (
    tester,
  ) async {
    final goRoute = GoRoute(
      path: '/filters',
      pageBuilder: (_, state) => ccGoRouterBottomSheetPage(
        key: state.pageKey,
        child: const Text('filters'),
        presentation: const CCModalBottomSheetPresentation(
          isScrollControlled: true,
        ),
      ),
    );
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        goRoute,
      ],
    );
    final adapter = CCGoRouterAdapter(
      router: router,
      bindings: [
        CCGoRouterRouteBinding(
          routeId: 'filters',
          goRoute: goRoute,
          presentationKind: CCGoRouterPresentationKind.bottomSheet,
        ),
      ],
    );
    addTearDown(router.dispose);
    await adapter.initialize([
      CCNavigationRoute(
        routeId: 'filters',
        patterns: [const CCPathPattern('/filters', primary: true)],
        presentation: const CCModalBottomSheetPresentation(
          isScrollControlled: true,
        ),
        deepLink: CCDeepLinkPolicy.disabled,
      ),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final pushed = adapter.navigate(
      request(
        id: 'filters',
        operation: CCNavigationOperation.push,
        uri: Uri.parse('/filters'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('filters'), findsOneWidget);

    adapter.pop(result: 'selected');
    await tester.pumpAndSettle();
    expect(await pushed, 'selected');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('presents a dialog with a dismissible barrier configuration', (
    tester,
  ) async {
    final goRoute = GoRoute(
      path: '/confirm',
      pageBuilder: (_, state) => ccGoRouterDialogPage(
        key: state.pageKey,
        child: const Text('confirm'),
        presentation: const CCDialogPresentation(
          routeType: CCDialogRouteType.material,
        ),
      ),
    );
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        goRoute,
      ],
    );
    final adapter = CCGoRouterAdapter(
      router: router,
      bindings: [
        CCGoRouterRouteBinding(
          routeId: 'confirm',
          goRoute: goRoute,
          presentationKind: CCGoRouterPresentationKind.dialog,
        ),
      ],
    );
    addTearDown(router.dispose);
    await adapter.initialize([
      CCNavigationRoute(
        routeId: 'confirm',
        patterns: [const CCPathPattern('/confirm', primary: true)],
        presentation: const CCDialogPresentation(
          routeType: CCDialogRouteType.material,
        ),
        deepLink: CCDeepLinkPolicy.disabled,
      ),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final pushed = adapter.navigate(
      request(
        id: 'confirm',
        operation: CCNavigationOperation.push,
        uri: Uri.parse('/confirm'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('confirm'), findsOneWidget);

    final pages = router.routerDelegate.navigatorKey.currentState!.widget.pages;
    final dialogPage = pages.whereType<CCGoRouterDialogPage>().single;
    expect(dialogPage.presentation.barrierDismissible, isNull);
    adapter.pop();
    await tester.pumpAndSettle();
    expect(await pushed, isNull);
    expect(find.text('home'), findsOneWidget);
  });

  test('guards adapter lifecycle transitions', () async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
    );
    final adapter = CCGoRouterAdapter(router: router);
    addTearDown(router.dispose);
    final navigation = request(
      id: 'detail',
      operation: CCNavigationOperation.go,
      uri: Uri.parse('/detail/1'),
    );

    expect(
      () => adapter.navigate(navigation),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    await adapter.initialize([route('detail')]);
    await expectLater(
      adapter.initialize([route('detail')]),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    await adapter.dispose();
    expect(adapter.isInitialized, isFalse);
    expect(
      () => adapter.navigate(navigation),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    expect(() => adapter.canPop(), throwsA(isA<CCNavigationAdapterError>()));
    await expectLater(
      adapter.initialize([route('detail')]),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    await adapter.dispose();
  });

  test('Runtime owns adapter disposal while Session close does not', () async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
    );
    final adapter = CCGoRouterAdapter(router: router);
    addTearDown(router.dispose);
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      components: const [],
    );

    await runtime.initialize();
    runtime.openSession(accountId: 'account');
    await runtime.closeSession();
    expect(adapter.isInitialized, isTrue);
    await runtime.dispose();
    expect(adapter.isInitialized, isFalse);
  });

  test('validates one-to-one Runtime route bindings', () async {
    final goRoute = GoRoute(
      path: '/detail/:value',
      builder: (_, _) => const SizedBox(),
    );
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox()),
        goRoute,
      ],
    );
    final adapter = CCGoRouterAdapter(
      router: router,
      bindings: [CCGoRouterRouteBinding(routeId: 'detail', goRoute: goRoute)],
    );
    addTearDown(router.dispose);

    await adapter.initialize([route('detail')]);
    expect(adapter.bindings.single.routeId, 'detail');
    expect(adapter.bindings.single.goRoute, same(goRoute));
    await adapter.dispose();
  });

  test('rejects missing and unknown route bindings', () async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
    );
    final adapter = CCGoRouterAdapter(
      router: router,
      bindings: [
        CCGoRouterRouteBinding(
          routeId: 'unknown',
          goRoute: GoRoute(
            path: '/unknown',
            builder: (_, _) => const SizedBox(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await expectLater(
      adapter.initialize([route('detail')]),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    expect(adapter.isInitialized, isFalse);
  });

  test('rejects non-root Outlet routes without a Navigator key', () async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
    );
    final adapter = CCGoRouterAdapter(router: router);
    addTearDown(router.dispose);

    final placed = CCNavigationRoute(
      routeId: 'detail',
      patterns: [const CCPathPattern('/detail', primary: true)],
      presentation: const CCPagePresentation(),
      deepLink: CCDeepLinkPolicy.disabled,
      placement: const CCRoutePlacement(navigatorOutlet: 'detail'),
    );
    await expectLater(
      adapter.initialize([placed]),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    expect(adapter.isInitialized, isFalse);
  });

  test('rejects Runtime Shell contracts without GoRouter bindings', () async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
    );
    final adapter = CCGoRouterAdapter(router: router);
    addTearDown(router.dispose);

    await expectLater(
      adapter.initialize(
        const [],
        shells: [
          CCNavigationShell(
            shellId: 'workspace',
            type: CCShellType.singleNavigator,
            outlets: const ['content'],
            initialOutlet: 'content',
          ),
        ],
      ),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    expect(adapter.isInitialized, isFalse);
  });

  test(
    'rejects Stateful Shell bindings with mismatched Outlet order',
    () async {
      final homeKey = GlobalKey<NavigatorState>();
      final settingsKey = GlobalKey<NavigatorState>();
      final shellRoute = StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) => navigationShell,
        branches: [
          StatefulShellBranch(
            navigatorKey: homeKey,
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const SizedBox()),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: settingsKey,
            routes: [
              GoRoute(path: '/settings', builder: (_, _) => const SizedBox()),
            ],
          ),
        ],
      );
      final router = GoRouter(routes: [shellRoute]);
      final adapter = CCGoRouterAdapter(
        router: router,
        shells: [
          CCGoRouterShellBinding(
            shellId: 'tabs',
            route: shellRoute,
            initialOutlet: 'home',
            outlets: {'settings': settingsKey, 'home': homeKey},
          ),
        ],
      );
      addTearDown(router.dispose);

      await expectLater(
        adapter.initialize(
          const [],
          shells: [
            CCNavigationShell(
              shellId: 'tabs',
              type: CCShellType.statefulBranches,
              outlets: const ['home', 'settings'],
              initialOutlet: 'home',
            ),
          ],
        ),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      expect(adapter.isInitialized, isFalse);
    },
  );

  testWidgets('uses the configured Shell Navigator for an Outlet route', (
    tester,
  ) async {
    final shellNavigatorKey = GlobalKey<NavigatorState>();
    final detailRoute = GoRoute(
      path: '/detail',
      builder: (_, _) => const Text('detail'),
    );
    final shellRoute = ShellRoute(
      navigatorKey: shellNavigatorKey,
      builder: (_, _, child) => Scaffold(body: child),
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const Text('home')),
        detailRoute,
      ],
    );
    final router = GoRouter(initialLocation: '/home', routes: [shellRoute]);
    final adapter = CCGoRouterAdapter(
      router: router,
      shells: [
        CCGoRouterShellBinding(
          shellId: 'workspace-shell',
          route: shellRoute,
          initialOutlet: 'detail',
          outlets: {'detail': shellNavigatorKey},
        ),
      ],
      bindings: [
        CCGoRouterRouteBinding(routeId: 'detail', goRoute: detailRoute),
      ],
    );
    addTearDown(router.dispose);
    final placement = const CCRoutePlacement(
      shellId: 'workspace-shell',
      navigatorOutlet: 'detail',
    );
    await adapter.initialize(
      [
        CCNavigationRoute(
          routeId: 'detail',
          patterns: [const CCPathPattern('/detail', primary: true)],
          presentation: const CCPagePresentation(),
          deepLink: CCDeepLinkPolicy.disabled,
          placement: placement,
        ),
      ],
      shells: [
        CCNavigationShell(
          shellId: 'workspace-shell',
          type: CCShellType.singleNavigator,
          outlets: const ['detail'],
          initialOutlet: 'detail',
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final pushed = adapter.navigate(
      request(
        id: 'detail',
        operation: CCNavigationOperation.push,
        uri: Uri.parse('/detail'),
        placement: placement,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(adapter.canPop(), isTrue);

    adapter.pop(result: 'closed');
    await tester.pumpAndSettle();
    expect(await pushed, 'closed');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('binds StatefulShellRoute branch Navigators by Outlet', (
    tester,
  ) async {
    final homeKey = GlobalKey<NavigatorState>();
    final settingsKey = GlobalKey<NavigatorState>();
    final homeRoute = GoRoute(
      path: '/home',
      builder: (_, _) => const Text('home'),
    );
    final settingsDetailRoute = GoRoute(
      path: 'detail',
      builder: (_, _) => const Text('settings-detail'),
    );
    final settingsRoute = GoRoute(
      path: '/settings',
      builder: (_, _) => const Text('settings'),
      routes: [settingsDetailRoute],
    );
    final shellRoute = StatefulShellRoute.indexedStack(
      builder: (_, _, navigationShell) => Scaffold(body: navigationShell),
      branches: [
        StatefulShellBranch(navigatorKey: homeKey, routes: [homeRoute]),
        StatefulShellBranch(navigatorKey: settingsKey, routes: [settingsRoute]),
      ],
    );
    final router = GoRouter(initialLocation: '/home', routes: [shellRoute]);
    final adapter = CCGoRouterAdapter(
      router: router,
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
          routeId: 'settings.detail',
          goRoute: settingsDetailRoute,
        ),
      ],
    );
    addTearDown(router.dispose);
    const placement = CCRoutePlacement(
      shellId: 'tabs',
      navigatorOutlet: 'settings',
    );
    await adapter.initialize(
      [
        CCNavigationRoute(
          routeId: 'settings.detail',
          patterns: [const CCPathPattern('/settings/detail', primary: true)],
          presentation: const CCPagePresentation(),
          deepLink: CCDeepLinkPolicy.disabled,
          placement: placement,
        ),
      ],
      shells: [
        CCNavigationShell(
          shellId: 'tabs',
          type: CCShellType.statefulBranches,
          outlets: const ['home', 'settings'],
          initialOutlet: 'home',
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await adapter.navigate(
      request(
        id: 'settings.detail',
        operation: CCNavigationOperation.go,
        uri: Uri.parse('https://example.com/settings/detail'),
        placement: placement,
        origin: CCNavigationOrigin.externalPlatform,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('settings-detail'), findsOneWidget);
  });

  testWidgets('supports popAndPush and completes the removed result', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(path: '/one', builder: (_, _) => const Text('one')),
        GoRoute(path: '/two', builder: (_, _) => const Text('two')),
        GoRoute(path: '/three', builder: (_, _) => const Text('three')),
      ],
    );
    final adapter = CCGoRouterAdapter(router: router);
    addTearDown(router.dispose);
    await adapter.initialize([
      route('one', path: '/one'),
      route('two', path: '/two'),
      route('three', path: '/three'),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await adapter.navigate(
      request(
        id: 'one',
        operation: CCNavigationOperation.go,
        uri: Uri.parse('/one'),
      ),
    );
    final removed = adapter.navigate(
      request(
        id: 'two',
        operation: CCNavigationOperation.push,
        uri: Uri.parse('/two'),
      ),
    );
    await tester.pumpAndSettle();
    final pushed = adapter.popAndPush(
      request(
        id: 'three',
        operation: CCNavigationOperation.popAndPush,
        uri: Uri.parse('/three'),
      ),
      popResult: 'removed',
    );
    await tester.pumpAndSettle();

    expect(find.text('three'), findsOneWidget);
    expect(await removed, 'removed');
    adapter.pop(result: 'done');
    await tester.pumpAndSettle();
    expect(await pushed, 'done');
    expect(find.text('one'), findsOneWidget);
  });

  testWidgets('supports pushAndRemoveUntil with a route predicate', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(path: '/one', builder: (_, _) => const Text('one')),
        GoRoute(path: '/two', builder: (_, _) => const Text('two')),
        GoRoute(path: '/three', builder: (_, _) => const Text('three')),
        GoRoute(path: '/four', builder: (_, _) => const Text('four')),
      ],
    );
    final adapter = CCGoRouterAdapter(router: router);
    addTearDown(router.dispose);
    await adapter.initialize([
      route('one', path: '/one'),
      route('two', path: '/two'),
      route('three', path: '/three'),
      route('four', path: '/four'),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await adapter.navigate(
      request(
        id: 'one',
        operation: CCNavigationOperation.go,
        uri: Uri.parse('/one'),
      ),
    );
    final removedTwo = adapter.navigate(
      request(
        id: 'two',
        operation: CCNavigationOperation.push,
        uri: Uri.parse('/two'),
      ),
    );
    final removedThree = adapter.navigate(
      request(
        id: 'three',
        operation: CCNavigationOperation.push,
        uri: Uri.parse('/three'),
      ),
    );
    await tester.pumpAndSettle();
    final pushed = adapter.pushAndRemoveUntil(
      request(
        id: 'four',
        operation: CCNavigationOperation.pushAndRemoveUntil,
        uri: Uri.parse('/four'),
      ),
      (entry) => entry.routeId == 'one',
    );
    await tester.pumpAndSettle();

    expect(find.text('four'), findsOneWidget);
    expect(await removedTwo, isNull);
    expect(await removedThree, isNull);
    adapter.pop(result: 'done');
    await tester.pumpAndSettle();
    expect(await pushed, 'done');
    expect(find.text('one'), findsOneWidget);
  });

  testWidgets('supports popUntil with a route predicate', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(path: '/one', builder: (_, _) => const Text('one')),
        GoRoute(path: '/two', builder: (_, _) => const Text('two')),
        GoRoute(path: '/three', builder: (_, _) => const Text('three')),
      ],
    );
    final adapter = CCGoRouterAdapter(router: router);
    addTearDown(router.dispose);
    await adapter.initialize([
      route('one', path: '/one'),
      route('two', path: '/two'),
      route('three', path: '/three'),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await adapter.navigate(
      request(
        id: 'one',
        operation: CCNavigationOperation.go,
        uri: Uri.parse('/one'),
      ),
    );
    final removedTwo = adapter.navigate(
      request(
        id: 'two',
        operation: CCNavigationOperation.push,
        uri: Uri.parse('/two'),
      ),
    );
    final removedThree = adapter.navigate(
      request(
        id: 'three',
        operation: CCNavigationOperation.push,
        uri: Uri.parse('/three'),
      ),
    );
    await tester.pumpAndSettle();

    await adapter.popUntil((entry) => entry.routeId == 'one');
    await tester.pumpAndSettle();

    expect(await removedTwo, isNull);
    expect(await removedThree, isNull);
    expect(find.text('one'), findsOneWidget);
  });
}
