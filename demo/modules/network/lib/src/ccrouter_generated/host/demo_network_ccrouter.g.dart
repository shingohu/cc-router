// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

/// Host-only generated Package Bundle for `demo_network`.
library;

import 'package:ccrouter/ccrouter_host.dart'
    show
        CCContractBundleDescriptor,
        CCContractDescriptor,
        CCContractKind,
        CCFlutterRouteCatalog,
        CCGeneratedPackageBundle;
import 'package:demo_network/src/ccrouter_generated/component/demo_network_component.component.g.dart'
    as component_0;

/// Generated runtime contribution and direct dependency graph for `demo_network`.
final ccrouterGeneratedPackageBundle = CCGeneratedPackageBundle(
  packageName: 'demo_network',
  packageVersion: '0.1.0',
  contentFingerprint:
      'f4cfd63d2fb0cac52b7d3db321e5fb1cba73e83fc5cfbdab3bdd00966ab51966',
  contractBundle: CCContractBundleDescriptor(
    packageName: 'demo_network',
    packageVersion: '0.1.0',
    contracts: [
      CCContractDescriptor(
        kind: CCContractKind.service,
        id: "demo.network.client",
        ownerComponentId: "demo_network_component",
        version: "0.1.0",
        shapeFingerprint:
            "c0a7cb128881259780a44aedc62de6cf5efdd5925ab7dad09997add3f0aeeb8b",
      ),
    ],
    requirements: [],
  ),
  componentManifests: [component_0.demoNetworkComponentManifest],
  routeCatalog: CCFlutterRouteCatalog.merge([
    component_0.demoNetworkComponentRouteCatalog,
  ]),
  dependencies: [],
);
