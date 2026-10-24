import 'dart:async';
import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_demo/ccrouter_demo.dart';
import 'package:ccrouter_demo/multi_host_demo.dart';
import 'package:ccrouter_demo/platform_deep_link_bridge.dart';
import 'package:demo_navigation_lab/demo_navigation_lab_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(CCRouterHost.shutdown);
  testWidgets(
    'Demo split fold unfold releases destroyed popup and preserves identities',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      CCRouterHost.initialize(
        hostAssembly: ccrouterGeneratedHostAssembly,
        deepLinkIngressPolicy: demoDeepLinkIngressPolicy,
      );
      await tester.pumpWidget(createMultiHostDemoApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('自适应布局'));
      await tester.pumpAndSettle();
      var context = tester.element(find.text('Detail View · adaptive.detail'));
      final pushed = CCRouter.navigator.push(
        demoStackIntent(level: 73, returnsResult: true),
        context: context,
      );
      unawaited(
        pushed.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      await tester.pumpAndSettle();
      context = tester.element(find.text('栈操作 · Level 73'));
      final handle = CCRouter.routeEntryHandleOf(context)!;
      final popup = DialogRoute<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('demo-local-popup')),
      );
      unawaited(Navigator.of(context).push(popup));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(500, 900);
      await tester.pumpAndSettle();
      expect(find.text('demo-local-popup'), findsNothing);
      tester.view.physicalSize = const Size(1280, 900);
      await tester.pumpAndSettle();
      expect(find.text('栈操作 · Level 73'), findsOneWidget);
      expect(
        CCRouter.activeRouteEntries
            .where((e) => e.routeId == 'demo_navigation_lab.stack')
            .single
            .handle,
        same(handle),
      );
      final stale = CCRouter.activeBackendEntries
          .where(
            (e) =>
                e.owner == CCBackendEntryOwner.foreign &&
                e.navigatorOutlet == 'adaptive.detail',
          )
          .length;
      final close = await CCRouter.navigator.close(handle, result: 'closed');
      await tester.pumpAndSettle();
      expect(close.status, CCRouteCloseStatus.closed);
      expect(await pushed, 'closed');
      expect(
        find.text('Detail View · adaptive.detail'),
        findsOneWidget,
        reason:
            'closing the final managed detail must reveal its base surface, not an obsolete empty anchor',
      );
      expect(stale, 0);
    },
  );
}
