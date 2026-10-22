import 'package:ccrouter/ccrouter.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';
import 'package:flutter/material.dart';

/// Stable identity of the standalone example's Host-owned component.
const orderExampleComponentId = CCComponentId('demo_order_example_component');

/// Host-owned component contributing the example landing Route.
const orderExampleComponent = CCComponent(
  id: orderExampleComponentId,
  version: '0.1.0',
  dependencies: [demoOrderComponentId],
);

/// Entry page that exercises the generated Order Route contract.
@CCRoute<void>(
  id: 'demo_order_example.home',
  pattern: CCPathPattern('/'),
  presentation: CCPagePresentation(transition: CCPageTransitionType.none),
  description: 'Standalone Order component development home.',
)
final class OrderExampleHomePage extends StatelessWidget {
  const OrderExampleHomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Order component')),
    body: Center(
      child: FilledButton.icon(
        onPressed: () async {
          final result = await CCRouter.navigator.push(
            OrderDetailRoute.intent(orderId: 1001),
          );
          if (!context.mounted || result == null) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Order result: $result')));
        },
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('Open order #1001'),
      ),
    ),
  );
}
