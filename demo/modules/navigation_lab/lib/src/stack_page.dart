import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/material.dart';

import 'lab_configuration.dart';
import 'component_capabilities.dart';
import 'ccrouter_generated/demo_navigation_lab_component.api.g.dart';

@CCRoute<String>(
  id: 'demo_navigation_lab.stack',
  pattern: CCPathPattern('/lab/stack/:level'),
  description: '交互验证 Push、Replace、Pop、Go 与 Reset。',
)
final class DemoStackPage extends StatefulWidget {
  const DemoStackPage({
    required this.level,
    @CCQueryParam() this.returnsResult = false,
    super.key,
  });

  final int level;
  final bool returnsResult;

  @override
  State<DemoStackPage> createState() => _DemoStackPageState();
}

final class _DemoStackPageState extends State<DemoStackPage> {
  String _status = '当前是第 ${0} 层';
  CCRouteEntryHandle? _handle;
  Timer? _closeTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _handle ??= CCRouter.routeEntryHandleOf(context);
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  void _coverAndClose() {
    final handle = _handle;
    if (handle == null || _closeTimer?.isActive == true) return;
    final service = CCRouter.routeService<DemoRouteService>(context);
    demoNavigationLabStore.record(
      'Exact close · captured Scope #${service.instanceId}',
    );
    _closeTimer = Timer(const Duration(seconds: 2), () {
      observeDemoOperation('Exact close', () async {
        final outcome = await CCRouter.navigator.close(
          handle,
          result: 'exact:${widget.level}',
        );
        demoNavigationLabStore.record('Exact close · ${outcome.status.name}');
      }());
    });
    observeDemoOperation(
      'Cover exact-close page',
      CCRouter.navigator.push(
        DemoNavigationLabRoutes.stack(
          level: widget.level + 1,
          returnsResult: true,
        ),
        context: context,
      ),
    );
  }

  Future<void> _revalidate(DemoRevalidationAction action) async {
    demoNavigationLabStore
      ..revalidationTarget = _handle
      ..revalidationAction = action;
    final report = await CCRouter.revalidateActiveRoutes(
      reason: 'demo_stack_policy',
    );
    final outcomes = report.entries
        .map((entry) => entry.outcome.name)
        .join(',');
    demoNavigationLabStore.record('Revalidation ${action.name} · $outcomes');
    if (mounted) {
      setState(() => _status = 'Revalidation ${action.name} · $outcomes');
    }
  }

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
    if (widget.returnsResult && CCRouter.navigator.canPop(context: context)) {
      CCRouter.navigator.pop(
        result: 'stack:${widget.level}:done',
        context: context,
      );
      return;
    }
    observeDemoOperation(
      'Stack 返回首页',
      CCRouter.navigator.go(DemoNavigationLabRoutes.home(), context: context),
    );
  }

  void _completeWithWrongType() {
    if (widget.returnsResult && CCRouter.navigator.canPop(context: context)) {
      CCRouter.navigator.pop(result: 42, context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = CCRouter.activeRouteEntries;
    final returnsResult =
        widget.returnsResult && CCRouter.navigator.canPop(context: context);
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
                DemoNavigationLabRoutes.stack(
                  level: widget.level + 1,
                  returnsResult: true,
                ),
                source: const CCNavigationSource.feature('stack.push'),
                context: context,
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
                context: context,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _complete,
            icon: Icon(returnsResult ? Icons.check : Icons.home_outlined),
            label: Text(returnsResult ? 'Pop 并返回结果' : 'Go 返回首页'),
          ),
          if (returnsResult) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _completeWithWrongType,
              icon: const Icon(Icons.warning_amber_outlined),
              label: const Text('故意返回错误类型'),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            returnsResult
                ? 'String 路由收到 int 结果时，Runtime 应报告 resultTypeMismatch，'
                      '并清理当前 RouteEntry。'
                : 'Go / Reset 不提供页面返回结果；返回首页使用声明式 Go，'
                      '不会在首页下面保留当前页面。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 32),
          _StackAction(
            icon: Icons.remove_from_queue,
            title: '覆盖后精确关闭本页',
            onPressed: _coverAndClose,
          ),
          const Text('先打开覆盖页，2 秒后按本页 identity 关闭；覆盖页继续可用，本页 Scope 只释放一次。'),
          for (final action in DemoRevalidationAction.values)
            _StackAction(
              icon: Icons.policy_outlined,
              title: 'Revalidation · ${action.name}',
              onPressed: () => _run(
                'Revalidation ${action.name}',
                () => _revalidate(action),
              ),
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

CCRouteIntent<String> demoStackIntent({
  required int level,
  bool returnsResult = false,
}) => DemoNavigationLabRoutes.stack(level: level, returnsResult: returnsResult);
