import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'backend.dart';
import 'assembler.dart';
import 'navigation_observer.dart';
import 'shell_binding.dart';

/// Creates one GoRouter Backend from immutable Host configuration.
///
/// [CCGoRouterApp] calls the factory exactly once from its State initialization.
/// Use this extension point when a Host needs custom Shell, redirect, refresh,
/// or Router construction that cannot be represented by the default managed
/// Backend. The returned Backend is transferred to [CCRouterApp.managed] and
/// follows that widget's normal ownership and shutdown contract.
typedef CCGoRouterBackendFactory =
    CCGoRouterBackend Function(CCGoRouterBackendConfiguration configuration);

/// Immutable inputs used to create one [CCGoRouterBackend].
///
/// Custom factories receive the same configuration consumed by the default
/// managed Backend. This keeps the application wrapper stable when Backend
/// construction moves between the built-in path and an application-owned
/// factory.
final class CCGoRouterBackendConfiguration {
  /// Creates a snapshot of the Host's GoRouter Backend configuration.
  const CCGoRouterBackendConfiguration({
    required this.catalog,
    required this.host,
    required this.hostRoutes,
    required this.overrides,
    required this.shells,
    required this.outletObservers,
    required this.additionalRootObservers,
    required this.initialLocation,
    required this.lifecycleEventCapacity,
    required this.enablePredictiveBack,
  });

  /// Generated backend-neutral route catalog assembled for this Host.
  final CCFlutterRouteCatalog catalog;

  /// Optional explicit Host identity and Navigator Outlet keys.
  final CCNavigationHost? host;

  /// Application-owned root routes mounted before generated routes.
  final Iterable<RouteBase> hostRoutes;

  /// Host overrides for generated route bindings.
  final Map<String, CCGoRouterRouteOverride> overrides;

  /// Shell and StatefulShell bindings mounted beside generated routes.
  final Iterable<CCGoRouterShellBinding> shells;

  /// Observers installed on managed Shell and Outlet Navigators.
  final Iterable<CCGoRouterNavigationObserver> outletObservers;

  /// Additional observers installed on the root GoRouter Navigator.
  final Iterable<NavigatorObserver> additionalRootObservers;

  /// Initial location passed to the managed GoRouter.
  final String initialLocation;

  /// Bounded backend lifecycle event capacity.
  final int lifecycleEventCapacity;

  /// Whether the predictive-back bridge is enabled for this Host.
  final bool enablePredictiveBack;

  /// Creates the framework's default managed Backend from this configuration.
  CCGoRouterBackend createManagedBackend() => CCGoRouterBackend.managed(
    catalog: catalog,
    host: host,
    hostRoutes: hostRoutes,
    overrides: overrides,
    shells: shells,
    outletObservers: outletObservers,
    additionalRootObservers: additionalRootObservers,
    initialLocation: initialLocation,
    lifecycleEventCapacity: lifecycleEventCapacity,
    enablePredictiveBack: enablePredictiveBack,
  );
}

/// Minimal GoRouter Host for applications that use generated CCRouter routes.
///
/// The application Composition Root must call [CCRouter.initialize] before
/// mounting this widget. This widget deliberately does not initialize or shut
/// down the process Runtime; it only creates and registers one navigation Host.
///
/// The widget creates one GoRouter and installs the CCRouter Adapter, root
/// Observer, generated route assembly, and [MaterialApp.router] in one place.
/// Supply [backendFactory] for an application-specific Router topology while
/// retaining the same Host and Material application wrapper.
/// It never stores a global [BuildContext], and removing it does not shut down
/// the Runtime; the application composition root remains responsible for that.
final class CCGoRouterApp extends StatefulWidget {
  /// Creates a managed GoRouter Host from the initialized Host Catalog.
  ///
  /// The Composition Root must call `CCRouter.initialize` first. This wrapper
  /// resolves the exact Catalog retained from that Host Assembly so callers do
  /// not repeat or accidentally mismatch generated startup inputs.
  const CCGoRouterApp({
    this.backendFactory,
    this.host,
    this.hostRoutes = const [],
    this.overrides = const {},
    this.shells = const [],
    this.outletObservers = const [],
    this.additionalRootObservers = const [],
    this.initialLocation = '/',
    this.lifecycleEventCapacity = 1000,
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

  /// Optional application-owned Backend factory called once for this Host.
  ///
  /// Omit this for the default [CCGoRouterBackend.managed] assembly. A custom
  /// factory should use the supplied immutable configuration rather than read
  /// mutable Widget State or perform Runtime initialization.
  final CCGoRouterBackendFactory? backendFactory;

  /// Optional Host identity and Navigator Outlet keys.
  final CCNavigationHost? host;

  /// Application-owned root routes mounted before generated routes.
  final Iterable<RouteBase> hostRoutes;

  /// Host overrides for generated route bindings.
  final Map<String, CCGoRouterRouteOverride> overrides;

  /// Shell and StatefulShell bindings mounted beside generated routes.
  final Iterable<CCGoRouterShellBinding> shells;

  /// Observers installed on managed Shell and Outlet Navigators.
  final Iterable<CCGoRouterNavigationObserver> outletObservers;

  /// Additional observers installed on the root GoRouter Navigator.
  final Iterable<NavigatorObserver> additionalRootObservers;

  /// Initial location passed to the managed GoRouter.
  final String initialLocation;

  /// Bounded backend lifecycle event capacity.
  final int lifecycleEventCapacity;

  /// Whether the predictive-back bridge is enabled for this Host.
  final bool enablePredictiveBack;

  /// Material application title.
  final String title;

  /// Generates a localized application title from the active context.
  final GenerateAppTitle? onGenerateTitle;

  /// Observes navigation notifications emitted by the Material application.
  final NotificationListenerCallback<NavigationNotification>?
  onNavigationNotification;

  /// Primary application color used by the operating system interface.
  final Color? color;

  /// Light theme used by [MaterialApp.router].
  final ThemeData? theme;

  /// Dark theme used by [MaterialApp.router].
  final ThemeData? darkTheme;

  /// High-contrast light theme used by [MaterialApp.router].
  final ThemeData? highContrastTheme;

  /// High-contrast dark theme used by [MaterialApp.router].
  final ThemeData? highContrastDarkTheme;

  /// Theme selection used by [MaterialApp.router].
  final ThemeMode themeMode;

  /// Duration used when [MaterialApp.router] animates theme changes.
  final Duration themeAnimationDuration;

  /// Curve used when [MaterialApp.router] animates theme changes.
  final Curve themeAnimationCurve;

  /// Optional animation style overriding theme duration and curve.
  final AnimationStyle? themeAnimationStyle;

  /// Locale selected for the Material application.
  final Locale? locale;

  /// Localization delegates available to the Material application.
  final Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates;

  /// Resolves a locale from the complete platform locale preference list.
  final LocaleListResolutionCallback? localeListResolutionCallback;

  /// Resolves one platform locale against [supportedLocales].
  final LocaleResolutionCallback? localeResolutionCallback;

  /// Locales supported by the Material application.
  final Iterable<Locale> supportedLocales;

  /// Optional Material application builder.
  final TransitionBuilder? builder;

  /// Key used to access the application-level [ScaffoldMessenger].
  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;

  /// Application-level keyboard shortcut mappings.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// Application-level intent action mappings.
  final Map<Type, Action<Intent>>? actions;

  /// Restoration scope identity used by the Material application.
  final String? restorationScopeId;

  /// Default scrolling behavior used by the Material application.
  final ScrollBehavior? scrollBehavior;

  /// Whether the Material baseline grid is shown in debug mode.
  final bool debugShowMaterialGrid;

  /// Whether the Flutter performance overlay is shown.
  final bool showPerformanceOverlay;

  /// Whether raster cache images are checkerboarded for debugging.
  final bool checkerboardRasterCacheImages;

  /// Whether offscreen layers are checkerboarded for debugging.
  final bool checkerboardOffscreenLayers;

  /// Whether the semantics debugger overlay is shown.
  final bool showSemanticsDebugger;

  /// Whether Flutter's debug banner is shown.
  final bool debugShowCheckedModeBanner;

  /// Observes process-level Flutter lifecycle changes.
  final ValueChanged<AppLifecycleState>? onLifecycleChanged;

  @override
  /// Creates state that owns this Host's managed Backend.
  State<CCGoRouterApp> createState() => _CCGoRouterAppState();
}

/// State that creates one managed GoRouter Backend for the Host lifetime.
final class _CCGoRouterAppState extends State<CCGoRouterApp> {
  /// Managed Backend retained for the complete mounted Host lifetime.
  late final CCGoRouterBackend _backend;

  @override
  /// Validates the process Runtime and creates the Host Backend once.
  void initState() {
    super.initState();
    late final CCFlutterRouteCatalog catalog;
    try {
      catalog = CCRouterHostBinding.routeCatalog;
    } on CCRouterNotInitializedError {
      throw FlutterError(
        'CCRouter is not initialized. Call CCRouter.initialize from the '
        'application Composition Root before mounting CCGoRouterApp.',
      );
    }
    final configuration = CCGoRouterBackendConfiguration(
      catalog: catalog,
      host: widget.host,
      hostRoutes: List<RouteBase>.unmodifiable(widget.hostRoutes),
      overrides: Map<String, CCGoRouterRouteOverride>.unmodifiable(
        widget.overrides,
      ),
      shells: List<CCGoRouterShellBinding>.unmodifiable(widget.shells),
      outletObservers: List<CCGoRouterNavigationObserver>.unmodifiable(
        widget.outletObservers,
      ),
      additionalRootObservers: List<NavigatorObserver>.unmodifiable(
        widget.additionalRootObservers,
      ),
      initialLocation: widget.initialLocation,
      lifecycleEventCapacity: widget.lifecycleEventCapacity,
      enablePredictiveBack: widget.enablePredictiveBack,
    );
    _backend =
        widget.backendFactory?.call(configuration) ??
        configuration.createManagedBackend();
  }

  @override
  /// Builds the Material Router tree and transfers Backend attachment to the
  /// core Host lifecycle widget.
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
      routerConfig: _backend.router,
    );
    return CCRouterApp.managed(
      key: const ValueKey<String>('ccrouter.go_router.managed_host'),
      backend: _backend,
      onLifecycleChanged: widget.onLifecycleChanged,
      child: materialApp,
    );
  }

  @override
  /// Rejects configuration changes that would require rebuilding the Router.
  void didUpdateWidget(covariant CCGoRouterApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.host, oldWidget.host) ||
        widget.initialLocation != oldWidget.initialLocation ||
        widget.lifecycleEventCapacity != oldWidget.lifecycleEventCapacity ||
        widget.enablePredictiveBack != oldWidget.enablePredictiveBack) {
      throw FlutterError(
        'CCGoRouterApp Backend configuration is immutable after mounting. '
        'Recreate it with a new Key when its Backend inputs change.',
      );
    }
  }
}
