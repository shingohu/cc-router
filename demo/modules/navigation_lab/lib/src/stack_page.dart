import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/material.dart';

import 'lab_configuration.dart';
import 'navigation_lab_component.dart';
import 'ccrouter_generated/demo_navigation_lab_component.route_api.g.dart';

@CCRoute<String>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.stack',
  pattern: CCPathPattern('/lab/stack/:level'),
  description: '交互验证 Push、Replace、Pop、Go 与 Reset。',
)
final class DemoStackPage extends StatefulWidget {
  const DemoStackPage({required this.level, super.key});

  final int level;

  @override
  State<DemoStackPage> createState() => _DemoStackPageState();
}

final class _DemoStackPageState extends State<DemoStackPage> {
  String _status = '当前是第 ${0} 层';

  @override
  void initState() {
    super.initState();
    _status = '当前是第 ${widget.level} 层';
  }

  Future<void> _run(String label, Future<Object?> Function() operation) async {
    setState(() => _status = '$label 执行中');
    try {
      final result = await operation();
      if (mounted) setState(() => _status = '$label 完成 · result=$result');
    } on Object catch (error) {
      demoNavigationLabStore.record('$label failed · ${error.runtimeType}');
      if (mounted) {
        setState(() => _status = '$label 失败 · ${error.runtimeType}');
      }
    }
  }

  void _complete() {
    if (CCRouter.navigator.canPop()) {
      CCRouter.navigator.pop(result: 'stack:${widget.level}:done');
      return;
    }
    unawaited(CCRouter.navigator.open(Uri.parse('/')));
  }

  @override
  Widget build(BuildContext context) {
    final entries = CCRouter.activeRouteEntries;
    return Scaffold(
      appBar: AppBar(title: Text('栈操作 · Level ${widget.level}')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(_status, key: const ValueKey('stack-status')),
          const SizedBox(height: 12),
          Text(
            'Managed Entries: ${entries.map((entry) => entry.routeId).join(' → ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          _StackAction(
            icon: Icons.add_to_photos_outlined,
            title: 'Push 下一层',
            onPressed: () => _run(
              'push',
              () => CCRouter.navigator.push<String>(
                DemoNavigationLabRoutes.stack(level: widget.level + 1),
                source: const CCNavigationSource.feature('stack.push'),
              ),
            ),
          ),
          _StackAction(
            icon: Icons.find_replace,
            title: 'Replace 当前层',
            onPressed: () => _run(
              'replace',
              () => CCRouter.navigator.replace<String>(
                DemoNavigationLabRoutes.stack(level: widget.level + 1),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _complete,
            icon: const Icon(Icons.check),
            label: const Text('Pop 并返回结果'),
          ),
        ],
      ),
    );
  }
}

final class _StackAction extends StatelessWidget {
  const _StackAction({
    required this.icon,
    required this.title,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: onPressed,
  );
}

CCRouteIntent<String> demoStackIntent({required int level}) =>
    DemoNavigationLabRoutes.stack(level: level);
