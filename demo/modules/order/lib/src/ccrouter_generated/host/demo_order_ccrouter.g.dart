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
      '45c45aa3f4c7794ec04521940d86fa5455f399ed64dc73f9ab7cbc36bacfc6d5',
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
            "733a9cbb3afe25c35855e48a5f37d70433427971629d0a6e53ff2613a3161316",
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
            "5ae284d3c0990ac5c7edb8608e3bd3238bdd52c7241bb275f182c150913f891b",
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
