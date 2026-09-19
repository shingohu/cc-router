import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/material.dart';

import 'detail_page.dart';
import 'lab_configuration.dart';
import 'navigation_lab_component.dart';

part 'ccrouter_generated/stack_page.route.g.dart';

@CCRoute<String>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.stack',
  pattern: CCPathPattern('/lab/stack/:level'),
  description: '交互验证 Push、Replace、组合栈操作与精确 Route Entry 句柄。',
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

  Future<void> _removePrevious() async {
    final entries = CCRouter.activeRouteEntries;
    if (entries.length < 2) {
      setState(() => _status = '没有可精确移除的前一 Entry');
      return;
    }
    final previous = entries[entries.length - 2];
    await _run('removeRoute', () async {
      await CCRouter.navigator.removeRoute(previous.handle);
      return previous.routeId;
    });
  }

  Future<void> _removeBelowCurrent() async {
    final entries = CCRouter.activeRouteEntries;
    if (entries.isEmpty) return;
    final current = entries.last;
    await _run('removeRouteBelow', () async {
      await CCRouter.navigator.removeRouteBelow(current.handle);
      return current.routeId;
    });
  }

  Future<void> _replaceBelowCurrent() async {
    final entries = CCRouter.activeRouteEntries;
    if (entries.length < 2) {
      setState(() => _status = '当前 Entry 下方没有可替换页面');
      return;
    }
    final current = entries.last;
    await _run('replaceRouteBelow', () async {
      await CCRouter.navigator.replaceRouteBelow(
        current.handle,
        demoDetailIntent(
          id: 700 + widget.level,
          title: '替换后的下层页面',
          tags: const ['replaceRouteBelow'],
        ),
      );
      return current.routeId;
    });
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
                demoStackIntent(level: widget.level + 1),
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
                demoStackIntent(level: widget.level + 1),
              ),
            ),
          ),
          _StackAction(
            icon: Icons.swap_vertical_circle_outlined,
            title: 'PopAndPush 下一层',
            onPressed: () => _run(
              'popAndPush',
              () => CCRouter.navigator.popAndPush<String>(
                demoStackIntent(level: widget.level + 1),
                popResult: 'replaced-by-popAndPush',
              ),
            ),
          ),
          _StackAction(
            icon: Icons.filter_alt_off_outlined,
            title: 'PopUntil Level 1',
            onPressed: () => _run('popUntil', () async {
              await CCRouter.navigator.popUntil(
                (entry) =>
                    entry.routeId == 'demo_navigation_lab.stack' &&
                    entry.uri.path.endsWith('/1'),
              );
              return null;
            }),
          ),
          _StackAction(
            icon: Icons.vertical_align_top,
            title: 'PushAndRemoveUntil（GoRouter 暂不支持）',
            onPressed: () {
              unawaited(
                _run(
                  'pushAndRemoveUntil',
                  () => CCRouter.navigator.pushAndRemoveUntil<String>(
                    demoStackIntent(level: 99),
                    (entry) => entry.routeId == 'demo_navigation_lab.home',
                  ),
                ),
              );
            },
          ),
          _StackAction(
            icon: Icons.layers_clear_outlined,
            title: '精确移除前一 Entry（GoRouter 暂不支持）',
            onPressed: _removePrevious,
          ),
          _StackAction(
            icon: Icons.low_priority,
            title: '移除当前 Entry 下方（GoRouter 暂不支持）',
            onPressed: _removeBelowCurrent,
          ),
          _StackAction(
            icon: Icons.flip_to_back_outlined,
            title: '替换当前 Entry 下方（GoRouter 暂不支持）',
            onPressed: _replaceBelowCurrent,
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
    _DemoStackPageRoute.intent(level: level);
