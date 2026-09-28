// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_element

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:demo_network/src/demo_network_component.dart'
    as component_source;
import '../service/network_service.service.g.dart'
    as route_src_ccrouter_generated_service_network_service_service_g_dart;

/// Generated capability Registrar for component `demo_network_component`.
final class _DemoNetworkComponentGeneratedRegistrar
    implements CCComponentRegistrar {
  /// Creates the stateless generated Registrar.
  const _DemoNetworkComponentGeneratedRegistrar();

  /// Registers every generated capability in stable order.
  @override
  void register(CCRegistry registry) {
    route_src_ccrouter_generated_service_network_service_service_g_dart
        .ccrouterRegisterDemoNetworkServiceImplService(registry);
  }
}

/// Generated Runtime Manifest for component `demo_network_component`.
const demoNetworkComponentManifest = CCComponentManifest.fromComponent(
  component: component_source.demoNetworkComponent,
  registrar: _DemoNetworkComponentGeneratedRegistrar(),
);

/// Backend-neutral Flutter destinations owned by `demo_network_component`.
final demoNetworkComponentRouteCatalog = CCFlutterRouteCatalog([]);
