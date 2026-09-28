import 'package:ccrouter/ccrouter.dart';
import 'package:demo_network/demo_network.dart';
import 'package:flutter/material.dart';

import 'ccrouter_generated/component/navigation_lab_component.service_api.g.dart';

/// Demonstrates a backend-neutral network Service backed by Dio.
@CCRoute<void>(
  id: 'demo_navigation_lab.network',
  pattern: CCPathPattern('/lab/network'),
  description: '动态 API 环境、Header、授权和网络拦截器示例。',
)
final class DemoNetworkPage extends StatefulWidget {
  /// Creates the network integration page.
  const DemoNetworkPage({super.key});

  @override
  State<DemoNetworkPage> createState() => _DemoNetworkPageState();
}

final class _DemoNetworkPageState extends State<DemoNetworkPage> {
  DemoNetworkService get _service => DemoNavigationLabServices.demoNetwork;
  String _status = '尚未发送请求';
  bool _busy = false;

  Future<void> _send(CCNetworkMethod method) async {
    setState(() {
      _busy = true;
      _status = '${method.name.toUpperCase()} 请求中 · ${_service.environmentId}';
    });
    try {
      final response = await _service.request(
        CCNetworkRequest(
          method: method,
          path: 'anything',
          query: const {'source': 'ccrouter-demo'},
          body: method == CCNetworkMethod.post
              ? const {'message': 'hello from CCRouter'}
              : null,
        ),
      );
      if (!mounted) return;
      setState(() {
        _status =
            '${method.name.toUpperCase()} · ${response.statusCode} · '
            '${response.duration.inMilliseconds}ms';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _status = '失败 · ${error.runtimeType}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleLogin() {
    if (_service.isAuthenticated) {
      _service.setAccessToken(null);
      _service.removeDefaultHeader('X-Demo-User');
    } else {
      _service.setAccessToken('demo-token-after-login');
      _service.setDefaultHeader('X-Demo-User', 'demo-account');
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final environment = demoNetworkEnvironments.firstWhere(
      (item) => item.id == _service.environmentId,
    );
    final logs = _service.logs;
    return Scaffold(
      appBar: AppBar(title: const Text('Network · Dio Backend')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        children: [
          const Text(
            '共享网络 Service',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '业务组件只依赖 CCNetworkClient 抽象。Dio 是当前 Demo 的后端实现，'
            '登录、环境和 Header 切换不会替换 Service 或请求调用方。',
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: environment.id,
            decoration: const InputDecoration(
              labelText: 'API 环境',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final item in demoNetworkEnvironments)
                DropdownMenuItem(value: item.id, child: Text(item.id)),
            ],
            onChanged: (value) {
              if (value == null) return;
              final next = demoNetworkEnvironments.firstWhere(
                (item) => item.id == value,
              );
              _service.switchEnvironment(next);
              _service.setDefaultHeader('X-Demo-Environment', value);
              setState(() => _status = '已切换到 $value');
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _service.isAuthenticated,
            title: const Text('登录授权 Header'),
            subtitle: Text(
              _service.isAuthenticated
                  ? 'Authorization: Bearer <redacted>'
                  : '当前请求不附加访问令牌',
            ),
            onChanged: (_) => _toggleLogin(),
          ),
          const Divider(height: 32),
          Text('请求操作', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _send(CCNetworkMethod.get),
                icon: const Icon(Icons.download_outlined),
                label: const Text('GET /anything'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _send(CCNetworkMethod.post),
                icon: const Icon(Icons.upload_outlined),
                label: const Text('POST /anything'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(_status),
          const Divider(height: 32),
          Text('安全网络日志', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('只显示方法、相对路径、环境、状态和耗时，不显示 Token、完整 URL 或 Body。'),
          const SizedBox(height: 8),
          if (logs.isEmpty) const Text('暂无请求日志'),
          ...logs
              .take(12)
              .map(
                (log) => ListTile(
                  dense: true,
                  leading: Icon(
                    log.stage == CCNetworkLogStage.error
                        ? Icons.error_outline
                        : log.stage == CCNetworkLogStage.response
                        ? Icons.check_circle_outline
                        : Icons.outbound,
                  ),
                  title: Text(
                    '${log.stage.name} · ${log.method.name.toUpperCase()} ${log.path}',
                  ),
                  subtitle: Text(
                    '${log.environmentId} · status=${log.statusCode ?? '-'} · '
                    '${log.duration.inMilliseconds}ms',
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
