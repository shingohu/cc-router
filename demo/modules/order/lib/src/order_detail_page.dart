import 'package:ccrouter/ccrouter.dart';
import 'package:demo_order_contracts/demo_order_contracts_owner.dart';
import 'package:flutter/material.dart';

@CCRouteImplementation(OrderDetailRouteContract)
final class OrderDetailPage extends StatelessWidget {
  const OrderDetailPage({
    required this.orderId,
    this.tab = 'summary',
    super.key,
  });

  /// 需要展示的稳定订单 ID。
  final int orderId;

  /// 首次展示的详情标签。
  final String tab;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('订单 #$orderId')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('当前标签：$tab'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () =>
                CCRouter.navigator.pop(result: 'confirmed:$orderId'),
            icon: const Icon(Icons.check),
            label: const Text('确认订单'),
          ),
        ],
      ),
    ),
  );
}
