// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

/// Host-only generated Package Bundle for `demo_order`.
library;

import 'package:ccrouter/ccrouter_host.dart'
    show
        CCContractBundleDescriptor,
        CCContractDescriptor,
        CCContractKind,
        CCFlutterRouteCatalog,
        CCGeneratedPackageBundle;
import 'package:demo_order/src/ccrouter_generated/component/demo_order_component.component.g.dart'
    as component_0;

/// Generated runtime contribution and direct dependency graph for `demo_order`.
final ccrouterGeneratedPackageBundle = CCGeneratedPackageBundle(
  packageName: 'demo_order',
  packageVersion: '0.1.0',
  contentFingerprint:
      'eb7aede68c621c458080b4133992f778a058b5ad52da99d1433c6bd01612b59c',
  contractBundle: CCContractBundleDescriptor(
    packageName: 'demo_order',
    packageVersion: '0.1.0',
    contracts: [
      CCContractDescriptor(
        kind: CCContractKind.command,
        id: "demo_order.reserve",
        ownerComponentId: "demo_order_component",
        version: "0.1.0",
        shapeFingerprint:
            "51da7bd343fa650642a09a23a9efe8e2da9c3537983d1cd33ea0d50dfd885af6",
      ),
      CCContractDescriptor(
        kind: CCContractKind.initTask,
        id: "demo_order.startup.foundation",
        ownerComponentId: "demo_order_component",
        version: "0.1.0",
        shapeFingerprint:
            "f9fbdb847ffe8a503fb446cfe6925bf84023a152226fc0d25cc846f9cf778146",
      ),
      CCContractDescriptor(
        kind: CCContractKind.service,
        id: "demo_order.summary",
        ownerComponentId: "demo_order_component",
        version: "0.1.0",
        shapeFingerprint:
            "c7b41467fd53598a4cba11c746a0886a4132be3d91372a4dac642ec926bb8e46",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "order.detail",
        ownerComponentId: "demo_order_component",
        version: "0.1.0",
        shapeFingerprint:
            "6ee7d5adc723f67d460fe0dc28b24514793e3bb1f89e8a2836952223f8dfeb73",
      ),
    ],
    requirements: [],
  ),
  componentManifests: [component_0.demoOrderComponentManifest],
  routeCatalog: CCFlutterRouteCatalog.merge([
    component_0.demoOrderComponentRouteCatalog,
  ]),
  dependencies: [],
);
