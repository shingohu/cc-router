import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_ui/ccrouter_ui.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';
import 'package:demo_network/demo_network.dart';
import 'package:demo_kv_storage/demo_kv_storage.dart';
import 'package:demo_web_contracts/demo_web_contracts.dart';

const demoNavigationLabComponentId = CCComponentId(
  'demo_navigation_lab_component',
);

const demoNavigationLabComponent = CCComponent(
  id: demoNavigationLabComponentId,
  version: '0.1.0',
  dependencies: [
    demoOrderComponentId,
    demoNetworkComponentId,
    demoKvStorageComponentId,
    demoWebComponentId,
  ],
  serviceDependencies: [
    CCServiceDependency<OrderSummaryService>(),
    CCServiceDependency<DemoNetworkService>(),
    CCServiceDependency<DemoKeyValueStorageService>(),
  ],
  commandDependencies: [CCCommandDependency<ReserveOrderCommand>()],
  uiDependencies: [
    CCUIFragmentDependency<OrderPanelFragmentContract>(
      versionRange: '^1.0.0',
      alias: 'orderPanel',
    ),
    CCUIFragmentDependency<OrderSummaryFragmentContract>(
      versionRange: '^1.0.0',
      alias: 'orderSummary',
    ),
    CCUIFragmentDependency<OrderRecommendationsFragmentContract>(
      versionRange: '^2.0.0',
      alias: 'orderRecommendations',
    ),
  ],
);
