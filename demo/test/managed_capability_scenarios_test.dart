import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_demo/ccrouter_demo.dart';
import 'package:ccrouter_demo/main.dart';
import 'package:demo_navigation_lab/demo_navigation_lab.dart';
import 'package:demo_navigation_lab/demo_navigation_lab_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    demoNavigationLabStore
      ..blockDetailGlobally = false
      ..allowDeferredOnce = false
      ..clear();
  });
  tearDown(CCRouterHost.shutdown);

  Future<void> mount(WidgetTester tester) async {
    CCRouterHost.initialize(
      hostAssembly: ccrouterGeneratedHostAssembly,
      routeRevalidationPolicies: const [
        CCGlobalRouteRevalidationPolicy(
          id: 'demo.active_routes',
          policy: DemoRouteRevalidationPolicy(),
        ),
      ],
    );
    await tester.pumpWidget(
      const CCRouterDemoApp(listenForPlatformLinks: false),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    if (find.text(text).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text(text),
        250,
        scrollable: find.byType(Scrollable).last,
      );
    }
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'covered exact-close Demo keeps cover and disposes its own Scope once',
    (tester) async {
      await mount(tester);
      final original = CCRouter.navigator.push(
        demoStackIntent(level: 1, returnsResult: true),
      );
      await tester.pumpAndSettle();
      final handle = CCRouter.routeEntryHandleOf(
        tester.element(find.text('栈操作 · Level 1')),
      )!;
      await tap(tester, '覆盖后精确关闭本页');
      expect(find.text('栈操作 · Level 2'), findsOneWidget);
      final covering = CCRouter.activeRouteEntries.last.routeEntryId;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(await original, 'exact:1');
      expect(
        CCRouter.activeRouteEntries.any((entry) => entry.handle == handle),
        isFalse,
      );
      expect(CCRouter.activeRouteEntries.last.routeEntryId, covering);
      expect(
        demoNavigationLabStore.events.where(
          (event) =>
              event.contains('Route Service #') && event.contains('disposed'),
        ),
        hasLength(1),
      );
      await tap(tester, 'Pop 并返回结果');
      expect(find.text('CCRouter Lab'), findsOneWidget);
      expect(find.text('栈操作 · Level 1'), findsNothing);
    },
  );

  for (final action in ['keep', 'close', 'replace', 'reset']) {
    testWidgets('interactive revalidation $action reports its real outcome', (
      tester,
    ) async {
      await mount(tester);
      final original = CCRouter.navigator.push(
        demoStackIntent(level: 11, returnsResult: true),
      );
      await tester.pumpAndSettle();
      final handle = CCRouter.activeRouteEntries.last.handle;
      await tap(tester, 'Revalidation · $action');
      switch (action) {
        case 'keep':
          expect(CCRouter.activeRouteEntries.last.handle, handle);
          CCRouter.navigator.pop();
          await tester.pumpAndSettle();
        case 'replace':
          expect(find.text('栈操作 · Level 900'), findsOneWidget);
          expect(CCRouter.activeRouteEntries.last.handle, isNot(handle));
        case 'close':
          expect(find.text('CCRouter Lab'), findsOneWidget);
        case 'reset':
          expect(find.text('CCRouter Lab'), findsOneWidget);
          expect(CCRouter.activeRouteEntries, hasLength(1));
      }
      await original;
      expect(
        demoNavigationLabStore.events.any(
          (event) => event.contains('Revalidation $action ·'),
        ),
        isTrue,
      );
    });
  }

  testWidgets(
    'Pending cancellation Demo releases continuation without navigating',
    (tester) async {
      await mount(tester);
      await tap(tester, '策略');
      await tap(tester, 'Defer Navigation');
      expect(CCRouter.pendingNavigations, hasLength(1));
      final count = CCRouter.activeRouteEntries.length;
      await tap(tester, '取消第一个 Pending Navigation');
      expect(CCRouter.pendingNavigations, isEmpty);
      expect(CCRouter.activeRouteEntries, hasLength(count));
      expect(find.text('Deferred Navigation 已恢复'), findsNothing);
    },
  );
}
