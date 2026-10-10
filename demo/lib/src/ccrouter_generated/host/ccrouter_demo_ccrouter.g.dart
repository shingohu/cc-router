// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

/// Host-only generated Package Bundle for `ccrouter_demo`.
library;

import 'package:ccrouter/ccrouter_host.dart'
    show
        CCContractBundleDescriptor,
        CCContractDescriptor,
        CCContractKind,
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
      'a0db1163a17e1776c3cb4810de24f9c4aeee49755446775759def19a531d4241',
  contractBundle: CCContractBundleDescriptor(
    packageName: 'ccrouter_demo',
    packageVersion: '0.1.0+1',
    contracts: [
      CCContractDescriptor(
        kind: CCContractKind.service,
        id: "demo.kv_storage",
        ownerComponentId: "demo_kv_storage_component",
        version: "0.1.0",
        shapeFingerprint:
            "74f1d13513448f76b3db9f996cbb349687376d851b6cb1420ee2a0825fcca1f2",
      ),
      CCContractDescriptor(
        kind: CCContractKind.service,
        id: "demo.network.client",
        ownerComponentId: "demo_network_component",
        version: "0.1.0",
        shapeFingerprint:
            "c0a7cb128881259780a44aedc62de6cf5efdd5925ab7dad09997add3f0aeeb8b",
      ),
      CCContractDescriptor(
        kind: CCContractKind.initTask,
        id: "demo.startup.foundation",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "ef963961ee2df34404352b04e5c03229c5f25238acc42f222a6ce30fd4df21cd",
      ),
      CCContractDescriptor(
        kind: CCContractKind.initTask,
        id: "demo.startup.optional-sdk",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "a1000ff9ae3a0ead579ed47281ee8efe911f49b9cda61ec8eb7c4174cb689fe5",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.cancel",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "3ad59bb76a0029a12bf63a3071a50c296658faa876d80ef06d0c3d1dbfc8c297",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.capabilities",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "46b78332b923aa679c0f936d966125ef2a76235246e9a23f0895f682740ad71f",
      ),
      CCContractDescriptor(
        kind: CCContractKind.command,
        id: "demo_navigation_lab.create_receipt",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "09931f73ce124e81a90b5e6e23fa4f8b1b4ab33d886ddaea4af81cce35bf606f",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.defer",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "e783fd008648a6f566b4d53840dcebd04eef3c805d6c687a8a4b451ce70c1110",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.detail",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "ef1b3a3e2d7b26cdeb4a052c2b88ec9512f08ca2734ac774dfc46f69fd66d803",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.extra",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "9a4da8c6d49c60b06ca36ba3d1288310ab9a899693557beb5f98269b2a796621",
      ),
      CCContractDescriptor(
        kind: CCContractKind.command,
        id: "demo_navigation_lab.fail",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "08a3329921842e2c924e9d08d7887649d5cf7c280737c2fd96eb534ec518211e",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.failure",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "02fecf40ea786cdc1341710d48ad0b24627eb4dc051b0440674729bdc59969d5",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.guarded",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "e5812753477899a9005c20e563b11a4cd8c7a3436b3123d32b3f58220d9e409b",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.home",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "6839985b384f36da449c10f681971534fb22559f47988f1e462568cf5a5ca28b",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.lifecycle",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "6acc1542689b9374315c66daca1a5c9bfcefc976f0d3b9946874667da7fca5be",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.network",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "c86b6e101cb906b2fe7d56e78c32ee749e3cbbf7bc906f6b922c26b880a6fe5d",
      ),
      CCContractDescriptor(
        kind: CCContractKind.event,
        id: "demo_navigation_lab.order_completed",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "bff2d0710d6acbfdf9e08d2fc6cc0afdcbcd4dcd739d3d5a1db9db63d203b545",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.presentation.bottom_page",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "350efbde8cb1b9c215c8cbbba6f00b20812db2ca7f5240ce156e85688801c1d1",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.presentation.cupertino",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "496c76ad7c7c3d36ce3cac601caaae4a901f4bf7fe9fb38b673245504f2e293c",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.presentation.dialog",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "0c54dc9c16c7e73c1890e4fb14fa3439d2e630c242e883009dbcbeb71c64bc10",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.presentation.fade",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "7e3aa0be5cf0e7f2d1c572d5672651a37c9a9f573c74418aab097c0d4f91545b",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.presentation.scale",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "1757365a9908a6eea6f50095b07f633faf47021386ce35c5f03847862ab232c1",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.presentation.sheet",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "9a996567fe68f558647e90a97fe90375bba315724d5a1fdf51289f112cbbfd77",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.presentation.transparent",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "3327e98114939cdcba6915b84413f6622e579a8fa952b8e0e25946a9327cb5bd",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.proceed",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "6276e2d3dbfd06ea478d3fba8c5095c96a52179ccb0651fd364b9702c207f6d0",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.redirect.source",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "82084cb0cd13488bf57b1867fc3f862b092b6d7aa5256b13450f7a00e3026a75",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.redirect.target",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "fedba2238f347450290947dc9607870875b0f2ef9d42827d5002badafef439e6",
      ),
      CCContractDescriptor(
        kind: CCContractKind.command,
        id: "demo_navigation_lab.refresh_cache",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "d31eec781301e6d10b3f44a7f28db3381e16c9e25167afb9b5395a6f0d5100e9",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.shell.detail",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "dc689560b9d62ad6fbd7de26a4a88e017cae5278e28055302e32ec1c750a5325",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.shell.feed",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "4775302e6e81170d11f13a2dbb1410439223e0a062d5ff638ca59dd6c21a4c7c",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.shell.settings",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "c0cdea2873de94aaa3fdf274a2e1520ec22b40037fc8bf4c36d68c5b7d6d1711",
      ),
      CCContractDescriptor(
        kind: CCContractKind.event,
        id: "demo_navigation_lab.slow",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "391cd8b777de2aab3883930e1429affe70609d159c0f1b2bfceee68c1a81152b",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.stack",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "ba64794c0165031686adcc744bd38ded1aa6669b62d345b36daf263ccfbf2caa",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.storage",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "cd802378bf89719e92e8f82c3d65d5232d6af396d4e914a09587286ac3aee20f",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.timeout",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "ab3712cc71d3d06d2ca15ada548efadf53cefc7e166a212cb40446e92a60c18b",
      ),
      CCContractDescriptor(
        kind: CCContractKind.event,
        id: "demo_navigation_lab.unobserved",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "5b6fabc6ed4d6f80485e9259289d9c682548788a5eb18ede05c5221e749d9030",
      ),
      CCContractDescriptor(
        kind: CCContractKind.command,
        id: "demo_navigation_lab.wait",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "c51c009f1e86883d91ffaf0f1d8d34143e659f04b4e6dcf929f4daa32d5166b5",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.workspace.activity",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "0c1c1365fdafa7db333d2613b15d34e07c77e8c23e08cf2e7fec6a2b31b198c9",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.workspace.detail",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "36e1e78da1ff909fd37ca765ee31e5802e14db196b2efd4968bb806dc27c0004",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.workspace.home",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "f8df3b268ef2eaa8139344f8e8110574f766a5904140cf3af1a10ab9395b0f9c",
      ),
      CCContractDescriptor(
        kind: CCContractKind.route,
        id: "demo_navigation_lab.workspace.profile",
        ownerComponentId: "demo_navigation_lab_component",
        version: "0.1.0",
        shapeFingerprint:
            "d1e1e86f5ce8fe67c33022fb04e736f81b5b5e43904bbaab6c15a46f836e5b41",
      ),
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
