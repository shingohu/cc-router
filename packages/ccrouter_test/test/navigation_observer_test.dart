import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';

void main() {
  testWidgets('emits Outlet-tagged push, replace, and pop events', (
    tester,
  ) async {
    final events = <CCGoRouterNavigationEvent>[];
    final observer = CCGoRouterNavigationObserver(
      hostId: 'window.main',
      outlet: 'root',
      onEvent: events.add,
    );
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: const Text('home'),
      ),
    );
    await tester.pumpAndSettle();

    navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(builder: (_) => const Text('detail')),
    );
    await tester.pumpAndSettle();
    navigatorKey.currentState!.pushReplacement<void, void>(
      MaterialPageRoute<void>(builder: (_) => const Text('replacement')),
    );
    await tester.pumpAndSettle();
    navigatorKey.currentState!.pop('selected');
    await tester.pumpAndSettle();

    expect(events.length, greaterThanOrEqualTo(7));
    expect(
      events
          .where(
            (event) => event.kind != CCGoRouterNavigationEventKind.topChanged,
          )
          .map((event) => event.kind)
          .toList()
          .sublist(1),
      [
        CCGoRouterNavigationEventKind.push,
        CCGoRouterNavigationEventKind.replace,
        CCGoRouterNavigationEventKind.pop,
      ],
    );
    expect(
      events.where(
        (event) => event.kind == CCGoRouterNavigationEventKind.topChanged,
      ),
      isNotEmpty,
    );
    expect(events.every((event) => event.hostId == 'window.main'), isTrue);
    expect(events.every((event) => event.outlet == 'root'), isTrue);
    // NavigatorObserver in the current Flutter SDK does not expose Pop result.
  });

  testWidgets(
    'keeps GoRouter 17 forwarded Shell events on their actual Outlet',
    (tester) async {
      final rootEvents = <CCGoRouterNavigationEvent>[];
      final outletEvents = <CCGoRouterNavigationEvent>[];
      final rootKey = GlobalKey<NavigatorState>();
      final outletKey = GlobalKey<NavigatorState>();
      final rootObserver = CCGoRouterNavigationObserver(
        outlet: 'root',
        onEvent: rootEvents.add,
      );
      final outletObserver = CCGoRouterNavigationObserver(
        outlet: 'content',
        onEvent: outletEvents.add,
      );
      final router = GoRouter(
        navigatorKey: rootKey,
        initialLocation: '/home',
        observers: [rootObserver],
        routes: [
          ShellRoute(
            navigatorKey: outletKey,
            observers: [outletObserver],
            builder: (_, _, child) => child,
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const Text('home')),
              GoRoute(path: '/detail', builder: (_, _) => const Text('detail')),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      rootEvents.clear();
      outletEvents.clear();

      final pushed = router.push<void>('/detail');
      await tester.pumpAndSettle();

      expect(find.text('detail'), findsOneWidget);
      expect(
        outletEvents.where(
          (event) => event.kind == CCGoRouterNavigationEventKind.push,
        ),
        isNotEmpty,
      );
      expect(outletEvents.every((event) => event.outlet == 'content'), isTrue);
      expect(rootEvents, isEmpty);

      router.pop();
      await tester.pumpAndSettle();
      await pushed;
    },
  );
}
