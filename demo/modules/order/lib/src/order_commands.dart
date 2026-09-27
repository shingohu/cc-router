import 'package:ccrouter/ccrouter.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';

/// Handles the public Order reservation Command for consumer components.
@CCCommandHandler()
Future<String> handleReserveOrder(
  ReserveOrderCommand command,
  CCInvocationContext context,
) async {
  if (context.cancellation.isCancelled) {
    throw const CCInvocationCancelledError();
  }
  return 'order-receipt:${command.orderId}';
}
