import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_demo/ccrouter_demo.dart';
import 'package:ccrouter_demo/multi_host_demo.dart';
import 'package:ccrouter_demo/platform_deep_link_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    CCRouter.initialize(
      components: ccrouterGeneratedComponentManifests,
      deepLinkIngressPolicy: demoDeepLinkIngressPolicy,
    );
  });

  tearDown(CCRouter.shutdown);

  testWidgets('two Hosts retain independent visible navigation state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(createMultiHostDemoApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.textContaining('Primary Host'), findsOneWidget);
    expect(find.textContaining('Secondary Host'), findsOneWidget);
    final navigateButtons = find.byTooltip('打开隔离栈页');
    expect(navigateButtons, findsNWidgets(2));

    await tester.ensureVisible(navigateButtons.at(1));
    await tester.tap(navigateButtons.at(1));
    await tester.pumpAndSettle();
    expect(find.text('栈操作 · Level 202'), findsOneWidget);
    expect(CCRouter.activeRouteEntries.single.hostId, 'host.secondary');

    await tester.ensureVisible(navigateButtons.at(0));
    await tester.tap(navigateButtons.at(0));
    await tester.pumpAndSettle();
    expect(find.text('栈操作 · Level 101'), findsOneWidget);
    expect(find.text('栈操作 · Level 202'), findsOneWidget);
    expect(CCRouter.activeRouteEntries.map((entry) => entry.hostId).toSet(), {
      'host.primary',
      'host.secondary',
    });

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'one Host adapts orientation, list-detail Outlets, and display features',
    (tester) async {
      tester.view.physicalSize = const Size(520, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(createMultiHostDemoApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('自适应布局'));
      await tester.pumpAndSettle();
      expect(find.text('同一 Host：host.primary'), findsOneWidget);
      expect(find.byKey(const ValueKey('adaptive-list-pane')), findsOneWidget);
      expect(find.byKey(const ValueKey('adaptive-detail-pane')), findsNothing);
      expect(find.textContaining('纵向 · compact'), findsOneWidget);
      expect(find.text('Active Outlet：adaptive.list'), findsOneWidget);

      await tester.tap(find.text('Item 2'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('adaptive-detail-pane')),
        findsOneWidget,
      );
      expect(find.text('Item 2'), findsOneWidget);

      tester.view.physicalSize = const Size(1200, 700);
      await tester.pumpAndSettle();
      expect(find.text('同一 Host：host.primary'), findsOneWidget);
      expect(find.textContaining('横向 · expanded'), findsOneWidget);
      expect(find.byKey(const ValueKey('adaptive-list-pane')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('adaptive-detail-pane')),
        findsOneWidget,
      );
      expect(
        find.text('Active Outlet：adaptive.list + adaptive.detail'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('simulate-hinge')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('adaptive-hinge')), findsOneWidget);
      expect(find.textContaining('1 个 Display Feature'), findsOneWidget);
      expect(find.text('同一 Host：host.primary'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
