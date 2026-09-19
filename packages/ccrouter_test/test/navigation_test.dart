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

final class BackendEventNavigationAdapter
    implements
        CCNavigationAdapter,
        CCNavigationBackendEventSource,
        CCNavigationAdapterCapabilitySource,
        CCNavigationBackendSnapshotSource,
        CCNavigationPredictiveBackSource {
  BackendEventNavigationAdapter({this.predictiveBackSupported = true});

  final CCMemoryNavigationAdapter delegate = CCMemoryNavigationAdapter();
  final Set<CCNavigationBackendEventListener> listeners = {};
  final Set<CCPredictiveBackEventListener> predictiveBackListeners = {};
  final bool predictiveBackSupported;
  bool consumeForeignMaybePop = false;
  List<CCNavigationBackendEntrySnapshot> initialSnapshot = const [];

  @override
  CCNavigationAdapterCapabilities get capabilities =>
      CCNavigationAdapterCapabilities(
        supportsPredictiveBack: predictiveBackSupported,
      );

  @override
  Future<List<CCNavigationBackendEntrySnapshot>>
  readInitialBackendSnapshot() async => initialSnapshot;

  void emit(
    CCNavigationBackendEventKind kind, {
    String? backendEntryId,
    String? backendOperationId,
    String? previousBackendEntryId,
    String? navigationId,
    String? routeId,
    CCBackendEntryOwner? owner,
    int? sequence,
  }) {
    final event = CCNavigationBackendEvent(
      kind: kind,
      timestamp: DateTime.now(),
      backendEntryId: backendEntryId,
      backendOperationId: backendOperationId,
      previousBackendEntryId: previousBackendEntryId,
      navigationId: navigationId,
      routeId: routeId,
      owner: owner,
      sequence: sequence,
      location: 'foreign:${kind.name}',
    );
    for (final listener in listeners.toList()) {
      listener(event);
    }
  }

  void emitPredictive(CCPredictiveBackEvent event) {
    for (final listener in predictiveBackListeners.toList()) {
      listener(event);
    }
  }

  @override
  void Function() addBackendEventListener(
    CCNavigationBackendEventListener listener,
  ) {
    listeners.add(listener);
    return () => listeners.remove(listener);
  }

  @override
  void Function() addPredictiveBackListener(
    CCPredictiveBackEventListener listener,
  ) {
    predictiveBackListeners.add(listener);
    return () => predictiveBackListeners.remove(listener);
  }

  @override
  bool canPop() => delegate.canPop();

  @override
  Future<void> dispose() => delegate.dispose();

  @override
  Future<void> initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) => delegate.initialize(routes, shells: shells);

  @override
  Future<bool> maybePop({Object? result}) => consumeForeignMaybePop
      ? Future<bool>.value(true)
      : delegate.maybePop(result: result);

  @override
  Future<Object?> navigate(CCNavigationRequest request) =>
      delegate.navigate(request);

  @override
  void pop({Object? result}) => delegate.pop(result: result);

  @override
  Future<Object?> popAndPush(
    CCNavigationRequest request, {
    Object? popResult,
  }) => delegate.popAndPush(request, popResult: popResult);

  @override
  Future<void> popUntil(CCNavigationStackPredicate predicate) =>
      delegate.popUntil(predicate);

  @override
  Future<Object?> pushAndRemoveUntil(
    CCNavigationRequest request,
    CCNavigationStackPredicate predicate,
  ) => delegate.pushAndRemoveUntil(request, predicate);
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
  CCRoutePresentation presentation = const CCPagePresentation(),
}) => CCRouteDefinition<RouteArgs, String>(
  routeId: routeId,
  patterns: [
    CCPathPattern(path, primary: true, constraints: {'value': r'\d+'}),
  ],
  codec: const RouteArgsCodec(),
  deepLink: deepLink,
  interceptorIds: interceptorIds,
  presentation: presentation,
);

void main() {
  test(
    'imports initial backend snapshots without creating Route Entries',
    () async {
      final adapter = BackendEventNavigationAdapter()
        ..initialSnapshot = const [
          CCNavigationBackendEntrySnapshot(
            backendEntryId: 'window-a-root',
            owner: CCBackendEntryOwner.foreign,
            hostId: 'window-a',
            navigatorOutlet: 'root',
            location: '/external',
          ),
          CCNavigationBackendEntrySnapshot(
            backendEntryId: 'window-b-detail',
            owner: CCBackendEntryOwner.opaque,
            hostId: 'window-b',
            navigatorOutlet: 'detail',
            location: 'overlay:menu',
          ),
        ];
      final runtime = CCRouterRuntime.forTesting(navigationAdapter: adapter);
      await runtime.initialize();

      expect(runtime.activeRouteEntries, isEmpty);
      expect(runtime.activeBackendEntries, hasLength(2));
      expect(runtime.activeBackendEntries.map((entry) => entry.hostId), [
        'window-a',
        'window-b',
      ]);
      expect(
        runtime.activeBackendEntries.map((entry) => entry.navigatorOutlet),
        ['root', 'detail'],
      );
      expect(
        runtime.backendEntriesFor(hostId: 'window-a', activeOnly: true),
        hasLength(1),
      );
      expect(
        runtime.backendEntriesFor(navigatorOutlet: 'detail').single.hostId,
        'window-b',
      );
      expect(runtime.recentBackendNavigationEvents, isEmpty);
      await runtime.dispose();
    },
  );

  test(
    'capability-aware adapters reject unsupported static and composite work',
    () async {
      final modalRuntime = CCRouterRuntime.forTesting(
        navigationAdapter: BackendEventNavigationAdapter(),
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(
              pathRoute(presentation: const CCDialogPresentation()),
            ),
          ),
        ],
      );
      expect(
        modalRuntime.initialize(),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      await modalRuntime.dispose();

      final adapter = BackendEventNavigationAdapter();
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
        runtime.popAndPushRoute<void>(
          const TestIntent<void>('orders.detail', RouteArgs('1')),
        ),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      await expectLater(
        runtime.pushAndRemoveUntilRoute<void>(
          const TestIntent<void>('orders.detail', RouteArgs('2')),
          (_) => false,
        ),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      await runtime.dispose();

      final unsupportedPredictiveRuntime = CCRouterRuntime.forTesting(
        navigationAdapter: BackendEventNavigationAdapter(
          predictiveBackSupported: false,
        ),
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      expect(
        unsupportedPredictiveRuntime.initialize(),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      await unsupportedPredictiveRuntime.dispose();
    },
  );

  test(
    'uncorrelated backend events never mutate managed Route Entries',
    () async {
      final adapter = BackendEventNavigationAdapter();
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
      final observed = <CCNavigationBackendEvent>[];
      runtime.addBackendNavigationListener(observed.add);

      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('1')),
      );
      final pushed = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );
      final before = runtime.activeRouteEntries;

      for (final kind in CCNavigationBackendEventKind.values) {
        adapter.emit(kind);
      }

      expect(runtime.activeRouteEntries, hasLength(2));
      expect(
        runtime.activeRouteEntries.map((entry) => entry.routeEntryId),
        before.map((entry) => entry.routeEntryId),
      );
      expect(
        runtime.activeRouteEntries.map((entry) => entry.lifecycleState),
        before.map((entry) => entry.lifecycleState),
      );
      expect(observed.map((event) => event.kind), [
        CCNavigationBackendEventKind.push,
        CCNavigationBackendEventKind.pop,
        CCNavigationBackendEventKind.replace,
        CCNavigationBackendEventKind.remove,
      ]);
      expect(runtime.recentBackendNavigationEvents, observed);

      adapter.consumeForeignMaybePop = true;
      expect(await runtime.maybePopRoute(), isTrue);
      expect(runtime.activeRouteEntries, hasLength(2));
      expect(
        runtime.activeRouteEntries.last.routeEntryId,
        before.last.routeEntryId,
      );

      runtime.popRoute(result: 'managed');
      expect(await pushed, 'managed');
      expect(runtime.activeRouteEntries, hasLength(1));
      await runtime.dispose();
    },
  );

  test(
    'tracks foreign and managed backend Entry ownership independently',
    () async {
      final adapter = BackendEventNavigationAdapter();
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

      adapter.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'foreign-1',
        backendOperationId: 'foreign-op-1',
        sequence: 1,
      );
      expect(
        runtime.activeBackendEntries.single.owner,
        CCBackendEntryOwner.foreign,
      );
      expect(runtime.activeBackendEntries.single.backendEntryId, 'foreign-1');

      adapter.emit(
        CCNavigationBackendEventKind.pop,
        backendEntryId: 'foreign-1',
        backendOperationId: 'foreign-op-2',
        sequence: 2,
      );
      expect(runtime.activeBackendEntries, isEmpty);
      expect(
        runtime.backendEntries.single.lifecycleState,
        CCBackendEntryLifecycleState.removed,
      );

      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('1')),
      );
      final managed = runtime.activeRouteEntries.single;
      adapter.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'managed-1',
        backendOperationId: 'managed-op-1',
        navigationId: managed.navigationId,
        routeId: managed.routeId,
        owner: CCBackendEntryOwner.managed,
        sequence: 3,
      );
      adapter.emit(
        CCNavigationBackendEventKind.pop,
        backendEntryId: 'managed-1',
        backendOperationId: 'managed-op-2',
        navigationId: managed.navigationId,
        routeId: managed.routeId,
        owner: CCBackendEntryOwner.managed,
        sequence: 4,
      );
      expect(
        runtime.activeRouteEntries.single.routeEntryId,
        managed.routeEntryId,
      );
      expect(
        runtime.backendEntries.last.lifecycleState,
        CCBackendEntryLifecycleState.removed,
      );
      await runtime.dispose();
    },
  );

  test('predictive back closes a managed entry only after commit', () async {
    final adapter = BackendEventNavigationAdapter();
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
      const TestIntent<void>('orders.detail', RouteArgs('42')),
    );
    final managed = runtime.activeRouteEntries.single;
    adapter.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'managed-predictive',
      backendOperationId: 'managed-predictive-push',
      navigationId: managed.navigationId,
      routeId: managed.routeId,
      owner: CCBackendEntryOwner.managed,
      sequence: 1,
    );
    const outcome = CCPopOutcome(
      handled: true,
      removedBackendEntryId: 'managed-predictive',
      removedOwner: CCPopRemovedOwner.managed,
    );

    for (final phase in [
      CCPredictiveBackPhase.started,
      CCPredictiveBackPhase.updated,
      CCPredictiveBackPhase.cancelled,
    ]) {
      adapter.emitPredictive(
        CCPredictiveBackEvent(
          phase: phase,
          progress: phase == CCPredictiveBackPhase.updated ? .5 : 0,
          timestamp: DateTime.now(),
          outcome: outcome,
        ),
      );
    }
    expect(runtime.activeRouteEntries, hasLength(1));
    expect(
      runtime.activeRouteEntries.single.routeEntryId,
      managed.routeEntryId,
    );

    adapter.emitPredictive(
      CCPredictiveBackEvent(
        phase: CCPredictiveBackPhase.committed,
        progress: 1,
        timestamp: DateTime.now(),
        outcome: outcome,
      ),
    );
    expect(runtime.activeRouteEntries, isEmpty);

    await runtime.goRoute(
      const TestIntent<void>('orders.detail', RouteArgs('43')),
    );
    final protected = runtime.activeRouteEntries.single;
    adapter.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'foreign-predictive',
      backendOperationId: 'foreign-predictive-push',
      owner: CCBackendEntryOwner.foreign,
      sequence: 2,
    );
    adapter.emitPredictive(
      CCPredictiveBackEvent(
        phase: CCPredictiveBackPhase.committed,
        progress: 1,
        timestamp: DateTime.now(),
        outcome: const CCPopOutcome(
          handled: true,
          removedBackendEntryId: 'foreign-predictive',
          removedOwner: CCPopRemovedOwner.foreign,
        ),
      ),
    );
    expect(runtime.activeRouteEntries, hasLength(1));
    expect(
      runtime.activeRouteEntries.single.routeEntryId,
      protected.routeEntryId,
    );
    await runtime.dispose();
  });

  test(
    'tracks opaque backend Entries without changing managed Route Entries',
    () async {
      final adapter = BackendEventNavigationAdapter();
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
      final managedEntry = runtime.activeRouteEntries.single;

      adapter.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'opaque-1',
        backendOperationId: 'opaque-op-1',
        owner: CCBackendEntryOwner.opaque,
        sequence: 1,
      );
      expect(
        runtime.activeRouteEntries.single.routeEntryId,
        managedEntry.routeEntryId,
      );
      expect(
        runtime.activeBackendEntries.single.owner,
        CCBackendEntryOwner.opaque,
      );

      adapter.emit(
        CCNavigationBackendEventKind.remove,
        backendEntryId: 'opaque-1',
        backendOperationId: 'opaque-op-2',
        owner: CCBackendEntryOwner.opaque,
        sequence: 2,
      );
      expect(
        runtime.activeRouteEntries.single.routeEntryId,
        managedEntry.routeEntryId,
      );
      expect(runtime.activeBackendEntries, isEmpty);
      await runtime.dispose();
    },
  );

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

  test(
    'removes exact managed Entries and preserves the handle target',
    () async {
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
      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('1')),
      );
      final firstResult = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );
      final secondResult = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('3')),
      );
      final thirdResult = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('4')),
      );
      final entries = runtime.activeRouteEntries;
      final first = entries[1];
      final second = entries[2];
      final third = entries[3];

      await runtime.removeRoute(second.handle);
      expect(await secondResult, isNull);
      expect(runtime.activeRouteEntries.map((entry) => entry.routeEntryId), [
        entries[0].routeEntryId,
        first.routeEntryId,
        third.routeEntryId,
      ]);

      await runtime.removeRouteBelow(third.handle);
      expect(await firstResult, isNull);
      expect(runtime.activeRouteEntries, hasLength(1));
      expect(
        runtime.activeRouteEntries.single.routeEntryId,
        third.routeEntryId,
      );

      await runtime.removeRoute(third.handle);
      expect(await thirdResult, isNull);
      expect(runtime.activeRouteEntries, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(
        runtime.recentRouteEntryEvents
            .where(
              (event) => event.state == CCRouteEntryLifecycleState.disposed,
            )
            .length,
        4,
      );

      expect(
        () => runtime.removeRoute(second.handle),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      await runtime.dispose();
    },
  );

  test('rejects exact handles from another Runtime', () async {
    CCRouterRuntime createRuntime() => CCRouterRuntime.forTesting(
      navigationAdapter: CCMemoryNavigationAdapter(),
      components: [
        routeComponent(
          'orders',
          (registry) => registry.registerRoute(pathRoute()),
        ),
      ],
    );

    final firstRuntime = createRuntime();
    await firstRuntime.initialize();
    await firstRuntime.goRoute(
      const TestIntent<void>('orders.detail', RouteArgs('1')),
    );
    final handle = firstRuntime.activeRouteEntries.single.handle;

    final secondRuntime = createRuntime();
    await secondRuntime.initialize();
    await secondRuntime.goRoute(
      const TestIntent<void>('orders.detail', RouteArgs('2')),
    );
    expect(
      () => secondRuntime.removeRoute(handle),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    expect(secondRuntime.activeRouteEntries, hasLength(1));
    await firstRuntime.dispose();
    await secondRuntime.dispose();
  });

  test(
    'reports exact removal capability errors instead of removing by position',
    () async {
      final adapter = BackendEventNavigationAdapter();
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
      final handle = runtime.activeRouteEntries.single.handle;
      expect(
        () => runtime.removeRoute(handle),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      expect(runtime.activeRouteEntries, hasLength(1));
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
    expect(lifecycle.last.state, CCRouteEntryLifecycleState.disposed);
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

  test(
    'runs navigation aspects across match, arrival, and terminal phases',
    () async {
      final phases = <CCNavigationAspectPhase>[];
      final outcomes = <CCNavigationAspectOutcome?>[];
      final elapsed = <Duration>[];
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        navigationAspects: [
          CCNavigationAspect(
            id: 'telemetry',
            onFound: (event) {
              phases.add(event.phase);
              elapsed.add(event.elapsed!);
              expect(event.entry, isNull);
              expect(event.request.uri.toString(), '/orders/42');
            },
            onArrival: (event) {
              phases.add(event.phase);
              elapsed.add(event.elapsed!);
              expect(event.entry, isNotNull);
              expect(
                event.entry!.lifecycleState,
                CCRouteEntryLifecycleState.visible,
              );
            },
            onAfter: (event) {
              phases.add(event.phase);
              elapsed.add(event.elapsed!);
              outcomes.add(event.outcome);
            },
          ),
        ],
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      await runtime.initialize();

      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('42')),
      );

      expect(phases, [
        CCNavigationAspectPhase.found,
        CCNavigationAspectPhase.arrival,
        CCNavigationAspectPhase.after,
      ]);
      expect(outcomes, [CCNavigationAspectOutcome.succeeded]);
      expect(elapsed, hasLength(3));
      expect(elapsed[2], greaterThanOrEqualTo(elapsed[0]));
      await runtime.dispose();
    },
  );

  test(
    'aspect before can cancel and emits isolated lost and after hooks',
    () async {
      final phases = <CCNavigationAspectPhase>[];
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        navigationAspects: [
          CCNavigationAspect(
            id: 'policy',
            before: (_) => const CCNavigationCancel(code: 'blocked'),
            onFound: (event) => phases.add(event.phase),
            onLost: (event) {
              phases.add(event.phase);
              expect(event.outcome, CCNavigationAspectOutcome.cancelled);
              expect(event.errorType, 'CCRouteCancelledError');
            },
            onAfter: (event) {
              phases.add(event.phase);
              expect(event.outcome, CCNavigationAspectOutcome.cancelled);
            },
          ),
        ],
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
          const TestIntent<void>('orders.detail', RouteArgs('42')),
        ),
        throwsA(isA<CCRouteCancelledError>()),
      );
      expect(phases, [
        CCNavigationAspectPhase.found,
        CCNavigationAspectPhase.lost,
        CCNavigationAspectPhase.after,
      ]);
      expect(runtime.activeRouteEntries, isEmpty);
      await runtime.dispose();
    },
  );

  test('orders aspects by ID and isolates observer failures', () async {
    final calls = <String>[];
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: CCMemoryNavigationAdapter(),
      navigationAspects: [
        CCNavigationAspect(
          id: 'z-last',
          onFound: (_) => throw StateError('aspect failure'),
        ),
        CCNavigationAspect(id: 'a-first', onFound: (_) => calls.add('a-first')),
      ],
      components: [
        routeComponent(
          'orders',
          (registry) => registry.registerRoute(pathRoute()),
        ),
      ],
    );
    await runtime.initialize();

    await runtime.goRoute(
      const TestIntent<void>('orders.detail', RouteArgs('42')),
    );

    expect(calls, ['a-first']);
    expect(runtime.subscriberErrors.single.message, contains('StateError'));
    await runtime.dispose();
  });

  test('Aspect callbacks cannot synchronously re-enter navigation', () async {
    late CCRouterRuntime runtime;
    late Future<void> reentry;
    late Future<void> reentryExpectation;
    runtime = CCRouterRuntime.forTesting(
      navigationAdapter: CCMemoryNavigationAdapter(),
      navigationAspects: [
        CCNavigationAspect(
          id: 'reentry',
          onFound: (_) {
            reentry = runtime.goRoute(
              const TestIntent<void>('orders.detail', RouteArgs('43')),
            );
            reentryExpectation = expectLater(
              reentry,
              throwsA(isA<CCNavigationReentrancyError>()),
            );
          },
        ),
      ],
      components: [
        routeComponent(
          'orders',
          (registry) => registry.registerRoute(pathRoute()),
        ),
      ],
    );
    await runtime.initialize();
    await runtime.goRoute(
      const TestIntent<void>('orders.detail', RouteArgs('42')),
    );
    await reentryExpectation;
    expect(runtime.activeRouteEntries, hasLength(1));
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
    expect(runtime.activeRouteEntries, isEmpty);
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
      expect(
        runtime.activeRouteEntries.map((entry) => entry.normalizedUri.path),
        ['/orders/1', '/orders/3'],
      );

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
      final declined = await runtime.maybePopOutcomeRoute();
      expect(declined.handled, isFalse);
      expect(declined.removedOwner, CCPopRemovedOwner.none);
      expect(declined.trigger, CCPopTrigger.system);

      final pushed = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );
      final handled = await runtime.maybePopOutcomeRoute(
        result: 'back',
        trigger: CCPopTrigger.gesture,
      );
      expect(handled.handled, isTrue);
      expect(handled.removedOwner, CCPopRemovedOwner.managed);
      expect(handled.resultAvailable, isTrue);
      expect(handled.trigger, CCPopTrigger.gesture);
      expect(await pushed, 'back');
      expect(runtime.activeRouteEntries, hasLength(1));
      expect(adapter.entries.map((entry) => entry.uri.path), ['/orders/1']);
      await runtime.dispose();
    },
  );

  test('allow concurrency policy permits identical pushes', () async {
    final adapter = CCMemoryNavigationAdapter();
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      navigationConcurrencyPolicy: CCNavigationConcurrencyPolicy.allow,
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

    final first = runtime.pushRoute<String>(
      const TestIntent<String>('orders.detail', RouteArgs('2')),
    );
    final second = runtime.pushRoute<String>(
      const TestIntent<String>('orders.detail', RouteArgs('2')),
    );

    expect(adapter.stack, hasLength(3));
    runtime.popRoute(result: 'second');
    expect(await second, 'second');
    runtime.popRoute(result: 'first');
    expect(await first, 'first');
    await runtime.dispose();
  });

  test(
    'rejectDuplicate only rejects an identical in-flight navigation',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        navigationConcurrencyPolicy:
            CCNavigationConcurrencyPolicy.rejectDuplicate,
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

      final first = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );
      await expectLater(
        runtime.pushRoute<String>(
          const TestIntent<String>('orders.detail', RouteArgs('2')),
        ),
        throwsA(isA<CCNavigationDuplicateError>()),
      );
      final different = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('3')),
      );
      expect(adapter.stack, hasLength(3));

      runtime.popRoute(result: 'different');
      expect(await different, 'different');
      runtime.popRoute(result: 'first');
      expect(await first, 'first');
      final retry = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );
      runtime.popRoute(result: 'retry');
      expect(await retry, 'retry');
      await runtime.dispose();
    },
  );

  test('singleFlight shares one in-flight navigation result', () async {
    final adapter = CCMemoryNavigationAdapter();
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      navigationConcurrencyPolicy: CCNavigationConcurrencyPolicy.singleFlight,
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

    final first = runtime.pushRoute<String>(
      const TestIntent<String>('orders.detail', RouteArgs('2')),
    );
    final second = runtime.pushRoute<String>(
      const TestIntent<String>('orders.detail', RouteArgs('2')),
    );
    expect(adapter.stack, hasLength(2));
    runtime.popRoute(result: 'shared');
    expect(await first, 'shared');
    expect(await second, 'shared');

    final retry = runtime.pushRoute<String>(
      const TestIntent<String>('orders.detail', RouteArgs('2')),
    );
    runtime.popRoute(result: 'retry');
    expect(await retry, 'retry');
    await runtime.dispose();
  });

  test(
    'deferred navigation resumes through the full interceptor pipeline',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      var authorized = false;
      final calls = <String>[];
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          routeComponent('orders', (registry) {
            registry.registerRouteInterceptor(
              'orders.auth',
              TestNavigationInterceptor('orders.auth', (_) {
                if (!authorized) {
                  return const CCNavigationDefer(
                    code: 'login_required',
                    timeout: Duration(seconds: 1),
                  );
                }
                return const CCNavigationProceed();
              }, calls),
            );
            registry.registerRoute(pathRoute(interceptorIds: ['orders.auth']));
          }),
        ],
      );
      await runtime.initialize();

      final pushed = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('42')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(runtime.pendingNavigations, hasLength(1));
      final pending = runtime.pendingNavigations.single;
      expect(pending.routeId, 'orders.detail');
      expect(pending.uri.path, '/orders/42');
      expect(pending.origin, CCNavigationOrigin.internal);
      expect(pending.navigationId, isNotEmpty);

      authorized = true;
      final resumed = runtime.resumePendingNavigation(pending.navigationId);
      await Future<void>.delayed(Duration.zero);
      expect(runtime.pendingNavigations, isEmpty);
      runtime.popRoute(result: 'authorized');
      expect(await pushed, 'authorized');
      expect(await resumed, 'authorized');
      expect(calls, ['orders.auth:orders.detail', 'orders.auth:orders.detail']);
      await runtime.dispose();
    },
  );

  test(
    'pending navigation is cleared by cancellation and Session close',
    () async {
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        components: [
          routeComponent('orders', (registry) {
            registry.registerRouteInterceptor(
              'orders.defer',
              TestNavigationInterceptor(
                'orders.defer',
                (_) => const CCNavigationDefer(),
                [],
              ),
            );
            registry.registerRoute(pathRoute(interceptorIds: ['orders.defer']));
          }),
        ],
      );
      await runtime.initialize();
      final cancelled = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('1')),
      );
      await Future<void>.delayed(Duration.zero);
      final first = runtime.pendingNavigations.single.navigationId;
      expect(runtime.cancelPendingNavigation(first), isTrue);
      await expectLater(cancelled, throwsA(isA<CCRouteCancelledError>()));
      expect(runtime.pendingNavigations, isEmpty);

      runtime.openSession(accountId: 'account-1');
      final closed = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );
      await Future<void>.delayed(Duration.zero);
      final closedExpectation = expectLater(
        closed,
        throwsA(isA<CCRouteCancelledError>()),
      );
      await runtime.closeSession();
      expect(runtime.pendingNavigations, isEmpty);
      await closedExpectation;
      await runtime.dispose();
    },
  );

  test(
    'deferred resume revalidates active component state and closes timing',
    () async {
      var shouldDefer = true;
      final phases = <CCNavigationAspectPhase>[];
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        navigationAspects: [
          CCNavigationAspect(
            id: 'resume-diagnostics',
            onFound: (event) => phases.add(event.phase),
            onLost: (event) {
              phases.add(event.phase);
              expect(event.elapsed, isNotNull);
            },
            onAfter: (event) {
              phases.add(event.phase);
              expect(event.elapsed, isNotNull);
            },
          ),
        ],
        components: [
          routeComponent('orders', (registry) {
            registry.registerRouteInterceptor(
              'orders.defer',
              TestNavigationInterceptor('orders.defer', (_) {
                if (shouldDefer) {
                  shouldDefer = false;
                  return const CCNavigationDefer();
                }
                return const CCNavigationProceed();
              }, []),
            );
            registry.registerRoute(pathRoute(interceptorIds: ['orders.defer']));
          }),
        ],
      );
      await runtime.initialize();
      final pushed = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('42')),
      );
      await Future<void>.delayed(Duration.zero);
      final pendingId = runtime.pendingNavigations.single.navigationId;
      final pushedExpectation = expectLater(
        pushed,
        throwsA(isA<CCRouteUnavailableError>()),
      );
      runtime.deactivateComponent('orders');
      await expectLater(
        runtime.resumePendingNavigation(pendingId),
        throwsA(isA<CCRouteUnavailableError>()),
      );
      await pushedExpectation;
      expect(phases, [
        CCNavigationAspectPhase.found,
        CCNavigationAspectPhase.lost,
        CCNavigationAspectPhase.after,
      ]);
      expect(runtime.pendingNavigations, isEmpty);
      await runtime.dispose();
    },
  );

  test(
    'pending navigation timeout and Runtime dispose release continuations',
    () async {
      final timeoutRuntime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        components: [
          routeComponent('orders', (registry) {
            registry.registerRouteInterceptor(
              'orders.timeout',
              TestNavigationInterceptor(
                'orders.timeout',
                (_) => const CCNavigationDefer(
                  code: 'timeout',
                  timeout: Duration(milliseconds: 1),
                ),
                [],
              ),
            );
            registry.registerRoute(
              pathRoute(interceptorIds: ['orders.timeout']),
            );
          }),
        ],
      );
      await timeoutRuntime.initialize();
      final timedOut = timeoutRuntime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('1')),
      );
      await expectLater(timedOut, throwsA(isA<CCRouteCancelledError>()));
      expect(timeoutRuntime.pendingNavigations, isEmpty);
      await timeoutRuntime.dispose();

      final disposedRuntime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        components: [
          routeComponent('orders', (registry) {
            registry.registerRouteInterceptor(
              'orders.dispose',
              TestNavigationInterceptor(
                'orders.dispose',
                (_) => const CCNavigationDefer(),
                [],
              ),
            );
            registry.registerRoute(
              pathRoute(interceptorIds: ['orders.dispose']),
            );
          }),
        ],
      );
      await disposedRuntime.initialize();
      final disposed = disposedRuntime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );
      final disposedExpectation = expectLater(
        disposed,
        throwsA(isA<CCRouteCancelledError>()),
      );
      await disposedRuntime.dispose();
      expect(disposedRuntime.pendingNavigations, isEmpty);
      await disposedExpectation;
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
      expect(
        runtime.activeRouteEntries.map((entry) => entry.normalizedUri.path),
        ['/orders/1', '/orders/3'],
      );
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
      expect(
        runtime.activeRouteEntries.map((entry) => entry.normalizedUri.path),
        ['/orders/1', '/orders/3'],
      );
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
