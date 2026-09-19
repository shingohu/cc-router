import 'package:ccrouter_contracts/ccrouter_contracts.dart';

/// Stable cross-component API for formatting an order summary.
abstract interface class OrderSummaryService {
  /// Returns a display-safe summary for the stable [orderId].
  String summaryFor(int orderId);
}

/// Stable service identity retained if the interface moves between packages.
const demoOrderSummaryService = CCServiceToken<OrderSummaryService>(
  'demo_order.summary',
);
