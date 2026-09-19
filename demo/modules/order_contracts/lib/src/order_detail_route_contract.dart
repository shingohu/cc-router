import 'package:ccrouter_contracts/ccrouter_contracts.dart';

/// Stable component identity shared by the order contract and implementation.
const demoOrderComponent = CCComponentDescriptor(
  id: 'demo_order_component',
  version: '0.1.0',
);

/// Cross-component contract for opening one order detail destination.
@CCRouteContract<String>(
  component: demoOrderComponent,
  id: 'order.detail',
  patterns: [
    CCPathPattern('/orders/:orderId', primary: true),
    CCPathPattern('/order/:orderId'),
  ],
  description: '订单详情，确认后返回订单编号。',
)
abstract class OrderDetailRouteContract {
  /// Declares the stable route arguments independently from the Flutter page.
  const OrderDetailRouteContract({
    required this.orderId,
    @CCQueryParam() this.tab = 'summary',
  });

  /// Stable order identity encoded in the path.
  final int orderId;

  /// Initially selected detail tab encoded as a query value.
  final String tab;
}
