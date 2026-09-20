// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteBindingGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_test/src/query_codec_fixture.dart' as route_page;
import 'package:ccrouter_test/src/ccrouter_generated/query_codec_fixture.route.g.dart'
    as route_contract;

/// Package-internal page factory bridge used by generated Flutter catalogs.
route_page.QueryCodecFixturePage ccrouterBuildQueryCodecFixturePageRoute(
  CCEncodedRouteArguments arguments,
) {
  final decoded = route_contract
      .ccrouterDescribeQueryCodecFixturePageRoute()
      .codec
      .decode(arguments);
  return route_page.QueryCodecFixturePage(
    tags: decoded.tags,
    ids: decoded.ids,
    states: decoded.states,
    filter: decoded.filter,
  );
}
