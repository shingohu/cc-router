import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_demo/ccrouter_demo.dart';
import 'package:ccrouter_demo/demo_router_backend.dart';
import 'package:ccrouter_demo/main.dart';
import 'package:demo_navigation_lab/demo_navigation_lab_host.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const detailId = 'demo_navigation_lab.shell.detail';
  const target = ValueKey('shell-presentation-target');

  // Exercise the real Demo Shell tree with a substituted destination, without
  // attaching a Runtime. Existing widget tests cover managed Entry ownership.
  for (final (label, presentation) in <(String, CCRoutePresentation)>[
    (
      'cupertino',
      const CCPagePresentation(routeType: CCPageRouteType.cupertino),
    ),
    (
      'transparent',
      const CCPagePresentation(
        transition: CCPageTransitionType.slideFromBottom,
        opaque: false,
      ),
    ),
    (
      'dialog',
      const CCDialogPresentation(routeType: CCDialogRouteType.material),
    ),
    ('bottom sheet', const CCModalBottomSheetPresentation()),
  ]) {
    testWidgets('Shell preserves $label presentation, arguments and result', (
      tester,
    ) async {
      CCRouteCodecValues? received;
      final original = ccrouterGeneratedHostAssembly.routeCatalog;
      final catalog = CCFlutterRouteCatalog([
        for (final destination in original.destinations)
          if (destination.routeId != detailId)
            destination
          else
            CCFlutterRouteDestination(
              route: CCNavigationRoute(
                routeId: detailId,
                patterns: destination.route.patterns,
                presentation: presentation,
                deepLink: destination.route.deepLink,
                placement: destination.route.placement,
              ),
              builder: (arguments) {
                received = arguments;
                return const SizedBox(key: target, height: 120, width: 120);
              },
            ),
      ], componentVersions: original.componentVersions);
      final backend = createDemoRouterBackend(
        catalog: catalog,
        initialLocation: '/shell/feed',
      );
      addTearDown(() async {
        backend.adapter.dispose();
        await backend.dispose();
      });
      await tester.pumpWidget(MaterialApp.router(routerConfig: backend.router));
      await tester.pumpAndSettle();
      final extra = Object();
      final result = backend.router.push<String>(
        '/shell/feed/27?tag=one&tag=two',
        extra: extra,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(received!.path['item'], '27');
      expect(received!.query['tag'], ['one', 'two']);
      expect(received!.extra, same(extra));
      final context = tester.element(find.byKey(target));
      final route = ModalRoute.of(context)!;
      expect(route.settings.name, detailId);
      expect(route.settings.arguments, same(extra));
      expect(
        Navigator.of(context),
        same(backend.host.navigatorKeyFor('shell.content').currentState),
      );
      switch (label) {
        case 'cupertino':
          expect(route, isA<CupertinoPageRoute<Object?>>());
        case 'transparent':
          expect(route.opaque, isFalse);
          expect(route, isA<PageRouteBuilder<Object?>>());
          expect(route.transitionDuration, const Duration(milliseconds: 300));
          expect(find.text('Shell Feed'), findsOneWidget);
        case 'dialog':
          expect(route, isA<DialogRoute<Object?>>());
        case 'bottom sheet':
          expect(route, isA<ModalBottomSheetRoute<Object?>>());
      }

      backend.router.pop('done');
      await tester.pumpAndSettle();
      expect(await result, 'done');
      expect(find.byKey(target), findsNothing);
      expect(find.text('Shell Feed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('Managed Backend preserves Shell branches and typed Pop', (
    tester,
  ) async {
    CCRouterHost.initialize(hostAssembly: ccrouterGeneratedHostAssembly);
    addTearDown(CCRouterHost.shutdown);
    await tester.pumpWidget(
      const CCRouterDemoApp(
        initialLocation: '/shell/feed',
        listenForPlatformLinks: false,
        useManagedBackend: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shell Feed'), findsOneWidget);
    await CCRouter.navigator.go(demoWorkspaceHomeIntent());
    await tester.pumpAndSettle();
    expect(find.text('Workspace Home'), findsOneWidget);

    final detail = CCRouter.navigator.push<void>(
      demoWorkspaceDetailIntent(item: 42),
    );
    await tester.pumpAndSettle();
    expect(find.text('Workspace Detail #42'), findsOneWidget);
    CCRouter.navigator.pop();
    await tester.pumpAndSettle();
    await detail;
    expect(find.text('Workspace Home'), findsOneWidget);
  });
}
