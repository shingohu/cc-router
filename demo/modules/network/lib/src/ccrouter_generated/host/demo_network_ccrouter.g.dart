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
      'd14a2959994efcafdf0848e856e6502607db5eaffca5cc19f99ed370114cbc6a',
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
            "cc271813e81d60863b08f881874c711d6c367e9b131f4635ea0ec274e7bdb1d0",
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
