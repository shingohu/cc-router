// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

/// Host-only generated Package Bundle for `demo_order_example`.
library;

import 'package:ccrouter/ccrouter_host.dart'
    show
        CCContractBundleDescriptor,
        CCContractDescriptor,
        CCContractKind,
        CCFlutterRouteCatalog,
        CCGeneratedPackageBundle;
import 'package:demo_order_example/src/ccrouter_generated/component/demo_order_example_component.component.g.dart'
    as component_0;
import 'package:demo_order/src/ccrouter_generated/host/demo_order_ccrouter.g.dart'
    as dependency_demo_order;

/// Generated runtime contribution and direct dependency graph for `demo_order_example`.
final ccrouterGeneratedPackageBundle = CCGeneratedPackageBundle(
  packageName: 'demo_order_example',
  packageVersion: '0.1.0+1',
  contentFingerprint:
      '9b9d74e390eac7bbf9c2f0abd971525d634107094eec5316514c41bb9527e554',
  contractBundle: CCContractBundleDescriptor(
    packageName: 'demo_order_example',
    packageVersion: '0.1.0+1',
    contracts: [
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_order_example.home",
        ownerComponentId: "demo_order_example_component",
        version: "0.1.0",
        shapeFingerprint:
            "596981c66d9bf22beb1797c772e6236576b84a8a42b1cae628409440fbe98aa9",
      ),
    ],
    requirements: [],
  ),
  componentManifests: [component_0.demoOrderExampleComponentManifest],
  routeCatalog: CCFlutterRouteCatalog.merge([
    component_0.demoOrderExampleComponentRouteCatalog,
  ]),
  dependencies: [dependency_demo_order.ccrouterGeneratedPackageBundle],
);
