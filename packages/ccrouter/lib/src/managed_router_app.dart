import 'package:flutter/material.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';

import 'app.dart';
import 'facade.dart';
import 'managed_router.dart';
import 'route_catalog.dart';

/// Creates one Managed Router Backend for a Host.
typedef CCManagedRouterBackendFactory =
    CCManagedRouterBackend Function(CCManagedRouterBackendConfiguration);

/// Immutable inputs supplied to [CCManagedRouterBackendFactory].
final class CCManagedRouterBackendConfiguration {
  /// Creates configuration for one Managed Host.
  const CCManagedRouterBackendConfiguration({
    required this.catalog,
    required this.host,
    required this.shellBindings,
    required this.initialLocation,
    this.overridePlatformDefaultLocation = false,
    required this.additionalObservers,
    required this.enablePredictiveBack,
    this.initializeFromRouteInformation = true,
  });

  /// Catalog retained by the initialized Host Assembly.
  final CCFlutterRouteCatalog catalog;

  /// Optional Host identity and Navigator keys.
  final CCNavigationHost? host;

  /// Application-owned Shell renderers.
  final List<CCManagedShellBinding> shellBindings;

  /// Trusted startup fallback, or null to always consume the platform URI.
  final String? initialLocation;

  /// Forces the trusted fallback even when the platform supplies another URI.
  final bool overridePlatformDefaultLocation;

  /// Additional observers installed on Managed Navigators.
  final List<NavigatorObserver> additionalObservers;

  /// Enables the optional Android predictive-back bridge.
  final bool enablePredictiveBack;

  /// Controls whether this Backend consumes Flutter's initial location.
  final bool initializeFromRouteInformation;

  /// Creates the default Managed Backend from this configuration.
  CCManagedRouterBackend createManagedBackend() => CCManagedRouterBackend(
    routeCatalog: catalog,
    host: host,
    shellBindings: shellBindings,
    initialLocation: initialLocation,
    overridePlatformDefaultLocation: overridePlatformDefaultLocation,
    additionalObservers: additionalObservers,
    enablePredictiveBack: enablePredictiveBack,
    initializeFromRouteInformation: initializeFromRouteInformation,
  );
}

/// Convenience Host widget for the CCRouter Managed Backend.
///
/// The application must call `CCRouterHost.initialize` before mounting this
/// widget. It creates one [CCManagedRouterBackend], installs it through
/// [CCRouterApp.managed], and supplies its [RouterConfig] to
/// [MaterialApp.router]. The Runtime remains owned by [CCRouterHost]; removing
/// this widget does not shut down the Runtime.
///
/// Use [backendFactory] when the Host needs custom Shell/Outlet topology that
/// cannot be expressed by the direct constructor fields. The factory is called
/// once for the widget lifetime and receives the exact Catalog retained by the
/// initialized Host Assembly.
final class CCManagedRouterApp extends StatefulWidget {
  /// Creates a Managed Router Host with the standard Material application
  /// configuration.
  const CCManagedRouterApp({
    this.backendFactory,
    this.host,
    this.shellBindings = const [],
    this.initialLocation = '/',
    this.overridePlatformDefaultLocation = false,
    this.additionalObservers = const [],
    this.enablePredictiveBack = false,
    this.title = '',
    this.onGenerateTitle,
    this.onNavigationNotification,
    this.color,
    this.theme,
    this.darkTheme,
    this.highContrastTheme,
    this.highContrastDarkTheme,
    this.themeMode = ThemeMode.system,
    this.themeAnimationDuration = kThemeAnimationDuration,
    this.themeAnimationCurve = Curves.linear,
    this.themeAnimationStyle,
    this.locale,
    this.localizationsDelegates,
    this.localeListResolutionCallback,
    this.localeResolutionCallback,
    this.supportedLocales = const <Locale>[Locale('en', 'US')],
    this.builder,
    this.scaffoldMessengerKey,
    this.shortcuts,
    this.actions,
    this.restorationScopeId,
    this.scrollBehavior,
    this.debugShowMaterialGrid = false,
    this.showPerformanceOverlay = false,
    this.checkerboardRasterCacheImages = false,
    this.checkerboardOffscreenLayers = false,
    this.showSemanticsDebugger = false,
    this.debugShowCheckedModeBanner = true,
    this.onLifecycleChanged,
    super.key,
  });

  /// Optional custom Managed Backend factory.
  final CCManagedRouterBackendFactory? backendFactory;

  /// Optional Host identity and Navigator keys.
  final CCNavigationHost? host;

  /// Shell bindings used by the default Managed Backend.
  final Iterable<CCManagedShellBinding> shellBindings;

  /// Trusted startup fallback, or null to always consume the platform URI.
  final String? initialLocation;

  /// Explicitly ignores platform startup links in favor of [initialLocation].
  final bool overridePlatformDefaultLocation;

  /// Additional observers installed on Managed Navigators.
  final Iterable<NavigatorObserver> additionalObservers;

  /// Enables the optional Android predictive-back bridge for generated Pages.
  final bool enablePredictiveBack;

  /// Material application title.
  final String title;

  /// Generates a localized application title.
  final GenerateAppTitle? onGenerateTitle;

  /// Observes Material navigation notifications.
  final NotificationListenerCallback<NavigationNotification>?
  onNavigationNotification;

  /// Primary application color.
  final Color? color;

  /// Light theme.
  final ThemeData? theme;

  /// Dark theme.
  final ThemeData? darkTheme;

  /// High-contrast light theme.
  final ThemeData? highContrastTheme;

  /// High-contrast dark theme.
  final ThemeData? highContrastDarkTheme;

  /// Theme selection.
  final ThemeMode themeMode;

  /// Theme animation duration.
  final Duration themeAnimationDuration;

  /// Theme animation curve.
  final Curve themeAnimationCurve;

  /// Optional theme animation style.
  final AnimationStyle? themeAnimationStyle;

  /// Application locale.
  final Locale? locale;

  /// Localization delegates.
  final Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates;

  /// Resolves a locale from platform preferences.
  final LocaleListResolutionCallback? localeListResolutionCallback;

  /// Resolves one platform locale.
  final LocaleResolutionCallback? localeResolutionCallback;

  /// Supported application locales.
  final Iterable<Locale> supportedLocales;

  /// Optional Material application builder.
  final TransitionBuilder? builder;

  /// Application ScaffoldMessenger key.
  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;

  /// Keyboard shortcut mappings.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// Keyboard action mappings.
  final Map<Type, Action<Intent>>? actions;

  /// Material restoration scope identity.
  final String? restorationScopeId;

  /// Application scroll behavior.
  final ScrollBehavior? scrollBehavior;

  /// Shows the Material baseline grid in debug mode.
  final bool debugShowMaterialGrid;

  /// Shows Flutter's performance overlay.
  final bool showPerformanceOverlay;

  /// Checkerboards raster-cache images.
  final bool checkerboardRasterCacheImages;

  /// Checkerboards offscreen layers.
  final bool checkerboardOffscreenLayers;

  /// Shows the semantics debugger.
  final bool showSemanticsDebugger;

  /// Shows Flutter's debug banner.
  final bool debugShowCheckedModeBanner;

  /// Observes process-level Flutter lifecycle changes.
  final ValueChanged<AppLifecycleState>? onLifecycleChanged;

  @override
  State<CCManagedRouterApp> createState() => _CCManagedRouterAppState();
}

/// State that creates one Managed Backend for the Host lifetime.
final class _CCManagedRouterAppState extends State<CCManagedRouterApp> {
  late final CCManagedRouterBackend _backend;

  @override
  void initState() {
    super.initState();
    late final CCFlutterRouteCatalog catalog;
    try {
      catalog = CCRouterHostBinding.routeCatalog;
    } on CCRouterNotInitializedError {
      throw FlutterError(
        'CCRouter is not initialized. Call CCRouterHost.initialize from the '
        'application Composition Root before mounting CCManagedRouterApp.',
      );
    }
    final configuration = CCManagedRouterBackendConfiguration(
      catalog: catalog,
      host: widget.host,
      shellBindings: List<CCManagedShellBinding>.unmodifiable(
        widget.shellBindings,
      ),
      initialLocation: widget.initialLocation,
      overridePlatformDefaultLocation: widget.overridePlatformDefaultLocation,
      additionalObservers: List<NavigatorObserver>.unmodifiable(
        widget.additionalObservers,
      ),
      enablePredictiveBack: widget.enablePredictiveBack,
    );
    _backend =
        widget.backendFactory?.call(configuration) ??
        configuration.createManagedBackend();
  }

  @override
  Widget build(BuildContext context) {
    final materialApp = MaterialApp.router(
      scaffoldMessengerKey: widget.scaffoldMessengerKey,
      debugShowCheckedModeBanner: widget.debugShowCheckedModeBanner,
      title: widget.title,
      onGenerateTitle: widget.onGenerateTitle,
      onNavigationNotification: widget.onNavigationNotification,
      color: widget.color,
      theme: widget.theme,
      darkTheme: widget.darkTheme,
      highContrastTheme: widget.highContrastTheme,
      highContrastDarkTheme: widget.highContrastDarkTheme,
      themeMode: widget.themeMode,
      themeAnimationDuration: widget.themeAnimationDuration,
      themeAnimationCurve: widget.themeAnimationCurve,
      themeAnimationStyle: widget.themeAnimationStyle,
      locale: widget.locale,
      localizationsDelegates: widget.localizationsDelegates,
      localeListResolutionCallback: widget.localeListResolutionCallback,
      localeResolutionCallback: widget.localeResolutionCallback,
      supportedLocales: widget.supportedLocales,
      builder: widget.builder,
      shortcuts: widget.shortcuts,
      actions: widget.actions,
      restorationScopeId: widget.restorationScopeId,
      scrollBehavior: widget.scrollBehavior,
      debugShowMaterialGrid: widget.debugShowMaterialGrid,
      showPerformanceOverlay: widget.showPerformanceOverlay,
      checkerboardRasterCacheImages: widget.checkerboardRasterCacheImages,
      checkerboardOffscreenLayers: widget.checkerboardOffscreenLayers,
      showSemanticsDebugger: widget.showSemanticsDebugger,
      routerConfig: _backend.routerConfig,
    );
    return CCRouterApp.managed(
      key: const ValueKey<String>('ccrouter.managed_host'),
      backend: _backend,
      onLifecycleChanged: widget.onLifecycleChanged,
      child: materialApp,
    );
  }

  @override
  void didUpdateWidget(covariant CCManagedRouterApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.host, oldWidget.host) ||
        widget.initialLocation != oldWidget.initialLocation ||
        widget.overridePlatformDefaultLocation !=
            oldWidget.overridePlatformDefaultLocation ||
        widget.enablePredictiveBack != oldWidget.enablePredictiveBack ||
        !identical(widget.backendFactory, oldWidget.backendFactory) ||
        !identical(widget.shellBindings, oldWidget.shellBindings) ||
        !identical(widget.additionalObservers, oldWidget.additionalObservers)) {
      throw FlutterError(
        'CCManagedRouterApp Backend configuration is immutable after mounting. '
        'Recreate it with a new Key when its Backend inputs change.',
      );
    }
  }
}
