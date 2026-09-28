// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

/// Host-only generated Package Bundle for `demo_navigation_lab`.
library;

import 'package:ccrouter/ccrouter_host.dart'
    show CCFlutterRouteCatalog, CCGeneratedPackageBundle;
import 'package:demo_navigation_lab/src/ccrouter_generated/component/demo_navigation_lab_component.component.g.dart'
    as component_0;
import 'package:demo_network/src/ccrouter_generated/host/demo_network_ccrouter.g.dart'
    as dependency_demo_network;

/// Generated runtime contribution and direct dependency graph for `demo_navigation_lab`.
final ccrouterGeneratedPackageBundle = CCGeneratedPackageBundle(
  packageName: 'demo_navigation_lab',
  packageVersion: '0.1.0',
  contentFingerprint:
      '61ac16812eea9debe3fa5e106fd7eddd2c4260422e32dd9007190c5b89d36539',
  componentManifests: [component_0.demoNavigationLabComponentManifest],
  routeCatalog: CCFlutterRouteCatalog.merge([
    component_0.demoNavigationLabComponentRouteCatalog,
  ]),
  dependencies: [dependency_demo_network.ccrouterGeneratedPackageBundle],
);
