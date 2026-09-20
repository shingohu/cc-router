// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_element

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'order_detail_page.route_binding.g.dart'
    as route_src_ccrouter_generated_order_detail_page_route_binding_g_dart;

/// Generated registration index for component `demo_order_component`.
final class DemoOrderComponentGeneratedRoutes {
  /// Creates the immutable component route index.
  const DemoOrderComponentGeneratedRoutes();

  /// Registers every route owned by `demo_order_component` in stable order.
  void register(CCRegistry registry) {
    route_src_ccrouter_generated_order_detail_page_route_binding_g_dart
        .ccrouterRegisterOrderDetailPageRoute(registry);
  }
}

/// Shared generated index used by the component Registrar.
const demoOrderComponentGeneratedRoutes = DemoOrderComponentGeneratedRoutes();

/// Backend-neutral Flutter destinations owned by `demo_order_component`.
final demoOrderComponentRouteCatalog = CCFlutterRouteCatalog([
  CCFlutterRouteDestination.fromDefinition(
    definition:
        route_src_ccrouter_generated_order_detail_page_route_binding_g_dart
            .ccrouterDescribeOrderDetailPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_order_detail_page_route_binding_g_dart
            .ccrouterBuildOrderDetailPageRoute(arguments),
  ),
]);
