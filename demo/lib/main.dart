import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';
import 'package:flutter/material.dart';

import 'ccrouter_generated/ccrouter_host.routes.g.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  CCRouter.initialize(components: ccrouterGeneratedComponentManifests);
  runApp(const CCRouterDemoApp());
}

final class CCRouterDemoApp extends StatefulWidget {
  const CCRouterDemoApp({super.key});

  @override
  State<CCRouterDemoApp> createState() => _CCRouterDemoAppState();
}

final class _CCRouterDemoAppState extends State<CCRouterDemoApp> {
  late final CCGoRouterBackend _backend;

  @override
  void initState() {
    super.initState();
    _backend = CCGoRouterBackend.managed(
      catalog: ccrouterGeneratedRouteCatalog,
      hostRoutes: [GoRoute(path: '/', builder: (_, _) => const RuntimePage())],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CCRouterApp.managed(
      backend: _backend,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        routerConfig: _backend.router,
      ),
    );
  }
}

final class RuntimePage extends StatefulWidget {
  const RuntimePage({super.key});

  @override
  State<RuntimePage> createState() => _RuntimePageState();
}

final class _RuntimePageState extends State<RuntimePage> {
  String _status = 'Runtime 已初始化';
  bool _sessionOpen = false;

  Future<void> _toggleSession() async {
    if (_sessionOpen) {
      await CCRouter.closeSession();
      if (!mounted) return;
      setState(() {
        _sessionOpen = false;
        _status = 'Session 已关闭';
      });
      return;
    }
    CCRouter.openSession(accountId: 'demo-account');
    setState(() {
      _sessionOpen = true;
      _status = 'Session 已开启';
    });
  }

  Future<void> _openOrder() async {
    try {
      final result = await CCRouter.navigator.push<String>(
        OrderDetailRoute.intent(orderId: 100, tab: 'items'),
      );
      if (mounted) setState(() => _status = result ?? '订单详情已返回');
    } on CCRouterError catch (error) {
      if (mounted) setState(() => _status = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final componentCount = CCRouter.registeredComponents.length;
    final accountId = _sessionOpen ? CCRouter.session?.accountId ?? '-' : '-';
    final traceCount = CCRouter.recentTraces.length;
    return Scaffold(
      appBar: AppBar(title: const Text('CCRouter Demo')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Flutter组件化', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(_status, key: const ValueKey('status')),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Runtime 状态',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('组件：$componentCount'),
                  Text('Session：${_sessionOpen ? '已开启' : '未开启'}'),
                  Text('账号：$accountId'),
                  Text('Trace：$traceCount'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _toggleSession,
            icon: Icon(_sessionOpen ? Icons.logout : Icons.login),
            label: Text(_sessionOpen ? '关闭 Session' : '开启 Session'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _openOrder,
            icon: const Icon(Icons.receipt_long),
            label: const Text('打开订单详情'),
          ),
        ],
      ),
    );
  }
}
