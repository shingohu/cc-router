// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteBindingGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';
import 'package:demo_navigation_lab/src/shell_pages.dart' as route_page;
import 'package:demo_navigation_lab/src/ccrouter_generated/route/shell_pages.route.g.dart'
    as route_contract;

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.DemoShellFeedPage ccrouterBuildDemoShellFeedPageRoute(
  CCRouteCodecValues _,
) => route_page.DemoShellFeedPage();

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.DemoShellDetailPage ccrouterBuildDemoShellDetailPageRoute(
  CCRouteCodecValues arguments,
) {
  final decoded = route_contract
      .ccrouterDescribeDemoShellDetailPageRoute()
      .codec
      .decode(arguments);
  return route_page.DemoShellDetailPage(item: decoded.item);
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.DemoShellSettingsPage ccrouterBuildDemoShellSettingsPageRoute(
  CCRouteCodecValues _,
) => route_page.DemoShellSettingsPage();

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.DemoWorkspaceHomePage ccrouterBuildDemoWorkspaceHomePageRoute(
  CCRouteCodecValues _,
) => route_page.DemoWorkspaceHomePage();

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.DemoWorkspaceDetailPage ccrouterBuildDemoWorkspaceDetailPageRoute(
  CCRouteCodecValues arguments,
) {
  final decoded = route_contract
      .ccrouterDescribeDemoWorkspaceDetailPageRoute()
      .codec
      .decode(arguments);
  return route_page.DemoWorkspaceDetailPage(item: decoded.item);
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.DemoWorkspaceActivityPage
ccrouterBuildDemoWorkspaceActivityPageRoute(CCRouteCodecValues _) =>
    route_page.DemoWorkspaceActivityPage();

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.DemoWorkspaceProfilePage ccrouterBuildDemoWorkspaceProfilePageRoute(
  CCRouteCodecValues _,
) => route_page.DemoWorkspaceProfilePage();

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.DemoExtraPage ccrouterBuildDemoExtraPageRoute(
  CCRouteCodecValues arguments,
) {
  final decoded = route_contract
      .ccrouterDescribeDemoExtraPageRoute()
      .codec
      .decode(arguments);
  return route_page.DemoExtraPage(decoded.payload);
}
