// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _ServiceGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter_generated.dart';
import 'package:demo_network/src/network_service.dart' as service_source;

/// Registers generated Service `demo.network.client` for its component.
void ccrouterRegisterDemoNetworkServiceImplService(CCRegistry registry) {
  registry.registerService<service_source.DemoNetworkService>(
    CCServiceProvider<service_source.DemoNetworkService>(
      factory: (_) => service_source.DemoNetworkServiceImpl(),
      contractToken: const CCServiceToken<service_source.DemoNetworkService>(
        "demo.network.client",
      ),
      scope: CCServiceScope.app,
      creationPolicy: CCServiceCreationPolicy.singleton,
      isDefault: false,
    ),
  );
}
