// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteBindingGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_test/src/generated_route_fixture.dart' as route_page;
import 'package:ccrouter_test/src/ccrouter_generated/route/generated_route_fixture.route.g.dart'
    as route_contract;

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.GeneratedDetailPage ccrouterBuildGeneratedDetailPageRoute(
  CCEncodedRouteArguments arguments,
) {
  final decoded = route_contract
      .ccrouterDescribeGeneratedDetailPageRoute()
      .codec
      .decode(arguments);
  return route_page.GeneratedDetailPage(
    id: decoded.id,
    search: decoded.search,
    tab: decoded.tab,
    enabled: decoded.enabled,
    ratio: decoded.ratio,
    snapshot: decoded.snapshot,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.GeneratedInternalPage ccrouterBuildGeneratedInternalPageRoute(
  CCEncodedRouteArguments _,
) => route_page.GeneratedInternalPage();

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.GeneratedPositionalPage ccrouterBuildGeneratedPositionalPageRoute(
  CCEncodedRouteArguments arguments,
) {
  final decoded = route_contract
      .ccrouterDescribeGeneratedPositionalPageRoute()
      .codec
      .decode(arguments);
  return route_page.GeneratedPositionalPage(decoded.value, decoded.input);
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.GeneratedExtraPage ccrouterBuildGeneratedExtraPageRoute(
  CCEncodedRouteArguments arguments,
) {
  final decoded = route_contract
      .ccrouterDescribeGeneratedExtraPageRoute()
      .codec
      .decode(arguments);
  return route_page.GeneratedExtraPage(snapshot: decoded.snapshot);
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.GeneratedPrefixedPage ccrouterBuildGeneratedPrefixedPageRoute(
  CCEncodedRouteArguments arguments,
) {
  final decoded = route_contract
      .ccrouterDescribeGeneratedPrefixedPageRoute()
      .codec
      .decode(arguments);
  return route_page.GeneratedPrefixedPage(
    mode: decoded.mode,
    payload: decoded.payload,
  );
}
