import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'adapter.dart';
import 'assembler.dart';
import 'navigation_observer.dart';
import 'route_binding.dart';
import 'shell_binding.dart';

/// Managed or attached GoRouter resources consumed by [CCRouterApp.managed].
///
/// Use [CCGoRouterBackend.managed] for a new application that wants generated
/// routes, observer wiring, and Adapter construction from one configuration.
/// Use [CCGoRouterBackend.attach] while incrementally adopting CCRouter in an
/// application that already owns its [GoRouter]. After successful attachment
/// the Runtime owns and disposes [adapter]; [CCRouterApp.managed] handles the
/// rejected-attachment path. This object only disposes a Router created by
/// the managed factory.
final class CCGoRouterBackend implements CCRouterAppBackend {
  /// Creates and owns a GoRouter from one generated route [catalog].
  ///
  /// [hostRoutes] are application-owned root destinations such as `/` and are
  /// mounted before generated routes. Each [shells] route is also mounted at the
  /// root; its Outlet observers must already be configured on the corresponding
  /// Shell because GoRouter cannot add them after route construction.
  factory CCGoRouterBackend.managed({
    required CCFlutterRouteCatalog catalog,
    CCNavigationHost? host,
    Iterable<RouteBase> hostRoutes = const [],
    Map<String, CCGoRouterRouteOverride> overrides = const {},
    Iterable<CCGoRouterShellBinding> shells = const [],
    Iterable<CCGoRouterNavigationObserver> outletObservers = const [],
    Iterable<NavigatorObserver> additionalRootObservers = const [],
    String initialLocation = '/',
    int lifecycleEventCapacity = 1000,
    bool enablePredictiveBack = false,
  }) {
    final resolvedHost = host ?? CCNavigationHost();
    final shellList = List<CCGoRouterShellBinding>.unmodifiable(shells);
    final outletObserverList = List<CCGoRouterNavigationObserver>.unmodifiable(
      outletObservers,
    );
    final rootObserver = CCGoRouterNavigationObserver(
      hostId: resolvedHost.id,
      outlet: 'root',
    );
    final assembly = CCGoRouterAssembler.assemble(
      catalog: catalog,
      overrides: overrides,
    );
    final routes = <RouteBase>[
      ...hostRoutes,
      ...shellList.map((binding) => binding.route),
      ...assembly.routes,
    ];
    if (routes.isEmpty) {
      throw const CCNavigationAdapterError(
        'A managed GoRouter backend requires at least one Host, Shell, or '
        'generated route.',
      );
    }
    final router = GoRouter(
      navigatorKey: resolvedHost.navigatorKey,
      initialLocation: initialLocation,
      observers: [rootObserver, ...additionalRootObservers],
      routes: routes,
    );
    try {
      final adapter = CCGoRouterAdapter(
        router: router,
        bindings: assembly.bindings,
        shells: shellList,
        host: resolvedHost,
        observers: [rootObserver, ...outletObserverList],
        lifecycleEventCapacity: lifecycleEventCapacity,
        enablePredictiveBack: enablePredictiveBack,
      );
      return CCGoRouterBackend._(
        routeCatalog: catalog,
        host: resolvedHost,
        router: router,
        adapter: adapter,
        ownsRouter: true,
      );
    } catch (_) {
      router.dispose();
      rethrow;
    }
  }

  /// Attaches CCRouter to an application-owned [router].
  ///
  /// The caller must have installed [observers] in the existing root or Shell
  /// route configuration before creating this backend. [dispose] never disposes
  /// [router], so the application can remove CCRouter without changing the
  /// Router's lifetime.
  factory CCGoRouterBackend.attach({
    required CCFlutterRouteCatalog catalog,
    required GoRouter router,
    required CCNavigationHost host,
    Iterable<CCGoRouterRouteBinding> bindings = const [],
    Iterable<CCGoRouterShellBinding> shells = const [],
    Iterable<CCGoRouterNavigationObserver> observers = const [],
    int lifecycleEventCapacity = 1000,
    bool enablePredictiveBack = false,
  }) {
    final adapter = CCGoRouterAdapter(
      router: router,
      bindings: bindings,
      shells: shells,
      host: host,
      observers: observers,
      lifecycleEventCapacity: lifecycleEventCapacity,
      enablePredictiveBack: enablePredictiveBack,
    );
    return CCGoRouterBackend._(
      routeCatalog: catalog,
      host: host,
      router: router,
      adapter: adapter,
      ownsRouter: false,
    );
  }

  /// Stores validated backend resources created by one public factory.
  CCGoRouterBackend._({
    required this.routeCatalog,
    required this.host,
    required this.router,
    required this.adapter,
    required bool ownsRouter,
  }) : _ownsRouter = ownsRouter;

  @override
  /// Generated destinations and component provenance consumed by GoRouter.
  final CCFlutterRouteCatalog routeCatalog;

  @override
  /// Stable Host whose Navigator keys are used by the Router and Adapter.
  final CCNavigationHost host;

  /// Concrete GoRouter rendered by the application's `MaterialApp.router`.
  final GoRouter router;

  /// Adapter transferred to the Runtime after successful attachment.
  final CCGoRouterAdapter adapter;

  /// Whether this backend created and therefore owns [router].
  final bool _ownsRouter;

  /// Whether backend-owned resources have already been released.
  bool _disposed = false;

  @override
  /// Adapter transferred by [CCRouterApp.managed] into the Runtime.
  CCNavigationAdapter get navigationAdapter => adapter;

  @override
  /// Releases a managed Router after Runtime shutdown.
  ///
  /// Attached Routers remain application-owned and are deliberately left
  /// usable. This method is idempotent and must not be used to bypass the
  /// ordered teardown performed by `CCRouter.shutdown`.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_ownsRouter) router.dispose();
  }
}
