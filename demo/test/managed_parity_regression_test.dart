import 'dart:async';

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
      ..dirtyForm = true
      ..blockDetailGlobally = false
      ..clear();
  });
  tearDown(CCRouterHost.shutdown);

  for (final managed in [true]) {
    const label = 'Managed';
    Future<void> mount(WidgetTester tester, {String initial = '/'}) async {
      CCRouterHost.initialize(
        hostAssembly: ccrouterGeneratedHostAssembly,
        deepLinkIngressPolicy: CCDeepLinkIngressPolicy(
          allowRelativePaths: true,
        ),
      );
      await tester.pumpWidget(
        CCRouterDemoApp(
          initialLocation: initial,
          listenForPlatformLinks: false,
        ),
      );
      await tester.pumpAndSettle();
    }

    if (managed) {
      testWidgets(
        '$label: root Context cannot bypass the selected Shell guard',
        (tester) async {
          await mount(tester);
          final rootContext = tester.element(find.byType(Navigator).first);
          unawaited(CCRouter.navigator.push(demoShellFeedIntent()));
          await tester.pumpAndSettle();
          unawaited(
            CCRouter.navigator.open(
              Uri.parse('/lab/policy/guarded'),
              context: tester.element(find.text('Shell Feed')),
            ),
          );
          await tester.pumpAndSettle();
          final handles = CCRouter.activeRouteEntries
              .map((entry) => entry.routeEntryId)
              .toList();
          final outcome = await CCRouter.navigator.maybePopOutcome(
            context: rootContext,
          );
          await tester.pumpAndSettle();
          expect(outcome.guardDeniedCode, 'demo_unsaved_form');
          expect(
            CCRouter.activeRouteEntries.map((entry) => entry.routeEntryId),
            handles,
          );
          expect(find.text('PopGuard'), findsOneWidget);
        },
      );

      for (final exit in ['close', 'go', 'reset']) {
        testWidgets('$label: $exit retires retained Shell ownership exactly', (
          tester,
        ) async {
          await mount(tester);
          await CCRouter.navigator.go(demoWorkspaceHomeIntent());
          await tester.pumpAndSettle();
          final original = CCRouter.routeEntryHandleOf(
            tester.element(find.text('Workspace Home')),
          )!;
          final pushed = CCRouter.navigator.push(demoShellFeedIntent());
          await tester.pumpAndSettle();
          if (exit == 'close') {
            final target = CCRouter.routeEntryHandleOf(
              tester.element(find.text('Shell Feed')),
            )!;
            expect(
              (await CCRouter.navigator.close(target)).status,
              CCRouteCloseStatus.closed,
            );
            await tester.pumpAndSettle();
            expect(find.text('Workspace Home'), findsOneWidget);
            expect(
              CCRouter.activeRouteEntries.any(
                (entry) => entry.routeEntryId == original.routeEntryId,
              ),
              isTrue,
            );
          } else {
            if (exit == 'go') {
              await CCRouter.navigator.go(demoHomeIntent());
            } else {
              await CCRouter.navigator.reset(demoHomeIntent());
            }
            await tester.pumpAndSettle();
            expect(CCRouter.activeRouteEntries, hasLength(1));
            expect(find.text('CCRouter Lab'), findsOneWidget);
          }
          await pushed;
        });
      }

      testWidgets('$label: first Shell page returns to the calling root', (
        tester,
      ) async {
        await mount(tester);
        final home = CCRouter.activeRouteEntries.single;
        final pushed = CCRouter.navigator.push(demoShellFeedIntent());
        await tester.pumpAndSettle();
        final context = tester.element(find.text('Shell Feed'));
        expect(CCRouter.navigator.canPop(context: context), isTrue);
        expect(await CCRouter.navigator.maybePop(context: context), isTrue);
        await tester.pumpAndSettle();
        await pushed;
        expect(find.text('CCRouter Lab'), findsOneWidget);
        expect(
          CCRouter.activeRouteEntries.single.routeEntryId,
          home.routeEntryId,
        );
      });

      testWidgets(
        '$label: cross Shell Back retains the original branch and State',
        (tester) async {
          await mount(tester);
          await CCRouter.navigator.go(demoWorkspaceActivityIntent());
          await tester.pumpAndSettle();
          await tester.tap(find.text('增加分支内状态'));
          await tester.pump();
          final original = CCRouter.activeRouteEntries
              .map((entry) => entry.routeEntryId)
              .toList();
          final pushed = CCRouter.navigator.push(demoShellFeedIntent());
          await tester.pumpAndSettle();
          expect(find.text('Shell Feed'), findsOneWidget);
          expect(await CCRouter.navigator.maybePop(), isTrue);
          await tester.pumpAndSettle();
          await pushed;
          expect(find.text('Workspace Activity'), findsOneWidget);
          expect(find.textContaining('本地计数：1'), findsOneWidget);
          expect(
            CCRouter.activeRouteEntries.map((entry) => entry.routeEntryId),
            original,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('$label: guarded page must not block a foreign dialog', (
      tester,
    ) async {
      await mount(tester);
      await CCRouter.navigator.open(Uri.parse('/lab/policy/guarded'));
      await tester.pumpAndSettle();
      final count = CCRouter.activeRouteEntries.length;
      final popup = showDialog<void>(
        context: tester.element(find.text('PopGuard')),
        builder: (_) => const AlertDialog(content: Text('review-popup')),
      );
      await tester.pumpAndSettle();
      final outcome = await CCRouter.navigator.maybePopOutcome();
      await tester.pumpAndSettle();
      expect(outcome.guardDeniedCode, isNull);
      expect(find.text('review-popup'), findsNothing);
      expect(CCRouter.activeRouteEntries, hasLength(count));
      await popup;
    });

    testWidgets('$label: cold nested link must return to its parent', (
      tester,
    ) async {
      await mount(tester, initial: '/workspace/home/42');
      expect(find.text('Workspace Detail #42'), findsOneWidget);
      final context = tester.element(find.text('Workspace Detail #42'));
      expect(CCRouter.navigator.canPop(context: context), isTrue);
      await CCRouter.navigator.maybePop(context: context);
      await tester.pumpAndSettle();
      expect(find.text('Workspace Home'), findsOneWidget);
    });

    if (managed) {
      for (final pop in ['maybePop', 'pop']) {
        testWidgets(
          '$label: $pop from guarded nested context consumes root popup only',
          (tester) async {
            await mount(tester);
            await CCRouter.navigator.go(demoWorkspaceHomeIntent());
            await tester.pumpAndSettle();
            await CCRouter.navigator.open(
              Uri.parse('/lab/policy/guarded'),
              context: tester.element(find.text('Workspace Home')),
            );
            await tester.pumpAndSettle();
            final context = tester.element(find.text('PopGuard'));
            final handle = CCRouter.routeEntryHandleOf(context);
            final count = CCRouter.activeRouteEntries.length;
            final popup = showDialog<String>(
              context: context,
              builder: (_) =>
                  const AlertDialog(content: Text('nested-root-popup')),
            );
            await tester.pumpAndSettle();
            if (pop == 'pop') {
              CCRouter.navigator.pop(context: context, result: 'popup-done');
            } else {
              final outcome = await CCRouter.navigator.maybePopOutcome(
                context: context,
                result: 'popup-done',
              );
              expect(outcome.guardDeniedCode, isNull);
              expect(outcome.removedEntryOwner, CCPopRemovedEntryOwner.foreign);
            }
            await tester.pumpAndSettle();
            expect(await popup, 'popup-done');
            expect(CCRouter.activeRouteEntries, hasLength(count));
            expect(CCRouter.routeEntryHandleOf(context), same(handle));
            expect(
              (await CCRouter.navigator.maybePopOutcome(
                context: context,
              )).guardDeniedCode,
              'demo_unsaved_form',
            );
          },
        );
      }
    }

    for (final operation in ['go', 'reset', 'openGo']) {
      testWidgets(
        '$label: $operation reconstructs the validated parent chain',
        (tester) async {
          await mount(tester);
          switch (operation) {
            case 'go':
              await CCRouter.navigator.go(demoWorkspaceDetailIntent(item: 42));
            case 'reset':
              await CCRouter.navigator.reset(
                demoWorkspaceDetailIntent(item: 42),
              );
            case 'openGo':
              await CCDeepLinkIngress.fromPlatform(
                Uri.parse('/workspace/home/42'),
                mode: CCDeepLinkOpenMode.go,
              );
          }
          await tester.pumpAndSettle();
          final context = tester.element(find.text('Workspace Detail #42'));
          expect(CCRouter.navigator.canPop(context: context), isTrue);
          await CCRouter.navigator.maybePop(context: context);
          await tester.pumpAndSettle();
          expect(find.text('Workspace Home'), findsOneWidget);
          if (managed) {
            expect(
              CCRouter.routeEntryHandleOf(
                tester.element(find.text('Workspace Home')),
              ),
              isNotNull,
            );
          }
        },
      );
    }

    testWidgets('$label: root overlay pop must restore Shell back target', (
      tester,
    ) async {
      await mount(tester);
      await CCRouter.navigator.go(demoWorkspaceHomeIntent());
      await tester.pumpAndSettle();
      unawaited(CCRouter.navigator.push(demoWorkspaceDetailIntent(item: 42)));
      await tester.pumpAndSettle();
      await CCRouter.navigator.open(Uri.parse('/lab/policy/proceed'));
      await tester.pumpAndSettle();
      expect(find.text('拦截器已放行'), findsWidgets);
      await CCRouter.navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Workspace Detail #42'), findsOneWidget);
      await CCRouter.navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Workspace Home'), findsOneWidget);
    });

    testWidgets('$label: retained branch URL must follow selected branch', (
      tester,
    ) async {
      await mount(tester);
      await CCRouter.navigator.go(demoWorkspaceHomeIntent());
      await tester.pumpAndSettle();
      unawaited(CCRouter.navigator.push(demoWorkspaceDetailIntent(item: 42)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(find.text('Workspace Activity'), findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Workspace Detail #42'), findsOneWidget);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final dynamic configuration =
          app.routerConfig!.routerDelegate.currentConfiguration;
      // GoRouter may intentionally omit imperative pushes from the URL, but
      // selecting Home must never leave another branch's Activity address.
      expect(configuration.uri.path, startsWith('/workspace/home'));
    });

    testWidgets('$label: default Host must honor platform startup path', (
      tester,
    ) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue =
          '/workspace/home/42';
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      await mount(tester);
      expect(find.text('Workspace Detail #42'), findsOneWidget);
    });

    testWidgets('$label: shutdown with mounted Shell must not rebuild errors', (
      tester,
    ) async {
      await mount(tester);
      await CCRouter.navigator.go(demoWorkspaceHomeIntent());
      await tester.pumpAndSettle();
      await CCRouterHost.shutdown();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('$label: foreign popup must hide underlying Runtime Entry', (
      tester,
    ) async {
      await mount(tester);
      await CCRouter.navigator.open(Uri.parse('/lab/policy/proceed'));
      await tester.pumpAndSettle();
      unawaited(
        showDialog<void>(
          context: tester.element(find.text('拦截器已放行').first),
          builder: (_) => const AlertDialog(content: Text('review-visibility')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        CCRouter.activeRouteEntries
            .singleWhere(
              (entry) => entry.routeId == 'demo_navigation_lab.proceed',
            )
            .lifecycleState,
        CCRouteEntryLifecycleState.hidden,
      );
    });

    testWidgets('$label: direct branch navigation must hide retained branch', (
      tester,
    ) async {
      await mount(tester);
      await CCRouter.navigator.go(demoWorkspaceHomeIntent());
      await tester.pumpAndSettle();
      unawaited(CCRouter.navigator.push(demoWorkspaceDetailIntent(item: 42)));
      await tester.pumpAndSettle();
      await CCRouter.navigator.go(demoWorkspaceActivityIntent());
      await tester.pumpAndSettle();
      expect(find.text('Workspace Activity'), findsOneWidget);
      expect(
        CCRouter.activeRouteEntries
            .singleWhere(
              (entry) =>
                  entry.routeId == 'demo_navigation_lab.workspace.detail',
            )
            .lifecycleState,
        CCRouteEntryLifecycleState.hidden,
      );
    });

    testWidgets(
      '$label: repeated iOS swipes remove exactly one Entry',
      (tester) async {
        await mount(tester);
        final baseCount = CCRouter.activeRouteEntries.length;
        for (var cycle = 0; cycle < 8; cycle++) {
          await CCRouter.navigator.open(Uri.parse('/lab/stack/101'));
          await tester.pumpAndSettle();
          final first = CCRouter.activeRouteEntries.last.routeEntryId;
          await CCRouter.navigator.open(Uri.parse('/lab/stack/202'));
          await tester.pumpAndSettle();
          final before = CCRouter.activeRouteEntries.length;
          final current = ModalRoute.of(
            tester.element(find.text('栈操作 · Level 202')),
          )!;
          expect(current.popGestureEnabled, isTrue);
          await tester.timedDragFrom(
            const Offset(1, 300),
            const Offset(650, 0),
            const Duration(milliseconds: 600),
          );
          await tester.pumpAndSettle();
          expect(CCRouter.activeRouteEntries, hasLength(before - 1));
          expect(CCRouter.activeRouteEntries.last.routeEntryId, same(first));
          expect(find.text('栈操作 · Level 101'), findsOneWidget);
          await CCRouter.navigator.maybePop();
          await tester.pumpAndSettle();
          expect(CCRouter.activeRouteEntries, hasLength(baseCount));
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets(
      '$label: cancelled iOS swipe preserves Entry identity',
      (tester) async {
        await mount(tester);
        await CCRouter.navigator.open(Uri.parse('/lab/stack/101'));
        await tester.pumpAndSettle();
        final before = CCRouter.activeRouteEntries
            .map((entry) => entry.routeEntryId)
            .toList();
        final gesture = await tester.startGesture(const Offset(1, 300));
        await gesture.moveBy(const Offset(100, 0));
        await tester.pump(const Duration(milliseconds: 100));
        await gesture.moveBy(const Offset(-90, 0));
        await tester.pump(const Duration(milliseconds: 200));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          CCRouter.activeRouteEntries.map((entry) => entry.routeEntryId),
          before,
        );
        expect(find.text('栈操作 · Level 101'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    if (managed) {
      testWidgets(
        'Managed: shutdown retires mounted Shell and foreign popup safely',
        (tester) async {
          await mount(tester);
          await CCRouter.navigator.go(demoWorkspaceHomeIntent());
          await tester.pumpAndSettle();
          unawaited(
            showDialog<void>(
              context: tester.element(find.text('Workspace Home')),
              builder: (_) =>
                  const AlertDialog(content: Text('shutdown-popup')),
            ),
          );
          await tester.pumpAndSettle();
          await CCRouterHost.shutdown();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'Managed: shutdown during a Shell edge swipe does not double remove',
        (tester) async {
          await mount(tester);
          await CCRouter.navigator.go(demoWorkspaceHomeIntent());
          await tester.pumpAndSettle();
          await CCRouter.navigator.open(
            Uri.parse('/lab/stack/101'),
            context: tester.element(find.text('Workspace Home')),
          );
          await tester.pumpAndSettle();
          final gesture = await tester.startGesture(const Offset(1, 300));
          await gesture.moveBy(const Offset(150, 0));
          await tester.pump();
          await CCRouterHost.shutdown();
          await tester.pumpAndSettle();
          await gesture.up();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      );

      testWidgets('Managed: close covered Shell seed must keep context child', (
        tester,
      ) async {
        await mount(tester);
        await CCRouter.navigator.go(demoWorkspaceHomeIntent());
        await tester.pumpAndSettle();
        final handle = CCRouter.routeEntryHandleOf(
          tester.element(find.text('Workspace Home')),
        )!;
        final context = tester.element(find.text('Workspace Home'));
        await CCRouter.navigator.open(
          Uri.parse('/lab/stack/101'),
          context: context,
        );
        await tester.pumpAndSettle();
        expect(find.text('栈操作 · Level 101'), findsOneWidget);
        final outcome = await CCRouter.navigator.close(handle);
        await tester.pumpAndSettle();
        expect(outcome.status, CCRouteCloseStatus.closed);
        expect(
          CCRouter.activeRouteEntries.any(
            (entry) => entry.routeId == 'demo_navigation_lab.stack',
          ),
          isTrue,
        );
        expect(find.text('栈操作 · Level 101'), findsOneWidget);
      });
    }
  }
}
