import 'package:ccrouter_contracts/ccrouter_contracts.dart';

import 'order_detail_route_contract.dart';

/// Typed order-owned value used to verify generic Service method forwarding.
///
/// Components use this immutable envelope when a value must retain its exact
/// static type across a generated Service Proxy without dynamic conversion.
final class OrderSummaryValue<T extends Object> {
  /// Creates an envelope containing the strongly typed [value].
  const OrderSummaryValue(this.value);

  /// Value whose type must be preserved by the generated caller.
  final T value;
}

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

  /// Returns the typed value without weakening it to `Object` or `dynamic`.
  T unwrap<T extends Object>(OrderSummaryValue<T> value);

  /// Loads and returns the typed value through the asynchronous Proxy path.
  Future<T> loadValue<T extends Object>(OrderSummaryValue<T> value);

  /// Number of calls handled by the current app-scoped Service instance.
  int get invocationCount;
}
