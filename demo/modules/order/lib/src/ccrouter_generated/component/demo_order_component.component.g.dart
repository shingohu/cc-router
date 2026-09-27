// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_element

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:demo_order/src/demo_order_component.dart' as component_source;
import '../binding/order_detail_page.route_binding.g.dart'
    as route_src_ccrouter_generated_binding_order_detail_page_route_binding_g_dart;
import '../service/order_summary_service.service.g.dart'
    as route_src_ccrouter_generated_service_order_summary_service_service_g_dart;

/// Generated capability Registrar for component `demo_order_component`.
final class _DemoOrderComponentGeneratedRegistrar
    implements CCComponentRegistrar {
  /// Creates the stateless generated Registrar.
  const _DemoOrderComponentGeneratedRegistrar();

  /// Registers every generated capability in stable order.
  @override
  void register(CCRegistry registry) {
    route_src_ccrouter_generated_binding_order_detail_page_route_binding_g_dart
        .ccrouterRegisterOrderDetailPageRoute(registry);
    route_src_ccrouter_generated_service_order_summary_service_service_g_dart
        .ccrouterRegisterDemoOrderSummaryServiceService(registry);
  }
}

/// Generated Runtime Manifest for component `demo_order_component`.
const demoOrderComponentManifest = CCComponentManifest.fromComponent(
  component: component_source.demoOrderComponent,
  registrar: _DemoOrderComponentGeneratedRegistrar(),
);

/// Backend-neutral Flutter destinations owned by `demo_order_component`.
final demoOrderComponentRouteCatalog = CCFlutterRouteCatalog([
  CCFlutterRouteDestination.fromDefinition(
    definition:
        route_src_ccrouter_generated_binding_order_detail_page_route_binding_g_dart
            .ccrouterDescribeOrderDetailPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_order_detail_page_route_binding_g_dart
            .ccrouterBuildOrderDetailPageRoute(arguments),
  ),
]);
