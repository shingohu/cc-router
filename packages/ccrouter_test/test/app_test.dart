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
    expect(resolved!.id, 'default');

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
    final host = CCNavigationHost(id: 'window.main');
    final hostStates = <CCNavigationHostLifecycleState>[];
    final removeThrowingListener = host.addLifecycleListener((_) {
      throw StateError('isolated');
    });
    final removeListener = host.addLifecycleListener(
      (event) => hostStates.add(event.state),
    );

    await tester.pumpWidget(
      CCRouterApp(
        host: host,
        onLifecycleChanged: (state) => lifecycle = state,
        child: const SizedBox(),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(lifecycle, AppLifecycleState.paused);
    expect(host.lifecycleState, CCNavigationHostLifecycleState.paused);
    expect(hostStates, [
      CCNavigationHostLifecycleState.mounted,
      CCNavigationHostLifecycleState.paused,
    ]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    expect(host.lifecycleState, CCNavigationHostLifecycleState.unmounted);
    expect(hostStates.last, CCNavigationHostLifecycleState.unmounted);
    removeThrowingListener();
    removeListener();
  });

  test('CCNavigationHost owns one immutable key per Outlet', () {
    final root = GlobalKey<NavigatorState>();
    final detail = GlobalKey<NavigatorState>();
    final host = CCNavigationHost(
      id: 'window.main',
      navigatorKey: root,
      navigatorKeys: {'detail': detail},
    );

    expect(host.navigatorKey, same(root));
    expect(host.navigatorKeyFor('detail'), same(detail));
    expect(host.containsOutlet('root'), isTrue);
    expect(host.navigatorKeys.keys, containsAll(['root', 'detail']));
    expect(
      () => host.navigatorKeys['other'] = GlobalKey<NavigatorState>(),
      throwsUnsupportedError,
    );
    expect(() => host.navigatorKeyFor('missing'), throwsArgumentError);
    expect(
      () =>
          CCNavigationHost(navigatorKey: root, navigatorKeys: {'detail': root}),
      throwsArgumentError,
    );
  });

  testWidgets('one Host cannot be mounted by two CCRouterApp trees', (
    tester,
  ) async {
    final host = CCNavigationHost(id: 'window.shared');

    await tester.pumpWidget(
      Stack(
        textDirection: TextDirection.ltr,
        children: [
          CCRouterApp(
            key: const ValueKey('primary-host'),
            host: host,
            child: const SizedBox(),
          ),
        ],
      ),
    );
    expect(host.lifecycleState, CCNavigationHostLifecycleState.mounted);

    await tester.pumpWidget(
      Stack(
        textDirection: TextDirection.ltr,
        children: [
          CCRouterApp(
            key: const ValueKey('primary-host'),
            host: host,
            child: const SizedBox(),
          ),
          CCRouterApp(host: host, child: const SizedBox()),
        ],
      ),
    );

    expect(tester.takeException(), isA<FlutterError>());
    expect(host.lifecycleState, CCNavigationHostLifecycleState.mounted);
  });
}
