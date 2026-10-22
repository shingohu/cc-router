// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_element

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:demo_order_example/src/order_example_component.dart'
    as component_source;
import '../binding/order_example_component.route_binding.g.dart'
    as route_src_ccrouter_generated_binding_order_example_component_route_binding_g_dart;
import '../route/order_example_component.route.g.dart'
    as route_src_ccrouter_generated_route_order_example_component_route_g_dart;

/// Generated capability Registrar for component `demo_order_example_component`.
final class _DemoOrderExampleComponentGeneratedRegistrar
    implements CCComponentRegistrar {
  /// Creates the stateless generated Registrar.
  const _DemoOrderExampleComponentGeneratedRegistrar();

  /// Registers every generated capability in stable order.
  @override
  void register(CCRegistry registry) {
    route_src_ccrouter_generated_route_order_example_component_route_g_dart
        .ccrouterRegisterOrderExampleHomePageRoute(registry);
  }
}

/// Generated Runtime Manifest for component `demo_order_example_component`.
const demoOrderExampleComponentManifest = CCComponentManifest.fromComponent(
  component: component_source.orderExampleComponent,
  registrar: _DemoOrderExampleComponentGeneratedRegistrar(),
);

/// Backend-neutral Flutter destinations owned by `demo_order_example_component`.
final demoOrderExampleComponentRouteCatalog = CCFlutterRouteCatalog([
  CCFlutterRouteDestination.fromDefinition(
    definition:
        route_src_ccrouter_generated_route_order_example_component_route_g_dart
            .ccrouterDescribeOrderExampleHomePageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_order_example_component_route_binding_g_dart
            .ccrouterBuildOrderExampleHomePageRoute(arguments),
  ),
]);
