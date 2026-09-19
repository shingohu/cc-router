import 'package:demo_order_contracts/demo_order_contracts.dart';

/// Order-owned implementation kept outside the public contracts package.
final class DemoOrderSummaryService implements OrderSummaryService {
  /// Creates the stateless summary implementation.
  const DemoOrderSummaryService();

  /// Formats one order identity without exposing order UI or storage details.
  @override
  String summaryFor(int orderId) => '订单 #$orderId';
}
