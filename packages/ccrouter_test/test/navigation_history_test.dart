// ignore: deprecated_member_use
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final capacity in [0, 1, 2, 3, 1000]) {
    test('history capacity $capacity preserves order and backend delivery', () {
      var rawEvents = 0;
      final home = MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/'),
        builder: (_) => const SizedBox(),
      );
      final detail = MaterialPageRoute<void>(
        settings: RouteSettings(name: '/detail', arguments: Object()),
        builder: (_) => const SizedBox(),
      );
      final observer = CCGoRouterNavigationObserver(
        outlet: 'root',
        onEvent: (event) {
          rawEvents++;
          expect(event.route, same(detail));
          expect(event.previousRoute, same(home));
        },
      );
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
      );
      final adapter = CCGoRouterAdapter(
        router: router,
        observers: [observer],
        lifecycleEventCapacity: capacity,
      );
      addTearDown(() {
        adapter.dispose();
        router.dispose();
        home.dispose();
        detail.dispose();
      });
      adapter.initialize(const []);
      var backendEvents = 0;
      adapter.addBackendEventListener((_) => backendEvents++);
      observer.didPush(detail, home);
      final first = adapter.lifecycleEvents;
      if (capacity > 0) {
        expect(first.single.kind, CCGoRouterNavigationEventKind.push);
        expect(first.single.hostId, 'default');
        expect(first.single.outlet, 'root');
        expect(first.single.location, '/detail');
        expect(first.single.previousLocation, '/');
      }
      expect(() => first.clear(), throwsUnsupportedError);

      observer.didReplace(newRoute: detail, oldRoute: home);
      observer.didPop(detail, home);
      observer.didRemove(detail, home);
      observer.didChangeTop(detail, home);
      final kinds = [
        CCGoRouterNavigationEventKind.push,
        CCGoRouterNavigationEventKind.replace,
        CCGoRouterNavigationEventKind.pop,
        CCGoRouterNavigationEventKind.remove,
        CCGoRouterNavigationEventKind.topChanged,
      ];
      expect(rawEvents, 5);
      expect(backendEvents, 5);
      expect(
        adapter.lifecycleEvents.map((event) => event.kind),
        kinds.skip(capacity >= kinds.length ? 0 : kinds.length - capacity),
      );
      // A caller's earlier list is independent from subsequent writes/eviction.
      expect(first.length, capacity == 0 ? 0 : 1);
      if (first.isNotEmpty) {
        expect(first.single.kind, CCGoRouterNavigationEventKind.push);
      }
      // Exercise multiple wraps, including odd capacities. Compare against
      // the event sequence rather than the ring's physical slot layout.
      for (var index = 0; index < capacity * 3 + 7; index++) {
        final kind = CCGoRouterNavigationEventKind
            .values[index % CCGoRouterNavigationEventKind.values.length];
        switch (kind) {
          case CCGoRouterNavigationEventKind.push:
            observer.didPush(detail, home);
          case CCGoRouterNavigationEventKind.pop:
            observer.didPop(detail, home);
          case CCGoRouterNavigationEventKind.replace:
            observer.didReplace(newRoute: detail, oldRoute: home);
          case CCGoRouterNavigationEventKind.remove:
            observer.didRemove(detail, home);
          case CCGoRouterNavigationEventKind.topChanged:
            observer.didChangeTop(detail, home);
        }
        kinds.add(kind);
      }
      final wrapped = adapter.lifecycleEvents;
      final expectedKinds = kinds.skip(kinds.length - capacity).toList();
      expect(wrapped.map((event) => event.kind), expectedKinds);
      expect(() => wrapped.clear(), throwsUnsupportedError);
      observer.didPush(detail, home);
      expect(wrapped.map((event) => event.kind), expectedKinds);
      final deliveredBeforeDispose = backendEvents;
      adapter.dispose();
      expect(adapter.lifecycleEvents, isEmpty);
      expect(wrapped.map((event) => event.kind), expectedKinds);
      observer.didPush(detail, home);
      expect(backendEvents, deliveredBeforeDispose);
      expect(adapter.lifecycleEvents, isEmpty);
    });
  }
}
