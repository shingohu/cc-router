// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_element

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:demo_web/src/web_pages.dart' as route_src_web_pages_dart;

/// Generated registration index for component `demo_web_component`.
final class DemoWebComponentGeneratedRoutes {
  /// Creates the immutable component route index.
  const DemoWebComponentGeneratedRoutes();

  /// Registers every route owned by `demo_web_component` in stable order.
  void register(CCRegistry registry) {
    route_src_web_pages_dart.ccrouterRegisterDemoPrivateWebPageRoute(registry);
    route_src_web_pages_dart.ccrouterRegisterDemoPublicWebPageRoute(registry);
  }
}

/// Shared generated index used by the component Registrar.
const demoWebComponentGeneratedRoutes = DemoWebComponentGeneratedRoutes();

/// Backend-neutral Flutter destinations owned by `demo_web_component`.
final demoWebComponentRouteCatalog = CCFlutterRouteCatalog([
  CCFlutterRouteDestination(
    route: route_src_web_pages_dart.ccrouterDescribeDemoPrivateWebPageRoute(),
    builder: (arguments) => route_src_web_pages_dart
        .ccrouterBuildDemoPrivateWebPageRoute(arguments),
  ),
  CCFlutterRouteDestination(
    route: route_src_web_pages_dart.ccrouterDescribeDemoPublicWebPageRoute(),
    builder: (arguments) =>
        route_src_web_pages_dart.ccrouterBuildDemoPublicWebPageRoute(arguments),
  ),
]);
