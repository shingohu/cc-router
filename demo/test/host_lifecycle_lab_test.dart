import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_demo/ccrouter_demo.dart';
import 'package:ccrouter_demo/host_lifecycle_lab.dart';
import 'package:ccrouter_demo/multi_host_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(CCRouterHost.shutdown);

  testWidgets('reopened Host rejects old work and admits new work', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final policy = DemoHostLifecyclePolicy();
    CCRouterHost.initialize(
      hostAssembly: ccrouterGeneratedHostAssembly,
      navigationConcurrencyPolicy: CCNavigationConcurrencyPolicy.singleFlight,
      globalInterceptors: [
        CCGlobalNavigationInterceptor(
          id: 'demo.hostLifecycle',
          interceptor: policy,
        ),
      ],
    );
    await tester.pumpWidget(createMultiHostDemoApp(lifecyclePolicy: policy));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Host 生命周期'));
    await tester.pumpAndSettle();
    for (var visit = 0; visit < 2; visit++) {
      for (var generation = 1; generation <= 3; generation++) {
        await tester.tap(find.text('发起延迟导航'));
        await tester.pumpAndSettle();
        expect(find.text('第 $generation 代：等待策略'), findsOneWidget);
        await tester.tap(find.text('关闭并重开 Host'));
        await tester.pumpAndSettle();
        expect(find.text('辅助 Host 第 ${generation + 1} 代'), findsOneWidget);
        expect(find.text('第 $generation 代：host_detached'), findsOneWidget);
        expect(find.text('栈操作 · Level 901'), findsNothing);
        await tester.tap(find.text('新实例导航'));
        await tester.pumpAndSettle();
        expect(find.text('第 ${generation + 1} 代：导航成功'), findsOneWidget);
        expect(find.text('栈操作 · Level 901'), findsOneWidget);
        await tester.tap(find.text('Push 下一层'));
        await tester.pumpAndSettle();
        expect(find.text('栈操作 · Level 902'), findsOneWidget);
        final entries = CCRouter.activeRouteEntries
            .where((entry) => entry.hostId == DemoHostLifecyclePolicy.hostId)
            .map((entry) => entry.routeEntryId)
            .toList();
        await tester.tap(find.text('放行旧决策'));
        await tester.pumpAndSettle();
        expect(
          CCRouter.activeRouteEntries
              .where((entry) => entry.hostId == DemoHostLifecyclePolicy.hostId)
              .map((entry) => entry.routeEntryId),
          entries,
        );
        expect(find.text('栈操作 · Level 902'), findsOneWidget);
      }
      await tester.tap(find.text('Host 隔离'));
      await tester.pumpAndSettle();
      expect(
        CCRouter.activeRouteEntries.where(
          (entry) => entry.hostId == DemoHostLifecyclePolicy.hostId,
        ),
        isEmpty,
      );
      await tester.tap(find.text('Host 生命周期'));
      await tester.pumpAndSettle();
      expect(find.text('辅助 Host 第 1 代'), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(policy.hasGate, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auxiliary Host renders its trusted home on every mount', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CCRouterHost.initialize(hostAssembly: ccrouterGeneratedHostAssembly);
    final policy = DemoHostLifecyclePolicy();
    await tester.pumpWidget(createMultiHostDemoApp(lifecyclePolicy: policy));
    await tester.pumpAndSettle();
    final otherEntries = CCRouter.activeRouteEntries
        .map((entry) => entry.routeEntryId)
        .toList();
    for (var visit = 0; visit < 2; visit++) {
      await tester.tap(find.text('Host 生命周期'));
      await tester.pumpAndSettle();
      for (var generation = 1; generation <= 3; generation++) {
        final home = CCRouter.activeRouteEntries.singleWhere(
          (entry) => entry.hostId == DemoHostLifecyclePolicy.hostId,
        );
        expect(home.routeId, 'demo_navigation_lab.home');
        expect(find.text('Ready · 选择一个场景开始验证'), findsOneWidget);
        expect(
          CCRouter.activeRouteEntries
              .where((entry) => entry.hostId != DemoHostLifecyclePolicy.hostId)
              .map((entry) => entry.routeEntryId),
          otherEntries,
        );
        await tester.tap(find.text('关闭并重开 Host'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Host 隔离'));
      await tester.pumpAndSettle();
      expect(
        CCRouter.activeRouteEntries.where(
          (entry) => entry.hostId == DemoHostLifecyclePolicy.hostId,
        ),
        isEmpty,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
