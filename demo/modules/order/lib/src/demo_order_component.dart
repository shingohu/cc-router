import 'package:ccrouter/ccrouter.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';

export 'package:demo_order_contracts/demo_order_contracts_owner.dart'
    show demoOrderComponentId, OrderDetailRoute, OrderDetailRouteContract;

/// Build-time definition of the order implementation component.
const demoOrderComponent = CCComponent(
  id: demoOrderComponentId,
  version: '0.1.0',
);
