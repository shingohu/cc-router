// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

/// Host-only generated Package Bundle for `demo_web`.
library;

import 'package:ccrouter/ccrouter_host.dart'
    show
        CCContractBundleDescriptor,
        CCContractDescriptor,
        CCContractKind,
        CCFlutterRouteCatalog,
        CCGeneratedPackageBundle;
import 'package:demo_web/src/ccrouter_generated/component/demo_web_component.component.g.dart'
    as component_0;

/// Generated runtime contribution and direct dependency graph for `demo_web`.
final ccrouterGeneratedPackageBundle = CCGeneratedPackageBundle(
  packageName: 'demo_web',
  packageVersion: '0.1.0',
  contentFingerprint:
      'f21bfa77c9c068ef178a186b0af838db8ba18cbaba21b422fd6c124be6891c41',
  contractBundle: CCContractBundleDescriptor(
    packageName: 'demo_web',
    packageVersion: '0.1.0',
    contracts: [
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_web.private",
        ownerComponentId: "demo_web_component",
        version: "0.1.0",
        shapeFingerprint:
            "7660918c60234f57c95afbd5fc710dc5249786b8a9613d51bb455a607425324a",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_web.public",
        ownerComponentId: "demo_web_component",
        version: "0.1.0",
        shapeFingerprint:
            "229de44459e082130a811e1d753bdae08888a4b4e0b612af2fb64713c997c88b",
      ),
    ],
    requirements: [],
  ),
  componentManifests: [component_0.demoWebComponentManifest],
  routeCatalog: CCFlutterRouteCatalog.merge([
    component_0.demoWebComponentRouteCatalog,
  ]),
  dependencies: [],
);
