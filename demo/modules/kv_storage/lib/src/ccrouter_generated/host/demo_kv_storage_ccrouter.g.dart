// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

/// Host-only generated Package Bundle for `demo_kv_storage`.
library;

import 'package:ccrouter/ccrouter_host.dart'
    show
        CCContractBundleDescriptor,
        CCContractDescriptor,
        CCContractKind,
        CCFlutterRouteCatalog,
        CCGeneratedPackageBundle;
import 'package:demo_kv_storage/src/ccrouter_generated/component/demo_kv_storage_component.component.g.dart'
    as component_0;

/// Generated runtime contribution and direct dependency graph for `demo_kv_storage`.
final ccrouterGeneratedPackageBundle = CCGeneratedPackageBundle(
  packageName: 'demo_kv_storage',
  packageVersion: '0.1.0',
  contentFingerprint:
      '993054d8e1d8c4273474f3c688afbaa47145db67a15be334f9eb27be450ee958',
  contractBundle: CCContractBundleDescriptor(
    packageName: 'demo_kv_storage',
    packageVersion: '0.1.0',
    contracts: [
      CCContractDescriptor(
        kind: CCContractKind.service,
        id: "demo.kv_storage",
        ownerComponentId: "demo_kv_storage_component",
        version: "0.1.0",
        shapeFingerprint:
            "74f1d13513448f76b3db9f996cbb349687376d851b6cb1420ee2a0825fcca1f2",
      ),
    ],
    requirements: [],
  ),
  componentManifests: [component_0.demoKvStorageComponentManifest],
  routeCatalog: CCFlutterRouteCatalog.merge([
    component_0.demoKvStorageComponentRouteCatalog,
  ]),
  dependencies: [],
);
