import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'backend.dart';
import 'assembler.dart';
import 'navigation_observer.dart';
import 'shell_binding.dart';

/// Minimal GoRouter Host for applications that use generated CCRouter routes.
///
/// This widget creates and registers one managed Backend, while Runtime
/// ownership still follows the normal [CCRouter.initialize] and
/// [CCRouter.shutdown] contract.
/// When [components] is supplied and no Runtime exists yet, the widget performs
/// the basic component initialization as a startup convenience. Applications
/// that need interceptors, deep-link policy, telemetry, or other global options
/// should call [CCRouter.initialize] explicitly before mounting this widget.
///
/// The widget creates one GoRouter and installs the CCRouter Adapter, root
/// Observer, generated route assembly, and [MaterialApp.router] in one place.
/// It never stores a global [BuildContext], and removing it does not shut down
/// the Runtime; the application composition root remains responsible for that.
final class CCGoRouterApp extends StatefulWidget {
  /// Creates a managed GoRouter Host from a generated [catalog].
  ///
  /// Pass [components] only when this widget should perform the basic
  /// `CCRouter.initialize(components: ...)` startup step. If the Runtime is
  /// already initialized, the existing Runtime remains authoritative and the
  /// value is used only for startup documentation and diagnostics.
  const CCGoRouterApp({
    required this.catalog,
    this.components,
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

  /// Optional component manifests used for basic automatic initialization.
  ///
  /// Leave this null when the application already called
  /// [CCRouter.initialize] with its complete global configuration.
  final Iterable<CCComponentManifest>? components;

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
  /// Initializes the optional Runtime shorthand and creates the Backend once.
  void initState() {
    super.initState();
    _initializeRuntimeIfRequested();
    _backend = CCGoRouterBackend.managed(
      catalog: widget.catalog,
      host: widget.host,
      hostRoutes: widget.hostRoutes,
      overrides: widget.overrides,
      shells: widget.shells,
      outletObservers: widget.outletObservers,
      additionalRootObservers: widget.additionalRootObservers,
      initialLocation: widget.initialLocation,
      lifecycleEventCapacity: widget.lifecycleEventCapacity,
      enablePredictiveBack: widget.enablePredictiveBack,
    );
  }

  /// Performs only the basic component initialization when requested.
  void _initializeRuntimeIfRequested() {
    if (CCRouter.isInitialized) return;
    final components = widget.components;
    if (components == null) {
      throw FlutterError(
        'CCRouter is not initialized. Call CCRouter.initialize before '
        'mounting CCGoRouterApp, or provide components for the basic '
        'startup shorthand.',
      );
    }
    CCRouter.initialize(components: components);
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
        widget.initialLocation != oldWidget.initialLocation) {
      throw FlutterError(
        'CCGoRouterApp configuration is immutable after mounting. Recreate '
        'it with a new Key when the catalog, Host, or initialLocation changes.',
      );
    }
  }
}
