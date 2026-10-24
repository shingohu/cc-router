import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_demo/ccrouter_demo.dart';
import 'package:ccrouter_demo/main.dart';
import 'package:ccrouter_demo/platform_deep_link_bridge.dart';
import 'package:demo_navigation_lab/demo_navigation_lab.dart';
import 'package:demo_navigation_lab/demo_navigation_lab_host.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/demo_startup.dart';

Future<void> _initializeDemoHost(WidgetTester tester) async {
  demoNavigationLabStore
    ..blockDetailGlobally = false
    ..dirtyForm = true
    ..allowDeferredOnce = false
    ..clear();
  CCRouterHost.initialize(
    hostAssembly: ccrouterGeneratedHostAssembly,
    deepLinkIngressPolicy: demoDeepLinkIngressPolicy,
    globalInterceptors: const [
      CCGlobalNavigationInterceptor(
        id: DemoHostIds.globalNavigationInterceptor,
        interceptor: DemoGlobalNavigationInterceptor(),
      ),
    ],
    routeRevalidationPolicies: const [
      CCGlobalRouteRevalidationPolicy(
        id: DemoHostIds.routeRevalidationPolicy,
        policy: DemoRouteRevalidationPolicy(),
      ),
    ],
    navigationFailurePolicy: const DemoNavigationFailurePolicy(),
  );
  await pumpDemoStartup(tester);
}

void main() {
  tearDown(CCRouterHost.shutdown);

  testWidgets('explicit Cupertino page has readable body in Material Host', (
    tester,
  ) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    await _mount(tester, _DemoBackend.managed);
    final opened = CCRouter.navigator.open(
      Uri.parse('/lab/presentation/cupertino'),
    );
    await tester.pumpAndSettle();
    final body = find.text('显式 Cupertino 页面与返回手势语义');
    final context = tester.element(body);
    final expectedStyle = CupertinoTheme.of(context).textTheme.textStyle;
    final richText = tester.widget<RichText>(
      find.descendant(of: body, matching: find.byType(RichText)),
    );
    expect(richText.text.style?.fontSize, expectedStyle.fontSize);
    expect(richText.text.style?.decoration, isNot(TextDecoration.underline));
    expect(tester.takeException(), isNull);
    await CCRouter.navigator.maybePop();
    await tester.pumpAndSettle();
    await opened;
    expect(find.text('CCRouter Lab'), findsOneWidget);
  });

  for (final backend in _DemoBackend.values) {
    testWidgets(
      '${backend.label} resolves Regex aliases and rejects private ingress',
      (tester) async {
        await _mount(tester, backend);
        final opened = CCRouter.navigator.open(
          Uri.parse('/lab/regex/46?title=Regex%20alias'),
        );
        await tester.pumpAndSettle();
        expect(find.text('ID 46'), findsOneWidget);
        expect(find.text('Regex alias'), findsWidgets);
        await tester.tap(find.text('确认并返回类型安全结果'));
        await tester.pumpAndSettle();
        await opened;
        expect(find.text('CCRouter Lab'), findsOneWidget);
        final before = CCRouter.activeRouteEntries
            .map((entry) => entry.handle)
            .toList();
        await tester.tap(find.text('导航'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('拒绝未公开的外部链接'),
          250,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('拒绝未公开的外部链接'));
        await tester.pumpAndSettle();
        expect(
          CCRouter.activeRouteEntries.map((entry) => entry.handle),
          before,
        );
        expect(find.text('CCRouter Lab'), findsOneWidget);
        expect(
          demoNavigationLabStore.events.any(
            (event) => event.contains('CCDeepLinkRejectedError'),
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${backend.label} materializes the shared Demo feature matrix',
      (tester) async {
        await _initializeDemoHost(tester);
        await tester.pumpWidget(switch (backend) {
          _DemoBackend.managed => const CCRouterDemoApp(
            listenForPlatformLinks: false,
          ),
        });
        await tester.pumpAndSettle();

        final cases = <({String uri, Finder content})>[
          (uri: '/lab/presentation/fade', content: find.text('Fade Page')),
          (uri: '/lab/presentation/scale', content: find.text('Scale Page')),
          (
            uri: '/lab/presentation/cupertino',
            content: find.text('显式 Cupertino 页面与返回手势语义'),
          ),
          (
            uri: '/lab/presentation/bottom-page',
            content: find.text('全屏页面从底部滑入'),
          ),
          (
            uri: '/lab/presentation/transparent',
            content: find.text('透明全屏海报预览'),
          ),
          (
            uri: '/lab/presentation/dialog',
            content: find.text('Managed Dialog Route'),
          ),
          (
            uri: '/lab/presentation/sheet',
            content: find.text('Managed BottomSheet'),
          ),
          (uri: '/shell/feed', content: find.text('Shell Feed')),
          (uri: '/shell/settings', content: find.text('Shell Settings')),
          (uri: '/shell/feed/7', content: find.text('Shell Detail #7')),
          (uri: '/workspace/home', content: find.text('Workspace Home')),
          (
            uri: '/workspace/home/42',
            content: find.text('Workspace Detail #42'),
          ),
          (
            uri: '/workspace/activity',
            content: find.text('Workspace Activity'),
          ),
          (uri: '/workspace/profile', content: find.text('Workspace Profile')),
        ];

        for (final testCase in cases) {
          await CCRouter.navigator.open(Uri.parse(testCase.uri));
          await tester.pumpAndSettle();
          expect(testCase.content, findsWidgets, reason: testCase.uri);
          expect(tester.takeException(), isNull, reason: testCase.uri);
          await CCRouter.navigator.maybePop();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'pop ${testCase.uri}');
        }
      },
    );

    testWidgets('${backend.label} preserves typed result and policy behavior', (
      tester,
    ) async {
      await _mount(tester, backend);

      await tester.tap(find.text('导航'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Push + typed result'));
      await tester.pumpAndSettle();
      expect(find.text('ID 42'), findsOneWidget);
      await tester.tap(find.text('确认并返回类型安全结果'));
      await tester.pumpAndSettle();
      expect(find.textContaining('detail:42:confirmed'), findsOneWidget);

      await expectLater(
        CCRouter.navigator.open(Uri.parse('/lab/policy/cancel')),
        throwsA(isA<CCRouteCancelledError>()),
      );
      await tester.pumpAndSettle();
      expect(find.text('不应到达的页面'), findsNothing);

      final redirected = CCRouter.navigator.open(
        Uri.parse('/lab/policy/redirect-source'),
      );
      await tester.pumpAndSettle();
      expect(find.text('已重定向到目标页'), findsWidgets);
      CCRouter.navigator.pop();
      await tester.pumpAndSettle();
      await redirected;

      final deferred = CCRouter.navigator.open(Uri.parse('/lab/policy/defer'));
      await tester.pump();
      expect(CCRouter.pendingNavigations, hasLength(1));
      demoNavigationLabStore.allowDeferredOnce = true;
      await CCRouter.resumePendingNavigation(
        CCRouter.pendingNavigations.single.navigationId,
      );
      await tester.pumpAndSettle();
      expect(find.text('Deferred Navigation 已恢复'), findsWidgets);
      CCRouter.navigator.pop();
      await tester.pumpAndSettle();
      await deferred;
      expect(CCRouter.pendingNavigations, isEmpty);
    });

    testWidgets('${backend.label} preserves guarded and modal ownership', (
      tester,
    ) async {
      await _mount(tester, backend);

      final guarded = CCRouter.navigator.open(Uri.parse('/lab/policy/guarded'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('模拟系统返回'));
      await tester.pumpAndSettle();
      expect(find.text('PopGuard'), findsOneWidget);
      expect(
        demoNavigationLabStore.events.any(
          (event) => event.contains('PopGuard · system · deny'),
        ),
        isTrue,
      );
      await tester.tap(find.text('存在未保存修改'));
      await tester.tap(find.text('模拟系统返回'));
      await tester.pumpAndSettle();
      expect(find.text('PopGuard'), findsNothing);
      await guarded;

      final fallback = CCRouter.navigator.open(Uri.parse('/lab/not-found'));
      await tester.pumpAndSettle();
      expect(find.text('导航兜底'), findsOneWidget);
      CCRouter.navigator.pop();
      await tester.pumpAndSettle();
      await fallback;

      final dialog = CCRouter.navigator.open(
        Uri.parse('/lab/presentation/dialog'),
      );
      await tester.pumpAndSettle();
      expect(
        CCRouter.activeRouteEntries.any(
          (entry) => entry.routeId == 'demo_navigation_lab.presentation.dialog',
        ),
        isTrue,
      );
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      await dialog;
      final managedCount = CCRouter.activeRouteEntries.length;
      unawaited(
        showDialog<void>(
          context: tester.element(find.text('CCRouter Lab')),
          builder: (_) =>
              const AlertDialog(content: Text('这是 Foreign PopupRoute。')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('这是 Foreign PopupRoute。'), findsOneWidget);
      expect(CCRouter.activeRouteEntries, hasLength(managedCount));
      Navigator.of(tester.element(find.text('这是 Foreign PopupRoute。'))).pop();
      await tester.pumpAndSettle();
      expect(CCRouter.activeRouteEntries, hasLength(managedCount));
    });

    testWidgets('${backend.label} revalidates already-open route identities', (
      tester,
    ) async {
      await _mount(tester, backend);
      final detail = CCRouter.navigator.open(Uri.parse('/lab/detail/42'));
      await tester.pumpAndSettle();
      final covering = CCRouter.navigator.open(
        Uri.parse('/lab/policy/proceed'),
      );
      await tester.pumpAndSettle();
      expect(
        CCRouter.activeRouteEntries.any(
          (entry) => entry.routeId == 'demo_navigation_lab.detail',
        ),
        isTrue,
      );

      demoNavigationLabStore.setBlockDetailGlobally(true);
      final report = await tester.runAsync(
        () => CCRouter.revalidateActiveRoutes(reason: 'detail_policy_changed'),
      );
      await tester.pumpAndSettle();

      expect(report, isNotNull);
      expect(report!.changed, isTrue);
      expect(
        CCRouter.activeRouteEntries.any(
          (entry) => entry.routeId == 'demo_navigation_lab.detail',
        ),
        isFalse,
      );
      await detail;
      expect(find.text('拦截器已放行'), findsWidgets);
      CCRouter.navigator.pop();
      await tester.pumpAndSettle();
      await covering;
    });

    testWidgets('${backend.label} preserves StatefulShell branch state', (
      tester,
    ) async {
      await _mount(tester, backend);
      await CCRouter.navigator.go(demoWorkspaceHomeIntent());
      await tester.pumpAndSettle();
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
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(find.textContaining('本地计数：1'), findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Workspace Detail #42'), findsOneWidget);
    });
  }
}

Future<void> _mount(WidgetTester tester, _DemoBackend backend) async {
  await _initializeDemoHost(tester);
  await tester.pumpWidget(switch (backend) {
    _DemoBackend.managed => const CCRouterDemoApp(
      listenForPlatformLinks: false,
    ),
  });
  await tester.pumpAndSettle();
}

enum _DemoBackend {
  managed('native Managed Backend');

  const _DemoBackend(this.label);

  final String label;
}
