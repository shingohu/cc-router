import 'package:ccrouter_contracts/ccrouter_contracts.dart';

import 'order_detail_route_contract.dart';

/// Cross-component startup dependency provided by the Order component.
const demoOrderFoundationInitTask = CCInitTaskContract(
  id: 'demo_order.startup.foundation',
  componentId: demoOrderComponentId,
  description: '准备订单组件供其它组件启动任务依赖的基础状态。',
);
