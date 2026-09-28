// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_element

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:demo_kv_storage/src/demo_kv_storage_component.dart'
    as component_source;
import '../service/storage_service.service.g.dart'
    as route_src_ccrouter_generated_service_storage_service_service_g_dart;

/// Generated capability Registrar for component `demo_kv_storage_component`.
final class _DemoKvStorageComponentGeneratedRegistrar
    implements CCComponentRegistrar {
  /// Creates the stateless generated Registrar.
  const _DemoKvStorageComponentGeneratedRegistrar();

  /// Registers every generated capability in stable order.
  @override
  void register(CCRegistry registry) {
    route_src_ccrouter_generated_service_storage_service_service_g_dart
        .ccrouterRegisterDemoKeyValueStorageServiceImplService(registry);
  }
}

/// Generated Runtime Manifest for component `demo_kv_storage_component`.
const demoKvStorageComponentManifest = CCComponentManifest.fromComponent(
  component: component_source.demoKvStorageComponent,
  registrar: _DemoKvStorageComponentGeneratedRegistrar(),
);

/// Backend-neutral Flutter destinations owned by `demo_kv_storage_component`.
final demoKvStorageComponentRouteCatalog = CCFlutterRouteCatalog([]);
