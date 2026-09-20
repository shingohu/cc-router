// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteBindingGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';
import 'package:demo_navigation_lab/src/failure_page.dart' as route_page;
import 'package:demo_navigation_lab/src/ccrouter_generated/failure_page.route.g.dart'
    as route_contract;

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.DemoFailurePage ccrouterBuildDemoFailurePageRoute(
  CCEncodedRouteArguments arguments,
) {
  final decoded = route_contract
      .ccrouterDescribeDemoFailurePageRoute()
      .codec
      .decode(arguments);
  return route_page.DemoFailurePage(
    stage: decoded.stage,
    errorType: decoded.errorType,
  );
}
