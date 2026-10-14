import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_demo/ccrouter_demo.dart';
import 'package:ccrouter_demo/multi_host_demo.dart';
import 'package:ccrouter_demo/platform_deep_link_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    CCRouterHost.initialize(
      hostAssembly: ccrouterGeneratedHostAssembly,
      deepLinkIngressPolicy: demoDeepLinkIngressPolicy,
    );
  });

  tearDown(CCRouterHost.shutdown);

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
    final primaryPane = find.byKey(const ValueKey('host.primary'));
    final secondaryPane = find.byKey(const ValueKey('host.secondary'));

    await tester.ensureVisible(navigateButtons.at(1));
    await tester.tap(navigateButtons.at(1));
    await tester.pumpAndSettle();
    expect(
      _inside(secondaryPane, find.text('栈操作 · Level 202')),
      findsOneWidget,
    );
    expect(_inside(primaryPane, find.text('栈操作 · Level 202')), findsNothing);
    expect(find.byKey(const ValueKey('host.secondary-active')), findsOneWidget);
    expect(CCRouter.activeRouteEntries.single.hostId, 'host.secondary');

    await tester.ensureVisible(navigateButtons.at(0));
    await tester.tap(navigateButtons.at(0));
    await tester.pumpAndSettle();
    expect(_inside(primaryPane, find.text('栈操作 · Level 101')), findsOneWidget);
    expect(
      _inside(secondaryPane, find.text('栈操作 · Level 202')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('host.primary-active')), findsOneWidget);
    expect(CCRouter.activeRouteEntries.map((entry) => entry.hostId).toSet(), {
      'host.primary',
      'host.secondary',
    });

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('interaction inside a Host activates local navigation and pop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(createMultiHostDemoApp());
    await tester.pumpAndSettle();

    final primaryPane = find.byKey(const ValueKey('host.primary'));
    final secondaryPane = find.byKey(const ValueKey('host.secondary'));

    await tester.tap(_inside(secondaryPane, find.text('导航')));
    await tester.pumpAndSettle();
    final secondaryPush = _inside(
      secondaryPane,
      find.text('Push + typed result'),
    );
    await tester.ensureVisible(secondaryPush);
    await tester.tap(secondaryPush);
    await tester.pumpAndSettle();

    expect(_inside(secondaryPane, find.text('ID 42')), findsOneWidget);
    expect(_inside(primaryPane, find.text('ID 42')), findsNothing);
    expect(CCRouter.activeRouteEntries.single.hostId, 'host.secondary');

    await tester.tap(_inside(primaryPane, find.text('导航')));
    await tester.pumpAndSettle();
    final primaryPush = _inside(primaryPane, find.text('Push + typed result'));
    await tester.ensureVisible(primaryPush);
    await tester.tap(primaryPush);
    await tester.pumpAndSettle();

    expect(_inside(primaryPane, find.text('ID 42')), findsOneWidget);
    expect(_inside(secondaryPane, find.text('ID 42')), findsOneWidget);
    expect(CCRouter.activeRouteEntries.map((entry) => entry.hostId).toSet(), {
      'host.primary',
      'host.secondary',
    });

    final secondaryComplete = _inside(secondaryPane, find.text('确认并返回类型安全结果'));
    await tester.ensureVisible(secondaryComplete);
    await tester.tap(secondaryComplete);
    await tester.pumpAndSettle();

    expect(_inside(secondaryPane, find.text('ID 42')), findsNothing);
    expect(_inside(primaryPane, find.text('ID 42')), findsOneWidget);
    expect(CCRouter.activeRouteEntries.single.hostId, 'host.primary');

    final primaryComplete = _inside(primaryPane, find.text('确认并返回类型安全结果'));
    await tester.ensureVisible(primaryComplete);
    await tester.tap(primaryComplete);
    await tester.pumpAndSettle();

    expect(_inside(primaryPane, find.text('ID 42')), findsNothing);
    expect(CCRouter.activeRouteEntries, isEmpty);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('wide low window keeps nested NavigationRail usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(createMultiHostDemoApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('narrow embedded Host keeps simulated split panes usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 960);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(createMultiHostDemoApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('自适应布局'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('simulate-hinge')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('adaptive-list-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('adaptive-detail-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('adaptive-hinge')), findsOneWidget);
    expect(tester.takeException(), isNull);

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

Finder _inside(Finder pane, Finder matching) =>
    find.descendant(of: pane, matching: matching);
