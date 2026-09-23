import 'package:ccrouter/ccrouter.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';

import 'order_summary_service_proxy.dart';

/// Internal payment workflow that opens an order without importing order UI.
abstract final class PaymentOrderNavigation {
  /// Payment-attributed caller for the promoted order capability.
  static const OrderSummaryService _orderSummaryService =
      OrderSummaryServiceProxy();

  /// Opens the stable order destination and returns its typed confirmation.
  static Future<String?> openOrder(int orderId) => CCRouter.navigator.push(
    OrderDetailRoute.intent(orderId: orderId, tab: 'payment'),
  );

  /// Resolves the promoted order Service without importing its implementation.
  static String orderSummary(int orderId) =>
      _orderSummaryService.summaryFor(orderId);
}
