import 'package:ccrouter/ccrouter.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';

/// Order-owned implementation kept outside the public contracts package.
@CCService()
final class DemoOrderSummaryService implements OrderSummaryService {
  /// Creates the stateless summary implementation.
  DemoOrderSummaryService();

  /// Calls handled by this app-scoped instance.
  int _invocationCount = 0;

  /// Formats one order identity without exposing order UI or storage details.
  @override
  String summaryFor(int orderId) {
    _invocationCount++;
    return '订单 #$orderId';
  }

  /// Simulates an asynchronous repository boundary for Proxy verification.
  @override
  Future<String> loadSummary(int orderId) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return summaryFor(orderId);
  }

  /// Preserves the generic value type across the synchronous generated Proxy.
  @override
  T unwrap<T extends Object>(OrderSummaryValue<T> value) => value.value;

  /// Preserves the generic value type across the asynchronous generated Proxy.
  @override
  Future<T> loadValue<T extends Object>(OrderSummaryValue<T> value) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return value.value;
  }

  /// Reports calls retained by the app-scoped singleton.
  @override
  int get invocationCount => _invocationCount;
}
