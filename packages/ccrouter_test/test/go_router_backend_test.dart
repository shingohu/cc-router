import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(CCRouter.shutdown);

  testWidgets('CCGoRouterApp requires an explicitly initialized Runtime', (
    tester,
  ) async {
    await tester.pumpWidget(const CCGoRouterApp());

    expect(
      tester.takeException(),
      isA<FlutterError>().having(
        (error) => error.message,
        'message',
        contains('Call CCRouter.initialize'),
      ),
    );
  });

  testWidgets('CCGoRouterApp uses an explicitly initialized Runtime', (
    tester,
  ) async {
    CCRouter.initialize(
      hostAssembly: CCHostAssembly.fromComponents(components: const []),
    );

    await tester.pumpWidget(
      CCGoRouterApp(
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

  testWidgets('CCGoRouterApp forwards MaterialApp.router configuration', (
    tester,
  ) async {
    CCRouter.initialize(
      hostAssembly: CCHostAssembly.fromComponents(components: const []),
    );
    final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
    final lightTheme = ThemeData.light();
    final darkTheme = ThemeData.dark();
    final highContrastTheme = ThemeData.light(useMaterial3: false);
    final highContrastDarkTheme = ThemeData.dark(useMaterial3: false);
    const animationStyle = AnimationStyle(
      duration: Duration(milliseconds: 80),
      curve: Curves.easeIn,
    );
    const scrollBehavior = MaterialScrollBehavior();
    final shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.keyL): const ActivateIntent(),
    };
    final actions = <Type, Action<Intent>>{
      ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => null),
    };
    String generateTitle(BuildContext context) => 'Localized Host';
    bool onNavigationNotification(NavigationNotification notification) => false;

    await tester.pumpWidget(
      CCGoRouterApp(
        hostRoutes: [
          GoRoute(path: '/', builder: (_, _) => const Text('configured host')),
        ],
        scaffoldMessengerKey: scaffoldMessengerKey,
        title: 'Fallback Host',
        onGenerateTitle: generateTitle,
        onNavigationNotification: onNavigationNotification,
        color: const Color(0xFF123456),
        theme: lightTheme,
        darkTheme: darkTheme,
        highContrastTheme: highContrastTheme,
        highContrastDarkTheme: highContrastDarkTheme,
        themeMode: ThemeMode.dark,
        themeAnimationDuration: const Duration(milliseconds: 120),
        themeAnimationCurve: Curves.easeOut,
        themeAnimationStyle: animationStyle,
        locale: const Locale('en', 'GB'),
        localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
        localeListResolutionCallback: (locales, supported) => supported.last,
        localeResolutionCallback: (locale, supported) => supported.first,
        supportedLocales: const [Locale('en', 'US'), Locale('en', 'GB')],
        shortcuts: shortcuts,
        actions: actions,
        restorationScopeId: 'configured-host',
        scrollBehavior: scrollBehavior,
        debugShowMaterialGrid: true,
        showPerformanceOverlay: true,
        checkerboardRasterCacheImages: true,
        checkerboardOffscreenLayers: true,
        showSemanticsDebugger: true,
        debugShowCheckedModeBanner: false,
      ),
    );
    await tester.pump();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.scaffoldMessengerKey, same(scaffoldMessengerKey));
    expect(materialApp.title, 'Fallback Host');
    expect(materialApp.onGenerateTitle, same(generateTitle));
    expect(
      materialApp.onNavigationNotification,
      same(onNavigationNotification),
    );
    expect(materialApp.color, const Color(0xFF123456));
    expect(materialApp.theme, same(lightTheme));
    expect(materialApp.darkTheme, same(darkTheme));
    expect(materialApp.highContrastTheme, same(highContrastTheme));
    expect(materialApp.highContrastDarkTheme, same(highContrastDarkTheme));
    expect(materialApp.themeMode, ThemeMode.dark);
    expect(
      materialApp.themeAnimationDuration,
      const Duration(milliseconds: 120),
    );
    expect(materialApp.themeAnimationCurve, Curves.easeOut);
    expect(materialApp.themeAnimationStyle, animationStyle);
    expect(materialApp.locale, const Locale('en', 'GB'));
    expect(materialApp.localizationsDelegates, hasLength(1));
    expect(materialApp.localeListResolutionCallback, isNotNull);
    expect(materialApp.localeResolutionCallback, isNotNull);
    expect(materialApp.supportedLocales, const [
      Locale('en', 'US'),
      Locale('en', 'GB'),
    ]);
    expect(materialApp.shortcuts, same(shortcuts));
    expect(materialApp.actions, same(actions));
    expect(materialApp.restorationScopeId, 'configured-host');
    expect(materialApp.scrollBehavior, same(scrollBehavior));
    expect(materialApp.debugShowMaterialGrid, isTrue);
    expect(materialApp.showPerformanceOverlay, isTrue);
    expect(materialApp.checkerboardRasterCacheImages, isTrue);
    expect(materialApp.checkerboardOffscreenLayers, isTrue);
    expect(materialApp.showSemanticsDebugger, isTrue);
    expect(materialApp.debugShowCheckedModeBanner, isFalse);
  });

  testWidgets('CCGoRouterApp creates a custom Backend exactly once', (
    tester,
  ) async {
    final hostAssembly = CCHostAssembly.fromComponents(components: const []);
    CCRouter.initialize(hostAssembly: hostAssembly);
    var factoryCalls = 0;

    await tester.pumpWidget(
      CCGoRouterApp(
        title: 'Custom Host',
        backendFactory: (configuration) {
          factoryCalls += 1;
          expect(configuration.catalog, same(hostAssembly.routeCatalog));
          return configuration.createManagedBackend();
        },
        hostRoutes: [
          GoRoute(path: '/', builder: (_, _) => const Text('custom host')),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      CCGoRouterApp(
        title: 'Updated Host',
        backendFactory: (configuration) {
          factoryCalls += 1;
          return configuration.createManagedBackend();
        },
        hostRoutes: [
          GoRoute(path: '/', builder: (_, _) => const Text('unused rebuild')),
        ],
      ),
    );
    await tester.pump();

    expect(factoryCalls, 1);
    expect(find.text('custom host'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(CCRouter.isInitialized, isTrue);
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
