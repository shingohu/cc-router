import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

CCNavigationRoute route(String id) => CCNavigationRoute(
  routeId: id,
  patterns: [const CCPathPattern('/detail/:value', primary: true)],
  presentation: const CCPagePresentation(),
  deepLink: CCDeepLinkPolicy.disabled,
);

CCNavigationRequest request({
  required String id,
  required CCNavigationOperation operation,
  required Uri uri,
}) => CCNavigationRequest(
  navigationId: 'test-$id-${operation.name}',
  operation: operation,
  routeId: id,
  uri: uri,
  arguments: const Object(),
  presentation: const CCPagePresentation(),
  origin: CCNavigationOrigin.internal,
);

void main() {
  testWidgets('maps typed Push and Pop through the supplied GoRouter', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Text('home'),
        ),
        GoRoute(
          path: '/detail/:value',
          builder: (_, state) => Text('detail:${state.pathParameters['value']}'),
        ),
      ],
    );
    final adapter = CCGoRouterAdapter(router: router);
    addTearDown(router.dispose);

    await adapter.initialize([route('detail')]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final result = adapter.navigate(
      request(
        id: 'detail',
        operation: CCNavigationOperation.push,
        uri: Uri.parse('/detail/42'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('detail:42'), findsOneWidget);
    adapter.pop(result: 'done');
    await tester.pumpAndSettle();
    expect(await result, 'done');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('normalizes absolute URI requests to GoRouter paths', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Text('home'),
        ),
        GoRoute(
          path: '/detail/:value',
          builder: (_, state) => Text(
            'detail:${state.pathParameters['value']}:${state.uri.queryParameters['tab']}',
          ),
        ),
      ],
    );
    final adapter = CCGoRouterAdapter(router: router);
    addTearDown(router.dispose);

    await adapter.initialize([route('detail')]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await adapter.navigate(
      request(
        id: 'detail',
        operation: CCNavigationOperation.go,
        uri: Uri.parse('https://example.com/detail/42?tab=items'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('detail:42:items'), findsOneWidget);
  });

  test('rejects modal presentations until their backend semantics are ready',
      () async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
    );
    final adapter = CCGoRouterAdapter(router: router);
    addTearDown(router.dispose);

    final modal = CCNavigationRoute(
      routeId: 'filters',
      patterns: [const CCPathPattern('/filters', primary: true)],
      presentation: const CCModalBottomSheetPresentation(),
      deepLink: CCDeepLinkPolicy.disabled,
    );

    await expectLater(
      adapter.initialize([modal]),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    expect(adapter.isInitialized, isFalse);
  });

  test('guards adapter lifecycle transitions', () async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
    );
    final adapter = CCGoRouterAdapter(router: router);
    addTearDown(router.dispose);
    final navigation = request(
      id: 'detail',
      operation: CCNavigationOperation.go,
      uri: Uri.parse('/detail/1'),
    );

    expect(
      () => adapter.navigate(navigation),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    await adapter.initialize([route('detail')]);
    await expectLater(
      adapter.initialize([route('detail')]),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    await adapter.dispose();
    expect(adapter.isInitialized, isFalse);
    expect(
      () => adapter.navigate(navigation),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    expect(
      () => adapter.canPop(),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    await expectLater(
      adapter.initialize([route('detail')]),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    await adapter.dispose();
  });

  test('Runtime owns adapter disposal while Session close does not', () async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
    );
    final adapter = CCGoRouterAdapter(router: router);
    addTearDown(router.dispose);
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      components: const [],
    );

    await runtime.initialize();
    runtime.openSession(accountId: 'account');
    await runtime.closeSession();
    expect(adapter.isInitialized, isTrue);
    await runtime.dispose();
    expect(adapter.isInitialized, isFalse);
  });

  test('validates one-to-one Runtime route bindings', () async {
    final goRoute = GoRoute(
      path: '/detail/:value',
      builder: (_, _) => const SizedBox(),
    );
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox()),
        goRoute,
      ],
    );
    final adapter = CCGoRouterAdapter(
      router: router,
      bindings: [
        CCGoRouterRouteBinding(routeId: 'detail', goRoute: goRoute),
      ],
    );
    addTearDown(router.dispose);

    await adapter.initialize([route('detail')]);
    expect(adapter.bindings.single.routeId, 'detail');
    expect(adapter.bindings.single.goRoute, same(goRoute));
    await adapter.dispose();
  });

  test('rejects missing and unknown route bindings', () async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
    );
    final adapter = CCGoRouterAdapter(
      router: router,
      bindings: [
        CCGoRouterRouteBinding(
          routeId: 'unknown',
          goRoute: GoRoute(
            path: '/unknown',
            builder: (_, _) => const SizedBox(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await expectLater(
      adapter.initialize([route('detail')]),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    expect(adapter.isInitialized, isFalse);
  });
}
