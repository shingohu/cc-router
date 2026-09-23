import 'package:ccrouter/ccrouter_generated.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';

/// Navigation Lab typed caller proxy for the promoted order Service.
final class OrderSummaryServiceProxy implements OrderSummaryService {
  /// Creates the stateless Navigation Lab caller proxy.
  const OrderSummaryServiceProxy();

  /// Invokes the synchronous order capability through the traced boundary.
  @override
  String summaryFor(int orderId) =>
      CCRouterGeneratedServiceBinding.invokeSync<OrderSummaryService, String>(
        contract: demoOrderSummaryService,
        methodId: 'summaryFor',
        callerComponentId: 'demo_navigation_lab_component',
        call: (service, _) => service.summaryFor(orderId),
      );
}
