import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_demo/ccrouter_generated/ccrouter_host.routes.g.dart';
import 'package:ccrouter_demo/main.dart';
import 'package:demo_navigation_lab/demo_navigation_lab.dart';
import 'package:demo_web_contracts/demo_web_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    demoNavigationLabStore
      ..blockDetailGlobally = false
      ..dirtyForm = true
      ..allowDeferredOnce = false
      ..clear();
    CCRouter.initialize(
      components: ccrouterGeneratedComponentManifests,
      globalInterceptors: const [
        CCGlobalNavigationInterceptor(
          id: 'demo.global.policy',
          interceptor: DemoGlobalNavigationInterceptor(),
        ),
      ],
      navigationFailurePolicy: const DemoNavigationFailurePolicy(),
      navigationAspects: [demoNavigationAspect],
      telemetryContextProvider: const DemoNavigationTelemetryProvider(),
    );
  });

  tearDown(CCRouter.shutdown);

  testWidgets('runs typed navigation, result and cross-component route', (
    tester,
  ) async {
    await _pumpDemo(tester);

    expect(find.text('CCRouter Lab'), findsOneWidget);
    expect(find.text('运行总览'), findsOneWidget);
    expect(find.text('4'), findsWidgets);

    await tester.tap(find.text('导航'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push + typed result'));
    await tester.pumpAndSettle();

    expect(find.text('类型安全详情'), findsOneWidget);
    expect(find.text('ID 42'), findsOneWidget);
    expect(find.text('typed'), findsOneWidget);
    await tester.tap(find.text('确认并返回类型安全结果'));
    await tester.pumpAndSettle();

    expect(find.textContaining('detail:42:confirmed'), findsOneWidget);

    await tester.tap(find.text('总览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开订单组件公开契约'));
    await tester.pumpAndSettle();
    expect(find.text('订单 #100'), findsOneWidget);
    expect(find.text('当前标签：routing-lab'), findsOneWidget);
    await tester.tap(find.text('确认订单'));
    await tester.pumpAndSettle();
    expect(find.textContaining('confirmed:100'), findsOneWidget);

    await _unmountDemo(tester);
  });

  testWidgets('dynamic URI Pop releases its managed Route Entry', (
    tester,
  ) async {
    await _pumpDemo(tester);

    expect(CCRouter.activeBackendEntries, hasLength(1));
    await tester.tap(find.text('导航'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open custom scheme'));
    await tester.pumpAndSettle();

    expect(find.text('Custom Scheme'), findsOneWidget);
    expect(
      CCRouter.activeRouteEntries
          .where((entry) => entry.routeId == 'demo_navigation_lab.detail')
          .length,
      1,
    );

    await tester.tap(find.text('确认并返回类型安全结果'));
    await tester.pumpAndSettle();

    expect(find.text('CCRouter Lab'), findsOneWidget);
    expect(CCRouter.activeRouteEntries, isEmpty);
    expect(
      demoNavigationLabStore.events.any(
        (event) =>
            event.contains('Aspect removed · demo_navigation_lab.detail'),
      ),
      isTrue,
    );
    expect(
      demoNavigationLabStore.events.any(
        (event) =>
            event.contains('Aspect disposed · demo_navigation_lab.detail'),
      ),
      isTrue,
    );

    await _unmountDemo(tester);
  });

  testWidgets('simulated external Deep Link preserves platform origin', (
    tester,
  ) async {
    await _pumpDemo(tester);
    await tester.tap(find.text('导航'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('模拟外部 Deep Link'));
    await tester.pumpAndSettle();

    expect(find.text('Simulated External Deep Link'), findsOneWidget);
    expect(find.text('ID 46'), findsOneWidget);
    expect(
      CCRouter.activeRouteEntries.last.origin,
      CCNavigationOrigin.externalPlatform,
    );
    expect(
      demoNavigationLabStore.events.any(
        (event) => event.contains('source=demo.simulated_external'),
      ),
      isTrue,
    );

    await _unmountDemo(tester);
  });

  testWidgets('platform link stream handles a cold-start URI after attach', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      CCRouterDemoApp(
        platformLinkStream: Stream<Uri>.value(
          Uri.parse(
            'ccrouter://lab/detail/88?title=macOS%20External%20Deep%20Link'
            '&tags=terminal&tags=app-links',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('macOS External Deep Link'), findsOneWidget);
    expect(find.text('ID 88'), findsOneWidget);
    expect(
      CCRouter.activeRouteEntries.last.origin,
      CCNavigationOrigin.externalPlatform,
    );
    expect(
      demoNavigationLabStore.events.any(
        (event) => event.contains('Platform Deep Link dispatch complete'),
      ),
      isTrue,
    );

    await _unmountDemo(tester);
  });

  testWidgets('public Web route serializes a validated URL', (tester) async {
    await _pumpDemo(tester);
    await tester.tap(find.text('导航'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('打开公开 Web 容器'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('打开公开 Web 容器'));
    await tester.pumpAndSettle();

    expect(find.text('公开 Web 页面'), findsOneWidget);
    expect(find.text('docs.flutter.dev'), findsWidgets);
    expect(find.text('WebView 平台未加载，但路由参数已验证'), findsOneWidget);
    expect(CCRouter.activeRouteEntries.last.routeId, DemoPublicWebRoute.id);
    expect(
      CCRouter.activeRouteEntries.last.normalizedUri.queryParameters['url'],
      'https://docs.flutter.dev/ui/navigation',
    );
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('CCRouter Lab'), findsOneWidget);
    expect(
      CCRouter.activeRouteEntries.any(
        (entry) => entry.routeId == DemoPublicWebRoute.id,
      ),
      isFalse,
    );

    await _unmountDemo(tester);
  });

  testWidgets('private Web route keeps URL and headers out of its URI', (
    tester,
  ) async {
    await _pumpDemo(tester);
    await tester.tap(find.text('导航'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('打开私密 Web 容器'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('打开私密 Web 容器'));
    await tester.pumpAndSettle();

    expect(find.text('私密 Web 页面'), findsOneWidget);
    expect(find.text('Header names: X-Demo-Session'), findsOneWidget);
    expect(find.textContaining('runtime-only'), findsNothing);
    expect(CCRouter.activeRouteEntries.last.routeId, DemoPrivateWebRoute.id);
    expect(
      CCRouter.activeRouteEntries.last.normalizedUri.toString(),
      '/web/private',
    );
    expect(
      CCRouter.activeRouteEntries.last.normalizedUri.toString(),
      isNot(contains('runtime-only')),
    );

    await _unmountDemo(tester);
  });

  testWidgets('allowlisted HTTPS platform link opens the public Web route', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      CCRouterDemoApp(
        platformLinkStream: Stream<Uri>.value(
          Uri.parse('https://docs.flutter.dev/ui/navigation?source=ccrouter'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(CCRouter.activeRouteEntries.last.routeId, DemoPublicWebRoute.id);
    expect(
      CCRouter.activeRouteEntries.last.origin,
      CCNavigationOrigin.externalPlatform,
    );
    expect(
      demoNavigationLabStore.events.any(
        (event) => event.contains('source=platform.web_link'),
      ),
      isTrue,
    );
    expect(CCRouter.navigator.canPop(), isFalse);
    expect(find.byTooltip('返回'), findsNothing);

    await _unmountDemo(tester);
  });

  test('public Web mapper rejects unsafe and unowned URLs', () {
    expect(
      demoMapExternalWebUri(Uri.parse('https://docs.flutter.dev/ui')),
      isNotNull,
    );
    expect(
      demoMapExternalWebUri(Uri.parse('http://docs.flutter.dev/ui')),
      isNull,
    );
    expect(
      demoMapExternalWebUri(Uri.parse('https://attacker.example/ui')),
      isNull,
    );
    expect(
      demoMapExternalWebUri(
        Uri.parse('https://user:secret@docs.flutter.dev/ui'),
      ),
      isNull,
    );
    expect(
      demoMapExternalWebUri(Uri.parse('https://docs.flutter.dev:8443/ui')),
      isNull,
    );
    expect(
      () => DemoPublicWebTarget(Uri.parse('javascript:alert(1)')),
      throwsArgumentError,
    );
  });

  testWidgets('runs interceptor cancel, redirect and deferred resume', (
    tester,
  ) async {
    await _pumpDemo(tester);
    await tester.tap(find.text('策略'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Route Interceptor · Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CCRouteCancelledError'), findsWidgets);
    expect(find.text('不应到达的页面'), findsNothing);

    await tester.tap(find.text('Route Interceptor · Redirect'));
    await tester.pumpAndSettle();
    expect(find.text('已重定向到目标页'), findsWidgets);
    await tester.tap(find.text('返回实验台'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Defer Navigation'));
    await tester.tap(find.text('Defer Navigation'));
    await tester.pump();
    expect(CCRouter.pendingNavigations, hasLength(1));
    await tester.ensureVisible(find.text('恢复第一个 Pending Navigation'));
    await tester.tap(find.text('恢复第一个 Pending Navigation'));
    await tester.pumpAndSettle();
    expect(find.text('Deferred Navigation 已恢复'), findsWidgets);
    await tester.tap(find.text('返回实验台'));
    await tester.pumpAndSettle();
    expect(CCRouter.pendingNavigations, isEmpty);

    await _unmountDemo(tester);
  });

  testWidgets('failure fallback can return without leaking Route Entries', (
    tester,
  ) async {
    await _pumpDemo(tester);
    await tester.tap(find.text('策略'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('打开不存在的路由'));
    await tester.tap(find.text('打开不存在的路由'));
    await tester.pumpAndSettle();

    expect(find.text('导航兜底'), findsOneWidget);
    expect(CCRouter.navigator.canPop(), isTrue);
    expect(CCRouter.activeRouteEntries, hasLength(1));

    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();

    expect(find.text('CCRouter Lab'), findsOneWidget);
    expect(CCRouter.activeRouteEntries, isEmpty);

    await _unmountDemo(tester);
  });

  testWidgets('managed and foreign modal routes preserve ownership', (
    tester,
  ) async {
    await _pumpDemo(tester);
    await tester.tap(find.text('展示'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Managed Dialog Route'));
    await tester.tap(find.text('Managed Dialog Route'));
    await tester.pumpAndSettle();
    expect(
      find.text('它具备 typed result、Interceptor、Aspect 和 RouteEntry。'),
      findsOneWidget,
    );
    expect(
      CCRouter.activeRouteEntries.any(
        (entry) => entry.routeId == 'demo_navigation_lab.presentation.dialog',
      ),
      isTrue,
    );
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.textContaining('dialog:confirmed'), findsOneWidget);

    final managedBeforeForeign = CCRouter.activeRouteEntries.length;
    await tester.ensureVisible(find.text('Foreign showDialog'));
    await tester.tap(find.text('Foreign showDialog'));
    await tester.pumpAndSettle();
    expect(find.text('这是 Foreign PopupRoute。'), findsOneWidget);
    expect(CCRouter.activeRouteEntries.length, managedBeforeForeign);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(CCRouter.activeRouteEntries.length, managedBeforeForeign);

    await _unmountDemo(tester);
  });

  testWidgets('page lifecycle reports cover, uncover and app state', (
    tester,
  ) async {
    await _pumpDemo(tester);
    await tester.tap(find.text('生命周期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开生命周期实验页'));
    await tester.pumpAndSettle();

    expect(find.text('页面生命周期'), findsOneWidget);
    await tester.tap(find.text('打开 Managed 覆盖页'));
    await tester.pumpAndSettle();
    expect(
      demoNavigationLabStore.events.any(
        (event) => event.contains('Lifecycle mixin · onPageHide'),
      ),
      isTrue,
    );
    await tester.tap(find.text('确认并返回类型安全结果'));
    await tester.pumpAndSettle();
    expect(
      demoNavigationLabStore.events.any(
        (event) => event.contains('Lifecycle mixin · onPageShow'),
      ),
      isTrue,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(
      demoNavigationLabStore.events.any(
        (event) => event.contains('Lifecycle mixin · onBackground'),
      ),
      isTrue,
    );
    expect(
      demoNavigationLabStore.events.any(
        (event) => event.contains('Lifecycle mixin · onForeground'),
      ),
      isTrue,
    );

    await _unmountDemo(tester);
  });

  testWidgets('single Shell keeps nested routes inside its outlet', (
    tester,
  ) async {
    await _pumpDemo(tester);
    await tester.tap(find.text('导航'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('进入 ShellRoute'));
    await tester.tap(find.text('进入 ShellRoute'));
    await tester.pumpAndSettle();

    expect(find.text('Shell Feed'), findsOneWidget);
    expect(find.text('Feed'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    await tester.tap(find.text('在 Shell Outlet 内打开详情'));
    await tester.pumpAndSettle();
    expect(find.text('Shell Detail #7'), findsOneWidget);
    expect(
      CCRouter.activeRouteEntries.last.placement.navigatorOutlet,
      'shell.content',
    );

    await tester.tap(find.text('返回 Feed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Shell Settings'), findsOneWidget);

    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('在 Root Navigator 打开透明页'));
    await tester.pumpAndSettle();
    expect(find.text('透明全屏海报预览'), findsOneWidget);
    expect(CCRouter.activeRouteEntries.last.placement.navigatorOutlet, 'root');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('Shell Feed'), findsOneWidget);

    await _unmountDemo(tester);
  });

  testWidgets('StatefulShell accepts an initial deep link into a branch', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const CCRouterDemoApp(
        initialLocation: '/workspace/home/73',
        listenForPlatformLinks: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Workspace Detail #73'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(
      CCRouter.activeBackendEntries.last.navigatorOutlet,
      'workspace.home',
    );

    await _unmountDemo(tester);
  });

  testWidgets('StatefulShell preserves branch state and history', (
    tester,
  ) async {
    await _pumpDemo(tester);
    await tester.tap(find.text('导航'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('进入 StatefulShellRoute'));
    await tester.tap(find.text('进入 StatefulShellRoute'));
    await tester.pumpAndSettle();

    expect(find.text('Workspace Home'), findsOneWidget);
    await tester.tap(find.text('打开 Home 分支详情'));
    await tester.pumpAndSettle();
    expect(find.text('Workspace Detail #42'), findsOneWidget);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('增加分支内状态'));
    await tester.pumpAndSettle();
    expect(find.textContaining('本地计数：1'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Workspace Profile'), findsOneWidget);
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.textContaining('本地计数：1'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Workspace Detail #42'), findsOneWidget);

    await _unmountDemo(tester);
  });

  testWidgets('typed Extra remains an in-process typed value', (tester) async {
    await _pumpDemo(tester);
    await tester.tap(find.text('导航'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('打开 Typed Extra'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('打开 Typed Extra'));
    await tester.pumpAndSettle();

    expect(find.text('Typed Extra'), findsOneWidget);
    expect(
      find.textContaining('owner=navigation_lab · revision=3'),
      findsOneWidget,
    );
    expect(
      CCRouter.activeRouteEntries.last.normalizedUri.toString(),
      '/lab/extra',
    );
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await _unmountDemo(tester);
  });
}

Future<void> _pumpDemo(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const CCRouterDemoApp(listenForPlatformLinks: false));
  await tester.pumpAndSettle();
}

Future<void> _unmountDemo(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}
