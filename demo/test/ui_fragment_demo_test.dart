import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_test/ccrouter_ui_test.dart';
import 'package:ccrouter_demo/ccrouter_demo.dart';
import 'package:ccrouter_demo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../modules/navigation_lab/test/support/recommendation_pair_fixture.dart';

Future<void> _settle(WidgetTester tester) async {
  // Fake loading uses a Timer, which does not itself schedule a Flutter frame.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(CCRouterHost.shutdown);

  testWidgets('extended generated Assembly retains UI lifecycle and routes', (
    tester,
  ) async {
    final generated = ccrouterGeneratedHostAssembly;
    final assembly = CCHostAssembly.extend(
      generated,
      additionalComponents: const [
        CCComponentManifest(
          id: 'test_extra',
          version: '1.0.0',
          registrar: _ExtraRegistrar(),
        ),
      ],
      routeCatalog: CCFlutterRouteCatalog(
        generated.routeCatalog.destinations.reversed,
      ),
    );
    for (var cycle = 0; cycle < 2; cycle++) {
      final host = CCUIFragmentTestHost(hostAssembly: assembly);
      addTearDown(host.dispose);
      await host.run(() async {
        expect(
          CCRouter.registeredComponents.map((c) => c.id),
          contains('test_extra'),
        );
        await tester.pumpWidget(
          const CCRouterDemoApp(
            initialLocation: '/ui-fragments',
            listenForPlatformLinks: false,
          ),
        );
        await _settle(tester);
        expect(find.text('订单摘要 · 1'), findsOneWidget);
        await tester.tap(find.text('选择').first);
        await tester.pump();
        expect(find.text('A 收到订单 1 的选择'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, unmount: () => tester.pumpWidget(const SizedBox()));
      expect(CCRouter.isInitialized, isFalse);
    }
    expect(assembly.packages, same(generated.packages));
    expect(assembly.contractBundle, same(generated.contractBundle));
  });

  testWidgets(
    'retained business callbacks recheck activity, pending data and disposal',
    (tester) async {
      final host = CCUIFragmentTestHost(
        hostAssembly: ccrouterGeneratedHostAssembly,
      );
      addTearDown(host.dispose);
      await host.run(() async {
        var selections = 0;
        Widget tree(String category, {bool active = true}) =>
            createRecommendationPairFixture(
              category: category,
              active: active,
              onFirstAction: (_) => selections++,
              onSecondAction: (_) {},
            );
        await tester.pumpWidget(tree('精选'));
        await _settle(tester);
        final oldSelect = tester
            .widget<TextButton>(find.widgetWithText(TextButton, '选择').first)
            .onPressed!;
        await tester.pumpWidget(tree('新品'));
        oldSelect(); // A new request has cleared the old selection.
        expect(selections, 0);
        await _settle(tester);
        await tester.pumpWidget(tree('新品', active: false));
        oldSelect();
        expect(selections, 0);
        await tester.pumpWidget(tree('error'));
        await _settle(tester);
        final oldRetry = tester
            .widget<TextButton>(find.widgetWithText(TextButton, '重试'))
            .onPressed!;
        await tester.pumpWidget(tree('error', active: false));
        oldRetry(); // Must not mutate B's state before the guarded Action sink.
        await tester.pump();
        expect(find.text('暂时无法加载'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        oldRetry();
        oldSelect();
        await tester.pump(const Duration(seconds: 1));
        expect(selections, 0);
        expect(tester.takeException(), isNull);
      }, unmount: () => tester.pumpWidget(const SizedBox()));
    },
  );

  testWidgets(
    'real generated Host renders B UI in A with isolated State and KeepAlive',
    (tester) async {
      CCRouterHost.initialize(hostAssembly: ccrouterGeneratedHostAssembly);
      await tester.pumpWidget(
        const CCRouterDemoApp(
          initialLocation: '/ui-fragments',
          listenForPlatformLinks: false,
        ),
      );
      await _settle(tester);
      final entries = CCRouter.activeRouteEntries.length;
      expect(find.text('订单摘要 · 1'), findsOneWidget);
      expect(find.text('订单摘要 · 2'), findsOneWidget);
      await tester.tap(find.text('选择').first);
      await tester.pump();
      expect(find.text('A 收到订单 1 的选择'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '只属于第一个实例');
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        isEmpty,
      );
      await tester.tap(find.text('切换 Tab'));
      await _settle(tester);
      expect(find.text('推荐列表 · 精选'), findsOneWidget);
      await tester.tap(find.text('选择'));
      await tester.pump();
      expect(find.text('A 收到推荐 recommendation-7301 的选择'), findsOneWidget);
      expect(CCRouter.activeRouteEntries.length, entries);
      await tester.tap(find.text('切换 Tab'));
      await _settle(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '只属于第一个实例',
      );
      await tester.tap(find.text('更新 Props'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('更新 Props'));
      await _settle(tester);
      expect(find.text('订单摘要 · 1'), findsNothing);
      expect(find.text('订单摘要 · 3'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '只属于第一个实例',
      );
      await tester.tap(find.text('选择').first);
      await tester.pump();
      expect(find.text('A 收到订单 3 的选择'), findsOneWidget);
      await tester.tap(find.text('切换模拟账号'));
      await _settle(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'payloads from two private loads stay instance-local and follow new Props',
    (tester) async {
      CCRouterHost.initialize(hostAssembly: ccrouterGeneratedHostAssembly);
      final first = <String>[];
      final second = <String>[];
      Widget tree(String category, {bool active = true}) =>
          createRecommendationPairFixture(
            category: category,
            active: active,
            onFirstAction: (action) => first.add(action.selectedId),
            onSecondAction: (action) => second.add(action.selectedId),
          );
      await tester.pumpWidget(tree('精选'));
      await _settle(tester);
      await tester.tap(find.text('选择').first);
      await tester.tap(find.text('选择').last);
      expect(first, ['recommendation-7301']);
      expect(second, ['recommendation-8426']);
      await tester.pumpWidget(tree('精选', active: false));
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '选择').first)
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(tree('新品'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpWidget(tree('精选'));
      await _settle(tester);
      await tester.tap(find.text('选择').first);
      expect(first, ['recommendation-7301', 'recommendation-7301']);
      await tester.pumpWidget(tree('新品'));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(first, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'business error, retry and rapid removal release pending fake requests',
    (tester) async {
      CCRouterHost.initialize(hostAssembly: ccrouterGeneratedHostAssembly);
      await tester.pumpWidget(
        const CCRouterDemoApp(
          initialLocation: '/ui-fragments',
          listenForPlatformLinks: false,
        ),
      );
      await _settle(tester);
      await tester.tap(find.text('切换加载错误'));
      await tester.tap(find.text('切换 Tab'));
      await _settle(tester);
      expect(find.text('暂时无法加载'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await _settle(tester);
      expect(find.text('暂时无法加载'), findsOneWidget);
      await tester.tap(find.text('切换加载错误'));
      await _settle(tester);
      expect(find.text('推荐列表 · 精选'), findsOneWidget);
      await tester.tap(find.text('更新 Props'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );
}

final class _ExtraRegistrar implements CCComponentRegistrar {
  const _ExtraRegistrar();
  @override
  void register(CCRegistry registry) {}
}
