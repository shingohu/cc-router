import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_demo/ccrouter_generated/ccrouter_host.routes.g.dart';
import 'package:ccrouter_demo/examples/multi_host_demo.dart';
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
    tester.view.physicalSize = const Size(760, 900);
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

    await tester.tap(navigateButtons.at(1));
    await tester.pumpAndSettle();
    expect(find.text('栈操作 · Level 202'), findsOneWidget);
    expect(CCRouter.activeRouteEntries.single.hostId, 'window.secondary');

    await tester.tap(navigateButtons.at(0));
    await tester.pumpAndSettle();
    expect(find.text('栈操作 · Level 101'), findsOneWidget);
    expect(find.text('栈操作 · Level 202'), findsOneWidget);
    expect(CCRouter.activeRouteEntries.map((entry) => entry.hostId).toSet(), {
      'window.primary',
      'window.secondary',
    });

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
