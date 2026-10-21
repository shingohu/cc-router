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
  bool enablePredictiveBack = false,
}) {
  final single = _DemoShellOutlet(hostId, demoSingleShellOutlet);
  final home = _DemoShellOutlet(hostId, demoWorkspaceHomeOutlet);
  final activity = _DemoShellOutlet(hostId, demoWorkspaceActivityOutlet);
  final profile = _DemoShellOutlet(hostId, demoWorkspaceProfileOutlet);
  final shellOutlets = [single, home, activity, profile];
  final host = CCNavigationHost(
    id: hostId,
    navigatorKeys: {
      for (final outlet in shellOutlets) outlet.id: outlet.key,
      // Adaptive panels mount their own Navigator outside the GoRouter tree.
      for (final id in [demoAdaptiveListOutlet, demoAdaptiveDetailOutlet])
        id: GlobalKey<NavigatorState>(debugLabel: '$hostId.$id'),
    },
  );
  late final CCGoRouterBackend backend;
  final mounts = _DemoRouteMounts(
    catalog,
    predictiveBackHandler: enablePredictiveBack
        ? () => backend.adapter.predictiveBackBridge
        : null,
  );
  final singleDetail = mounts.route(
    routeId: 'demo_navigation_lab.shell.detail',
    path: ':item',
  );
  final singleFeed = mounts.route(
    routeId: 'demo_navigation_lab.shell.feed',
    path: '/shell/feed',
    routes: [singleDetail],
  );
  final singleSettings = mounts.route(
    routeId: 'demo_navigation_lab.shell.settings',
    path: '/shell/settings',
  );
  final singleShell = ShellRoute(
    navigatorKey: single.key,
    observers: [single.observer],
    builder: (context, state, child) => _SingleShellFrame(
      selectedIndex: state.uri.path.startsWith('/shell/settings') ? 1 : 0,
      child: child,
    ),
    routes: [singleFeed, singleSettings],
  );

  final workspaceDetail = mounts.route(
    routeId: 'demo_navigation_lab.workspace.detail',
    path: ':item',
  );
  final workspaceHome = mounts.route(
    routeId: 'demo_navigation_lab.workspace.home',
    path: '/workspace/home',
    routes: [workspaceDetail],
  );
  final workspaceActivity = mounts.route(
    routeId: 'demo_navigation_lab.workspace.activity',
    path: '/workspace/activity',
  );
  final workspaceProfile = mounts.route(
    routeId: 'demo_navigation_lab.workspace.profile',
    path: '/workspace/profile',
  );
  final workspaceShell = StatefulShellRoute.indexedStack(
    builder: (context, state, navigationShell) =>
        _WorkspaceShellFrame(navigationShell: navigationShell),
    branches: [
      StatefulShellBranch(
        navigatorKey: home.key,
        observers: [home.observer],
        routes: [workspaceHome],
      ),
      StatefulShellBranch(
        navigatorKey: activity.key,
        observers: [activity.observer],
        routes: [workspaceActivity],
      ),
      StatefulShellBranch(
        navigatorKey: profile.key,
        observers: [profile.observer],
        routes: [workspaceProfile],
      ),
    ],
  );

  return backend = CCGoRouterBackend.managed(
    catalog: catalog,
    host: host,
    overrides: mounts.overrides,
    shells: [
      CCGoRouterShellBinding(
        shellId: demoSingleShellId,
        route: singleShell,
        initialOutlet: demoSingleShellOutlet,
        outlets: {single.id: single.key},
      ),
      CCGoRouterShellBinding(
        shellId: demoWorkspaceShellId,
        route: workspaceShell,
        initialOutlet: demoWorkspaceHomeOutlet,
        outlets: {
          for (final outlet in [home, activity, profile]) outlet.id: outlet.key,
        },
      ),
    ],
    outletObservers: [for (final outlet in shellOutlets) outlet.observer],
    initialLocation: initialLocation,
    enablePredictiveBack: enablePredictiveBack,
  );
}

/// Creates the opt-in Runtime Managed Backend used by migration tests.
///
/// The generated Catalog and Shell contracts are identical to the GoRouter
/// demo. Keeping this factory beside the compatibility factory makes the two
/// backends directly comparable while allowing existing demo callers to stay
/// on GoRouter until their Host is ready to migrate.
CCManagedRouterBackend createDemoManagedRouterBackend({
  required CCFlutterRouteCatalog catalog,
  String hostId = 'default',
  String initialLocation = '/',
  bool initializeFromRouteInformation = true,
}) {
  final single = _DemoShellOutlet(hostId, demoSingleShellOutlet);
  final home = _DemoShellOutlet(hostId, demoWorkspaceHomeOutlet);
  final activity = _DemoShellOutlet(hostId, demoWorkspaceActivityOutlet);
  final profile = _DemoShellOutlet(hostId, demoWorkspaceProfileOutlet);
  final host = CCNavigationHost(
    id: hostId,
    navigatorKeys: {
      for (final outlet in [single, home, activity, profile])
        outlet.id: outlet.key,
      demoAdaptiveListOutlet: GlobalKey<NavigatorState>(
        debugLabel: '$hostId.$demoAdaptiveListOutlet',
      ),
      demoAdaptiveDetailOutlet: GlobalKey<NavigatorState>(
        debugLabel: '$hostId.$demoAdaptiveDetailOutlet',
      ),
    },
  );
  return CCManagedRouterBackend(
    routeCatalog: catalog,
    host: host,
    initialLocation: initialLocation,
    initializeFromRouteInformation: initializeFromRouteInformation,
    shellBindings: [
      CCManagedShellBinding(
        shellId: demoSingleShellId,
        builder: (context, shell) => Scaffold(
          body: shell.navigatorFor(demoSingleShellOutlet),
          bottomNavigationBar: NavigationBar(
            selectedIndex: 0,
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
        ),
      ),
      CCManagedShellBinding(
        shellId: demoWorkspaceShellId,
        builder: (context, shell) {
          final activeIndex = shell.outlets.indexOf(shell.activeOutlet);
          return Scaffold(
            body: IndexedStack(
              index: activeIndex < 0 ? 0 : activeIndex,
              children: [
                for (final outlet in shell.outlets) shell.navigatorFor(outlet),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: activeIndex < 0 ? 0 : activeIndex,
              onDestinationSelected: (index) {
                final outlet = shell.outlets[index];
                shell.activateOutlet(outlet);
                unawaited(
                  CCRouter.navigator.go(switch (index) {
                    0 => demoWorkspaceHomeIntent(),
                    1 => demoWorkspaceActivityIntent(),
                    _ => demoWorkspaceProfileIntent(),
                  }),
                );
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  label: 'Home',
                ),
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
        },
      ),
    ],
  );
}

/// Host-owned pairing reused by the Navigator, Shell binding and Adapter.
final class _DemoShellOutlet {
  _DemoShellOutlet(String hostId, this.id)
    : key = GlobalKey<NavigatorState>(debugLabel: '$hostId.$id'),
      observer = CCGoRouterNavigationObserver(hostId: hostId, outlet: id);

  final String id;
  final GlobalKey<NavigatorState> key;
  final CCGoRouterNavigationObserver observer;
}

/// Keeps manually placed Shell routes and their Adapter bindings in one place.
/// The Host still explicitly chooses the Shell tree and relative child paths.
final class _DemoRouteMounts {
  _DemoRouteMounts(this.catalog, {this.predictiveBackHandler});

  final CCFlutterRouteCatalog catalog;
  final CCFlutterPredictiveBackHandler? Function()? predictiveBackHandler;
  final overrides = <String, CCGoRouterRouteOverride>{};

  GoRoute route({
    required String routeId,
    required String path,
    List<RouteBase> routes = const [],
  }) {
    final destination = catalog.destinationFor(routeId);
    if (destination == null) {
      throw StateError('Missing generated destination "$routeId".');
    }
    if (overrides.containsKey(routeId)) {
      throw StateError('Destination "$routeId" was mounted twice.');
    }
    final presentation = destination.route.presentation;
    final route = GoRoute(
      path: path,
      name: routeId,
      pageBuilder: (_, state) {
        final payload = state.extra;
        final extra = CCRouterHostBinding.decodeRouteExtra(payload);
        final child = destination.build(
          CCRouteCodecValues(
            path: state.pathParameters,
            query: state.uri.queryParametersAll,
            extra: extra,
          ),
        );
        return CCFlutterRouteFactory.createPage<Object?>(
          child: CCRouterHostBinding.bindRouteEntry(
            payload: payload,
            child: child,
          ),
          presentation: presentation,
          key: state.pageKey,
          name: routeId,
          arguments: extra,
          predictiveBackHandler: predictiveBackHandler?.call(),
        );
      },
      routes: routes,
    );
    overrides[routeId] = CCGoRouterRouteOverride(
      binding: CCGoRouterRouteBinding(
        routeId: routeId,
        goRoute: route,
        presentationType: switch (presentation) {
          CCPagePresentation() => CCGoRouterPresentationType.page,
          CCModalBottomSheetPresentation() =>
            CCGoRouterPresentationType.bottomSheet,
          CCDialogPresentation() => CCGoRouterPresentationType.dialog,
        },
      ),
      includeInRootRoutes: false,
    );
    return route;
  }
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
