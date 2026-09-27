import 'package:ccrouter_contracts/ccrouter_contracts.dart';

import '../demo_order_contracts_owner.dart';

/// Requests the Order component to reserve one order and return its receipt.
@CCCommandContract(
  componentId: demoOrderComponentId,
  id: 'demo_order.reserve',
  description: 'Reserves one order for a cross-component checkout flow.',
)
final class ReserveOrderCommand implements CCCommand<String> {
  /// Creates one immutable reserve request.
  const ReserveOrderCommand(this.orderId);

  /// Business order identifier understood by the Order component.
  final int orderId;
}
