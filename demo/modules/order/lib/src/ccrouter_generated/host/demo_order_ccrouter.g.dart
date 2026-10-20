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
      '51e730e234a76711eeba8ed43121ba2637d7731e06b3c6dfd2f0f8f05c586758',
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
