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
  /// Creates a managed GoRouter Host from a generated [catalog].
  const CCGoRouterApp({
    required this.catalog,
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
    this.theme,
    this.darkTheme,
    this.themeMode = ThemeMode.system,
    this.builder,
    this.debugShowCheckedModeBanner = true,
    this.onLifecycleChanged,
    super.key,
  });

  /// Generated backend-neutral route catalog assembled for this Host.
  final CCFlutterRouteCatalog catalog;

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

  /// Light theme used by [MaterialApp.router].
  final ThemeData? theme;

  /// Dark theme used by [MaterialApp.router].
  final ThemeData? darkTheme;

  /// Theme selection used by [MaterialApp.router].
  final ThemeMode themeMode;

  /// Optional Material application builder.
  final TransitionBuilder? builder;

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
    if (!CCRouter.isInitialized) {
      throw FlutterError(
        'CCRouter is not initialized. Call CCRouter.initialize from the '
        'application Composition Root before mounting CCGoRouterApp.',
      );
    }
    final configuration = CCGoRouterBackendConfiguration(
      catalog: widget.catalog,
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
      debugShowCheckedModeBanner: widget.debugShowCheckedModeBanner,
      title: widget.title,
      theme: widget.theme,
      darkTheme: widget.darkTheme,
      themeMode: widget.themeMode,
      builder: widget.builder,
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
    if (!identical(widget.catalog, oldWidget.catalog) ||
        !identical(widget.host, oldWidget.host) ||
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
