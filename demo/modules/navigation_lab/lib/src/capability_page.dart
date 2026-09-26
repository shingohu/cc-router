import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/material.dart';

import 'component_capabilities.dart';
import 'lab_configuration.dart';
import 'navigation_lab_component.dart';

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.capabilities',
  pattern: CCPathPattern('/lab/capabilities'),
  description: 'Command、Event、初始化任务与 Service 生命周期交互实验页。',
)
final class DemoCapabilitiesPage extends StatefulWidget {
  const DemoCapabilitiesPage({super.key});

  @override
  State<DemoCapabilitiesPage> createState() => _DemoCapabilitiesPageState();
}

final class _DemoCapabilitiesPageState extends State<DemoCapabilitiesPage> {
  String _status = '选择一个场景开始验证';

  void _setStatus(String value) {
    demoNavigationLabStore.record(value);
    if (mounted) setState(() => _status = value);
  }

  Future<void> _run(
    String label,
    FutureOr<Object?> Function() operation,
  ) async {
    _setStatus('$label · 执行中');
    try {
      final result = await operation();
      _setStatus('$label · 完成${result == null ? '' : ' · $result'}');
    } on Object catch (error) {
      _setStatus('$label · ${error.runtimeType}');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('组件能力实验室')),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Text(
            _status,
            key: const ValueKey('capability-status'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              _sectionTitle(context, 'Command'),
              _action(
                Icons.receipt_long_outlined,
                'Command · typed result',
                '单一 Handler 执行一次性操作并返回 String。',
                () => _run(
                  'Command typed result',
                  () => CCRouter.command<String>(
                    const DemoCreateReceiptCommand(88),
                  ),
                ),
              ),
              _action(
                Icons.refresh,
                'Command · void',
                '只等待完成或失败，不制造无意义结果类型。',
                () => _run(
                  'Command void',
                  () => CCRouter.command<void>(const DemoRefreshCacheCommand()),
                ),
              ),
              _action(
                Icons.timer_off_outlined,
                'Command · timeout',
                'Deadline 到期后向 Handler 传播协作取消。',
                () => _run(
                  'Command timeout',
                  () => CCRouter.command<void>(
                    const DemoWaitCommand(),
                    timeout: const Duration(milliseconds: 80),
                  ),
                ),
              ),
              _action(
                Icons.cancel_outlined,
                'Command · caller cancellation',
                '调用方主动取消正在等待的 Command。',
                () => _run('Command cancellation', () async {
                  final token = CCCancellationToken();
                  final pending = CCRouter.command<void>(
                    const DemoWaitCommand(),
                    cancellation: token,
                  );
                  await Future<void>.delayed(const Duration(milliseconds: 20));
                  token.cancel();
                  await pending;
                  return null;
                }),
              ),
              _action(
                Icons.error_outline,
                'Command · Handler error',
                '原始业务异常不进入安全 Trace 字段。',
                () => _run(
                  'Command error',
                  () => CCRouter.command<void>(const DemoFailCommand()),
                ),
              ),
              _sectionTitle(context, 'Event'),
              _action(
                Icons.campaign_outlined,
                'Event · multiple subscribers',
                '并发通知两个订阅者，其中一个失败但不影响发布成功。',
                () => _run(
                  'Event subscribers',
                  () => CCRouter.event(const DemoOrderCompletedEvent(1001)),
                ),
              ),
              _action(
                Icons.notifications_off_outlined,
                'Event · zero subscribers',
                '没有订阅者是可追踪的成功 no-op。',
                () => _run(
                  'Event zero subscribers',
                  () => CCRouter.event(const DemoUnobservedEvent()),
                ),
              ),
              _action(
                Icons.hourglass_bottom,
                'Event · timeout',
                '发布 deadline 会取消仍在等待的 Subscriber。',
                () => _run(
                  'Event timeout',
                  () => CCRouter.event(
                    const DemoSlowEvent(),
                    timeout: const Duration(milliseconds: 80),
                  ),
                ),
              ),
              _sectionTitle(context, 'Initialization DAG'),
              ...CCRouter.initializationTasks.map(
                (task) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.account_tree_outlined),
                  title: Text(task.id),
                  subtitle: Text('${task.gateId} · ${task.failurePolicy.name}'),
                  trailing: Text(task.state.name),
                ),
              ),
              _action(
                Icons.privacy_tip_outlined,
                '打开 Privacy Gate',
                '显式运行依赖基础任务、等待隐私同意的初始化节点。',
                () => _run('Initialization privacy gate', () async {
                  await CCRouter.runInitialization(
                    gate: CCInitializationGate.privacyGranted,
                  );
                  return CCRouter.initializationTasks
                      .firstWhere(
                        (task) =>
                            task.id == DemoInitializationTaskIds.analytics,
                      )
                      .state
                      .name;
                }),
              ),
              _sectionTitle(context, 'Service'),
              _action(
                Icons.apps_outlined,
                'Service · App Singleton',
                '同一 Runtime 重复解析得到同一个实例。',
                () => _run('App Singleton', () {
                  final first = CCRouter.service<DemoAppService>();
                  final second = CCRouter.service<DemoAppService>();
                  return '#${first.instanceId} · same=${identical(first, second)}';
                }),
              ),
              _action(
                Icons.person_outline,
                'Service · Session Singleton',
                '打开 Session 后创建账号级实例。',
                () => _run('Session Singleton', () {
                  if (CCRouter.session == null) {
                    CCRouter.openSession(accountId: 'capability-demo');
                  }
                  final first = CCRouter.service<DemoSessionService>();
                  final second = CCRouter.service<DemoSessionService>();
                  return '#${first.instanceId} · same=${identical(first, second)}';
                }),
              ),
              _action(
                Icons.logout,
                'Service · close Session',
                '关闭 Session，自动取消工作并 dispose 账号级实例。',
                () => _run('Session close', () async {
                  if (CCRouter.session != null) await CCRouter.closeSession();
                  return 'closed';
                }),
              ),
              _action(
                Icons.layers_outlined,
                'Service · Route Singleton',
                '实例绑定当前 Managed RouteEntry，页面 Pop 后自动 dispose。',
                () => _run('Route Singleton', () {
                  final first = CCRouter.routeService<DemoRouteService>(
                    context,
                  );
                  final second = CCRouter.routeService<DemoRouteService>(
                    context,
                  );
                  return '#${first.instanceId} · same=${identical(first, second)}';
                }),
              ),
              _action(
                Icons.copy_all_outlined,
                'Service · Factory',
                '每次解析创建新实例，仍由 App Scope 持有生命周期。',
                () => _run('Factory Service', () {
                  final first = CCRouter.service<DemoFactoryService>();
                  final second = CCRouter.service<DemoFactoryService>();
                  return '#${first.instanceId}/#${second.instanceId} · '
                      'same=${identical(first, second)}';
                }),
              ),
              _action(
                Icons.downloading_outlined,
                'Service · lazy readiness',
                '同步读取不会偷跑 I/O；异步读取 single-flight 初始化。',
                () => _run('Lazy Service', () async {
                  Object? syncError;
                  try {
                    CCRouter.service<DemoLazyService>();
                  } on Object catch (error) {
                    syncError = error;
                  }
                  final services = await Future.wait([
                    CCRouter.serviceAsync<DemoLazyService>(),
                    CCRouter.serviceAsync<DemoLazyService>(),
                  ]);
                  return '${syncError?.runtimeType ?? 'already-ready'} · '
                      'same=${identical(services.first, services.last)} · '
                      'ready=${services.first.ready}';
                }),
              ),
              _action(
                Icons.hub_outlined,
                'Service · multiple implementations',
                '默认实现、命名实现和确定性全量解析。',
                () => _run('Multiple Services', () {
                  final defaultService = CCRouter.service<DemoChannelService>();
                  final backup = CCRouter.service<DemoChannelService>(
                    key: demoBackupChannelKey,
                  );
                  final all = CCRouter.services<DemoChannelService>();
                  return '${defaultService.name}/${backup.name} · '
                      'all=${all.map((item) => item.name).join(',')}';
                }),
              ),
              _action(
                Icons.extension_off_outlined,
                'Service · optional lookup',
                '只有“未注册”转换为 null，生命周期和工厂错误仍抛出。',
                () => _run(
                  'Optional Service',
                  () =>
                      'missing=${CCRouter.serviceOrNull<DemoMissingService>() == null}',
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _sectionTitle(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );

  Widget _action(
    IconData icon,
    String title,
    String subtitle,
    FutureOr<void> Function() onTap,
  ) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    child: ListTile(
      minTileHeight: 72,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => onTap(),
    ),
  );
}
