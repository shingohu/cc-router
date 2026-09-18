import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/material.dart';

final class CreateOrder implements CCCommand<String> {
  const CreateOrder(this.amount);

  final int amount;
}

final class DemoComponentRegistrar implements CCComponentRegistrar {
  const DemoComponentRegistrar();

  static const manifest = CCComponentManifest(
    id: 'demo',
    version: '0.1.0',
    registrar: DemoComponentRegistrar(),
  );

  @override
  void register(CCRegistry registry) {
    registry.registerCommand<CreateOrder, String>((command, _) async {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      return '订单已创建：¥${command.amount}';
    });
  }
}

void main() {
  runApp(const CCRouterApp(child: CCRouterDemoApp()));
}

final class CCRouterDemoApp extends StatelessWidget {
  const CCRouterDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const RuntimePage(),
    );
  }
}

final class RuntimePage extends StatefulWidget {
  const RuntimePage({super.key});

  @override
  State<RuntimePage> createState() => _RuntimePageState();
}

final class _RuntimePageState extends State<RuntimePage> {
  String _status = '正在初始化 Runtime';
  bool _ready = false;
  bool _sessionOpen = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await CCRouter.initialize(
      components: const [DemoComponentRegistrar.manifest],
    );
    if (!mounted) return;
    setState(() {
      _ready = true;
      _status = 'Runtime 已初始化';
    });
  }

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

  Future<void> _createOrder() async {
    if (!_ready || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await CCRouter.command(const CreateOrder(100));
      if (mounted) setState(() => _status = result);
    } on CCRouterError catch (error) {
      if (mounted) setState(() => _status = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(CCRouter.shutdown());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final componentCount = _ready ? CCRouter.registeredComponents.length : 0;
    final accountId = _ready && _sessionOpen
        ? CCRouter.session?.accountId ?? '-'
        : '-';
    final traceCount = _ready ? CCRouter.recentTraces.length : 0;
    return Scaffold(
      appBar: AppBar(title: const Text('CCRouter Demo')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Flutter组件化',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
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
            onPressed: _ready && !_busy ? _toggleSession : null,
            icon: Icon(_sessionOpen ? Icons.logout : Icons.login),
            label: Text(_sessionOpen ? '关闭 Session' : '开启 Session'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _ready && !_busy ? _createOrder : null,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.shopping_bag_outlined),
            label: const Text('调用 CreateOrder Command'),
          ),
        ],
      ),
    );
  }
}
