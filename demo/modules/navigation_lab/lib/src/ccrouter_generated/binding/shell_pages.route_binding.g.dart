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
  CCEncodedRouteArguments _,
) => route_page.DemoShellFeedPage();

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.DemoShellDetailPage ccrouterBuildDemoShellDetailPageRoute(
  CCEncodedRouteArguments arguments,
) {
  final decoded = route_contract
      .ccrouterDescribeDemoShellDetailPageRoute()
      .codec
      .decode(arguments);
  return route_page.DemoShellDetailPage(item: decoded.item);
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.DemoShellSettingsPage ccrouterBuildDemoShellSettingsPageRoute(
  CCEncodedRouteArguments _,
) => route_page.DemoShellSettingsPage();

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.DemoWorkspaceHomePage ccrouterBuildDemoWorkspaceHomePageRoute(
  CCEncodedRouteArguments _,
) => route_page.DemoWorkspaceHomePage();

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.DemoWorkspaceDetailPage ccrouterBuildDemoWorkspaceDetailPageRoute(
  CCEncodedRouteArguments arguments,
) {
  final decoded = route_contract
      .ccrouterDescribeDemoWorkspaceDetailPageRoute()
      .codec
      .decode(arguments);
  return route_page.DemoWorkspaceDetailPage(item: decoded.item);
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.DemoWorkspaceActivityPage
ccrouterBuildDemoWorkspaceActivityPageRoute(CCEncodedRouteArguments _) =>
    route_page.DemoWorkspaceActivityPage();

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.DemoWorkspaceProfilePage ccrouterBuildDemoWorkspaceProfilePageRoute(
  CCEncodedRouteArguments _,
) => route_page.DemoWorkspaceProfilePage();

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.DemoExtraPage ccrouterBuildDemoExtraPageRoute(
  CCEncodedRouteArguments arguments,
) {
  final decoded = route_contract
      .ccrouterDescribeDemoExtraPageRoute()
      .codec
      .decode(arguments);
  return route_page.DemoExtraPage(decoded.payload);
}
