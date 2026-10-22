// ignore: deprecated_member_use
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

final class _Resources {
  final routes = <WeakReference<Route<void>>>[];
  final controllers = <WeakReference<AnimationController>>[];
  final arguments = <WeakReference<Object>>[];
  var disposedRoutes = 0;
}

final class _TrackedRoute extends MaterialPageRoute<void> {
  _TrackedRoute(this.resources, int index)
    : super(
        settings: RouteSettings(name: '/closed/$index', arguments: Object()),
        builder: (_) => const Text('temporary page'),
      ) {
    resources.routes.add(WeakReference(this));
    resources.arguments.add(WeakReference(settings.arguments!));
  }

  final _Resources resources;

  @override
  AnimationController createAnimationController() {
    final controller = super.createAnimationController();
    resources.controllers.add(WeakReference(controller));
    return controller;
  }

  @override
  void dispose() {
    super.dispose();
    resources.disposedRoutes++;
  }
}

// Keep strong Route locals out of the scope that later forces GC.
Future<void> _visit(
  WidgetTester tester,
  NavigatorState navigator,
  _Resources resources,
  String removal,
  int index,
) async {
  final route = _TrackedRoute(resources, index * 2);
  final completed = navigator.push<void>(route);
  await tester.pumpAndSettle();
  switch (removal) {
    case 'pop':
      navigator.pop();
    case 'replace':
      navigator.pushReplacement<void, void>(
        _TrackedRoute(resources, index * 2 + 1),
      );
      await tester.pumpAndSettle();
      navigator.pop();
    case 'remove':
      navigator.removeRoute(route);
  }
  await tester.pumpAndSettle();
  await completed;
}

void main() {
  for (final capacity in [0, 2, 1000]) {
    for (final removal in ['pop', 'replace', 'remove']) {
      testWidgets(
        '$removal releases Routes and controllers with live history capacity $capacity',
        (tester) async {
          final observer = CCGoRouterNavigationObserver(outlet: 'root');
          final navigatorKey = GlobalKey<NavigatorState>();
          final router = GoRouter(
            navigatorKey: navigatorKey,
            observers: [observer],
            routes: [GoRoute(path: '/', builder: (_, _) => const Text('home'))],
          );
          final adapter = CCGoRouterAdapter(
            router: router,
            observers: [observer],
            lifecycleEventCapacity: capacity,
          );
          addTearDown(() {
            adapter.dispose();
            router.dispose();
          });
          adapter.initialize(const []);
          await tester.pumpWidget(MaterialApp.router(routerConfig: router));
          await tester.pumpAndSettle();

          final resources = _Resources();
          for (var index = 0; index < 5; index++) {
            await _visit(
              tester,
              navigatorKey.currentState!,
              resources,
              removal,
              index,
            );
          }
          final expected = removal == 'replace' ? 10 : 5;
          expect(resources.disposedRoutes, expected);
          expect(resources.controllers, hasLength(expected));
          // Retain a caller's history snapshot too: neither it nor the live
          // Adapter may keep closed resources alive. No capacity eviction or
          // Adapter/Router disposal may be used to make this test pass.
          final history = adapter.lifecycleEvents;
          expect(history.length, capacity == 0 ? 0 : greaterThan(0));
          expect(history.length, lessThan(1000));
          await tester.runAsync(
            () =>
                forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20)),
          );
          expect(
            resources.routes.map((ref) => ref.target),
            everyElement(isNull),
          );
          expect(
            resources.controllers.map((ref) => ref.target),
            everyElement(isNull),
          );
          expect(
            resources.arguments.map((ref) => ref.target),
            everyElement(isNull),
          );
          expect(adapter.lifecycleEvents.length, history.length);
          expect(find.text('home'), findsOneWidget);
          expect(navigatorKey.currentState!.canPop(), isFalse);
        },
      );
    }
  }
}
