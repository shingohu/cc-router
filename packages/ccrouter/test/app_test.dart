import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CCRouterApp exposes the supplied navigation host', (
    tester,
  ) async {
    final host = CCNavigationHost(id: 'main');
    late CCNavigationHost resolved;

    await tester.pumpWidget(
      CCRouterApp(
        host: host,
        child: Builder(
          builder: (context) {
            resolved = CCRouterApp.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(identical(resolved, host), isTrue);
    expect(resolved.id, 'main');
    expect(resolved.navigatorKey, same(host.navigatorKey));
  });

  testWidgets('CCRouterApp creates an internal host and removes its scope', (
    tester,
  ) async {
    CCNavigationHost? resolved;

    await tester.pumpWidget(
      CCRouterApp(
        child: Builder(
          builder: (context) {
            resolved = CCRouterApp.maybeOf(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(resolved, isNotNull);
    expect(resolved!.id, 'root');

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          resolved = CCRouterApp.maybeOf(context);
          return const SizedBox();
        },
      ),
    );
    expect(resolved, isNull);
  });

  testWidgets('CCRouterApp forwards lifecycle changes without owning Runtime', (
    tester,
  ) async {
    AppLifecycleState? lifecycle;

    await tester.pumpWidget(
      CCRouterApp(
        onLifecycleChanged: (state) => lifecycle = state,
        child: const SizedBox(),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(lifecycle, AppLifecycleState.paused);
  });
}
