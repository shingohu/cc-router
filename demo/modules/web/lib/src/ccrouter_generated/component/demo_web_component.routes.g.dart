// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_element

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import '../binding/web_pages.route_binding.g.dart'
    as route_src_ccrouter_generated_binding_web_pages_route_binding_g_dart;

/// Generated registration index for component `demo_web_component`.
final class DemoWebComponentGeneratedRoutes {
  /// Creates the immutable component route index.
  const DemoWebComponentGeneratedRoutes();

  /// Registers every route owned by `demo_web_component` in stable order.
  void register(CCRegistry registry) {
    route_src_ccrouter_generated_binding_web_pages_route_binding_g_dart
        .ccrouterRegisterDemoPrivateWebPageRoute(registry);
    route_src_ccrouter_generated_binding_web_pages_route_binding_g_dart
        .ccrouterRegisterDemoPublicWebPageRoute(registry);
  }
}

/// Shared generated index used by the component Registrar.
const demoWebComponentGeneratedRoutes = DemoWebComponentGeneratedRoutes();

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
