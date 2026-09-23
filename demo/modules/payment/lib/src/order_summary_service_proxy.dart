import 'package:ccrouter/ccrouter_generated.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';

/// Payment-owned typed caller proxy for the promoted order Service.
final class OrderSummaryServiceProxy implements OrderSummaryService {
  /// Creates the stateless payment caller proxy.
  const OrderSummaryServiceProxy();

  /// Invokes the synchronous order capability through the traced boundary.
  @override
  String summaryFor(int orderId) =>
      CCRouterGeneratedServiceBinding.invokeSync<OrderSummaryService, String>(
        contract: demoOrderSummaryService,
        methodId: 'summaryFor',
        callerComponentId: 'demo_payment_component',
        call: (service, _) => service.summaryFor(orderId),
      );
}
