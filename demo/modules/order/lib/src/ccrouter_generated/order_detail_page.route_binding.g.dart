// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteBindingGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';
import 'package:demo_order/src/order_detail_page.dart' as route_page;
import 'package:demo_order_contracts/src/ccrouter_generated/order_detail_route_contract.route.contract.g.dart'
    as route_contract_0;

/// Package-internal bridge used by the generated component route index.
///
/// Registration retains the external Pure Dart contract as the single source
/// of route identity, parameters, and navigation policy.
void ccrouterRegisterOrderDetailPageRoute(CCRegistry registry) =>
    registry.registerRoute(route_contract_0.OrderDetailRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ccrouterDescribeOrderDetailPageRoute() =>
    route_contract_0.OrderDetailRoute.definition;

/// Package-internal page factory bound to the public route contract.
route_page.OrderDetailPage ccrouterBuildOrderDetailPageRoute(
  CCEncodedRouteArguments arguments,
) {
  final decoded = route_contract_0.OrderDetailRoute.definition.codec.decode(
    arguments,
  );
  return route_page.OrderDetailPage(orderId: decoded.orderId, tab: decoded.tab);
}
