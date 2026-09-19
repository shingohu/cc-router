import 'package:ccrouter/ccrouter.dart';

/// Stable identity and logical dependencies of the payment component.
const demoPaymentComponent = CCComponentDescriptor(
  id: 'demo_payment_component',
  version: '0.1.0',
  dependencies: ['demo_order_component'],
);
