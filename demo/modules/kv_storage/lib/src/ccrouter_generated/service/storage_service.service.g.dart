// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _ServiceGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter_generated.dart';
import 'package:demo_kv_storage/src/storage_service.dart' as service_source;

/// Registers generated Service `demo.kv_storage` for its component.
void ccrouterRegisterDemoKeyValueStorageServiceImplService(
  CCRegistry registry,
) {
  registry.registerService<service_source.DemoKeyValueStorageService>(
    CCServiceProvider<service_source.DemoKeyValueStorageService>(
      factory: (_) => service_source.DemoKeyValueStorageServiceImpl(),
      contractToken:
          const CCServiceToken<service_source.DemoKeyValueStorageService>(
            "demo.kv_storage",
          ),
      scope: CCServiceScope.app,
      creationPolicy: CCServiceCreationPolicy.singleton,
      isDefault: false,
    ),
  );
}
