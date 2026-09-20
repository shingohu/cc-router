import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:demo_navigation_lab/demo_navigation_lab_host.dart';
import 'package:flutter/material.dart';

const demoAdaptiveListOutlet = 'adaptive.list';
const demoAdaptiveDetailOutlet = 'adaptive.detail';

CCGoRouterBackend createDemoRouterBackend({
  required CCFlutterRouteCatalog catalog,
  String hostId = 'default',
  String initialLocation = '/',
}) {
  final singleOutletKey = GlobalKey<NavigatorState>(
    debugLabel: '$hostId.$demoSingleShellOutlet',
  );
  final workspaceHomeKey = GlobalKey<NavigatorState>(
    debugLabel: '$hostId.$demoWorkspaceHomeOutlet',
  );
  final workspaceActivityKey = GlobalKey<NavigatorState>(
    debugLabel: '$hostId.$demoWorkspaceActivityOutlet',
  );
  final workspaceProfileKey = GlobalKey<NavigatorState>(
    debugLabel: '$hostId.$demoWorkspaceProfileOutlet',
  );
  final adaptiveListKey = GlobalKey<NavigatorState>(
    debugLabel: '$hostId.$demoAdaptiveListOutlet',
  );
  final adaptiveDetailKey = GlobalKey<NavigatorState>(
    debugLabel: '$hostId.$demoAdaptiveDetailOutlet',
  );
  final host = CCNavigationHost(
    id: hostId,
    navigatorKeys: {
      demoSingleShellOutlet: singleOutletKey,
      demoWorkspaceHomeOutlet: workspaceHomeKey,
      demoWorkspaceActivityOutlet: workspaceActivityKey,
      demoWorkspaceProfileOutlet: workspaceProfileKey,
      demoAdaptiveListOutlet: adaptiveListKey,
      demoAdaptiveDetailOutlet: adaptiveDetailKey,
    },
  );

  final singleObserver = CCGoRouterNavigationObserver(
    hostId: hostId,
    outlet: demoSingleShellOutlet,
  );
  final workspaceHomeObserver = CCGoRouterNavigationObserver(
    hostId: hostId,
    outlet: demoWorkspaceHomeOutlet,
  );
  final workspaceActivityObserver = CCGoRouterNavigationObserver(
    hostId: hostId,
    outlet: demoWorkspaceActivityOutlet,
  );
  final workspaceProfileObserver = CCGoRouterNavigationObserver(
    hostId: hostId,
    outlet: demoWorkspaceProfileOutlet,
  );

  final singleDetail = _route(
    catalog,
    routeId: 'demo_navigation_lab.shell.detail',
    path: ':item',
  );
  final singleFeed = _route(
    catalog,
    routeId: 'demo_navigation_lab.shell.feed',
    path: '/shell/feed',
    routes: [singleDetail],
  );
  final singleSettings = _route(
    catalog,
    routeId: 'demo_navigation_lab.shell.settings',
    path: '/shell/settings',
  );
  final singleShell = ShellRoute(
    navigatorKey: singleOutletKey,
    observers: [singleObserver],
    builder: (context, state, child) => _SingleShellFrame(
      selectedIndex: state.uri.path.startsWith('/shell/settings') ? 1 : 0,
      child: child,
    ),
    routes: [singleFeed, singleSettings],
  );

  final workspaceDetail = _route(
    catalog,
    routeId: 'demo_navigation_lab.workspace.detail',
    path: ':item',
  );
  final workspaceHome = _route(
    catalog,
    routeId: 'demo_navigation_lab.workspace.home',
    path: '/workspace/home',
    routes: [workspaceDetail],
  );
  final workspaceActivity = _route(
    catalog,
    routeId: 'demo_navigation_lab.workspace.activity',
    path: '/workspace/activity',
  );
  final workspaceProfile = _route(
    catalog,
    routeId: 'demo_navigation_lab.workspace.profile',
    path: '/workspace/profile',
  );
  final workspaceShell = StatefulShellRoute.indexedStack(
    builder: (context, state, navigationShell) =>
        _WorkspaceShellFrame(navigationShell: navigationShell),
    branches: [
      StatefulShellBranch(
        navigatorKey: workspaceHomeKey,
        observers: [workspaceHomeObserver],
        routes: [workspaceHome],
      ),
      StatefulShellBranch(
        navigatorKey: workspaceActivityKey,
        observers: [workspaceActivityObserver],
        routes: [workspaceActivity],
      ),
      StatefulShellBranch(
        navigatorKey: workspaceProfileKey,
        observers: [workspaceProfileObserver],
        routes: [workspaceProfile],
      ),
    ],
  );

  final overrides = <String, CCGoRouterRouteOverride>{
    for (final entry in <String, GoRoute>{
      'demo_navigation_lab.shell.feed': singleFeed,
      'demo_navigation_lab.shell.detail': singleDetail,
      'demo_navigation_lab.shell.settings': singleSettings,
      'demo_navigation_lab.workspace.home': workspaceHome,
      'demo_navigation_lab.workspace.detail': workspaceDetail,
      'demo_navigation_lab.workspace.activity': workspaceActivity,
      'demo_navigation_lab.workspace.profile': workspaceProfile,
    }.entries)
      entry.key: CCGoRouterRouteOverride(
        binding: CCGoRouterRouteBinding(
          routeId: entry.key,
          goRoute: entry.value,
        ),
        includeInRootRoutes: false,
      ),
  };

  return CCGoRouterBackend.managed(
    catalog: catalog,
    host: host,
    overrides: overrides,
    shells: [
      CCGoRouterShellBinding(
        shellId: demoSingleShellId,
        route: singleShell,
        initialOutlet: demoSingleShellOutlet,
        outlets: {demoSingleShellOutlet: singleOutletKey},
      ),
      CCGoRouterShellBinding(
        shellId: demoWorkspaceShellId,
        route: workspaceShell,
        initialOutlet: demoWorkspaceHomeOutlet,
        outlets: {
          demoWorkspaceHomeOutlet: workspaceHomeKey,
          demoWorkspaceActivityOutlet: workspaceActivityKey,
          demoWorkspaceProfileOutlet: workspaceProfileKey,
        },
      ),
    ],
    outletObservers: [
      singleObserver,
      workspaceHomeObserver,
      workspaceActivityObserver,
      workspaceProfileObserver,
    ],
    initialLocation: initialLocation,
  );
}

GoRoute _route(
  CCFlutterRouteCatalog catalog, {
  required String routeId,
  required String path,
  List<RouteBase> routes = const [],
}) {
  final destination = catalog.destinationFor(routeId);
  if (destination == null) {
    throw StateError('Missing generated destination "$routeId".');
  }
  return GoRoute(
    path: path,
    name: routeId,
    builder: (_, state) => destination.build(
      CCEncodedRouteArguments(
        path: state.pathParameters,
        query: state.uri.queryParametersAll,
        extra: state.extra,
      ),
    ),
    routes: routes,
  );
}

final class _SingleShellFrame extends StatelessWidget {
  const _SingleShellFrame({required this.selectedIndex, required this.child});

  final int selectedIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: child,
    bottomNavigationBar: NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) => unawaited(
        CCRouter.navigator.go(
          index == 0 ? demoShellFeedIntent() : demoShellSettingsIntent(),
        ),
      ),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dynamic_feed_outlined),
          label: 'Feed',
        ),
        NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
      ],
    ),
  );
}

final class _WorkspaceShellFrame extends StatelessWidget {
  const _WorkspaceShellFrame({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: navigationShell,
    bottomNavigationBar: NavigationBar(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: (index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      ),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
        NavigationDestination(
          icon: Icon(Icons.notifications_none),
          label: 'Activity',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
    ),
  );
}
