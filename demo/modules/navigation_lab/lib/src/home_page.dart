import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';
import 'package:demo_web_contracts/demo_web_contracts.dart';
import 'package:flutter/material.dart';

import 'lab_configuration.dart';
import 'component_capabilities.dart';
import 'navigation_lab_component.dart';
import 'order_summary_service_proxy.dart';
import 'shell_contract.dart';
import 'ccrouter_generated/component/demo_navigation_lab_component.route_api.g.dart';

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.home',
  pattern: CCPathPattern('/'),
  presentation: CCPagePresentation(transition: CCPageTransitionType.none),
  description: 'CCRouter 全功能交互验证首页。',
)
final class DemoNavigationHomePage extends StatefulWidget {
  const DemoNavigationHomePage({super.key});

  @override
  State<DemoNavigationHomePage> createState() => _DemoNavigationHomePageState();
}

final class _DemoNavigationHomePageState extends State<DemoNavigationHomePage>
    with CCPageLifecycleMixin<DemoNavigationHomePage> {
  static const OrderSummaryService _orderSummaryService =
      OrderSummaryServiceProxy();

  int _section = 0;
  String _status = 'Ready · 选择一个场景开始验证';
  OverlayEntry? _overlayEntry;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _destinations = <_LabDestination>[
    _LabDestination('总览', Icons.dashboard_outlined),
    _LabDestination('导航', Icons.route_outlined),
    _LabDestination('策略', Icons.policy_outlined),
    _LabDestination('展示', Icons.layers_outlined),
    _LabDestination('生命周期', Icons.sync_alt),
    _LabDestination('诊断', Icons.monitor_heart_outlined),
  ];

  @override
  void onPageShow() => demoNavigationLabStore.record('Home onPageShow');

  @override
  void onPageHide() => demoNavigationLabStore.record('Home onPageHide');

  @override
  void onForeground() => demoNavigationLabStore.record('Home onForeground');

  @override
  void onBackground() => demoNavigationLabStore.record('Home onBackground');

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _setStatus(String value) {
    demoNavigationLabStore.record(value);
    if (mounted) setState(() => _status = value);
  }

  Future<void> _run(String label, Future<Object?> Function() operation) async {
    _setStatus('$label · 执行中');
    try {
      final result = await operation();
      _setStatus('$label · 完成${result == null ? '' : ' · $result'}');
    } on Object catch (error) {
      _setStatus('$label · ${error.runtimeType}');
    }
  }

  void _openDeferred() {
    _setStatus('Defer · 等待外部恢复');
    unawaited(
      CCRouter.navigator
          .push<void>(
            DemoNavigationLabRoutes.defer(),
            source: const CCNavigationSource.feature('policies.defer'),
          )
          .then((_) => _setStatus('Defer · 已完成'))
          .catchError((Object error) {
            _setStatus('Defer · ${error.runtimeType}');
          }),
    );
  }

  Future<void> _resumeDeferred() async {
    final pending = CCRouter.pendingNavigations;
    if (pending.isEmpty) {
      _setStatus('当前没有 Pending Navigation');
      return;
    }
    demoNavigationLabStore.allowDeferredOnce = true;
    await _run(
      '恢复 Pending Navigation',
      () => CCRouter.resumePendingNavigation(pending.first.navigationId),
    );
  }

  void _showOverlay(BuildContext context) {
    if (_overlayEntry != null) {
      _removeOverlay();
      _setStatus('Foreign OverlayEntry 已移除');
      return;
    }
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        top: 88,
        right: 24,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          color: const Color(0xFFFFF3CD),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.layers_outlined),
                const SizedBox(width: 10),
                const Text('Overlay 不进入 Navigator 栈'),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '关闭 Overlay',
                  onPressed: () => _showOverlay(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    _overlayEntry = entry;
    overlay.insert(entry);
    _setStatus('Foreign OverlayEntry 已显示，Managed 栈不应变化');
  }

  void _removeOverlay() {
    final entry = _overlayEntry;
    if (entry == null) return;
    entry.remove();
    entry.dispose();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 880;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.circle, size: 10, color: Colors.green.shade600),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _status,
                  key: const ValueKey('demo-status'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${CCRouter.activeRouteEntries.length} Route Entries'),
            ],
          ),
        ),
        Expanded(child: _buildSection(context)),
      ],
    );
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hub_outlined),
            SizedBox(width: 10),
            Text('CCRouter Lab'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '清空演示日志',
            onPressed: demoNavigationLabStore.clear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _section,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (value) =>
                      setState(() => _section = value),
                  destinations: _destinations
                      .map(
                        (item) => NavigationRailDestination(
                          icon: Icon(item.icon),
                          label: Text(item.label),
                        ),
                      )
                      .toList(),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _section,
              onDestinationSelected: (value) =>
                  setState(() => _section = value),
              destinations: _destinations
                  .map(
                    (item) => NavigationDestination(
                      icon: Icon(item.icon),
                      label: item.label,
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _buildSection(BuildContext context) => switch (_section) {
    0 => _overview(context),
    1 => _navigation(context),
    2 => _policies(context),
    3 => _presentation(context),
    4 => _lifecycle(context),
    _ => _diagnostics(context),
  };

  Widget _page(String title, String subtitle, List<Widget> children) =>
      ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(subtitle),
          const SizedBox(height: 20),
          ...children,
        ],
      );

  Widget _overview(BuildContext context) => AnimatedBuilder(
    animation: demoNavigationLabStore,
    builder: (context, _) => _page('运行总览', '真实 Runtime、组件、Session 与跨组件契约状态。', [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _Metric(
            label: 'Components',
            value: '${CCRouter.registeredComponents.length}',
            icon: Icons.extension_outlined,
          ),
          _Metric(
            label: 'Session',
            value: CCRouter.session == null ? 'Closed' : 'Open',
            icon: Icons.person_outline,
          ),
          _Metric(
            label: 'Route Entries',
            value: '${CCRouter.activeRouteEntries.length}',
            icon: Icons.layers_outlined,
          ),
          _Metric(
            label: 'Backend Entries',
            value: '${CCRouter.activeBackendEntries.length}',
            icon: Icons.account_tree_outlined,
          ),
        ],
      ),
      const SizedBox(height: 20),
      _ActionTile(
        icon: CCRouter.session == null ? Icons.login : Icons.logout,
        title: CCRouter.session == null ? '开启账号 Session' : '关闭账号 Session',
        subtitle: '验证账号级 Scope 只在登录/登出边界创建和销毁。',
        onTap: () async {
          if (CCRouter.session == null) {
            CCRouter.openSession(accountId: 'demo-account');
            _setStatus('Session 已开启');
          } else {
            await CCRouter.closeSession();
            _setStatus('Session 已关闭');
          }
        },
      ),
      _ActionTile(
        icon: Icons.receipt_long_outlined,
        title: '打开订单组件公开契约',
        subtitle: '宿主只依赖 demo_order_contracts，不引用订单页面实现。',
        onTap: () => _run(
          '跨组件订单路由',
          () => CCRouter.navigator.push<String>(
            OrderDetailRoute.intent(orderId: 100, tab: 'routing-lab'),
            source: const CCNavigationSource.feature('overview.order'),
          ),
        ),
      ),
      _ActionTile(
        icon: Icons.data_object,
        title: '解析订单组件 Service Contract',
        subtitle: '强类型 Proxy 验证跨组件调用、来源归属和 Trace。',
        onTap: () {
          final summary = _orderSummaryService.summaryFor(2048);
          _setStatus('Service 返回 · $summary');
        },
      ),
      _ActionTile(
        icon: Icons.memory_outlined,
        title: '打开组件能力实验室',
        subtitle: 'Command、Event、InitTask 与完整 Service 生命周期示例。',
        onTap: () => _run(
          '组件能力实验室',
          () => CCRouter.navigator.push<void>(
            DemoNavigationLabRoutes.capabilities(),
          ),
        ),
      ),
    ]),
  );

  Widget _navigation(
    BuildContext context,
  ) => _page('导航操作', '类型安全调用、动态地址、多 Path、返回值和栈变换。', [
    _ActionTile(
      icon: Icons.arrow_forward,
      title: 'Push + typed result',
      subtitle: 'int/List<String> 参数由生成 Codec 编解码。',
      onTap: () => _run(
        'Push typed detail',
        () => CCRouter.navigator.push<String>(
          DemoNavigationLabRoutes.detail(
            id: 42,
            tags: const ['typed', 'query', 'result'],
          ),
          source: const CCNavigationSource.feature('navigation.typed'),
        ),
      ),
    ),
    _ActionTile(
      icon: Icons.link,
      title: 'Open Path alias',
      subtitle: '/lab/item/43 与主 Path 指向同一页面。应用内 Open 默认 Push。',
      onTap: () => _run(
        'Open path alias',
        () => CCRouter.navigator.open(
          Uri.parse('/lab/item/43?title=Path%20Alias&tags=alias&tags=dynamic'),
          source: const CCNavigationSource.feature('navigation.path_alias'),
        ),
      ),
    ),
    _ActionTile(
      icon: Icons.public,
      title: 'Open custom scheme',
      subtitle: '应用内 URI 导航，不会标记为 external origin。',
      onTap: () => _run(
        'Open custom scheme',
        () => CCRouter.navigator.open(
          Uri.parse('ccrouter://lab/detail/44?title=Custom%20Scheme&tags=uri'),
          source: const CCNavigationSource.deepLink('navigation.scheme_demo'),
        ),
      ),
    ),
    _ActionTile(
      icon: Icons.input,
      title: '模拟外部 Deep Link',
      subtitle: '默认 Push，保留当前页面和返回路径，并执行 Deep Link Policy。',
      onTap: () => _run(
        'External Deep Link',
        () => CCDeepLinkIngress.fromPlatform(
          Uri.parse(
            'ccrouter://lab/detail/46?title=Simulated%20External%20Deep%20Link'
            '&tags=external&tags=platform',
          ),
          source: const CCNavigationSource.deepLink(
            DemoNavigationSourceIds.simulatedExternal,
          ),
        ),
      ),
    ),
    _ActionTile(
      icon: Icons.alt_route,
      title: '模拟外部 Deep Link · Go',
      subtitle: '声明式切换 location，适合重建 Shell 或切换 Tab。',
      onTap: () => _run(
        'External Deep Link · Go',
        () => CCDeepLinkIngress.fromPlatform(
          Uri.parse(
            'ccrouter://lab/detail/47?title=External%20Deep%20Link%20Go'
            '&tags=external&tags=go',
          ),
          mode: CCDeepLinkOpenMode.go,
          source: const CCNavigationSource.deepLink(
            DemoNavigationSourceIds.simulatedExternalGo,
          ),
        ),
      ),
    ),
    _ActionTile(
      icon: Icons.language,
      title: 'Open full URL',
      subtitle: 'https://ccrouter.example/lab/detail/45。',
      onTap: () => _run(
        'Open full URL',
        () => CCRouter.navigator.open(
          Uri.parse(
            'https://ccrouter.example/lab/detail/45?title=Full%20URL&tags=https',
          ),
        ),
      ),
    ),
    _ActionTile(
      icon: Icons.travel_explore,
      title: '模拟外部 HTTPS Web Link',
      subtitle: 'Host allowlist mapper 将标准网页 URL 转成公开 Web 路由。',
      onTap: () {
        final mapped = demoMapExternalWebUri(
          Uri.parse(
            'https://docs.flutter.dev/ui/navigation?source=ccrouter-demo',
          ),
        );
        return _run(
          'External HTTPS Web Link',
          () => CCDeepLinkIngress.fromPlatform(
            mapped!,
            source: const CCNavigationSource.deepLink('platform.web_link'),
          ),
        );
      },
    ),
    _ActionTile(
      icon: Icons.view_stream_outlined,
      title: '进入栈操作工作台',
      subtitle: 'Push、Replace、Pop、Go、Reset 与返回结果。',
      onTap: () => _run(
        'Stack workbench',
        () => CCRouter.navigator.push<String>(
          DemoNavigationLabRoutes.stack(level: 1, returnsResult: true),
        ),
      ),
    ),
    _ActionTile(
      icon: Icons.web_asset_outlined,
      title: '进入 ShellRoute',
      subtitle: '共享 Scaffold、单嵌套 Navigator、Shell 内详情与 Root 页面。',
      onTap: () => _run('ShellRoute', () async {
        await CCRouter.navigator.go(DemoNavigationLabRoutes.shellFeed());
        return null;
      }),
    ),
    _ActionTile(
      icon: Icons.space_dashboard_outlined,
      title: '进入 StatefulShellRoute',
      subtitle: '三个持久 Outlet、独立历史和分支内 State。',
      onTap: () => _run('StatefulShellRoute', () async {
        await CCRouter.navigator.go(DemoNavigationLabRoutes.workspaceHome());
        return null;
      }),
    ),
    _ActionTile(
      icon: Icons.data_object,
      title: '打开 Typed Extra',
      subtitle: '复杂对象只在进程内传递，不写入 URL 或诊断记录。',
      onTap: () => _run(
        'Typed Extra',
        () => CCRouter.navigator.push<void>(
          DemoNavigationLabRoutes.extra(
            payload: const DemoExtraPayload(
              owner: 'navigation_lab',
              revision: 3,
            ),
          ),
        ),
      ),
    ),
    _ActionTile(
      icon: Icons.public,
      title: '打开公开 Web 容器',
      subtitle: 'Allowlist HTTPS URL 通过 Query Codec 序列化，可用于 Deep Link。',
      onTap: () => _run(
        'Public Web',
        () => CCRouter.navigator.push<void>(
          DemoPublicWebRoute.intent(
            target: DemoPublicWebTarget(
              Uri.parse('https://docs.flutter.dev/ui/navigation'),
            ),
          ),
          source: const CCNavigationSource.feature('navigation.public_web'),
        ),
      ),
    ),
    _ActionTile(
      icon: Icons.lock_outline,
      title: '打开私密 Web 容器',
      subtitle: 'URL、Header 和 JavaScript policy 通过 Extra 传递，不写入路由 URI。',
      onTap: () => _run(
        'Private Web',
        () => CCRouter.navigator.push<void>(
          DemoPrivateWebRoute.intent(
            request: DemoPrivateWebRequest(
              uri: Uri.parse('https://example.com/private'),
              headers: const {'X-Demo-Session': 'runtime-only'},
            ),
          ),
          source: const CCNavigationSource.feature('navigation.private_web'),
        ),
      ),
    ),
    _ActionTile(
      icon: Icons.home_work_outlined,
      title: 'Go 到栈页',
      subtitle: '验证声明式 location 替换；栈页可通过 Open / 回退恢复首页。',
      onTap: () => _run('Go', () async {
        await CCRouter.navigator.go(DemoNavigationLabRoutes.stack(level: 10));
        return null;
      }),
    ),
    _ActionTile(
      icon: Icons.restart_alt,
      title: 'Reset 到栈页',
      subtitle: '将 Managed 导航状态重置为单一目标。',
      onTap: () => _run('Reset', () async {
        await CCRouter.navigator.reset(
          DemoNavigationLabRoutes.stack(level: 20),
        );
        return null;
      }),
    ),
  ]);

  Widget _policies(BuildContext context) => AnimatedBuilder(
    animation: demoNavigationLabStore,
    builder: (context, _) => _page(
      '策略与失败',
      'Global / Route Interceptor、Redirect、Defer、Timeout、PopGuard 与兜底。',
      [
        SwitchListTile(
          value: demoNavigationLabStore.blockDetailGlobally,
          onChanged: demoNavigationLabStore.setBlockDetailGlobally,
          title: const Text('全局阻止 Detail Route'),
          subtitle: const Text('打开后，任意 Detail 请求在 Adapter 前被取消。'),
        ),
        _ActionTile(
          icon: Icons.verified_outlined,
          title: 'Route Interceptor · Proceed',
          subtitle: '先执行 Global，再执行 Route interceptor。',
          onTap: () => _run(
            'Proceed interceptor',
            () => CCRouter.navigator.push<void>(
              DemoNavigationLabRoutes.proceed(),
            ),
          ),
        ),
        _ActionTile(
          icon: Icons.block,
          title: 'Route Interceptor · Cancel',
          subtitle: '返回标准 CCRouteCancelledError，页面不会创建。',
          onTap: () => _run(
            'Cancel interceptor',
            () =>
                CCRouter.navigator.push<void>(DemoNavigationLabRoutes.cancel()),
          ),
        ),
        _ActionTile(
          icon: Icons.alt_route,
          title: 'Route Interceptor · Redirect',
          subtitle: '保留 navigationId/source/redirect chain 后进入目标页。',
          onTap: () => _run(
            'Redirect interceptor',
            () => CCRouter.navigator.push<void>(
              DemoNavigationLabRoutes.redirectSource(),
            ),
          ),
        ),
        _ActionTile(
          icon: Icons.pause_circle_outline,
          title: 'Defer Navigation',
          subtitle: '创建 Pending Navigation，模拟等待登录、授权或同意。',
          onTap: _openDeferred,
        ),
        _ActionTile(
          icon: Icons.play_circle_outline,
          title: '恢复第一个 Pending Navigation',
          subtitle: '当前 pending: ${CCRouter.pendingNavigations.length}',
          onTap: _resumeDeferred,
        ),
        _ActionTile(
          icon: Icons.timer_off_outlined,
          title: 'Interceptor Timeout',
          subtitle: '180ms deadline 触发失败，异步任务需协作取消。',
          onTap: () => _run(
            'Timeout interceptor',
            () => CCRouter.navigator.push<void>(
              DemoNavigationLabRoutes.timeout(),
            ),
          ),
        ),
        _ActionTile(
          icon: Icons.edit_note,
          title: 'PopGuard 未保存表单',
          subtitle: '通过 CCRouter maybePop 返回时同步拒绝或放行。',
          onTap: () {
            demoNavigationLabStore.setDirtyForm(true);
            return _run(
              'PopGuard route',
              () => CCRouter.navigator.push<void>(
                DemoNavigationLabRoutes.guarded(),
              ),
            );
          },
        ),
        _ActionTile(
          icon: Icons.question_mark,
          title: '打开不存在的路由',
          subtitle: 'Failure Policy 将 resolution failure 恢复到安全兜底页。',
          onTap: () => _run(
            'Failure fallback',
            () => CCRouter.navigator.open(Uri.parse('/lab/not-found')),
          ),
        ),
      ],
    ),
  );

  Widget _presentation(BuildContext context) => _page(
    '展示与混合导航',
    '普通 Page 动画、透明页、Managed Modal，以及不会污染 Managed 栈的 Foreign UI。',
    [
      _ActionTile(
        icon: Icons.blur_on,
        title: 'Fade Page',
        subtitle: 'CCPageTransitionType.fade',
        onTap: () => CCRouter.navigator.push<void>(
          DemoNavigationLabRoutes.presentationFade(),
        ),
      ),
      _ActionTile(
        icon: Icons.zoom_out_map,
        title: 'Scale Page',
        subtitle: 'CCPageTransitionType.scale',
        onTap: () => CCRouter.navigator.push<void>(
          DemoNavigationLabRoutes.presentationScale(),
        ),
      ),
      _ActionTile(
        icon: Icons.phone_iphone,
        title: 'Cupertino PageRoute',
        subtitle: '显式 Cupertino route family。',
        onTap: () => CCRouter.navigator.push<void>(
          DemoNavigationLabRoutes.presentationCupertino(),
        ),
      ),
      _ActionTile(
        icon: Icons.vertical_align_top,
        title: '全屏页面从底部滑入',
        subtitle: '普通 Page，不是 BottomSheet。',
        onTap: () => CCRouter.navigator.push<void>(
          DemoNavigationLabRoutes.presentationBottomPage(),
        ),
      ),
      _ActionTile(
        icon: Icons.image_outlined,
        title: '透明全屏海报页',
        subtitle: 'opaque=false + slideFromBottom。',
        onTap: () => CCRouter.navigator.push<void>(
          DemoNavigationLabRoutes.presentationTransparent(),
        ),
      ),
      _ActionTile(
        icon: Icons.chat_bubble_outline,
        title: 'Managed Dialog Route',
        subtitle: '具备 typed result 与完整 RouteEntry 生命周期。',
        onTap: () => _run(
          'Managed Dialog',
          () => CCRouter.navigator.push<String>(
            DemoNavigationLabRoutes.presentationDialog(),
          ),
        ),
      ),
      _ActionTile(
        icon: Icons.call_to_action_outlined,
        title: 'Managed BottomSheet Route',
        subtitle: '拖拽/Barrier/Pop 都应精确关闭自身。',
        onTap: () => _run(
          'Managed BottomSheet',
          () => CCRouter.navigator.push<String>(
            DemoNavigationLabRoutes.presentationSheet(),
          ),
        ),
      ),
      const Divider(height: 32),
      _ActionTile(
        icon: Icons.open_in_new,
        title: 'Foreign Navigator.push',
        subtitle: '系统 MaterialPageRoute，不应创建或误删 CCRouter RouteEntry。',
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const _ForeignPage()),
        ),
      ),
      _ActionTile(
        icon: Icons.message_outlined,
        title: 'Foreign showDialog',
        subtitle: 'PopupRoute 的 Pop 不应移除底层 Managed Entry。',
        onTap: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('系统 Dialog'),
            content: const Text('这是 Foreign PopupRoute。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      ),
      _ActionTile(
        icon: Icons.expand_less,
        title: 'Foreign showModalBottomSheet',
        subtitle: '由 Flutter API 创建，不经过 CCRouter。',
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => Padding(
            padding: const EdgeInsets.all(24),
            child: FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('关闭 Foreign BottomSheet'),
            ),
          ),
        ),
      ),
      _ActionTile(
        icon: Icons.layers,
        title: 'Toggle OverlayEntry',
        subtitle: 'Overlay 不走 NavigatorObserver，Managed 栈必须保持不变。',
        onTap: () => _showOverlay(context),
      ),
      _ActionTile(
        icon: Icons.view_agenda_outlined,
        title: 'Scaffold LocalHistory BottomSheet',
        subtitle: 'maybePop 可消费 LocalHistoryEntry，但不得误删 Managed Entry。',
        onTap: () {
          _scaffoldKey.currentState?.showBottomSheet(
            (sheetContext) => Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Expanded(child: Text('Persistent BottomSheet')),
                    FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              ),
            ),
          );
          _setStatus('LocalHistoryEntry BottomSheet 已打开');
        },
      ),
    ],
  );

  Widget _lifecycle(BuildContext context) =>
      _page('生命周期', '区分 Widget、PageRoute 当前状态、Managed RouteEntry 与 App 前后台。', [
        _ActionTile(
          icon: Icons.sync_alt,
          title: '打开生命周期实验页',
          subtitle: '同时使用 CCPageLifecycleMixin 与 CCPageLifecycleListener。',
          onTap: () => CCRouter.navigator.push<void>(
            DemoNavigationLabRoutes.lifecycle(),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'macOS 实机步骤：进入实验页 → 打开覆盖页 → 返回 → 切换到其他 App → '
          '回到 Demo。诊断日志应依次出现 Hide/Show 与 Background/Foreground。',
        ),
      ]);

  Widget _diagnostics(BuildContext context) => AnimatedBuilder(
    animation: demoNavigationLabStore,
    builder: (context, _) {
      final routeEntries = CCRouter.activeRouteEntries.reversed.toList();
      final backendEntries = CCRouter.activeBackendEntries.reversed.toList();
      return _page('实时诊断', '所有数据均来自公开的只读快照；不会展示 arguments、extra 或账号敏感信息。', [
        Text(
          'Managed Route Entries',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (routeEntries.isEmpty) const Text('暂无 Managed Entry'),
        ...routeEntries.map(
          (entry) => ListTile(
            dense: true,
            leading: const Icon(Icons.route),
            title: Text(entry.routeId),
            subtitle: Text(
              '${entry.lifecycleState.name} · '
              '${entry.hostId}/${entry.placement.navigatorOutlet}',
            ),
          ),
        ),
        const Divider(height: 32),
        Text('Backend Entries', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (backendEntries.isEmpty) const Text('暂无 Backend Entry'),
        ...backendEntries.map(
          (entry) => ListTile(
            dense: true,
            leading: Icon(
              entry.owner == CCBackendEntryOwner.managed
                  ? Icons.check_circle_outline
                  : Icons.extension_outlined,
            ),
            title: Text(
              entry.routeId ?? entry.address.routePattern ?? 'opaque',
            ),
            subtitle: Text(
              '${entry.owner.name} · ${entry.lifecycleState.name}',
            ),
          ),
        ),
        const Divider(height: 32),
        Row(
          children: [
            Expanded(
              child: Text(
                'Aspect / Interceptor Timeline',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: demoNavigationLabStore.clear,
              icon: const Icon(Icons.clear_all),
              label: const Text('清空'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (demoNavigationLabStore.events.isEmpty) const Text('暂无事件'),
        ...demoNavigationLabStore.events.map(
          (event) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: SelectableText(
              event,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
      ]);
    },
  );
}

final class _LabDestination {
  const _LabDestination(this.label, this.icon);

  final String label;
  final IconData icon;
}

final class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 180,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon),
        const SizedBox(height: 16),
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        Text(label),
      ],
    ),
  );
}

final class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final FutureOr<void> Function() onTap;

  @override
  Widget build(BuildContext context) => Card(
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

final class _ForeignPage extends StatelessWidget {
  const _ForeignPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Foreign MaterialPageRoute')),
    body: const Center(child: Text('该页面由 Navigator.push 创建，不属于 CCRouter。')),
  );
}

CCRouteIntent<void> demoHomeIntent() => DemoNavigationLabRoutes.home();
