import 'package:ccrouter/ccrouter_host.dart'
    show
        CCFlutterBottomSheetPage,
        CCFlutterDialogPage,
        CCFlutterPage,
        CCFlutterRouteFactory;
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Material Android 页面不额外响应 Cupertino 边缘返回手势', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData(platform: TargetPlatform.android),
        home: const Text('root'),
      ),
    );
    final route = CCFlutterRouteFactory.createRoute<void>(
      context: navigatorKey.currentContext!,
      child: const Text('detail'),
      presentation: const CCPagePresentation(),
    );
    expect(route, isA<MaterialPageRoute<void>>());
    navigatorKey.currentState!.push<void>(route);
    await tester.pumpAndSettle();

    await tester.dragFrom(const Offset(1, 300), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('root'), findsOneWidget);
  });

  testWidgets('creates neutral page types without GoRouter', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox.shrink()),
    );

    final context = navigatorKey.currentContext!;
    final page = CCFlutterRouteFactory.createPage<void>(
      child: const Text('page'),
      presentation: const CCPagePresentation(
        routeType: CCPageRouteType.material,
      ),
      key: const ValueKey<String>('page'),
      name: '/page',
    );
    final sheet = CCFlutterRouteFactory.createPage<void>(
      child: const Text('sheet'),
      presentation: const CCModalBottomSheetPresentation(),
    );
    final dialog = CCFlutterRouteFactory.createPage<void>(
      child: const Text('dialog'),
      presentation: const CCDialogPresentation(),
    );

    expect(page, isA<CCFlutterPage<void>>());
    expect(sheet, isA<CCFlutterBottomSheetPage<void>>());
    expect(dialog, isA<CCFlutterDialogPage<void>>());

    final pageRoute = page.createRoute(context);
    expect(pageRoute.settings, same(page));
    expect(pageRoute, isA<MaterialPageRoute<void>>());
  });

  testWidgets('uses Cupertino native page routes when the host is Cupertino', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      CupertinoApp(navigatorKey: navigatorKey, home: const SizedBox.shrink()),
    );

    final route = CCFlutterRouteFactory.createRoute<void>(
      context: navigatorKey.currentContext!,
      child: const Text('cupertino'),
      presentation: const CCPagePresentation(),
      settings: const RouteSettings(name: '/cupertino'),
    );

    expect(route, isA<CupertinoPageRoute<void>>());
    expect(route.settings.name, '/cupertino');
  });

  testWidgets('platform-default page routes retain the iOS back gesture', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: const SizedBox.shrink(),
      ),
    );

    final route = CCFlutterRouteFactory.createRoute<void>(
      context: navigatorKey.currentContext!,
      child: const Text('typed result'),
      presentation: const CCPagePresentation(),
      settings: const RouteSettings(name: '/typed-result'),
    );

    expect(route, isA<MaterialPageRoute<void>>());
    final pageRoute = route as MaterialPageRoute<void>;
    navigatorKey.currentState!.push<void>(route);
    await tester.pumpAndSettle();

    expect(pageRoute.popGestureEnabled, isTrue);
    await tester.dragFrom(const Offset(1, 300), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('typed result'), findsNothing);
  });

  testWidgets('custom Cupertino hosts retain the Cupertino route family', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      CupertinoTheme(
        data: const CupertinoThemeData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Navigator(
            key: navigatorKey,
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              pageBuilder: (_, _, _) => const Text('root'),
            ),
          ),
        ),
      ),
    );

    final route = CCFlutterRouteFactory.createRoute<void>(
      context: navigatorKey.currentContext!,
      child: const Text('custom cupertino'),
      presentation: const CCPagePresentation(),
    );

    expect(route, isA<CupertinoPageRoute<void>>());
  });

  testWidgets('the nearest known App determines the route family', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      CupertinoApp(
        home: MaterialApp(
          navigatorKey: navigatorKey,
          home: const SizedBox.shrink(),
        ),
      ),
    );

    final route = CCFlutterRouteFactory.createRoute<void>(
      context: navigatorKey.currentContext!,
      child: const Text('nested material'),
      presentation: const CCPagePresentation(),
    );

    expect(route, isA<MaterialPageRoute<void>>());
  });

  testWidgets('creates configured custom page transitions', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox.shrink()),
    );

    final route = CCFlutterRouteFactory.createRoute<void>(
      context: navigatorKey.currentContext!,
      child: const Text('poster'),
      presentation: const CCPagePresentation(
        transition: CCPageTransitionType.slideFromBottom,
        opaque: false,
        fullscreenDialog: true,
      ),
    );

    expect(route, isA<PageRouteBuilder<void>>());
    final pageRoute = route as PageRouteBuilder<void>;
    expect(pageRoute.opaque, isFalse);
    expect(pageRoute.fullscreenDialog, isTrue);
    expect(pageRoute.transitionDuration, const Duration(milliseconds: 300));
    expect(pageRoute.reverseTransitionDuration, pageRoute.transitionDuration);

    navigatorKey.currentState!.push<void>(route);
    await tester.pumpAndSettle();
    expect(find.text('poster'), findsOneWidget);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
  });

  testWidgets('creates a configured bottom-sheet route', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox.shrink()),
    );

    final route = CCFlutterRouteFactory.createRoute<void>(
      context: navigatorKey.currentContext!,
      child: const Text('filters'),
      presentation: const CCModalBottomSheetPresentation(
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
      ),
    );

    expect(route, isA<ModalBottomSheetRoute<void>>());
    final sheet = route as ModalBottomSheetRoute<void>;
    expect(sheet.isDismissible, isFalse);
    expect(sheet.enableDrag, isFalse);
    expect(sheet.isScrollControlled, isTrue);
    expect(sheet.showDragHandle, isTrue);
    expect(sheet.useSafeArea, isTrue);
  });

  testWidgets('creates Material and Cupertino dialog routes', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox.shrink()),
    );
    final context = navigatorKey.currentContext!;

    final material = CCFlutterRouteFactory.createRoute<void>(
      context: context,
      child: const Text('material dialog'),
      presentation: const CCDialogPresentation(
        routeType: CCDialogRouteType.material,
        barrierDismissible: false,
        useSafeArea: false,
      ),
    );
    final cupertino = CCFlutterRouteFactory.createRoute<void>(
      context: context,
      child: const Text('cupertino dialog'),
      presentation: const CCDialogPresentation(
        routeType: CCDialogRouteType.cupertino,
        barrierDismissible: false,
      ),
    );

    expect(material, isA<DialogRoute<void>>());
    expect((material as DialogRoute<void>).barrierDismissible, isFalse);
    expect(cupertino, isA<CupertinoDialogRoute<void>>());
    expect(
      (cupertino as CupertinoDialogRoute<void>).barrierDismissible,
      isFalse,
    );
  });

  testWidgets('default dialogs follow the host route family', (tester) async {
    final materialNavigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: materialNavigatorKey,
        home: const SizedBox.shrink(),
      ),
    );

    final material = CCFlutterRouteFactory.createRoute<void>(
      context: materialNavigatorKey.currentContext!,
      child: const Text('material default dialog'),
      presentation: const CCDialogPresentation(),
    );
    expect(material, isA<DialogRoute<void>>());
    expect((material as DialogRoute<void>).barrierDismissible, isTrue);

    final cupertinoNavigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      CupertinoApp(
        navigatorKey: cupertinoNavigatorKey,
        home: const SizedBox.shrink(),
      ),
    );

    final cupertino = CCFlutterRouteFactory.createRoute<void>(
      context: cupertinoNavigatorKey.currentContext!,
      child: const Text('cupertino default dialog'),
      presentation: const CCDialogPresentation(),
    );
    expect(cupertino, isA<CupertinoDialogRoute<void>>());
    expect(
      (cupertino as CupertinoDialogRoute<void>).barrierDismissible,
      isFalse,
    );
  });
}
