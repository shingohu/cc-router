// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

part of '../order_detail_page.dart';

// **************************************************************************
// _RouteGenerator
// **************************************************************************

/// Package-internal bridge used by the generated component route index.
///
/// Registration retains the external Pure Dart contract as the single source
/// of route identity, parameters, and navigation policy.
void ccrouterRegisterOrderDetailPageRoute(CCRegistry registry) =>
    registry.registerRoute(OrderDetailRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ccrouterDescribeOrderDetailPageRoute() =>
    OrderDetailRoute.definition;

/// Package-internal page factory bound to the public route contract.
OrderDetailPage ccrouterBuildOrderDetailPageRoute(
  CCEncodedRouteArguments arguments,
) {
  final decoded = OrderDetailRoute.definition.codec.decode(arguments);
  return OrderDetailPage(orderId: decoded.orderId, tab: decoded.tab);
}
