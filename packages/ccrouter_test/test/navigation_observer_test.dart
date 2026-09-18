import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';

void main() {
  testWidgets('emits Outlet-tagged push, replace, and pop events', (
    tester,
  ) async {
    final events = <CCGoRouterNavigationEvent>[];
    final observer = CCGoRouterNavigationObserver(
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

    expect(events.length, greaterThanOrEqualTo(4));
    expect(
      events.map((event) => event.kind).toList().sublist(events.length - 3),
      [
        CCGoRouterNavigationEventKind.push,
        CCGoRouterNavigationEventKind.replace,
        CCGoRouterNavigationEventKind.pop,
      ],
    );
    expect(events.every((event) => event.outlet == 'root'), isTrue);
    // NavigatorObserver in the current Flutter SDK does not expose Pop result.
    expect(events.last.result, isNull);
  });
}
