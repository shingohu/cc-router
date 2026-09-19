import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/material.dart';

import 'detail_page.dart';
import 'lab_configuration.dart';
import 'navigation_lab_component.dart';

part 'ccrouter_generated/lifecycle_page.route.g.dart';

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.lifecycle',
  pattern: CCPathPattern('/lab/lifecycle'),
  description: '同时验证 CCPageLifecycleMixin 与 Listener 的页面和 App 生命周期。',
)
final class DemoLifecyclePage extends StatefulWidget {
  const DemoLifecyclePage({super.key});

  @override
  State<DemoLifecyclePage> createState() => _DemoLifecyclePageState();
}

final class _DemoLifecyclePageState extends State<DemoLifecyclePage>
    with CCPageLifecycleMixin<DemoLifecyclePage> {
  final List<String> _localEvents = <String>[];

  void _record(String event) {
    demoNavigationLabStore.record('Lifecycle mixin · $event');
    if (mounted) setState(() => _localEvents.insert(0, event));
  }

  @override
  void initState() {
    super.initState();
    _localEvents.add('State.initState');
  }

  @override
  void onPageShow() => _record('onPageShow');

  @override
  void onPageHide() => _record('onPageHide');

  @override
  void onForeground() => _record('onForeground');

  @override
  void onBackground() => _record('onBackground');

  @override
  void dispose() {
    demoNavigationLabStore.record('Lifecycle mixin · State.dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CCPageLifecycleListener(
    onPageShow: () =>
        demoNavigationLabStore.record('Lifecycle listener · onPageShow'),
    onPageHide: () =>
        demoNavigationLabStore.record('Lifecycle listener · onPageHide'),
    onForeground: () =>
        demoNavigationLabStore.record('Lifecycle listener · onForeground'),
    onBackground: () =>
        demoNavigationLabStore.record('Lifecycle listener · onBackground'),
    child: Scaffold(
      appBar: AppBar(title: const Text('页面生命周期')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            '打开覆盖页会产生 Hide/Show；将 macOS App 切到后台再回来会产生 '
            'Background/Foreground。Widget 创建和销毁仍使用 initState/dispose。',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => CCRouter.navigator.push<String>(
              demoDetailIntent(
                id: 88,
                title: '生命周期覆盖页',
                tags: const ['hide', 'show'],
              ),
            ),
            icon: const Icon(Icons.flip_to_front),
            label: const Text('打开 Managed 覆盖页'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Foreign PopupRoute'),
                content: const Text(
                  '它会影响 PageShow/PageHide，但不应销毁 Managed Entry。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('打开系统 Dialog'),
          ),
          const SizedBox(height: 24),
          Text('Mixin 事件', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._localEvents.map((event) => Text('• $event')),
        ],
      ),
    ),
  );
}

CCRouteIntent<void> demoLifecycleIntent() => _DemoLifecyclePageRoute.intent();
