import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_demo/ccrouter_demo.dart';
import 'package:ccrouter_demo/main.dart';
import 'package:demo_navigation_lab/demo_navigation_lab.dart';
import 'package:demo_navigation_lab/demo_navigation_lab_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _gesture(WidgetTester tester, String method) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(
        method,
        method == 'startBackGesture' || method == 'updateBackGestureProgress'
            ? <String, Object>{
                'touchOffset': <double>[5, 300],
                'progress': method == 'startBackGesture' ? 0.0 : .4,
                'swipeEdge': 0,
              }
            : null,
      ),
    ),
    (_) {},
  );
  await tester.pump();
}

List<String> get _phases => demoNavigationLabStore.events
    .where((event) => event.contains('Predictive back ·'))
    .map((event) => event.split('Predictive back ·').last.trim())
    .toList()
    .reversed
    .toList();

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    demoNavigationLabStore
      ..clear()
      ..blockDetailGlobally = false
      ..dirtyForm = true;
    CCRouterHost.initialize(hostAssembly: ccrouterGeneratedHostAssembly);
  });
  tearDown(() async {
    await CCRouterHost.shutdown();
  });

  for (final enabled in [false, true]) {
    _demoTest('real Demo typed page cancel/commit, bridge=$enabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        CCRouterDemoApp(
          enablePredictiveBack: enabled,
          listenForPlatformLinks: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('导航'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Push + typed result'));
      await tester.pumpAndSettle();
      final count = CCRouter.activeRouteEntries.length;
      await _gesture(tester, 'startBackGesture');
      await _gesture(tester, 'updateBackGestureProgress');
      await _gesture(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('ID 42'), findsOneWidget);
      expect(CCRouter.activeRouteEntries, hasLength(count));
      expect(
        demoNavigationLabStore.events.where(
          (event) => event.contains('Detail onPageHide'),
        ),
        isEmpty,
      );
      await _gesture(tester, 'startBackGesture');
      await _gesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('ID 42'), findsNothing);
      expect(CCRouter.activeRouteEntries, hasLength(count - 1));
      expect(
        _phases,
        enabled ? ['started', 'cancelled', 'started', 'committed'] : isEmpty,
      );
      expect(
        demoNavigationLabStore.events.where(
          (event) => event.contains('Detail dispose'),
        ),
        hasLength(1),
      );
      await _close(tester);
    });
  }

  _demoTest('real Demo Guard denies then allows non-interactive fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CCRouterDemoApp(
        enablePredictiveBack: true,
        listenForPlatformLinks: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('策略'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('PopGuard 未保存表单'),
      320,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('PopGuard 未保存表单'));
    await tester.pumpAndSettle();
    for (final dirty in [true, false]) {
      demoNavigationLabStore.setDirtyForm(dirty);
      await tester.pumpAndSettle();
      await _gesture(tester, 'startBackGesture');
      expect(
        Navigator.of(
          tester.element(find.text('PopGuard')),
        ).userGestureInProgress,
        isFalse,
      );
      await _gesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('PopGuard'), dirty ? findsOneWidget : findsNothing);
    }
    expect(_phases, isEmpty);
    await _close(tester);
  });

  for (final workspace in [false, true]) {
    _demoTest('Demo nested Outlet identity, StatefulShell=$workspace', (
      tester,
    ) async {
      await tester.pumpWidget(
        const CCRouterDemoApp(
          enablePredictiveBack: true,
          listenForPlatformLinks: false,
        ),
      );
      await tester.pumpAndSettle();
      await CCRouter.navigator.go(
        workspace ? demoWorkspaceHomeIntent() : demoShellFeedIntent(),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(workspace ? '打开 Home 分支详情' : '在 Shell Outlet 内打开详情'),
      );
      await tester.pumpAndSettle();
      await _gesture(tester, 'startBackGesture');
      await _gesture(tester, 'updateBackGestureProgress');
      await _gesture(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(
        find.text(workspace ? 'Workspace Detail #42' : 'Shell Detail #7'),
        findsOneWidget,
      );
      await _gesture(tester, 'startBackGesture');
      await _gesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(_phases, ['started', 'cancelled', 'started', 'committed']);
      final pop = CCRouter.recentBackendNavigationEvents.lastWhere(
        (event) => event.kind == CCNavigationBackendEventKind.pop,
      );
      expect(
        pop.navigatorOutlet,
        workspace ? demoWorkspaceHomeOutlet : demoSingleShellOutlet,
      );
      expect(
        find.text(workspace ? 'Workspace Home' : 'Shell Feed'),
        findsOneWidget,
      );
      await _close(tester);
    });
  }

  for (final workspace in [false, true]) {
    for (final timing in ['before', 'during', 'transient']) {
      _demoTest(
        'ancestor Popup protects nested detail: workspace=$workspace timing=$timing',
        (tester) async {
          await tester.pumpWidget(
            const CCRouterDemoApp(
              enablePredictiveBack: true,
              listenForPlatformLinks: false,
            ),
          );
          await tester.pumpAndSettle();
          await CCRouter.navigator.go(
            workspace ? demoWorkspaceHomeIntent() : demoShellFeedIntent(),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(workspace ? '打开 Home 分支详情' : '在 Shell Outlet 内打开详情'),
          );
          await tester.pumpAndSettle();
          final title = workspace ? 'Workspace Detail #42' : 'Shell Detail #7';
          final count = CCRouter.activeRouteEntries.length;
          if (timing != 'before') {
            await _gesture(tester, 'startBackGesture');
            await _gesture(tester, 'updateBackGestureProgress');
          }
          showDialog<void>(
            context: tester.element(find.text(title)),
            builder: (context) => AlertDialog(
              content: const Text('Ancestor popup'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Dismiss popup'),
                ),
              ],
            ),
          );
          await tester.pumpAndSettle();
          if (timing == 'transient') {
            await tester.tap(find.text('Dismiss popup'));
            await tester.pumpAndSettle();
          }
          if (timing == 'before') await _gesture(tester, 'startBackGesture');
          await _gesture(tester, 'commitBackGesture');
          await tester.pumpAndSettle();
          expect(find.text(title, skipOffstage: false), findsOneWidget);
          expect(CCRouter.activeRouteEntries, hasLength(count));
          final detailRoute = ModalRoute.of(
            tester.element(find.text(title, skipOffstage: false)),
          )!;
          expect(detailRoute.animation!.value, 1);
          expect(detailRoute.navigator!.userGestureInProgress, isFalse);
          expect(
            find.text('Ancestor popup'),
            timing == 'during' ? findsOneWidget : findsNothing,
          );
          expect(
            _phases,
            timing == 'before' ? isEmpty : ['started', 'cancelled'],
          );
          if (timing == 'during') {
            await _gesture(tester, 'startBackGesture');
            await _gesture(tester, 'commitBackGesture');
            await tester.pumpAndSettle();
            expect(find.text('Ancestor popup'), findsNothing);
            expect(CCRouter.activeRouteEntries, hasLength(count));
          }
          await _gesture(tester, 'startBackGesture');
          await _gesture(tester, 'commitBackGesture');
          await tester.pumpAndSettle();
          expect(find.text(title), findsNothing);
          expect(CCRouter.activeRouteEntries, hasLength(count - 1));
          expect(_phases, [
            ...(timing == 'before' ? <String>[] : ['started', 'cancelled']),
            'started',
            'committed',
          ]);
          await _close(tester);
        },
      );
    }
  }

  _demoTest('Demo branch switch invalidates in-flight preview', (tester) async {
    await tester.pumpWidget(
      const CCRouterDemoApp(
        enablePredictiveBack: true,
        listenForPlatformLinks: false,
      ),
    );
    await tester.pumpAndSettle();
    await CCRouter.navigator.go(demoWorkspaceHomeIntent());
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开 Home 分支详情'));
    await tester.pumpAndSettle();
    await _gesture(tester, 'startBackGesture');
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    await _gesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('Workspace Activity'), findsOneWidget);
    expect(_phases, ['started', 'cancelled']);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Workspace Detail #42'), findsOneWidget);
    await _close(tester);
  });
}

void _demoTest(String description, WidgetTesterCallback callback) {
  testWidgets(
    description,
    callback,
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
