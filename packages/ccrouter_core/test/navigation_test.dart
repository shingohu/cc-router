import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:test/test.dart';

final class TestRegistrar implements CCComponentRegistrar {
  TestRegistrar(this.body);

  final void Function(CCRegistry) body;

  @override
  void register(CCRegistry registry) => body(registry);
}

final class RouteArgs {
  const RouteArgs(this.value, {this.tab, this.payload});

  final String value;
  final String? tab;
  final Object? payload;
}

final class RouteArgsCodec implements CCRouteCodec<RouteArgs> {
  const RouteArgsCodec();

  @override
  RouteArgs decode(CCEncodedRouteArguments input) => RouteArgs(
    input.path['value']!,
    tab: input.query['tab']?.single,
    payload: input.extra,
  );

  @override
  CCEncodedRouteArguments encode(RouteArgs arguments) =>
      CCEncodedRouteArguments(
        path: {'value': arguments.value},
        query: {
          if (arguments.tab != null) 'tab': [arguments.tab!],
        },
        extra: arguments.payload,
      );
}

final class MissingPathCodec implements CCRouteCodec<RouteArgs> {
  const MissingPathCodec();

  @override
  RouteArgs decode(CCEncodedRouteArguments input) =>
      RouteArgs(input.path['value']!);

  @override
  CCEncodedRouteArguments encode(RouteArgs arguments) =>
      CCEncodedRouteArguments();
}

final class UnknownPathCodec implements CCRouteCodec<RouteArgs> {
  const UnknownPathCodec();

  @override
  RouteArgs decode(CCEncodedRouteArguments input) =>
      RouteArgs(input.path['value']!);

  @override
  CCEncodedRouteArguments encode(RouteArgs arguments) =>
      CCEncodedRouteArguments(
        path: {'value': arguments.value, 'unknown': 'unexpected'},
      );
}

final class TestIntent<R> implements CCRouteIntent<R> {
  const TestIntent(this.routeId, this.arguments);

  @override
  final String routeId;

  @override
  final Object arguments;
}

final class FailingNavigationAdapter implements CCNavigationAdapter {
  @override
  Future<void> initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) async {}

  @override
  Future<Object?> navigate(CCNavigationRequest request) async {
    throw StateError('backend secret should not be recorded');
  }

  @override
  Future<bool> maybePop({Object? result}) async => false;

  @override
  Future<Object?> popAndPush(
    CCNavigationRequest request, {
    Object? popResult,
  }) async => null;

  @override
  Future<void> popUntil(CCNavigationStackPredicate predicate) async {}

  @override
  Future<Object?> pushAndRemoveUntil(
    CCNavigationRequest request,
    CCNavigationStackPredicate predicate,
  ) async => null;

  @override
  void pop({Object? result}) {}

  @override
  bool canPop() => false;

  @override
  Future<void> dispose() async {}
}

final class TestNavigationInterceptor implements CCNavigationInterceptor {
  TestNavigationInterceptor(this.id, this.onIntercept, this.calls);

  final String id;
  final CCNavigationInterception Function(
    CCNavigationInterceptorContext context,
  )
  onIntercept;
  final List<String> calls;

  @override
  Future<CCNavigationInterception> intercept(
    CCNavigationInterceptorContext context,
  ) async {
    calls.add('$id:${context.request.routeId}');
    return onIntercept(context);
  }
}

CCComponentManifest routeComponent(
  String id,
  void Function(CCRegistry) register,
) => CCComponentManifest(
  id: id,
  version: '0.1.0',
  registrar: TestRegistrar(register),
);

CCRouteDefinition<RouteArgs, String> pathRoute({
  String routeId = 'orders.detail',
  String path = '/orders/:value',
  CCDeepLinkPolicy deepLink = CCDeepLinkPolicy.disabled,
  List<String> interceptorIds = const [],
}) => CCRouteDefinition<RouteArgs, String>(
  routeId: routeId,
  patterns: [
    CCPathPattern(path, primary: true, constraints: {'value': r'\d+'}),
  ],
  codec: const RouteArgsCodec(),
  deepLink: deepLink,
  interceptorIds: interceptorIds,
);

void main() {
  test(
    'creates independent Route Entries and scopes for repeated pushes',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      await runtime.initialize();
      final lifecycle = <CCRouteEntryLifecycleEvent>[];
      runtime.addRouteEntryListener(lifecycle.add);

      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('1')),
      );
      final first = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );
      final second = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );

      final entries = runtime.activeRouteEntries;
      expect(entries, hasLength(3));
      expect(entries.map((entry) => entry.routeEntryId).toSet(), hasLength(3));
      expect(entries[0].lifecycleState, CCRouteEntryLifecycleState.hidden);
      expect(entries[1].lifecycleState, CCRouteEntryLifecycleState.hidden);
      expect(entries[2].lifecycleState, CCRouteEntryLifecycleState.visible);
      expect(entries[1].routeId, entries[2].routeId);

    runtime.popRoute(result: 'first');
      expect(await second, 'first');
      expect(runtime.activeRouteEntries, hasLength(2));
      expect(
        runtime.activeRouteEntries.last.lifecycleState,
        CCRouteEntryLifecycleState.visible,
      );
    runtime.popRoute(result: 'second');
      expect(await first, 'second');
      await Future<void>.delayed(Duration.zero);
      expect(
        lifecycle.where(
          (event) => event.state == CCRouteEntryLifecycleState.disposed,
        ),
        hasLength(2),
      );
      await runtime.dispose();
    },
  );

  test('disposes retained Route Scopes during Runtime shutdown', () async {
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: CCMemoryNavigationAdapter(),
      components: [
        routeComponent(
          'orders',
          (registry) => registry.registerRoute(pathRoute()),
        ),
      ],
    );
    await runtime.initialize();
    final lifecycle = <CCRouteEntryLifecycleEvent>[];
    runtime.addRouteEntryListener(lifecycle.add);
    await runtime.goRoute(
      const TestIntent<void>('orders.detail', RouteArgs('42')),
    );
    expect(runtime.activeRouteEntries, hasLength(1));

    await runtime.dispose();

    expect(runtime.activeRouteEntries, isEmpty);
    expect(
      lifecycle.last.state,
      CCRouteEntryLifecycleState.disposed,
    );
    expect(lifecycle.last.reason, 'runtimeDispose');
  });

  test('runs global and route interceptors in deterministic order', () async {
    final calls = <String>[];
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: CCMemoryNavigationAdapter(),
      globalInterceptors: [
        CCGlobalNavigationInterceptor(
          id: 'global.z',
          interceptor: TestNavigationInterceptor(
            'global.z',
            (_) => const CCNavigationProceed(),
            calls,
          ),
        ),
        CCGlobalNavigationInterceptor(
          id: 'global.a',
          interceptor: TestNavigationInterceptor(
            'global.a',
            (_) => const CCNavigationProceed(),
            calls,
          ),
        ),
      ],
      components: [
        routeComponent('orders', (registry) {
          registry.registerRouteInterceptor(
            'route.first',
            TestNavigationInterceptor(
              'route.first',
              (_) => const CCNavigationProceed(),
              calls,
            ),
          );
          registry.registerRouteInterceptor(
            'route.second',
            TestNavigationInterceptor(
              'route.second',
              (_) => const CCNavigationProceed(),
              calls,
            ),
          );
          registry.registerRoute(
            pathRoute(interceptorIds: ['route.first', 'route.second']),
          );
        }),
      ],
    );
    await runtime.initialize();

    await runtime.goRoute(
      const TestIntent<void>('orders.detail', RouteArgs('42')),
    );

    expect(calls, [
      'global.a:orders.detail',
      'global.z:orders.detail',
      'route.first:orders.detail',
      'route.second:orders.detail',
    ]);
    await runtime.dispose();
  });

  test('runs interceptors for composite navigation targets', () async {
    final calls = <String>[];
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: CCMemoryNavigationAdapter(),
      globalInterceptors: [
        CCGlobalNavigationInterceptor(
          id: 'global.policy',
          interceptor: TestNavigationInterceptor(
            'global.policy',
            (_) => const CCNavigationProceed(),
            calls,
          ),
        ),
      ],
      components: [
        routeComponent('orders', (registry) {
          registry.registerRouteInterceptor(
            'orders.policy',
            TestNavigationInterceptor(
              'orders.policy',
              (_) => const CCNavigationProceed(),
              calls,
            ),
          );
          registry.registerRoute(pathRoute(interceptorIds: ['orders.policy']));
        }),
      ],
    );
    await runtime.initialize();

    await runtime.goRoute(
      const TestIntent<void>('orders.detail', RouteArgs('1')),
    );
    calls.clear();
    final popAndPush = runtime.popAndPushRoute<String>(
      const TestIntent<String>('orders.detail', RouteArgs('2')),
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, [
      'global.policy:orders.detail',
      'orders.policy:orders.detail',
    ]);
    runtime.popRoute(result: 'pop-and-push');
    expect(await popAndPush, 'pop-and-push');

    await runtime.goRoute(
      const TestIntent<void>('orders.detail', RouteArgs('3')),
    );
    calls.clear();
    final pushAndRemove = runtime.pushAndRemoveUntilRoute<String>(
      const TestIntent<String>('orders.detail', RouteArgs('4')),
      (_) => true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, [
      'global.policy:orders.detail',
      'orders.policy:orders.detail',
    ]);
    runtime.popRoute(result: 'push-and-remove');
    expect(await pushAndRemove, 'push-and-remove');
    await runtime.dispose();
  });

  test('redirect preserves origin and navigation identity', () async {
    final calls = <String>[];
    final seenIds = <String>[];
    final source = const CCNavigationSource.deepLink('platform');
    final adapter = CCMemoryNavigationAdapter();
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      components: [
        routeComponent('orders', (registry) {
          registry.registerRouteInterceptor(
            'orders.redirect',
            TestNavigationInterceptor('orders.redirect', (context) {
              seenIds.add(context.request.navigationId);
              if (context.request.routeId == 'orders.detail') {
                return CCNavigationRedirect.toIntent(
                  const TestIntent<Object?>('auth.login', RouteArgs('1')),
                );
              }
              return const CCNavigationProceed();
            }, calls),
          );
          registry.registerRoute(
            pathRoute(
              routeId: 'orders.detail',
              deepLink: CCDeepLinkPolicy.enabled,
              interceptorIds: ['orders.redirect'],
            ),
          );
          registry.registerRoute(
            pathRoute(
              routeId: 'auth.login',
              path: '/auth/:value',
              deepLink: CCDeepLinkPolicy.enabled,
            ),
          );
        }),
      ],
    );
    await runtime.initialize();

    await runtime.openRoute(
      Uri.parse('/orders/42'),
      origin: CCNavigationOrigin.externalPlatform,
      source: source,
    );

    expect(adapter.currentRequest?.routeId, 'auth.login');
    expect(adapter.currentRequest?.origin, CCNavigationOrigin.externalPlatform);
    expect(adapter.currentRequest?.source, same(source));
    expect(seenIds, hasLength(1));
    expect(adapter.currentRequest?.navigationId, seenIds.single);
    expect(calls, ['orders.redirect:orders.detail']);
    await runtime.dispose();
  });

  test('cancellation and redirect loops use standard errors', () async {
    final cancellation = CCRouterRuntime.forTesting(
      navigationAdapter: CCMemoryNavigationAdapter(),
      globalInterceptors: [
        CCGlobalNavigationInterceptor(
          id: 'deny',
          interceptor: TestNavigationInterceptor(
            'deny',
            (_) => const CCNavigationCancel(code: 'auth.required'),
            [],
          ),
        ),
      ],
      components: [
        routeComponent(
          'orders',
          (registry) => registry.registerRoute(pathRoute()),
        ),
      ],
    );
    await cancellation.initialize();
    await expectLater(
      cancellation.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('42')),
      ),
      throwsA(isA<CCRouteCancelledError>()),
    );
    await cancellation.dispose();

    final loop = CCRouterRuntime.forTesting(
      navigationAdapter: CCMemoryNavigationAdapter(),
      components: [
        routeComponent('orders', (registry) {
          registry.registerRouteInterceptor(
            'loop',
            TestNavigationInterceptor(
              'loop',
              (_) => CCNavigationRedirect.toUri(Uri(path: '/orders/42')),
              [],
            ),
          );
          registry.registerRoute(pathRoute(interceptorIds: ['loop']));
        }),
      ],
    );
    await loop.initialize();
    await expectLater(
      loop.openRoute(Uri.parse('/orders/42')),
      throwsA(isA<CCRouteRedirectLoopError>()),
    );
    await loop.dispose();
  });

  test('rejects route definitions with unknown interceptors', () async {
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: CCMemoryNavigationAdapter(),
      components: [
        routeComponent(
          'orders',
          (registry) =>
              registry.registerRoute(pathRoute(interceptorIds: ['missing'])),
        ),
      ],
    );
    await expectLater(
      runtime.initialize(),
      throwsA(isA<CCRouteRegistrationError>()),
    );
    await runtime.dispose();
  });

  test('records a sanitized failed lifecycle event', () async {
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: FailingNavigationAdapter(),
      components: [
        routeComponent(
          'orders',
          (registry) => registry.registerRoute(pathRoute()),
        ),
      ],
    );
    await runtime.initialize();

    await expectLater(
      runtime.goRoute(const TestIntent<void>('orders.detail', RouteArgs('42'))),
      throwsA(isA<CCNavigationAdapterError>()),
    );

    expect(runtime.recentNavigationEvents, hasLength(2));
    final failed = runtime.recentNavigationEvents.last;
    expect(failed.phase, CCNavigationLifecyclePhase.failed);
    expect(failed.errorType, 'StateError');
    expect(failed.errorType, isNot(contains('secret')));
    await runtime.dispose();
  });

  test(
    'records bounded navigation lifecycle events with attribution',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationEventCapacity: 2,
        navigationAdapter: adapter,
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      await runtime.initialize();

      final events = <CCNavigationLifecycleEvent>[];
      final removeListener = runtime.addNavigationListener(events.add);
      const source = CCNavigationSource.feature('home.order_banner');
      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('42')),
        source: source,
      );

      expect(events, hasLength(2));
      expect(events.map((event) => event.phase), [
        CCNavigationLifecyclePhase.requested,
        CCNavigationLifecyclePhase.completed,
      ]);
      expect(
        events.every(
          (event) => event.navigationId == events.first.navigationId,
        ),
        isTrue,
      );
      expect(events.every((event) => event.routeId == 'orders.detail'), isTrue);
      expect(
        events.every((event) => event.uri.toString() == '/orders/42'),
        isTrue,
      );
      expect(
        events.every((event) => event.origin == CCNavigationOrigin.internal),
        isTrue,
      );
      expect(events.every((event) => event.source == source), isTrue);
      expect(runtime.recentNavigationEvents, hasLength(2));

      removeListener();
      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('43')),
      );
      expect(events, hasLength(2));
      expect(
        runtime.recentNavigationEvents.map((event) => event.uri.toString()),
        ['/orders/43', '/orders/43'],
      );

      await runtime.dispose();
      expect(runtime.recentNavigationEvents, isEmpty);
    },
  );

  test(
    'typed Push generates the primary path and returns a Pop result',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      await runtime.initialize();

      const source = CCNavigationSource.feature('home.order_banner');
      final result = runtime.pushRoute<String>(
        const TestIntent<String>(
          'orders.detail',
          RouteArgs('42', tab: 'items', payload: 'snapshot'),
        ),
        source: source,
      );

      final request = adapter.currentRequest!;
      expect(request.operation, CCNavigationOperation.push);
      expect(request.routeId, 'orders.detail');
      expect(request.uri.toString(), '/orders/42?tab=items');
      expect(request.arguments, isA<RouteArgs>());
      expect(request.extra, 'snapshot');
      expect(request.origin, CCNavigationOrigin.internal);
      expect(request.source, same(source));
      expect(request.navigationId, contains('-navigation-1'));
      expect(runtime.canPopRoute(), isTrue);

      runtime.popRoute(result: 'selected');
      expect(await result, 'selected');
      expect(adapter.stack, isEmpty);
      await runtime.dispose();
      expect(adapter.isInitialized, isFalse);
    },
  );

  test('typed navigation generates a structured custom-scheme URI', () async {
    final adapter = CCMemoryNavigationAdapter();
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      components: [
        routeComponent(
          'orders',
          (registry) => registry.registerRoute<RouteArgs, String>(
            CCRouteDefinition<RouteArgs, String>(
              routeId: 'orders.scheme',
              patterns: [
                const CCUriPattern(
                  'therouter://orders/detail/:value',
                  primary: true,
                  constraints: {'value': r'\d+'},
                ),
              ],
              codec: const RouteArgsCodec(),
            ),
          ),
        ),
      ],
    );
    await runtime.initialize();

    await runtime.goRoute(
      const TestIntent<void>('orders.scheme', RouteArgs('43', tab: 'history')),
    );

    expect(
      adapter.currentRequest?.uri.toString(),
      'therouter://orders/detail/43?tab=history',
    );
    expect(adapter.currentRequest?.operation, CCNavigationOperation.go);
    expect(runtime.canPopRoute(), isFalse);
    await runtime.dispose();
  });

  test(
    'typed navigation rejects values that violate the primary pattern',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      await runtime.initialize();

      await expectLater(
        runtime.goRoute(
          const TestIntent<void>('orders.detail', RouteArgs('not-a-number')),
        ),
        throwsA(isA<CCRouteParameterError>()),
      );
      expect(adapter.stack, isEmpty);
      await runtime.dispose();
    },
  );

  test(
    'dynamic URI preserves trusted origin and enforces Deep Link policy',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          routeComponent('orders', (registry) {
            registry.registerRoute<RouteArgs, String>(
              CCRouteDefinition<RouteArgs, String>(
                routeId: 'orders.external',
                patterns: [
                  const CCPathPattern('/orders/:value', primary: true),
                  const CCUriPattern('https://therouter.com/orders/:value'),
                ],
                codec: const RouteArgsCodec(),
                deepLink: CCDeepLinkPolicy.enabled,
              ),
            );
            registry.registerRoute<RouteArgs, String>(
              pathRoute(routeId: 'orders.internal', path: '/internal/:value'),
            );
          }),
        ],
      );
      await runtime.initialize();

      final externalRoute = adapter.routes.singleWhere(
        (route) => route.routeId == 'orders.external',
      );
      expect(externalRoute.deepLink, CCDeepLinkPolicy.enabled);
      expect(externalRoute.patterns, hasLength(2));

      const source = CCNavigationSource.deepLink('universal_link');
      await runtime.openRoute(
        Uri.parse('https://therouter.com/orders/44?tab=items#summary'),
        origin: CCNavigationOrigin.externalPlatform,
        source: source,
      );
      final request = adapter.currentRequest!;
      expect(request.operation, CCNavigationOperation.open);
      expect(request.origin, CCNavigationOrigin.externalPlatform);
      expect(request.source, same(source));
      expect((request.arguments as RouteArgs).value, '44');
      expect((request.arguments as RouteArgs).tab, 'items');
      expect(request.extra, isNull);

      await expectLater(
        runtime.openRoute(
          Uri.parse('/internal/45'),
          origin: CCNavigationOrigin.externalNotification,
        ),
        throwsA(isA<CCRouteNotFoundError>()),
      );
      await runtime.openRoute(Uri.parse('/internal/45'));
      expect(adapter.currentRequest?.routeId, 'orders.internal');
      expect(adapter.currentRequest?.origin, CCNavigationOrigin.internal);
      await runtime.dispose();
    },
  );

  test(
    'typed navigation rejects missing and unknown encoded Path parameters',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          routeComponent('orders', (registry) {
            registry.registerRoute<RouteArgs, void>(
              CCRouteDefinition<RouteArgs, void>(
                routeId: 'orders.missing',
                patterns: [
                  const CCPathPattern('/missing/:value', primary: true),
                ],
                codec: const MissingPathCodec(),
              ),
            );
            registry.registerRoute<RouteArgs, void>(
              CCRouteDefinition<RouteArgs, void>(
                routeId: 'orders.unknown',
                patterns: [
                  const CCPathPattern('/unknown/:value', primary: true),
                ],
                codec: const UnknownPathCodec(),
              ),
            );
          }),
        ],
      );
      await runtime.initialize();

      await expectLater(
        runtime.goRoute(
          const TestIntent<void>('orders.missing', RouteArgs('42')),
        ),
        throwsA(isA<CCRouteParameterError>()),
      );
      await expectLater(
        runtime.goRoute(
          const TestIntent<void>('orders.unknown', RouteArgs('42')),
        ),
        throwsA(isA<CCRouteParameterError>()),
      );
      expect(adapter.stack, isEmpty);
      await runtime.dispose();
    },
  );

  test(
    'memory adapter models Push, Replace, Go, Reset, Open, and Pop',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      await runtime.initialize();

      const root = TestIntent<void>('orders.detail', RouteArgs('1'));
      await runtime.goRoute(root);
      expect(adapter.stack.single.operation, CCNavigationOperation.go);
      expect(runtime.canPopRoute(), isFalse);

      final pushed = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );
      expect(adapter.stack.length, 2);
      expect(runtime.canPopRoute(), isTrue);

      final replaced = runtime.replaceRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('3')),
      );
      expect(await pushed, isNull);
      expect(adapter.stack.length, 2);
      expect(adapter.currentRequest?.operation, CCNavigationOperation.replace);

      runtime.popRoute(result: 'replacement-result');
      expect(await replaced, 'replacement-result');
      expect(adapter.stack.length, 1);

      await runtime.openRoute(Uri.parse('/orders/4'));
      expect(adapter.currentRequest?.operation, CCNavigationOperation.open);
      expect(runtime.canPopRoute(), isTrue);
      runtime.popRoute();

      await runtime.resetRoute(
        const TestIntent<void>('orders.detail', RouteArgs('5')),
      );
      expect(adapter.stack.single.operation, CCNavigationOperation.reset);
      expect(runtime.canPopRoute(), isFalse);
      await runtime.dispose();
    },
  );

  test(
    'maybePop respects the root and completes a pushed route with its result',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      await runtime.initialize();

      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('1')),
      );
      expect(await runtime.maybePopRoute(), isFalse);

      final pushed = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );
      expect(await runtime.maybePopRoute(result: 'back'), isTrue);
      expect(await pushed, 'back');
      expect(adapter.entries.map((entry) => entry.uri.path), ['/orders/1']);
      await runtime.dispose();
    },
  );

  test(
    'popAndPush completes the old route and returns the new route result',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      await runtime.initialize();

      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('1')),
      );
      final oldRoute = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );
      final newRoute = runtime.popAndPushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('3')),
        popResult: 'selected',
      );

      expect(await oldRoute, 'selected');
      expect(adapter.entries.map((entry) => entry.uri.path), [
        '/orders/1',
        '/orders/3',
      ]);
      runtime.popRoute(result: 'replacement');
      expect(await newRoute, 'replacement');
      await runtime.dispose();
    },
  );

  test(
    'popUntil keeps the first matching entry and cancels removed results',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      await runtime.initialize();

      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('1')),
      );
      final second = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );
      final third = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('3')),
      );

      await runtime.popUntilRoute((entry) => entry.uri.path == '/orders/1');
      expect(adapter.entries.map((entry) => entry.uri.path), ['/orders/1']);
      expect(await third, isNull);
      expect(await second, isNull);
      await runtime.dispose();
    },
  );

  test(
    'pushAndRemoveUntil keeps the matched old entry and never tests the new one',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      await runtime.initialize();

      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('1')),
      );
      final removed = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );
      final result = runtime.pushAndRemoveUntilRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('3')),
        (entry) => entry.uri.path == '/orders/1',
      );

      expect(await removed, isNull);
      expect(adapter.entries.map((entry) => entry.uri.path), [
        '/orders/1',
        '/orders/3',
      ]);
      runtime.popRoute(result: 'done');
      expect(await result, 'done');
      await runtime.dispose();
    },
  );

  test('typed Push reports an incompatible adapter result', () async {
    final adapter = CCMemoryNavigationAdapter();
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      components: [
        routeComponent(
          'orders',
          (registry) => registry.registerRoute(pathRoute()),
        ),
      ],
    );
    await runtime.initialize();

    final result = runtime.pushRoute<String>(
      const TestIntent<String>('orders.detail', RouteArgs('42')),
    );
    runtime.popRoute(result: 42);
    await expectLater(result, throwsA(isA<CCRouteResultTypeError>()));
    await runtime.dispose();
  });

  test('navigation fails clearly when no adapter is configured', () async {
    final runtime = CCRouterRuntime.forTesting(
      components: [
        routeComponent(
          'orders',
          (registry) => registry.registerRoute(pathRoute()),
        ),
      ],
    );
    await runtime.initialize();

    await expectLater(
      runtime.goRoute(const TestIntent<void>('orders.detail', RouteArgs('42'))),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    await runtime.dispose();
  });
}
