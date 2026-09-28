// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

/// Host-only generated Package Bundle for `ccrouter_demo`.
library;

import 'package:ccrouter/ccrouter_host.dart'
    show
        CCContractBundleDescriptor,
        CCFlutterRouteCatalog,
        CCGeneratedPackageBundle;
import 'package:demo_kv_storage/src/ccrouter_generated/host/demo_kv_storage_ccrouter.g.dart'
    as dependency_demo_kv_storage;
import 'package:demo_navigation_lab/src/ccrouter_generated/host/demo_navigation_lab_ccrouter.g.dart'
    as dependency_demo_navigation_lab;
import 'package:demo_network/src/ccrouter_generated/host/demo_network_ccrouter.g.dart'
    as dependency_demo_network;
import 'package:demo_order/src/ccrouter_generated/host/demo_order_ccrouter.g.dart'
    as dependency_demo_order;
import 'package:demo_payment/src/ccrouter_generated/host/demo_payment_ccrouter.g.dart'
    as dependency_demo_payment;
import 'package:demo_web/src/ccrouter_generated/host/demo_web_ccrouter.g.dart'
    as dependency_demo_web;

/// Generated runtime contribution and direct dependency graph for `ccrouter_demo`.
final ccrouterGeneratedPackageBundle = CCGeneratedPackageBundle(
  packageName: 'ccrouter_demo',
  packageVersion: '0.1.0+1',
  contentFingerprint:
      'ca68026ca381192a5389847b6ffcd1884fa970899d6a63a36a4b41565386bb56',
  contractBundle: CCContractBundleDescriptor(
    packageName: 'ccrouter_demo',
    packageVersion: '0.1.0+1',
    contracts: [],
    requirements: [],
  ),
  componentManifests: [],
  routeCatalog: CCFlutterRouteCatalog.merge([]),
  dependencies: [
    dependency_demo_kv_storage.ccrouterGeneratedPackageBundle,
    dependency_demo_navigation_lab.ccrouterGeneratedPackageBundle,
    dependency_demo_network.ccrouterGeneratedPackageBundle,
    dependency_demo_order.ccrouterGeneratedPackageBundle,
    dependency_demo_payment.ccrouterGeneratedPackageBundle,
    dependency_demo_web.ccrouterGeneratedPackageBundle,
  ],
);
