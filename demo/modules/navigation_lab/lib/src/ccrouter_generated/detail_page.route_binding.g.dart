// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteBindingGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';
import 'package:demo_navigation_lab/src/detail_page.dart' as route_page;
import 'package:demo_navigation_lab/src/ccrouter_generated/detail_page.route.g.dart'
    as route_contract;

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.DemoDetailPage ccrouterBuildDemoDetailPageRoute(
  CCEncodedRouteArguments arguments,
) {
  final decoded = route_contract
      .ccrouterDescribeDemoDetailPageRoute()
      .codec
      .decode(arguments);
  return route_page.DemoDetailPage(
    id: decoded.id,
    title: decoded.title,
    tags: decoded.tags,
  );
}
