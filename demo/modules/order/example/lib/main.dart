import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';
import 'package:flutter/material.dart';

import 'src/ccrouter_generated/ccrouter_host.api.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  CCRouterHost.initialize(hostAssembly: ccrouterGeneratedHostAssembly);
  await CCRouterHost.runInitTasks(gate: CCInitTaskGate.appStarted);
  runApp(const OrderExampleApp());
}

/// Minimal standalone Host for developing the Order component in isolation.
final class OrderExampleApp extends StatelessWidget {
  const OrderExampleApp({super.key});

  @override
  Widget build(BuildContext context) => CCGoRouterApp(
    title: 'Order Example',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      useMaterial3: true,
    ),
    hostRoutes: [
      GoRoute(path: '/', builder: (_, _) => const _OrderExampleHomePage()),
    ],
  );
}

/// Entry page that exercises the generated Order Route contract.
final class _OrderExampleHomePage extends StatelessWidget {
  const _OrderExampleHomePage();

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
