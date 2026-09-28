import 'package:ccrouter_devtools/ccrouter_devtools.dart';

final demoDevToolsCatalog = CCDevToolsStaticCatalogSnapshot(
  capturedAt: DateTime.utc(2026, 9, 29),
  catalogFingerprint: 'demo-navigation-lab-v1',
  components: [
    CCDevToolsCatalogComponent(
      id: 'demo_navigation_lab_component',
      version: '0.1.0',
      dependencies: const [
        'demo_kv_storage_component',
        'demo_network_component',
        'demo_order_component',
        'demo_web_component',
      ],
    ),
    CCDevToolsCatalogComponent(
      id: 'demo_kv_storage_component',
      version: '0.1.0',
    ),
    CCDevToolsCatalogComponent(id: 'demo_network_component', version: '0.1.0'),
    CCDevToolsCatalogComponent(id: 'demo_order_component', version: '0.1.0'),
    CCDevToolsCatalogComponent(id: 'demo_web_component', version: '0.1.0'),
  ],
  records: const [
    CCDevToolsCatalogRecord(
      kind: 'route',
      id: 'demo_navigation_lab.detail',
      ownerComponentId: 'demo_navigation_lab_component',
      packageName: 'demo_navigation_lab',
      description: '类型安全详情页与返回结果演示。',
      source: CCDevToolsSourceLocation(
        packageName: 'demo_navigation_lab',
        packageUri: 'package:demo_navigation_lab/src/detail_page.dart',
        line: 7,
        column: 1,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: 'service',
      id: 'demo.network.client',
      ownerComponentId: 'demo_network_component',
      packageName: 'demo_network',
    ),
    CCDevToolsCatalogRecord(
      kind: 'command',
      id: 'demo_navigation_lab.create_receipt',
      ownerComponentId: 'demo_navigation_lab_component',
      packageName: 'demo_navigation_lab',
      source: CCDevToolsSourceLocation(
        packageName: 'demo_navigation_lab',
        packageUri:
            'package:demo_navigation_lab/src/component_capabilities.dart',
        line: 104,
        column: 1,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: 'event',
      id: 'demo_navigation_lab.order_completed',
      ownerComponentId: 'demo_navigation_lab_component',
      packageName: 'demo_navigation_lab',
      source: CCDevToolsSourceLocation(
        packageName: 'demo_navigation_lab',
        packageUri:
            'package:demo_navigation_lab/src/component_capabilities.dart',
        line: 138,
        column: 1,
      ),
    ),
    CCDevToolsCatalogRecord(
      kind: 'initTask',
      id: 'demo.startup.foundation',
      ownerComponentId: 'demo_navigation_lab_component',
      packageName: 'demo_navigation_lab',
      source: CCDevToolsSourceLocation(
        packageName: 'demo_navigation_lab',
        packageUri:
            'package:demo_navigation_lab/src/navigation_lab_component_registrar.dart',
        line: 76,
        column: 1,
      ),
    ),
  ],
  relations: const [
    CCDevToolsCatalogRelation(
      sourceId: 'demo_navigation_lab_component',
      targetId: 'demo_network_component',
      kind: 'dependsOn',
    ),
    CCDevToolsCatalogRelation(
      sourceId: 'demo_navigation_lab.detail',
      targetId: 'demo.network.client',
      kind: 'calls',
    ),
    CCDevToolsCatalogRelation(
      sourceId: 'demo_navigation_lab.detail',
      targetId: 'demo_navigation_lab.create_receipt',
      kind: 'executes',
    ),
    CCDevToolsCatalogRelation(
      sourceId: 'demo_navigation_lab.create_receipt',
      targetId: 'demo_navigation_lab.order_completed',
      kind: 'publishes',
    ),
    CCDevToolsCatalogRelation(
      sourceId: 'demo.startup.foundation',
      targetId: 'demo_order.startup.foundation',
      kind: 'dependsOn',
    ),
  ],
);

void registerDemoDevToolsExtension() {
  CCDevToolsServiceExtension.register(
    provider: CCRouterDevToolsSnapshotProvider(catalog: demoDevToolsCatalog),
    catalog: demoDevToolsCatalog,
  );
}
