import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/material.dart';

import 'navigation_lab_component.dart';
import 'shell_contract.dart';
import 'ccrouter_generated/demo_navigation_lab_component.route_api.g.dart';

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.shell.feed',
  pattern: CCPathPattern('/shell/feed'),
  placement: CCRoutePlacement(
    shellId: demoSingleShellId,
    navigatorOutlet: demoSingleShellOutlet,
  ),
  description: 'ShellRoute 共享框架中的内容首页。',
)
final class DemoShellFeedPage extends StatelessWidget {
  const DemoShellFeedPage({super.key});

  @override
  Widget build(BuildContext context) => _ShellPage(
    title: 'Shell Feed',
    icon: Icons.dynamic_feed_outlined,
    body: '该页面位于单一嵌套 Navigator，切换设置页时共享同一个 Shell。',
    actions: [
      FilledButton.icon(
        onPressed: () => unawaited(
          CCRouter.navigator.push<void>(
            DemoNavigationLabRoutes.shellDetail(item: 7),
          ),
        ),
        icon: const Icon(Icons.open_in_new),
        label: const Text('在 Shell Outlet 内打开详情'),
      ),
      OutlinedButton.icon(
        onPressed: () => unawaited(
          CCRouter.navigator.push<void>(
            DemoNavigationLabRoutes.presentationTransparent(),
          ),
        ),
        icon: const Icon(Icons.layers_outlined),
        label: const Text('在 Root Navigator 打开透明页'),
      ),
    ],
  );
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.shell.detail',
  pattern: CCPathPattern('/shell/feed/:item'),
  placement: CCRoutePlacement(
    parentRouteId: 'demo_navigation_lab.shell.feed',
    shellId: demoSingleShellId,
    navigatorOutlet: demoSingleShellOutlet,
  ),
  description: 'ShellRoute 嵌套子路由。',
)
final class DemoShellDetailPage extends StatelessWidget {
  const DemoShellDetailPage({required this.item, super.key});

  final int item;

  @override
  Widget build(BuildContext context) => _ShellPage(
    title: 'Shell Detail #$item',
    icon: Icons.article_outlined,
    body: 'parentRouteId 和 Outlet 都由路由契约声明，页面不读取 GoRouterState。',
    actions: [
      FilledButton.icon(
        onPressed: () => CCRouter.navigator.pop(),
        icon: const Icon(Icons.arrow_back),
        label: const Text('返回 Feed'),
      ),
    ],
  );
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.shell.settings',
  pattern: CCPathPattern('/shell/settings'),
  placement: CCRoutePlacement(
    shellId: demoSingleShellId,
    navigatorOutlet: demoSingleShellOutlet,
  ),
  description: 'ShellRoute 共享框架中的设置页。',
)
final class DemoShellSettingsPage extends StatelessWidget {
  const DemoShellSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => const _ShellPage(
    title: 'Shell Settings',
    icon: Icons.tune,
    body: 'Feed 与 Settings 共用一个嵌套 Navigator 和同一套外层导航。',
  );
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.workspace.home',
  pattern: CCPathPattern('/workspace/home'),
  placement: CCRoutePlacement(
    shellId: demoWorkspaceShellId,
    navigatorOutlet: demoWorkspaceHomeOutlet,
  ),
  description: 'StatefulShellRoute 首页分支。',
)
final class DemoWorkspaceHomePage extends StatelessWidget {
  const DemoWorkspaceHomePage({super.key});

  @override
  Widget build(BuildContext context) => _ShellPage(
    title: 'Workspace Home',
    icon: Icons.home_outlined,
    body: '打开详情后切换到其他分支，再切回来可验证独立 Navigator 历史。',
    actions: [
      FilledButton.icon(
        onPressed: () => unawaited(
          CCRouter.navigator.push<void>(
            DemoNavigationLabRoutes.workspaceDetail(item: 42),
          ),
        ),
        icon: const Icon(Icons.open_in_new),
        label: const Text('打开 Home 分支详情'),
      ),
    ],
  );
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.workspace.detail',
  pattern: CCPathPattern('/workspace/home/:item'),
  deepLink: CCDeepLinkPolicy.enabled,
  placement: CCRoutePlacement(
    parentRouteId: 'demo_navigation_lab.workspace.home',
    shellId: demoWorkspaceShellId,
    navigatorOutlet: demoWorkspaceHomeOutlet,
  ),
  description: 'StatefulShellRoute 首页分支的可 Deep Link 子路由。',
)
final class DemoWorkspaceDetailPage extends StatelessWidget {
  const DemoWorkspaceDetailPage({required this.item, super.key});

  final int item;

  @override
  Widget build(BuildContext context) => _ShellPage(
    title: 'Workspace Detail #$item',
    icon: Icons.description_outlined,
    body: '该页面保留在 Home 分支栈中，不会被 Activity 或 Profile 分支覆盖掉。',
    actions: [
      FilledButton.icon(
        onPressed: () => CCRouter.navigator.pop(),
        icon: const Icon(Icons.arrow_back),
        label: const Text('返回 Home 分支'),
      ),
    ],
  );
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.workspace.activity',
  pattern: CCPathPattern('/workspace/activity'),
  placement: CCRoutePlacement(
    shellId: demoWorkspaceShellId,
    navigatorOutlet: demoWorkspaceActivityOutlet,
  ),
  description: 'StatefulShellRoute 活动分支。',
)
final class DemoWorkspaceActivityPage extends StatefulWidget {
  const DemoWorkspaceActivityPage({super.key});

  @override
  State<DemoWorkspaceActivityPage> createState() =>
      _DemoWorkspaceActivityPageState();
}

final class _DemoWorkspaceActivityPageState
    extends State<DemoWorkspaceActivityPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => _ShellPage(
    title: 'Workspace Activity',
    icon: Icons.notifications_none,
    body: '本地计数：$_count。切换分支后 State 应保持。',
    actions: [
      FilledButton.icon(
        onPressed: () => setState(() => _count++),
        icon: const Icon(Icons.add),
        label: const Text('增加分支内状态'),
      ),
    ],
  );
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.workspace.profile',
  pattern: CCPathPattern('/workspace/profile'),
  placement: CCRoutePlacement(
    shellId: demoWorkspaceShellId,
    navigatorOutlet: demoWorkspaceProfileOutlet,
  ),
  description: 'StatefulShellRoute 个人分支。',
)
final class DemoWorkspaceProfilePage extends StatelessWidget {
  const DemoWorkspaceProfilePage({super.key});

  @override
  Widget build(BuildContext context) => const _ShellPage(
    title: 'Workspace Profile',
    icon: Icons.person_outline,
    body: '三个 Outlet 具有独立 Navigator key、Observer、RouteEntry 可见性和历史。',
  );
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.extra',
  pattern: CCPathPattern('/lab/extra'),
  description: '展示仅在进程内传递的类型安全 Extra 对象。',
)
final class DemoExtraPage extends StatelessWidget {
  const DemoExtraPage(@CCExtraParam() this.payload, {super.key});

  final DemoExtraPayload payload;

  @override
  Widget build(BuildContext context) => _ShellPage(
    title: 'Typed Extra',
    icon: Icons.data_object,
    body:
        'owner=${payload.owner} · revision=${payload.revision}\n'
        'Extra 不进入 URL，不用于外部 Deep Link 或状态恢复。',
    actions: [
      FilledButton.icon(
        onPressed: () => CCRouter.navigator.pop(),
        icon: const Icon(Icons.close),
        label: const Text('关闭'),
      ),
    ],
  );
}

final class _ShellPage extends StatelessWidget {
  const _ShellPage({
    required this.title,
    required this.icon,
    required this.body,
    this.actions = const [],
  });

  final String title;
  final IconData icon;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 64),
              const SizedBox(height: 20),
              Text(body, textAlign: TextAlign.center),
              if (actions.isNotEmpty) const SizedBox(height: 24),
              ...actions.map(
                (action) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: action,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

CCRouteIntent<void> demoShellFeedIntent() =>
    DemoNavigationLabRoutes.shellFeed();
CCRouteIntent<void> demoShellSettingsIntent() =>
    DemoNavigationLabRoutes.shellSettings();
CCRouteIntent<void> demoWorkspaceHomeIntent() =>
    DemoNavigationLabRoutes.workspaceHome();
CCRouteIntent<void> demoWorkspaceActivityIntent() =>
    DemoNavigationLabRoutes.workspaceActivity();
CCRouteIntent<void> demoWorkspaceProfileIntent() =>
    DemoNavigationLabRoutes.workspaceProfile();
