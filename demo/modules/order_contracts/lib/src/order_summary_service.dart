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

  /// Loads one summary through an asynchronous component boundary.
  Future<String> loadSummary(int orderId);

  /// Number of calls handled by the current app-scoped Service instance.
  int get invocationCount;
}
