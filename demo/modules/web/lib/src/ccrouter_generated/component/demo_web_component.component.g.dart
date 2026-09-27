// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_element

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:demo_web/src/demo_web_component.dart' as component_source;
import '../binding/web_pages.route_binding.g.dart'
    as route_src_ccrouter_generated_binding_web_pages_route_binding_g_dart;

/// Generated capability Registrar for component `demo_web_component`.
final class _DemoWebComponentGeneratedRegistrar
    implements CCComponentRegistrar {
  /// Creates the stateless generated Registrar.
  const _DemoWebComponentGeneratedRegistrar();

  /// Registers every generated capability in stable order.
  @override
  void register(CCRegistry registry) {
    route_src_ccrouter_generated_binding_web_pages_route_binding_g_dart
        .ccrouterRegisterDemoPrivateWebPageRoute(registry);
    route_src_ccrouter_generated_binding_web_pages_route_binding_g_dart
        .ccrouterRegisterDemoPublicWebPageRoute(registry);
  }
}

/// Generated Runtime Manifest for component `demo_web_component`.
const demoWebComponentManifest = CCComponentManifest.fromComponent(
  component: component_source.demoWebComponent,
  registrar: _DemoWebComponentGeneratedRegistrar(),
);

/// Backend-neutral Flutter destinations owned by `demo_web_component`.
final demoWebComponentRouteCatalog = CCFlutterRouteCatalog([
  CCFlutterRouteDestination.fromDefinition(
    definition:
        route_src_ccrouter_generated_binding_web_pages_route_binding_g_dart
            .ccrouterDescribeDemoPrivateWebPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_web_pages_route_binding_g_dart
            .ccrouterBuildDemoPrivateWebPageRoute(arguments),
  ),
  CCFlutterRouteDestination.fromDefinition(
    definition:
        route_src_ccrouter_generated_binding_web_pages_route_binding_g_dart
            .ccrouterDescribeDemoPublicWebPageRoute(),
    builder: (arguments) =>
        route_src_ccrouter_generated_binding_web_pages_route_binding_g_dart
            .ccrouterBuildDemoPublicWebPageRoute(arguments),
  ),
]);
