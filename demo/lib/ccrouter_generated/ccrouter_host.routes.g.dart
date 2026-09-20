// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

import 'package:ccrouter/ccrouter.dart' show CCComponentManifest;
import 'package:ccrouter/ccrouter_host.dart';
import 'package:demo_navigation_lab/demo_navigation_lab_ccrouter.g.dart'
    as component_demo_navigation_lab;
import 'package:demo_order/demo_order_ccrouter.g.dart' as component_demo_order;
import 'package:demo_payment/demo_payment_ccrouter.g.dart'
    as component_demo_payment;
import 'package:demo_web/demo_web_ccrouter.g.dart' as component_demo_web;

/// All generated component Manifests installed in this Host.
const ccrouterGeneratedComponentManifests = <CCComponentManifest>[
  component_demo_navigation_lab.demoNavigationLabComponentManifest,
  component_demo_order.demoOrderComponentManifest,
  component_demo_payment.demoPaymentComponentManifest,
  component_demo_web.demoWebComponentManifest,
];

/// All generated component destinations installed in this Host.
final ccrouterGeneratedRouteCatalog = CCFlutterRouteCatalog.merge(
  [
    component_demo_navigation_lab.demoNavigationLabComponentRouteCatalog,
    component_demo_order.demoOrderComponentRouteCatalog,
    component_demo_payment.demoPaymentComponentRouteCatalog,
    component_demo_web.demoWebComponentRouteCatalog,
  ],
  componentVersions: {
    for (final manifest in ccrouterGeneratedComponentManifests)
      manifest.id: manifest.version,
  },
);
