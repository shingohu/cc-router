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
      '2dfb22bc7e8cbd4ad8685ac3f56a365bddc135eb0344fcd67da0e4679c2f7d67',
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
            "c7b41467fd53598a4cba11c746a0886a4132be3d91372a4dac642ec926bb8e46",
      ),
    ],
  ),
  componentManifests: [component_0.demoPaymentComponentManifest],
  routeCatalog: CCFlutterRouteCatalog.merge([
    component_0.demoPaymentComponentRouteCatalog,
  ]),
  dependencies: [],
);
