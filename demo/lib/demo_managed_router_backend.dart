import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:demo_navigation_lab/demo_navigation_lab_host.dart';
import 'package:flutter/material.dart';

/// Outlet rendering the adaptive list pane in the Demo Host.
const demoAdaptiveListOutlet = 'adaptive.list';

/// Outlet rendering the adaptive detail pane in the Demo Host.
const demoAdaptiveDetailOutlet = 'adaptive.detail';

/// Creates the native Managed Backend used by the default Demo Host.
///
/// The generated Catalog remains the source of Route contracts while this
/// factory contributes the application-owned Shell and adaptive Outlet layout.
CCManagedRouterBackend createDemoManagedRouterBackend({
  required CCFlutterRouteCatalog catalog,
  String hostId = 'default',
  String initialLocation = '/',
  bool enablePredictiveBack = false,
  bool initializeFromRouteInformation = true,
}) {
  final single = _DemoManagedOutlet(hostId, demoSingleShellOutlet);
  final home = _DemoManagedOutlet(hostId, demoWorkspaceHomeOutlet);
  final activity = _DemoManagedOutlet(hostId, demoWorkspaceActivityOutlet);
  final profile = _DemoManagedOutlet(hostId, demoWorkspaceProfileOutlet);
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
    enablePredictiveBack: enablePredictiveBack,
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
                final wasActive = shell.activeOutlet == outlet;
                final needsInitialRoute = !shell.hasEntries(outlet);
                shell.activateOutlet(outlet);
                if (wasActive || needsInitialRoute) {
                  unawaited(
                    CCRouter.navigator.go(switch (index) {
                      0 => demoWorkspaceHomeIntent(),
                      1 => demoWorkspaceActivityIntent(),
                      _ => demoWorkspaceProfileIntent(),
                    }),
                  );
                }
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

/// Host-owned Navigator identity for one Managed Outlet.
final class _DemoManagedOutlet {
  /// Creates an Outlet key scoped to one Host.
  _DemoManagedOutlet(String hostId, this.id)
    : key = GlobalKey<NavigatorState>(debugLabel: '$hostId.$id');

  /// Stable Outlet identity declared by the generated Shell contract.
  final String id;

  /// Navigator key owned by the Demo Host.
  final GlobalKey<NavigatorState> key;
}
