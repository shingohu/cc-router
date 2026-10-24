import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/managed_test_home.dart';

CCHostAssembly _assembly() => CCHostAssembly.fromComponents(
  components: const [
    CCComponentManifest(
      id: 'fixture',
      version: '1.0.0',
      registrar: TestHomeRegistrar(),
    ),
  ],
  routeCatalog: CCFlutterRouteCatalog([testHomeDestination()]),
);

void main() {
  tearDown(CCRouterHost.shutdown);
  testWidgets('CCManagedRouterApp forwards MaterialApp.router configuration', (
    tester,
  ) async {
    CCRouterHost.initialize(hostAssembly: _assembly());
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
      CCManagedRouterApp(
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

  testWidgets('Managed custom factory runs once across presentation rebuilds', (
    tester,
  ) async {
    final assembly = _assembly();
    CCRouterHost.initialize(hostAssembly: assembly);
    var calls = 0;
    final CCManagedRouterBackend Function(CCManagedRouterBackendConfiguration)
    factory = (configuration) {
      calls++;
      expect(configuration.catalog, same(assembly.routeCatalog));
      return configuration.createManagedBackend();
    };
    await tester.pumpWidget(
      CCManagedRouterApp(title: 'first', backendFactory: factory),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      CCManagedRouterApp(title: 'second', backendFactory: factory),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('home'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(CCRouter.isInitialized, isTrue);
  });
}
