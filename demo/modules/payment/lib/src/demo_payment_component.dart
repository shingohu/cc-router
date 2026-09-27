import 'package:ccrouter/ccrouter.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';

/// Stable identity and logical dependencies of the payment component.
const demoPaymentComponentId = CCComponentId('demo_payment_component');

/// Build-time definition of the payment implementation component.
const demoPaymentComponent = CCComponent(
  id: demoPaymentComponentId,
  version: '0.1.0',
  dependencies: [demoOrderComponentId],
  serviceDependencies: [CCServiceDependency<OrderSummaryService>()],
);
