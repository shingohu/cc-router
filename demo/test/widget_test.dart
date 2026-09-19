import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_demo/ccrouter_generated/ccrouter_host.routes.g.dart';
import 'package:ccrouter_demo/main.dart';
import 'package:demo_navigation_lab/demo_navigation_lab.dart';
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
    expect(find.text('3'), findsWidgets);

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

  testWidgets('unsupported GoRouter stack operations fail without mutation', (
    tester,
  ) async {
    await _pumpDemo(tester);
    await tester.tap(find.text('导航'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入栈操作工作台'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('PushAndRemoveUntil（GoRouter 暂不支持）'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CCNavigationAdapterError'), findsOneWidget);
    expect(find.text('栈操作 · Level 1'), findsOneWidget);
    expect(CCRouter.activeRouteEntries, hasLength(1));

    await tester.tap(find.text('Push 下一层'));
    await tester.pumpAndSettle();
    expect(find.text('栈操作 · Level 2'), findsOneWidget);
    await tester.tap(find.text('精确移除前一 Entry（GoRouter 暂不支持）'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CCNavigationAdapterError'), findsOneWidget);
    expect(CCRouter.activeRouteEntries, hasLength(2));

    CCRouter.navigator.pop();
    await tester.pumpAndSettle();
    CCRouter.navigator.pop();
    await tester.pumpAndSettle();
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
}

Future<void> _pumpDemo(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const CCRouterDemoApp());
  await tester.pumpAndSettle();
}

Future<void> _unmountDemo(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}
