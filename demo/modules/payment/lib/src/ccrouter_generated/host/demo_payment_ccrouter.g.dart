// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

/// Host-only generated Package Bundle for `demo_payment`.
library;

import 'package:ccrouter/ccrouter_host.dart'
    show
        CCContractBundleDescriptor,
        CCContractKind,
        CCContractRequirement,
        CCFlutterRouteCatalog,
        CCGeneratedPackageBundle;
import 'package:demo_payment/src/ccrouter_generated/component/demo_payment_component.component.g.dart'
    as component_0;

/// Generated runtime contribution and direct dependency graph for `demo_payment`.
final ccrouterGeneratedPackageBundle = CCGeneratedPackageBundle(
  packageName: 'demo_payment',
  packageVersion: '0.1.0',
  contentFingerprint:
      '53ece294a050343528df2500e28df38cafc2f7246e0dc578215a2b2accc4322a',
  contractBundle: CCContractBundleDescriptor(
    packageName: 'demo_payment',
    packageVersion: '0.1.0',
    contracts: [],
    requirements: [
      CCContractRequirement(
        kind: CCContractKind.service,
        contractId: "demo_order.summary",
        consumerPackage: "demo_payment",
        ownerComponentId: "demo_order_component",
        requiredVersionRange: "0.1.0",
        requiredShapeFingerprint:
            "5ae284d3c0990ac5c7edb8608e3bd3238bdd52c7241bb275f182c150913f891b",
      ),
    ],
  ),
  componentManifests: [component_0.demoPaymentComponentManifest],
  routeCatalog: CCFlutterRouteCatalog.merge([
    component_0.demoPaymentComponentRouteCatalog,
  ]),
  dependencies: [],
);
