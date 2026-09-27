import 'package:ccrouter_contracts/ccrouter_contracts.dart';

import 'order_detail_route_contract.dart';

/// Stable cross-component API for formatting an order summary.
@CCServiceContract(
  componentId: demoOrderComponentId,
  id: 'demo_order.summary',
  description: 'Formats one order identity for cross-component display.',
)
abstract interface class OrderSummaryService {
  /// Returns a display-safe summary for the stable [orderId].
  String summaryFor(int orderId);
}
