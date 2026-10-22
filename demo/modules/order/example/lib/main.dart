import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/material.dart';

import 'src/ccrouter_generated/ccrouter_host.api.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  CCRouterHost.initialize(hostAssembly: ccrouterGeneratedHostAssembly);
  await CCRouterHost.runInitTasks(gate: CCInitTaskGate.appStarted);
  runApp(const OrderExampleApp());
}

/// Minimal standalone Managed Host for developing Order in isolation.
final class OrderExampleApp extends StatelessWidget {
  const OrderExampleApp({super.key});

  @override
  Widget build(BuildContext context) => CCManagedRouterApp(
    title: 'Order Example',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      useMaterial3: true,
    ),
  );
}
