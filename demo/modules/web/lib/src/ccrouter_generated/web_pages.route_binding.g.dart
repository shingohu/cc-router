// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteBindingGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';
import 'package:demo_web/src/web_pages.dart' as route_page;
import 'package:demo_web_contracts/src/ccrouter_generated/web_route_contracts.route.contract.g.dart'
    as route_contract_0;

/// Package-internal bridge used by the generated component route index.
///
/// Registration retains the external Pure Dart contract as the single source
/// of route identity, parameters, and navigation policy.
void ccrouterRegisterDemoPublicWebPageRoute(CCRegistry registry) =>
    registry.registerRoute(route_contract_0.DemoPublicWebRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ccrouterDescribeDemoPublicWebPageRoute() =>
    route_contract_0.DemoPublicWebRoute.definition;

/// Package-internal page factory bound to the public route contract.
route_page.DemoPublicWebPage ccrouterBuildDemoPublicWebPageRoute(
  CCEncodedRouteArguments arguments,
) {
  final decoded = route_contract_0.DemoPublicWebRoute.definition.codec.decode(
    arguments,
  );
  return route_page.DemoPublicWebPage(target: decoded.target);
}

/// Package-internal bridge used by the generated component route index.
///
/// Registration retains the external Pure Dart contract as the single source
/// of route identity, parameters, and navigation policy.
void ccrouterRegisterDemoPrivateWebPageRoute(CCRegistry registry) =>
    registry.registerRoute(route_contract_0.DemoPrivateWebRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ccrouterDescribeDemoPrivateWebPageRoute() =>
    route_contract_0.DemoPrivateWebRoute.definition;

/// Package-internal page factory bound to the public route contract.
route_page.DemoPrivateWebPage ccrouterBuildDemoPrivateWebPageRoute(
  CCEncodedRouteArguments arguments,
) {
  final decoded = route_contract_0.DemoPrivateWebRoute.definition.codec.decode(
    arguments,
  );
  return route_page.DemoPrivateWebPage(decoded.request);
}
