import 'package:ccrouter/ccrouter.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';
import 'package:demo_web_contracts/demo_web_contracts.dart';

const demoNavigationLabComponentId = CCComponentId(
  'demo_navigation_lab_component',
);

const demoNavigationLabComponent = CCComponent(
  id: demoNavigationLabComponentId,
  version: '0.1.0',
  dependencies: [demoOrderComponentId, demoWebComponentId],
  serviceDependencies: [CCServiceDependency<OrderSummaryService>()],
);
