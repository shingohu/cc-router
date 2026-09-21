import 'dart:async';

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

final class TestTelemetryContextProvider
    implements CCNavigationTelemetryContextProvider {
  const TestTelemetryContextProvider(this.context);

  final CCNavigationTelemetryContext? context;

  @override
  CCNavigationTelemetryContext? currentContext() => context;
}

final class MutableTelemetryContextProvider
    implements CCNavigationTelemetryContextProvider {
  MutableTelemetryContextProvider(this.context);

  CCNavigationTelemetryContext? context;

  @override
  CCNavigationTelemetryContext? currentContext() => context;
}

final class FailingNavigationAdapter implements CCNavigationAdapter {
  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) {}

  @override
  Future<Object?> navigate(CCNavigationRequest request) async {
    throw StateError('backend secret should not be recorded');
  }

  @override
  Future<bool> maybePop({Object? result}) async => false;

  @override
  void pop({Object? result}) {}

  @override
  bool canPop() => false;

  @override
  void dispose() {}
}

final class BackendEventNavigationAdapter
    implements
        CCNavigationAdapter,
        CCNavigationBackendEventSource,
        CCNavigationAdapterCapabilitySource,
        CCNavigationBackendSnapshotSource,
        CCNavigationPopTargetSource,
        CCNavigationPredictiveBackSource {
  BackendEventNavigationAdapter({
    this.predictiveBackSupported = true,
    this.visibilityObservationSupported = false,
  });

  final CCMemoryNavigationAdapter delegate = CCMemoryNavigationAdapter();
  final Set<CCNavigationBackendEventListener> listeners = {};
  final Set<CCPredictiveBackEventListener> predictiveBackListeners = {};
  final bool predictiveBackSupported;
  final bool visibilityObservationSupported;
  bool consumeForeignMaybePop = false;
  String activePopHostId = 'default';
  String activePopOutlet = 'root';
  List<CCNavigationBackendEntrySnapshot> initialSnapshot = const [];

  @override
  CCNavigationPopTarget get activePopTarget => CCNavigationPopTarget(
    hostId: activePopHostId,
    navigatorOutlet: activePopOutlet,
  );

  @override
  CCNavigationAdapterCapabilities get capabilities =>
      CCNavigationAdapterCapabilities(
        supportsPredictiveBack: predictiveBackSupported,
        supportsBackendVisibilityObservation: visibilityObservationSupported,
        supportsNestedNavigators: true,
        supportsStatefulShell: true,
      );

  @override
  List<CCNavigationBackendEntrySnapshot> readInitialBackendSnapshot() =>
      initialSnapshot;

  void emit(
    CCNavigationBackendEventKind kind, {
    String? backendEntryId,
    String? backendOperationId,
    String? previousBackendEntryId,
    String? navigationId,
    String? routeId,
    CCBackendEntryOwner? owner,
    int? sequence,
    Uri? uri,
    String? location,
    String hostId = 'default',
    String navigatorOutlet = 'root',
    String? shellId,
  }) {
    final event = CCNavigationBackendEvent(
      kind: kind,
      timestamp: DateTime.now(),
      backendEntryId: backendEntryId,
      backendOperationId: backendOperationId,
      previousBackendEntryId: previousBackendEntryId,
      navigationId: navigationId,
      routeId: routeId,
      uri: uri,
      owner: owner,
      sequence: sequence,
      hostId: hostId,
      navigatorOutlet: navigatorOutlet,
      placement: CCRoutePlacement(
        hostId: hostId,
        shellId: shellId,
        navigatorOutlet: navigatorOutlet,
      ),
      location: location ?? 'foreign:${kind.name}',
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
  void dispose() => delegate.dispose();

  @override
  void initialize(
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
}

final class UnidentifiedManagedPopAdapter
    implements
        CCNavigationAdapter,
        CCNavigationPopCoordinator,
        CCNavigationAdapterHostBinding,
        CCNavigationAdapterCapabilitySource {
  final CCMemoryNavigationAdapter delegate = CCMemoryNavigationAdapter();

  @override
  String get hostId => 'window.main';

  @override
  CCNavigationAdapterCapabilities get capabilities =>
      const CCNavigationAdapterCapabilities(
        supportsManagedPopObservation: true,
      );

  @override
  bool canPop() => delegate.canPop();

  @override
  void dispose() => delegate.dispose();

  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) => delegate.initialize(routes, shells: shells);

  @override
  Future<bool> maybePop({Object? result}) async => true;

  @override
  Future<CCPopOutcome> maybePopOutcome({Object? result}) async =>
      const CCPopOutcome(
        handled: true,
        removedOwner: CCPopRemovedOwner.managed,
        hostId: 'window.main',
        navigatorOutlet: 'root',
      );

  @override
  Future<Object?> navigate(CCNavigationRequest request) =>
      delegate.navigate(request);

  @override
  void pop({Object? result}) {}

  @override
  CCPopOutcome popOutcome({Object? result}) => const CCPopOutcome(
    handled: true,
    removedOwner: CCPopRemovedOwner.managed,
    hostId: 'window.main',
    navigatorOutlet: 'root',
  );
}

final class TestNavigationInterceptor implements CCNavigationInterceptor {
  TestNavigationInterceptor(this.id, this.onIntercept, this.calls);

  final String id;
  final FutureOr<CCNavigationInterception> Function(
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

final class TestPopGuard implements CCPopGuard {
  TestPopGuard(this.id, this.calls, this.onEvaluate);

  final String id;
  final List<String> calls;
  final CCPopGuardDecision Function(CCPopGuardContext context) onEvaluate;

  @override
  CCPopGuardDecision evaluate(CCPopGuardContext context) {
    calls.add('$id:${context.entry.routeId}:${context.trigger.name}');
    return onEvaluate(context);
  }
}

final class TestNavigationFailurePolicy implements CCNavigationFailurePolicy {
  TestNavigationFailurePolicy(this.callback);

  final FutureOr<CCNavigationFailureDecision> Function(
    CCNavigationFailureContext context,
  )
  callback;

  @override
  FutureOr<CCNavigationFailureDecision> onFailure(
    CCNavigationFailureContext context,
  ) => callback(context);
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
  List<String> popGuardIds = const [],
  CCRoutePresentation presentation = const CCPagePresentation(),
  CCRoutePlacement placement = const CCRoutePlacement.root(),
}) => CCRouteDefinition<RouteArgs, String>(
  routeId: routeId,
  patterns: [
    CCPathPattern(path, primary: true, constraints: {'value': r'\d+'}),
  ],
  codec: const RouteArgsCodec(),
  deepLink: deepLink,
  interceptorIds: interceptorIds,
  popGuardIds: popGuardIds,
  presentation: presentation,
  placement: placement,
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
            location: '/external/customer-42?token=secret-token#private',
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
      runtime.initialize();

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
      final sanitized = runtime.backendEntries.first.address;
      expect(sanitized.routePattern, isNull);
      expect(sanitized.hasQueryParameters, isTrue);
      expect(sanitized.hasFragment, isTrue);
      expect(runtime.recentBackendNavigationEvents, isEmpty);
      await runtime.dispose();
    },
  );

  test(
    'retained diagnostics summarize addresses without parameter values',
    () async {
      const pathValue = '42001';
      const queryValue = 'secret-token';
      const fragmentValue = 'private-fragment';
      var authorized = false;
      final adapter = BackendEventNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          routeComponent('orders', (registry) {
            registry.registerRouteInterceptor(
              'orders.auth',
              TestNavigationInterceptor(
                'orders.auth',
                (_) => authorized
                    ? const CCNavigationProceed()
                    : const CCNavigationDefer(code: 'login_required'),
                [],
              ),
            );
            registry.registerRoute(
              pathRoute(interceptorIds: const ['orders.auth']),
            );
          }),
        ],
      );
      runtime.initialize();

      final deferred = runtime.pushRoute<String>(
        const TestIntent<String>(
          'orders.detail',
          RouteArgs(pathValue, tab: queryValue),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final pending = runtime.pendingNavigations.single;
      expect(pending.address.routePattern, '/orders/:value');
      expect(pending.address.hasPathParameters, isTrue);
      expect(pending.address.hasQueryParameters, isTrue);
      final deferredFailure = expectLater(
        deferred,
        throwsA(isA<CCRouteCancelledError>()),
      );
      runtime.cancelPendingNavigation(pending.navigationId);
      await deferredFailure;

      authorized = true;
      final pushed = runtime.pushRoute<String>(
        const TestIntent<String>(
          'orders.detail',
          RouteArgs(pathValue, tab: queryValue),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final routeEntry = runtime.activeRouteEntries.single;
      final sensitiveUri = Uri.parse(
        '/orders/$pathValue?tab=$queryValue#$fragmentValue',
      );
      adapter.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'managed-sensitive-entry',
        navigationId: routeEntry.navigationId,
        routeId: routeEntry.routeId,
        owner: CCBackendEntryOwner.managed,
        uri: sensitiveUri,
        location: sensitiveUri.toString(),
      );

      final backendEvent = runtime.recentBackendNavigationEvents.single;
      final backendEntry = runtime.backendEntries.single;
      for (final address in [
        routeEntry.address,
        runtime.recentRouteEntryEvents.last.entry.address,
        runtime.recentRouteVisibilityEvents.last.entry.address,
        backendEvent.address,
        backendEntry.address,
      ]) {
        expect(address.routePattern, '/orders/:value');
        expect(address.hasPathParameters, isTrue);
        expect(address.toString(), isNot(contains(pathValue)));
        expect(address.toString(), isNot(contains(queryValue)));
        expect(address.toString(), isNot(contains(fragmentValue)));
      }
      expect(backendEvent.address.hasQueryParameters, isTrue);
      expect(backendEvent.address.hasFragment, isTrue);
      expect(backendEntry.address.hasQueryParameters, isTrue);
      expect(backendEntry.address.hasFragment, isTrue);

      runtime.popRoute();
      expect(await pushed, isNull);
      await runtime.dispose();
    },
  );

  test(
    'initial snapshots are structural state beyond event capacity',
    () async {
      final adapter = BackendEventNavigationAdapter()
        ..initialSnapshot = const [
          CCNavigationBackendEntrySnapshot(
            backendEntryId: 'first',
            owner: CCBackendEntryOwner.foreign,
            navigatorOutlet: 'root',
          ),
          CCNavigationBackendEntrySnapshot(
            backendEntryId: 'second',
            owner: CCBackendEntryOwner.opaque,
            navigatorOutlet: 'detail',
          ),
        ];
      final runtime = CCRouterRuntime.forTesting(
        navigationDiagnosticCapacity: 1,
        navigationAdapter: adapter,
      );
      runtime.initialize();

      expect(runtime.activeBackendEntries, hasLength(2));
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
        () => modalRuntime.initialize(),
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
      runtime.initialize();
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
        () => unsupportedPredictiveRuntime.initialize(),
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
      runtime.initialize();
      final observed = <CCNavigationBackendDiagnosticEvent>[];
      runtime.addBackendNavigationListener(observed.add);

      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('1')),
      );
      final pushed = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );
      final before = runtime.activeRouteEntries;

      const entryKinds = [
        CCNavigationBackendEventKind.push,
        CCNavigationBackendEventKind.pop,
        CCNavigationBackendEventKind.replace,
        CCNavigationBackendEventKind.remove,
        CCNavigationBackendEventKind.topChanged,
      ];
      for (final kind in entryKinds) {
        adapter.emit(kind);
      }
      await Future<void>.delayed(Duration.zero);

      expect(runtime.activeRouteEntries, hasLength(2));
      expect(
        runtime.activeRouteEntries.map((entry) => entry.routeEntryId),
        before.map((entry) => entry.routeEntryId),
      );
      expect(
        runtime.activeRouteEntries.map((entry) => entry.lifecycleState),
        before.map((entry) => entry.lifecycleState),
      );
      expect(observed.map((event) => event.kind), entryKinds);
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
      runtime.initialize();

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

  test('backend capacity never evicts active structural entries', () async {
    final adapter = BackendEventNavigationAdapter();
    final runtime = CCRouterRuntime.forTesting(
      navigationDiagnosticCapacity: 2,
      navigationAdapter: adapter,
    );
    runtime.initialize();

    for (var index = 0; index < 3; index++) {
      adapter.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'active-$index',
        backendOperationId: 'push-$index',
        sequence: index + 1,
      );
    }
    expect(runtime.activeBackendEntries, hasLength(3));

    for (var index = 0; index < 3; index++) {
      adapter.emit(
        CCNavigationBackendEventKind.pop,
        backendEntryId: 'removed-$index',
        backendOperationId: 'pop-$index',
        sequence: index + 4,
      );
    }
    expect(runtime.activeBackendEntries, hasLength(3));
    expect(
      runtime.backendEntries.where(
        (entry) => entry.lifecycleState == CCBackendEntryLifecycleState.removed,
      ),
      hasLength(2),
    );
    await runtime.dispose();
  });

  test('zero backend history capacity still deduplicates operations', () async {
    final adapter = BackendEventNavigationAdapter();
    final runtime = CCRouterRuntime.forTesting(
      navigationDiagnosticCapacity: 0,
      navigationAdapter: adapter,
    );
    runtime.initialize();
    final observed = <CCNavigationBackendDiagnosticEvent>[];
    runtime.addBackendNavigationListener(observed.add);

    for (var index = 0; index < 2; index++) {
      adapter.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'active',
        backendOperationId: 'same-operation',
      );
    }
    await Future<void>.delayed(Duration.zero);
    expect(runtime.activeBackendEntries, hasLength(1));
    expect(observed, hasLength(1));

    adapter.emit(
      CCNavigationBackendEventKind.pop,
      backendEntryId: 'active',
      backendOperationId: 'remove-operation',
    );
    expect(runtime.backendEntries, isEmpty);
    await runtime.dispose();
  });

  test('observer delivery is asynchronous, FIFO, and cancellable', () async {
    final adapter = BackendEventNavigationAdapter();
    final runtime = CCRouterRuntime.forTesting(navigationAdapter: adapter);
    runtime.initialize();
    final observed = <CCNavigationBackendEventKind>[];
    final removeListener = runtime.addBackendNavigationListener(
      (event) => observed.add(event.kind),
    );

    adapter.emit(
      CCNavigationBackendEventKind.push,
      backendOperationId: 'async-push',
    );
    adapter.emit(
      CCNavigationBackendEventKind.replace,
      backendOperationId: 'async-replace',
    );
    adapter.emit(
      CCNavigationBackendEventKind.topChanged,
      backendOperationId: 'async-top',
    );

    expect(observed, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(observed, [
      CCNavigationBackendEventKind.push,
      CCNavigationBackendEventKind.replace,
      CCNavigationBackendEventKind.topChanged,
    ]);

    adapter.emit(
      CCNavigationBackendEventKind.push,
      backendOperationId: 'cancelled-before-drain',
    );
    removeListener();
    await Future<void>.delayed(Duration.zero);
    expect(observed, hasLength(3));
    await runtime.dispose();
  });

  test('observer-produced events wait for the next drain cycle', () async {
    final adapter = BackendEventNavigationAdapter();
    final runtime = CCRouterRuntime.forTesting(navigationAdapter: adapter);
    runtime.initialize();
    final observed = <CCNavigationBackendEventKind>[];
    runtime.addBackendNavigationListener((event) {
      observed.add(event.kind);
      if (event.kind == CCNavigationBackendEventKind.push) {
        adapter.emit(
          CCNavigationBackendEventKind.replace,
          backendOperationId: 'observer-produced-replace',
        );
      }
    });

    adapter.emit(
      CCNavigationBackendEventKind.push,
      backendOperationId: 'observer-source-push',
    );
    await Future<void>.delayed(Duration.zero);
    expect(observed, [CCNavigationBackendEventKind.push]);
    await Future<void>.delayed(Duration.zero);
    expect(observed, [
      CCNavigationBackendEventKind.push,
      CCNavigationBackendEventKind.replace,
    ]);
    await runtime.dispose();
  });

  test('observer queue drops oldest non-terminal batches when full', () async {
    final adapter = BackendEventNavigationAdapter();
    final runtime = CCRouterRuntime.forTesting(
      navigationDiagnosticCapacity: 0,
      navigationAdapter: adapter,
    );
    runtime.initialize();
    final observed = <CCNavigationBackendDiagnosticEvent>[];
    runtime.addBackendNavigationListener(observed.add);

    for (var index = 0; index < 65; index++) {
      adapter.emit(
        CCNavigationBackendEventKind.push,
        backendOperationId: 'non-terminal-$index',
      );
    }

    expect(observed, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(observed, hasLength(64));
    expect(
      runtime.subscriberErrors.single.message,
      contains('non-terminal batch was dropped'),
    );
    await runtime.dispose();
  });

  test('observer queue never drops terminal batches when full', () async {
    final adapter = BackendEventNavigationAdapter();
    final runtime = CCRouterRuntime.forTesting(
      navigationDiagnosticCapacity: 0,
      navigationAdapter: adapter,
    );
    runtime.initialize();
    final observed = <CCNavigationBackendDiagnosticEvent>[];
    runtime.addBackendNavigationListener(observed.add);

    for (var index = 0; index < 65; index++) {
      adapter.emit(
        CCNavigationBackendEventKind.pop,
        backendOperationId: 'terminal-$index',
      );
    }

    expect(observed, hasLength(1));
    await Future<void>.delayed(Duration.zero);
    expect(observed, hasLength(65));
    expect(
      runtime.subscriberErrors.single.message,
      contains('terminal batch was delivered with backpressure'),
    );
    await runtime.dispose();
  });

  test(
    'Runtime dispose flushes queued observations and cancels drain',
    () async {
      final adapter = BackendEventNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(navigationAdapter: adapter);
      runtime.initialize();
      final observed = <CCNavigationBackendDiagnosticEvent>[];
      runtime.addBackendNavigationListener(observed.add);
      adapter.emit(
        CCNavigationBackendEventKind.push,
        backendOperationId: 'dispose-flush',
      );

      expect(observed, isEmpty);
      await runtime.dispose();
      expect(observed, hasLength(1));
      await Future<void>.delayed(Duration.zero);
      expect(observed, hasLength(1));
    },
  );

  test(
    'Host detach resets sequence state for the same Host identity',
    () async {
      final adapter = BackendEventNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(navigationAdapter: adapter);
      runtime.initialize();

      adapter.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'old-entry',
        backendOperationId: 'old-push',
        hostId: 'window.reused',
        sequence: 8,
      );
      adapter.emit(
        CCNavigationBackendEventKind.hostDetached,
        backendOperationId: 'old-detach',
        hostId: 'window.reused',
        sequence: 9,
      );
      adapter.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'new-entry',
        backendOperationId: 'new-push',
        hostId: 'window.reused',
        sequence: 1,
      );

      expect(
        runtime.activeBackendEntries.map((entry) => entry.backendEntryId),
        ['new-entry'],
      );
      expect(runtime.desynchronizedBackendHosts, isEmpty);
      await runtime.dispose();
    },
  );

  test(
    'confirmed backend tops drive visibility without removing covered entries',
    () async {
      final adapter = BackendEventNavigationAdapter(
        visibilityObservationSupported: true,
      );
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      runtime.initialize();

      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('1')),
      );
      final first = runtime.activeRouteEntries.single;
      expect(first.lifecycleState, CCRouteEntryLifecycleState.pushed);

      adapter.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'managed-1',
        backendOperationId: 'managed-push-1',
        navigationId: first.navigationId,
        routeId: first.routeId,
        owner: CCBackendEntryOwner.managed,
        sequence: 1,
      );
      expect(
        runtime.activeRouteEntries.single.lifecycleState,
        CCRouteEntryLifecycleState.pushed,
      );
      adapter.emit(
        CCNavigationBackendEventKind.topChanged,
        backendEntryId: 'managed-1',
        backendOperationId: 'managed-top-1',
        navigationId: first.navigationId,
        routeId: first.routeId,
        owner: CCBackendEntryOwner.managed,
        sequence: 2,
      );
      expect(
        runtime.activeRouteEntries.single.lifecycleState,
        CCRouteEntryLifecycleState.visible,
      );

      final secondResult = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );
      final second = runtime.activeRouteEntries.last;
      expect(second.lifecycleState, CCRouteEntryLifecycleState.pushed);
      adapter.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'managed-2',
        backendOperationId: 'managed-push-2',
        previousBackendEntryId: 'managed-1',
        navigationId: second.navigationId,
        routeId: second.routeId,
        owner: CCBackendEntryOwner.managed,
        sequence: 3,
      );
      expect(
        runtime.backendEntries
            .singleWhere((entry) => entry.backendEntryId == 'managed-1')
            .lifecycleState,
        CCBackendEntryLifecycleState.active,
      );
      adapter.emit(
        CCNavigationBackendEventKind.topChanged,
        backendEntryId: 'managed-2',
        backendOperationId: 'managed-top-2',
        previousBackendEntryId: 'managed-1',
        navigationId: second.navigationId,
        routeId: second.routeId,
        owner: CCBackendEntryOwner.managed,
        sequence: 4,
      );
      expect(runtime.activeRouteEntries.map((entry) => entry.lifecycleState), [
        CCRouteEntryLifecycleState.hidden,
        CCRouteEntryLifecycleState.visible,
      ]);

      adapter.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'foreign-popup',
        backendOperationId: 'foreign-push',
        previousBackendEntryId: 'managed-2',
        owner: CCBackendEntryOwner.foreign,
        sequence: 5,
      );
      adapter.emit(
        CCNavigationBackendEventKind.topChanged,
        backendEntryId: 'foreign-popup',
        backendOperationId: 'foreign-top',
        previousBackendEntryId: 'managed-2',
        owner: CCBackendEntryOwner.foreign,
        sequence: 6,
      );
      expect(
        runtime.activeRouteEntries.last.lifecycleState,
        CCRouteEntryLifecycleState.hidden,
      );
      expect(runtime.activeRouteEntries, hasLength(2));

      adapter.emit(
        CCNavigationBackendEventKind.pop,
        backendEntryId: 'foreign-popup',
        backendOperationId: 'foreign-pop',
        previousBackendEntryId: 'managed-2',
        owner: CCBackendEntryOwner.foreign,
        sequence: 7,
      );
      adapter.emit(
        CCNavigationBackendEventKind.topChanged,
        backendEntryId: 'managed-2',
        backendOperationId: 'managed-top-restored',
        previousBackendEntryId: 'foreign-popup',
        owner: CCBackendEntryOwner.managed,
        sequence: 8,
      );
      expect(
        runtime.activeRouteEntries.last.lifecycleState,
        CCRouteEntryLifecycleState.visible,
      );

      final eventCount = runtime.recentRouteVisibilityEvents.length;
      adapter.emit(
        CCNavigationBackendEventKind.topChanged,
        backendEntryId: 'managed-2',
        backendOperationId: 'managed-top-restored',
        owner: CCBackendEntryOwner.managed,
        sequence: 8,
      );
      expect(runtime.recentRouteVisibilityEvents, hasLength(eventCount));

      runtime.popRoute(result: 'done');
      expect(await secondResult, 'done');
      await runtime.dispose();
    },
  );

  test('detects backend sequence gaps and ignores stale repeats', () async {
    final adapter = BackendEventNavigationAdapter(
      visibilityObservationSupported: true,
    );
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      components: [
        routeComponent(
          'orders',
          (registry) => registry.registerRoute(pathRoute()),
        ),
      ],
    );
    runtime.initialize();

    adapter.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'foreign-1',
      backendOperationId: 'foreign-1-push',
      sequence: 1,
      hostId: 'window.main',
    );
    adapter.emit(
      CCNavigationBackendEventKind.topChanged,
      backendEntryId: 'foreign-1',
      backendOperationId: 'foreign-1-top',
      sequence: 3,
      hostId: 'window.main',
    );
    expect(runtime.desynchronizedBackendHosts, contains('window.main'));
    expect(
      runtime.visibleBackendEntries.single.visibilityState,
      CCBackendEntryVisibilityState.visible,
    );

    final eventCount = runtime.recentBackendNavigationEvents.length;
    adapter.emit(
      CCNavigationBackendEventKind.remove,
      backendEntryId: 'foreign-1',
      backendOperationId: 'stale-remove',
      sequence: 2,
      hostId: 'window.main',
    );
    expect(runtime.recentBackendNavigationEvents, hasLength(eventCount));
    expect(runtime.activeBackendEntries, hasLength(1));
    await runtime.dispose();
  });

  test(
    'Stateful Shell activation hides and restores retained branch entries',
    () async {
      final adapter = BackendEventNavigationAdapter(
        visibilityObservationSupported: true,
      );
      const homePlacement = CCRoutePlacement(
        shellId: 'tabs',
        navigatorOutlet: 'home',
      );
      const settingsPlacement = CCRoutePlacement(
        shellId: 'tabs',
        navigatorOutlet: 'settings',
      );
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          routeComponent('shell', (registry) {
            registry.registerShell(
              CCShellDefinition(
                shellId: 'tabs',
                type: CCShellType.statefulBranches,
                outlets: const ['home', 'settings'],
                initialOutlet: 'home',
              ),
            );
            registry.registerRoute(
              pathRoute(
                routeId: 'home.detail',
                path: '/home/:value',
                placement: homePlacement,
              ),
            );
            registry.registerRoute(
              pathRoute(
                routeId: 'settings.detail',
                path: '/settings/:value',
                placement: settingsPlacement,
              ),
            );
          }),
        ],
      );
      runtime.initialize();

      await runtime.goRoute(
        const TestIntent<void>('home.detail', RouteArgs('1')),
      );
      final home = runtime.activeRouteEntries.single;
      adapter.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'home-entry',
        backendOperationId: 'home-push',
        navigationId: home.navigationId,
        routeId: home.routeId,
        owner: CCBackendEntryOwner.managed,
        sequence: 1,
        navigatorOutlet: 'home',
        shellId: 'tabs',
      );
      adapter.emit(
        CCNavigationBackendEventKind.topChanged,
        backendEntryId: 'home-entry',
        backendOperationId: 'home-top',
        navigationId: home.navigationId,
        routeId: home.routeId,
        owner: CCBackendEntryOwner.managed,
        sequence: 2,
        navigatorOutlet: 'home',
        shellId: 'tabs',
      );

      final settingsResult = runtime.pushRoute<String>(
        const TestIntent<String>('settings.detail', RouteArgs('2')),
      );
      final settings = runtime.activeRouteEntries.last;
      adapter.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'settings-entry',
        backendOperationId: 'settings-push',
        navigationId: settings.navigationId,
        routeId: settings.routeId,
        owner: CCBackendEntryOwner.managed,
        sequence: 3,
        navigatorOutlet: 'settings',
        shellId: 'tabs',
      );
      adapter.emit(
        CCNavigationBackendEventKind.topChanged,
        backendEntryId: 'settings-entry',
        backendOperationId: 'settings-top',
        navigationId: settings.navigationId,
        routeId: settings.routeId,
        owner: CCBackendEntryOwner.managed,
        sequence: 4,
        navigatorOutlet: 'settings',
        shellId: 'tabs',
      );
      adapter.emit(
        CCNavigationBackendEventKind.outletActivated,
        backendOperationId: 'settings-activated',
        sequence: 5,
        navigatorOutlet: 'settings',
        shellId: 'tabs',
      );
      expect(runtime.activeRouteEntries.map((entry) => entry.lifecycleState), [
        CCRouteEntryLifecycleState.hidden,
        CCRouteEntryLifecycleState.visible,
      ]);

      adapter.emit(
        CCNavigationBackendEventKind.outletActivated,
        backendOperationId: 'home-activated',
        sequence: 6,
        navigatorOutlet: 'home',
        shellId: 'tabs',
      );
      expect(runtime.activeRouteEntries.map((entry) => entry.lifecycleState), [
        CCRouteEntryLifecycleState.visible,
        CCRouteEntryLifecycleState.hidden,
      ]);
      expect(runtime.activeRouteEntries, hasLength(2));

      runtime.popRoute(result: 'done');
      expect(await settingsResult, 'done');
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
    runtime.initialize();
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
      runtime.initialize();
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
      runtime.initialize();
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
          (event) =>
              event.entry.lifecycleState == CCRouteEntryLifecycleState.disposed,
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
    runtime.initialize();
    final lifecycle = <CCRouteEntryLifecycleEvent>[];
    runtime.addRouteEntryListener(lifecycle.add);
    await runtime.goRoute(
      const TestIntent<void>('orders.detail', RouteArgs('42')),
    );
    expect(runtime.activeRouteEntries, hasLength(1));

    await runtime.dispose();

    expect(runtime.activeRouteEntries, isEmpty);
    expect(
      lifecycle.last.entry.lifecycleState,
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
    runtime.initialize();

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
              expect(event.request.routePattern, '/orders/:value');
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
      runtime.initialize();

      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('42')),
      );
      await Future<void>.delayed(Duration.zero);

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
    'global interceptor decisions are observed by read-only aspects',
    () async {
      final phases = <CCNavigationAspectPhase>[];
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        globalInterceptors: [
          CCGlobalNavigationInterceptor(
            id: 'policy',
            interceptor: TestNavigationInterceptor(
              'policy',
              (_) => const CCNavigationCancel(code: 'blocked'),
              [],
            ),
          ),
        ],
        navigationAspects: [
          CCNavigationAspect(
            id: 'telemetry',
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
      runtime.initialize();

      await expectLater(
        runtime.goRoute(
          const TestIntent<void>('orders.detail', RouteArgs('42')),
        ),
        throwsA(isA<CCRouteCancelledError>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(phases, [
        CCNavigationAspectPhase.found,
        CCNavigationAspectPhase.lost,
        CCNavigationAspectPhase.after,
      ]);
      expect(runtime.activeRouteEntries, isEmpty);
      await runtime.dispose();
    },
  );

  test(
    'aspects expose safe attribution, stage timing, and Entry visibility',
    () async {
      final observed = <CCNavigationAspectEvent>[];
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        telemetryContextProvider: const TestTelemetryContextProvider(
          CCNavigationTelemetryContext(
            anonymousVisitorId: 'visitor-opaque',
            applicationSessionId: 'app-session-opaque',
          ),
        ),
        globalInterceptors: [
          CCGlobalNavigationInterceptor(
            id: 'timed.policy',
            interceptor: TestNavigationInterceptor('timed.policy', (_) async {
              await Future<void>.delayed(const Duration(milliseconds: 1));
              return const CCNavigationProceed();
            }, []),
          ),
        ],
        navigationAspects: [
          CCNavigationAspect(
            id: 'telemetry',
            onFound: observed.add,
            onArrival: observed.add,
            onShow: observed.add,
            onHide: observed.add,
            onRemoved: observed.add,
            onDisposed: observed.add,
            onAfter: observed.add,
          ),
        ],
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      runtime.initialize();

      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('10001')),
      );
      final pushed = runtime.pushRoute<String>(
        const TestIntent<String>(
          'orders.detail',
          RouteArgs('20002', payload: Object()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(runtime.activeRouteEntries, hasLength(2));
      runtime.popRoute(result: 'done');
      expect(await pushed, 'done');
      await Future<void>.delayed(Duration.zero);

      final childFound = observed.lastWhere(
        (event) =>
            event.phase == CCNavigationAspectPhase.found &&
            event.request.referrerRouteId != null,
      );
      expect(childFound.request.resolvedHostId, 'default');
      expect(childFound.request.navigatorOutlet, 'root');
      expect(childFound.request.ownerComponentId, 'orders');
      expect(childFound.request.referrerRouteId, 'orders.detail');
      expect(childFound.request.redirectChain, ['orders.detail']);
      expect(
        childFound.request.telemetryContext?.anonymousVisitorId,
        'visitor-opaque',
      );
      expect(
        childFound.request.telemetryContext?.applicationSessionId,
        'app-session-opaque',
      );
      expect(childFound.request.toString(), isNot(contains('20002')));
      expect(childFound.timing?.resolve, isNotNull);

      final childNavigationId = childFound.request.navigationId;
      final childEvents = observed
          .where((event) => event.request.navigationId == childNavigationId)
          .toList();
      final childPhases = childEvents.map((event) => event.phase).toList();
      expect(
        childPhases,
        containsAll([
          CCNavigationAspectPhase.found,
          CCNavigationAspectPhase.arrival,
          CCNavigationAspectPhase.removed,
          CCNavigationAspectPhase.disposed,
          CCNavigationAspectPhase.after,
        ]),
      );
      expect(
        childPhases.indexOf(CCNavigationAspectPhase.found),
        lessThan(childPhases.indexOf(CCNavigationAspectPhase.arrival)),
      );
      expect(
        childPhases.indexOf(CCNavigationAspectPhase.arrival),
        lessThan(childPhases.indexOf(CCNavigationAspectPhase.removed)),
      );
      final arrival = childEvents.firstWhere(
        (event) => event.phase == CCNavigationAspectPhase.arrival,
      );
      expect(arrival.timing?.intercept, isNotNull);
      expect(arrival.timing?.dispatch, isNotNull);
      expect(arrival.timing?.arrival, isNotNull);
      final removed = childEvents.firstWhere(
        (event) => event.phase == CCNavigationAspectPhase.removed,
      );
      expect(removed.timing?.stay, isNotNull);

      final rootEvents = observed.where(
        (event) =>
            event.request.navigationId != childNavigationId &&
            (event.phase == CCNavigationAspectPhase.hide ||
                event.phase == CCNavigationAspectPhase.show),
      );
      expect(rootEvents.map((event) => event.phase), [
        CCNavigationAspectPhase.hide,
        CCNavigationAspectPhase.show,
      ]);
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
    runtime.initialize();

    await runtime.goRoute(
      const TestIntent<void>('orders.detail', RouteArgs('42')),
    );
    await Future<void>.delayed(Duration.zero);

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
    runtime.initialize();
    await runtime.goRoute(
      const TestIntent<void>('orders.detail', RouteArgs('42')),
    );
    await Future<void>.delayed(Duration.zero);
    await reentryExpectation;
    expect(runtime.activeRouteEntries, hasLength(1));
    await runtime.dispose();
  });

  test('redirect preserves origin and navigation identity', () async {
    final calls = <String>[];
    final seenIds = <String>[];
    late CCNavigationAspectRequest arrivedRequest;
    final source = const CCNavigationSource.deepLink('platform');
    final adapter = CCMemoryNavigationAdapter();
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      deepLinkIngressPolicy: CCDeepLinkIngressPolicy(allowRelativePaths: true),
      navigationAspects: [
        CCNavigationAspect(
          id: 'redirect.trace',
          onArrival: (event) => arrivedRequest = event.request,
        ),
      ],
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
    runtime.initialize();

    await runtime.openRoute(
      Uri.parse('/orders/42'),
      origin: CCNavigationOrigin.externalPlatform,
      mode: CCDeepLinkOpenMode.go,
      source: source,
    );
    await Future<void>.delayed(Duration.zero);

    expect(adapter.currentRequest?.routeId, 'auth.login');
    expect(adapter.currentRequest?.origin, CCNavigationOrigin.externalPlatform);
    expect(adapter.currentRequest?.openMode, CCDeepLinkOpenMode.go);
    expect(adapter.currentRequest?.source, same(source));
    expect(seenIds, hasLength(1));
    expect(adapter.currentRequest?.navigationId, seenIds.single);
    expect(calls, ['orders.redirect:orders.detail']);
    expect(arrivedRequest.redirectChain, ['orders.detail', 'auth.login']);
    expect(arrivedRequest.openMode, CCDeepLinkOpenMode.go);
    await runtime.dispose();
  });

  test('URI redirect cannot bypass the Host authority allowlist', () async {
    final adapter = CCMemoryNavigationAdapter();
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      deepLinkIngressPolicy: CCDeepLinkIngressPolicy(
        allowRelativePaths: true,
        allowedAuthorities: [
          CCDeepLinkAuthorityRule(scheme: 'https', host: 'trusted.example'),
        ],
      ),
      components: [
        routeComponent('orders', (registry) {
          registry.registerRouteInterceptor(
            'orders.external.redirect',
            TestNavigationInterceptor(
              'orders.external.redirect',
              (_) => CCNavigationRedirect.toUri(
                Uri.parse('https://evil.example/target/42'),
              ),
              <String>[],
            ),
          );
          registry.registerRoute(
            pathRoute(
              routeId: 'orders.detail',
              deepLink: CCDeepLinkPolicy.enabled,
              interceptorIds: ['orders.external.redirect'],
            ),
          );
          registry.registerRoute<RouteArgs, void>(
            CCRouteDefinition<RouteArgs, void>(
              routeId: 'orders.target',
              patterns: const [
                CCPathPattern('/target/:value', primary: true),
                CCUriPattern('https://evil.example/target/:value'),
              ],
              codec: const RouteArgsCodec(),
              deepLink: CCDeepLinkPolicy.enabled,
            ),
          );
        }),
      ],
    );
    runtime.initialize();

    await expectLater(
      runtime.openRoute(
        Uri.parse('/orders/42'),
        origin: CCNavigationOrigin.externalPlatform,
      ),
      throwsA(
        isA<CCDeepLinkIngressRejectedError>().having(
          (error) => error.reason,
          'reason',
          CCDeepLinkIngressRejectionReason.authorityNotAllowed,
        ),
      ),
    );
    expect(adapter.stack, isEmpty);
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
    cancellation.initialize();
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
    loop.initialize();
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
    expect(
      () => runtime.initialize(),
      throwsA(isA<CCRouteRegistrationError>()),
    );
    await runtime.dispose();
  });

  test('rejects route interceptors owned by another component', () async {
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: CCMemoryNavigationAdapter(),
      components: [
        routeComponent(
          'auth',
          (registry) => registry.registerRouteInterceptor(
            'auth.private',
            TestNavigationInterceptor(
              'auth.private',
              (_) => const CCNavigationProceed(),
              [],
            ),
          ),
        ),
        routeComponent(
          'orders',
          (registry) => registry.registerRoute(
            pathRoute(interceptorIds: ['auth.private']),
          ),
        ),
      ],
    );

    expect(
      () => runtime.initialize(),
      throwsA(isA<CCRouteRegistrationError>()),
    );
    await runtime.dispose();
  });

  test(
    'failure context keeps original and current IDs for typed redirect errors',
    () async {
      final contexts = <CCNavigationFailureContext>[];
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        navigationFailurePolicy: TestNavigationFailurePolicy((context) {
          contexts.add(context);
          return const CCNavigationFailurePropagate();
        }),
        components: [
          routeComponent('orders', (registry) {
            registry.registerRoute(
              pathRoute(
                routeId: 'orders.detail',
                interceptorIds: const ['orders.redirect'],
              ),
            );
            registry.registerRoute(
              pathRoute(routeId: 'auth.login', path: '/auth/:value'),
            );
            registry.registerRouteInterceptor(
              'orders.redirect',
              TestNavigationInterceptor(
                'orders.redirect',
                (_) => const CCNavigationRedirect.toIntent(
                  TestIntent<Object?>('auth.login', RouteArgs('invalid')),
                ),
                <String>[],
              ),
            );
          }),
        ],
      );
      runtime.initialize();

      await expectLater(
        runtime.pushRoute<void>(
          const TestIntent<void>('orders.detail', RouteArgs('42')),
        ),
        throwsA(isA<CCRouteParameterError>()),
      );

      expect(contexts, hasLength(1));
      expect(contexts.single.initialRouteId, 'orders.detail');
      expect(contexts.single.routeId, 'auth.login');
      expect(contexts.single.stage, CCNavigationFailureStage.parameters);
      expect(
        contexts.single.reason,
        CCNavigationFailureReason.invalidParameters,
      );
      await runtime.dispose();
    },
  );

  test(
    'interceptor timeout cancels work and reports a dedicated error',
    () async {
      CCNavigationInterceptorContext? seenContext;
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        globalInterceptors: [
          CCGlobalNavigationInterceptor(
            id: 'slow.policy',
            timeout: const Duration(milliseconds: 1),
            interceptor: TestNavigationInterceptor('slow.policy', (context) {
              seenContext = context;
              return context.cancellation.whenCancelled.then(
                (_) => const CCNavigationProceed(),
              );
            }, []),
          ),
        ],
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      runtime.initialize();

      await expectLater(
        runtime.goRoute(
          const TestIntent<void>('orders.detail', RouteArgs('42')),
        ),
        throwsA(
          isA<CCNavigationInterceptorTimeoutError>().having(
            (error) => error.interceptorId,
            'interceptorId',
            'slow.policy',
          ),
        ),
      );
      expect(seenContext?.deadline, isNotNull);
      expect(seenContext?.cancellation.isCancelled, isTrue);
      expect(runtime.activeRouteEntries, isEmpty);
      await runtime.dispose();
    },
  );

  test('interceptor failures use a sanitized dedicated error', () async {
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: CCMemoryNavigationAdapter(),
      globalInterceptors: [
        CCGlobalNavigationInterceptor(
          id: 'broken.policy',
          interceptor: TestNavigationInterceptor(
            'broken.policy',
            (_) => throw StateError('sensitive policy details'),
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
    runtime.initialize();

    await expectLater(
      runtime.goRoute(const TestIntent<void>('orders.detail', RouteArgs('42'))),
      throwsA(
        isA<CCNavigationInterceptorError>()
            .having(
              (error) => error.interceptorId,
              'interceptorId',
              'broken.policy',
            )
            .having((error) => error.causeType, 'causeType', 'StateError')
            .having(
              (error) => error.message,
              'message',
              isNot(contains('sensitive')),
            ),
      ),
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
    runtime.initialize();

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
        navigationDiagnosticCapacity: 2,
        navigationAdapter: adapter,
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      runtime.initialize();

      final events = <CCNavigationLifecycleEvent>[];
      final removeListener = runtime.addNavigationListener(events.add);
      const source = CCNavigationSource.feature('home.order_banner');
      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('42')),
        source: source,
      );
      await Future<void>.delayed(Duration.zero);

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
        events.every((event) => event.routePattern == '/orders/:value'),
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
        runtime.recentNavigationEvents.map((event) => event.routePattern),
        ['/orders/:value', '/orders/:value'],
      );

      await runtime.dispose();
      expect(runtime.recentNavigationEvents, isEmpty);
    },
  );

  test(
    'invalid navigation source IDs degrade without leaking attribution',
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
      runtime.initialize();

      final invalidSources = <CCNavigationSource>[
        const CCNavigationSource.feature(''),
        const CCNavigationSource.feature(' account.id'),
        const CCNavigationSource.feature('account@example.com'),
        const CCNavigationSource.deepLink('https://example.com/campaign'),
        CCNavigationSource.feature('a${'b' * 64}'),
      ];
      for (var index = 0; index < invalidSources.length; index++) {
        await runtime.goRoute(
          TestIntent<void>('orders.detail', RouteArgs('$index')),
          source: invalidSources[index],
        );
        expect(adapter.currentRequest!.source, isNull);
        expect(runtime.recentNavigationEvents.last.source, isNull);
      }

      const valid = CCNavigationSource.feature('home.order_banner');
      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('100')),
        source: valid,
      );
      expect(adapter.currentRequest!.source, same(valid));
      expect(
        runtime.subscriberErrors
            .where((error) => error.message.contains('invalid stable ID'))
            .length,
        invalidSources.length,
      );
      expect(
        runtime.subscriberErrors.map((error) => error.message).join(),
        isNot(contains('example.com')),
      );
      await runtime.dispose();
    },
  );

  test(
    'telemetry context accepts opaque IDs and drops malformed snapshots',
    () async {
      final provider = MutableTelemetryContextProvider(
        const CCNavigationTelemetryContext(
          anonymousVisitorId: '123e4567-e89b-12d3-a456-426614174000',
          applicationSessionId: 'run_2026.09-20',
        ),
      );
      final observed = <CCNavigationAspectEvent>[];
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        telemetryContextProvider: provider,
        navigationAspects: [
          CCNavigationAspect(id: 'telemetry', onFound: observed.add),
        ],
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      runtime.initialize();

      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('200')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        observed.last.request.telemetryContext?.anonymousVisitorId,
        '123e4567-e89b-12d3-a456-426614174000',
      );

      final invalidContexts = <CCNavigationTelemetryContext>[
        const CCNavigationTelemetryContext(
          anonymousVisitorId: 'account@example.com',
        ),
        const CCNavigationTelemetryContext(
          anonymousVisitorId: 'anonymous',
          applicationSessionId: 'https://example.com/session',
        ),
        CCNavigationTelemetryContext(anonymousVisitorId: 'v${'x' * 64}'),
      ];
      for (var index = 0; index < invalidContexts.length; index++) {
        provider.context = invalidContexts[index];
        await runtime.goRoute(
          TestIntent<void>('orders.detail', RouteArgs('${201 + index}')),
        );
        await Future<void>.delayed(Duration.zero);
        expect(observed.last.request.telemetryContext, isNull);
      }
      expect(
        runtime.subscriberErrors
            .where((error) => error.message.contains('invalid anonymous ID'))
            .length,
        invalidContexts.length,
      );
      expect(
        runtime.subscriberErrors.map((error) => error.message).join(),
        isNot(contains('example.com')),
      );
      await runtime.dispose();
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
      runtime.initialize();

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
    runtime.initialize();

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
      runtime.initialize();

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
        deepLinkIngressPolicy: CCDeepLinkIngressPolicy(
          allowedAuthorities: [
            CCDeepLinkAuthorityRule(scheme: 'https', host: 'therouter.com'),
          ],
          allowRelativePaths: true,
        ),
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
      runtime.initialize();

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
        throwsA(isA<CCDeepLinkRejectedError>()),
      );
      await runtime.openRoute(Uri.parse('/internal/45'));
      expect(adapter.currentRequest?.routeId, 'orders.internal');
      expect(adapter.currentRequest?.origin, CCNavigationOrigin.internal);
      await runtime.dispose();
    },
  );

  test(
    'failure policy falls back with sanitized context and attribution',
    () async {
      final contexts = <CCNavigationFailureContext>[];
      final adapter = CCMemoryNavigationAdapter();
      const source = CCNavigationSource.deepLink('campaign');
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        deepLinkIngressPolicy: CCDeepLinkIngressPolicy(
          allowRelativePaths: true,
        ),
        navigationFailurePolicy: TestNavigationFailurePolicy((context) {
          contexts.add(context);
          return const CCNavigationFailureFallback.toIntent(
            TestIntent<Object?>('routing.error', RouteArgs('404')),
            operation: CCNavigationOperation.go,
          );
        }),
        components: [
          routeComponent('orders', (registry) {
            registry.registerRoute(pathRoute(path: '/orders/:value'));
            registry.registerRoute(
              pathRoute(
                routeId: 'routing.error',
                path: '/routing-error/:value',
                deepLink: CCDeepLinkPolicy.enabled,
              ),
            );
          }),
        ],
      );
      runtime.initialize();

      await runtime.openRoute(
        Uri.parse('/orders/42?token=secret'),
        origin: CCNavigationOrigin.externalPlatform,
        mode: CCDeepLinkOpenMode.go,
        source: source,
      );

      expect(contexts, hasLength(1));
      expect(contexts.single.routeId, 'orders.detail');
      expect(contexts.single.initialRouteId, 'orders.detail');
      expect(contexts.single.stage, CCNavigationFailureStage.resolution);
      expect(
        contexts.single.reason,
        CCNavigationFailureReason.deepLinkRejected,
      );
      expect(contexts.single.errorType, 'CCDeepLinkRejectedError');
      expect(contexts.single.origin, CCNavigationOrigin.externalPlatform);
      expect(contexts.single.openMode, CCDeepLinkOpenMode.go);
      expect(contexts.single.source, same(source));
      expect(adapter.currentRequest?.routeId, 'routing.error');
      expect(
        adapter.currentRequest?.origin,
        CCNavigationOrigin.externalPlatform,
      );
      expect(runtime.recentNavigationFailures, hasLength(1));
      expect(runtime.recentNavigationFailures.single.recovered, isTrue);
      await runtime.dispose();
    },
  );

  test(
    'failure recovery inherits Push semantics instead of replacing top',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        deepLinkIngressPolicy: CCDeepLinkIngressPolicy(
          allowRelativePaths: true,
        ),
        navigationFailurePolicy: TestNavigationFailurePolicy(
          (_) => const CCNavigationFailureFallback.toIntent(
            TestIntent<Object?>('routing.error', RouteArgs('404')),
          ),
        ),
        components: [
          routeComponent('orders', (registry) {
            registry.registerRoute(pathRoute());
            registry.registerRoute(
              pathRoute(
                routeId: 'routing.error',
                path: '/routing-error/:value',
                deepLink: CCDeepLinkPolicy.enabled,
              ),
            );
          }),
        ],
      );
      runtime.initialize();
      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('1')),
      );
      final pending = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );

      await runtime.openRoute(Uri.parse('/missing'));

      expect(adapter.currentRequest?.operation, CCNavigationOperation.open);
      expect(adapter.currentRequest?.openMode, CCDeepLinkOpenMode.push);
      expect(runtime.activeRouteEntries.map((entry) => entry.routeId), [
        'orders.detail',
        'orders.detail',
        'routing.error',
      ]);
      runtime.popRoute();
      runtime.popRoute(result: 'preserved');
      expect(await pending, 'preserved');
      await runtime.dispose();
    },
  );

  test(
    'failure policy propagates unresolved routes and records one event',
    () async {
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        navigationFailurePolicy: TestNavigationFailurePolicy(
          (_) => const CCNavigationFailurePropagate(),
        ),
      );
      runtime.initialize();

      await expectLater(
        runtime.openRoute(Uri.parse('/missing/sensitive-value')),
        throwsA(isA<CCRouteNotFoundError>()),
      );

      final event = runtime.recentNavigationFailures.single;
      expect(event.context.routeId, isNull);
      expect(event.context.initialRouteId, isNull);
      expect(event.context.stage, CCNavigationFailureStage.resolution);
      expect(event.context.reason, CCNavigationFailureReason.routeNotFound);
      expect(event.context.errorType, 'CCRouteNotFoundError');
      expect(event.recovered, isFalse);
      await runtime.dispose();
    },
  );

  test(
    'failures are recorded without a recovery policy before request creation',
    () async {
      final observed = <CCNavigationFailureEvent>[];
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        navigationDiagnosticCapacity: 1,
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      runtime.initialize();
      final removeListener = runtime.addNavigationFailureListener(observed.add);

      await expectLater(
        runtime.openRoute(Uri.parse('/missing/private?token=secret')),
        throwsA(isA<CCRouteNotFoundError>()),
      );
      await expectLater(
        runtime.goRoute(
          const TestIntent<void>('orders.detail', RouteArgs('invalid')),
        ),
        throwsA(isA<CCRouteParameterError>()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(runtime.recentNavigationFailures, hasLength(1));
      expect(
        runtime.recentNavigationFailures.single.context.stage,
        CCNavigationFailureStage.parameters,
      );
      expect(observed, hasLength(2));
      expect(observed.map((event) => event.context.operation), [
        CCNavigationOperation.open,
        CCNavigationOperation.go,
      ]);
      expect(observed.map((event) => event.context.routeId), [
        null,
        'orders.detail',
      ]);
      expect(observed.map((event) => event.context.stage), [
        CCNavigationFailureStage.resolution,
        CCNavigationFailureStage.parameters,
      ]);
      expect(observed.map((event) => event.context.reason), [
        CCNavigationFailureReason.routeNotFound,
        CCNavigationFailureReason.invalidParameters,
      ]);
      expect(observed.map((event) => event.context.errorType), [
        'CCRouteNotFoundError',
        'CCRouteParameterError',
      ]);
      expect(observed.every((event) => !event.recovered), isTrue);

      removeListener();
      await runtime.dispose();
    },
  );

  test(
    'capability fallbacks are bounded sanitized asynchronous observations',
    () async {
      final observed = <CCNavigationCapabilityFallbackEvent>[];
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        navigationDiagnosticCapacity: 1,
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      runtime.initialize();
      final removeListener = runtime.addNavigationCapabilityFallbackListener(
        observed.add,
      );

      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('1')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        observed.single.capability,
        CCNavigationCapabilityType.backendVisibilityObservation,
      );
      observed.clear();

      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('42')),
      );

      expect(observed, isEmpty);
      expect(runtime.recentNavigationCapabilityFallbacks, hasLength(1));
      await Future<void>.delayed(Duration.zero);

      expect(observed, hasLength(2));
      expect(observed.map((event) => event.capability), [
        CCNavigationCapabilityType.managedPopObservation,
        CCNavigationCapabilityType.backendVisibilityObservation,
      ]);
      expect(observed.map((event) => event.behavior), [
        CCNavigationCapabilityFallbackBehavior.partitionLocalReconciliation,
        CCNavigationCapabilityFallbackBehavior.runtimeCommitVisibility,
      ]);
      expect(observed.map((event) => event.navigationId).toSet(), hasLength(1));
      expect(
        observed.every((event) => event.routeId == 'orders.detail'),
        isTrue,
      );
      expect(observed.every((event) => event.hostId == 'default'), isTrue);
      expect(
        observed.every((event) => event.navigatorOutlet == 'root'),
        isTrue,
      );
      expect(
        runtime.recentNavigationCapabilityFallbacks.single.capability,
        CCNavigationCapabilityType.backendVisibilityObservation,
      );

      removeListener();
      await runtime.dispose();
    },
  );

  test(
    'failure recovery is bounded and preserves one navigation identity',
    () async {
      final contexts = <CCNavigationFailureContext>[];
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        navigationFailurePolicy: TestNavigationFailurePolicy((context) {
          contexts.add(context);
          return CCNavigationFailureRedirect.toUri(
            Uri.parse('/still-missing/${context.recoveryDepth}'),
            operation: CCNavigationOperation.go,
          );
        }),
      );
      runtime.initialize();

      await expectLater(
        runtime.openRoute(Uri.parse('/missing')),
        throwsA(isA<CCNavigationFailureRecoveryLoopError>()),
      );

      expect(contexts.map((context) => context.recoveryDepth), [0, 1, 2, 3, 4]);
      expect(
        contexts.map((context) => context.navigationId).toSet(),
        hasLength(1),
      );
      expect(runtime.recentNavigationFailures, hasLength(5));
      expect(runtime.recentNavigationFailures.last.recovered, isFalse);
      expect(contexts.map((context) => context.reason), [
        CCNavigationFailureReason.routeNotFound,
        CCNavigationFailureReason.routeNotFound,
        CCNavigationFailureReason.routeNotFound,
        CCNavigationFailureReason.routeNotFound,
        CCNavigationFailureReason.recoveryLoop,
      ]);
      expect(
        contexts.map((context) => context.initialRouteId),
        everyElement(isNull),
      );
      await runtime.dispose();
    },
  );

  test(
    'failure events classify parameters, component state, and adapter errors',
    () async {
      final contexts = <CCNavigationFailureContext>[];
      final policy = TestNavigationFailurePolicy((context) {
        contexts.add(context);
        return const CCNavigationFailurePropagate();
      });
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        navigationFailurePolicy: policy,
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      runtime.initialize();

      await expectLater(
        runtime.goRoute(
          const TestIntent<void>('orders.detail', RouteArgs('invalid')),
        ),
        throwsA(isA<CCRouteParameterError>()),
      );
      runtime.deactivateComponent('orders');
      await expectLater(
        runtime.goRoute(
          const TestIntent<void>('orders.detail', RouteArgs('42')),
        ),
        throwsA(isA<CCRouteUnavailableError>()),
      );
      await runtime.dispose();

      final failingRuntime = CCRouterRuntime.forTesting(
        navigationAdapter: FailingNavigationAdapter(),
        navigationFailurePolicy: policy,
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      failingRuntime.initialize();
      await expectLater(
        failingRuntime.goRoute(
          const TestIntent<void>('orders.detail', RouteArgs('42')),
        ),
        throwsA(isA<CCNavigationAdapterError>()),
      );

      expect(contexts.map((context) => context.stage), [
        CCNavigationFailureStage.parameters,
        CCNavigationFailureStage.resolution,
        CCNavigationFailureStage.dispatch,
      ]);
      expect(contexts.map((context) => context.routeId), [
        'orders.detail',
        'orders.detail',
        'orders.detail',
      ]);
      expect(contexts.map((context) => context.initialRouteId), [
        'orders.detail',
        'orders.detail',
        'orders.detail',
      ]);
      expect(contexts.map((context) => context.reason), [
        CCNavigationFailureReason.invalidParameters,
        CCNavigationFailureReason.routeUnavailable,
        CCNavigationFailureReason.adapterFailed,
      ]);
      await failingRuntime.dispose();
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
      runtime.initialize();

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
        deepLinkIngressPolicy: CCDeepLinkIngressPolicy(
          allowRelativePaths: true,
        ),
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(
              pathRoute(deepLink: CCDeepLinkPolicy.enabled),
            ),
          ),
        ],
      );
      runtime.initialize();

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
      expect(adapter.stack.map((entry) => entry.uri.path), [
        '/orders/1',
        '/orders/3',
      ]);

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

      final pendingBeforeExternalOpen = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('6')),
      );
      var pendingCompleted = false;
      pendingBeforeExternalOpen.whenComplete(() => pendingCompleted = true);
      await runtime.openRoute(
        Uri.parse('/orders/7'),
        origin: CCNavigationOrigin.externalPlatform,
      );
      expect(pendingCompleted, isFalse);
      expect(adapter.stack, hasLength(3));
      expect(runtime.canPopRoute(), isTrue);
      expect(adapter.stack.map((entry) => entry.uri.path), [
        '/orders/5',
        '/orders/6',
        '/orders/7',
      ]);
      runtime.popRoute();
      runtime.popRoute(result: 'preserved');
      expect(await pendingBeforeExternalOpen, 'preserved');

      final displacedByGo = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('8')),
      );
      await runtime.openRoute(
        Uri.parse('/orders/9'),
        origin: CCNavigationOrigin.externalPlatform,
        mode: CCDeepLinkOpenMode.go,
      );
      expect(await displacedByGo, isNull);
      expect(adapter.stack.single.operation, CCNavigationOperation.open);
      expect(adapter.currentRequest?.openMode, CCDeepLinkOpenMode.go);
      expect(runtime.canPopRoute(), isFalse);
      expect(adapter.currentRequest?.uri.path, '/orders/9');
      await runtime.dispose();
    },
  );

  test(
    'Go preserves sibling Outlets while Reset clears the target Host',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          routeComponent('workspace', (registry) {
            registry.registerRoute(
              pathRoute(routeId: 'workspace.root', path: '/root/:value'),
            );
            registry.registerRoute(
              pathRoute(
                routeId: 'workspace.detail',
                path: '/detail/:value',
                placement: const CCRoutePlacement(navigatorOutlet: 'detail'),
              ),
            );
          }),
        ],
      );
      runtime.initialize();

      await runtime.goRoute(
        const TestIntent<void>('workspace.root', RouteArgs('1')),
      );
      final detail = runtime.pushRoute<String>(
        const TestIntent<String>('workspace.detail', RouteArgs('2')),
      );
      await runtime.goRoute(
        const TestIntent<void>('workspace.root', RouteArgs('3')),
      );

      expect(runtime.activeRouteEntries.map((entry) => entry.routeId), [
        'workspace.detail',
        'workspace.root',
      ]);
      expect(adapter.stack.map((entry) => entry.routeId), [
        'workspace.detail',
        'workspace.root',
      ]);

      await runtime.resetRoute(
        const TestIntent<void>('workspace.root', RouteArgs('4')),
      );
      expect(await detail, isNull);
      expect(runtime.activeRouteEntries.single.routeId, 'workspace.root');
      expect(adapter.stack.single.operation, CCNavigationOperation.reset);
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
      runtime.initialize();

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
      expect(handled.removedOwner, CCPopRemovedOwner.managed);
      expect(handled.trigger, CCPopTrigger.gesture);
      expect(await pushed, 'back');
      expect(runtime.activeRouteEntries, hasLength(1));
      expect(adapter.stack.map((entry) => entry.uri.path), ['/orders/1']);
      await runtime.dispose();
    },
  );

  test(
    'managed Pop guards run globally then locally and preserve the entry',
    () async {
      final calls = <String>[];
      final adapter = CCMemoryNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        globalPopGuards: [
          CCGlobalPopGuard(
            id: 'app.guard',
            guard: TestPopGuard('global', calls, (_) => const CCPopAllow()),
          ),
        ],
        components: [
          routeComponent('orders', (registry) {
            registry.registerRoutePopGuard(
              'orders.dirty',
              TestPopGuard(
                'local',
                calls,
                (_) => const CCPopDeny(code: 'unsaved_changes'),
              ),
            );
            registry.registerRoute(pathRoute(popGuardIds: ['orders.dirty']));
          }),
        ],
      );
      runtime.initialize();
      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('1')),
      );

      final outcome = await runtime.maybePopOutcomeRoute(
        trigger: CCPopTrigger.gesture,
      );

      expect(outcome.handled, isTrue);
      expect(outcome.removedOwner, CCPopRemovedOwner.none);
      expect(outcome.guardDeniedCode, 'unsaved_changes');
      expect(calls, [
        'global:orders.detail:gesture',
        'local:orders.detail:gesture',
      ]);
      expect(runtime.activeRouteEntries, hasLength(1));
      expect(adapter.stack, hasLength(1));
      await runtime.dispose();
    },
  );

  test('direct business Pop throws a stable guard denial', () async {
    final adapter = CCMemoryNavigationAdapter();
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      components: [
        routeComponent('orders', (registry) {
          registry.registerRoutePopGuard(
            'orders.locked',
            TestPopGuard(
              'local',
              <String>[],
              (_) => const CCPopDeny(code: 'flow_locked'),
            ),
          );
          registry.registerRoute(pathRoute(popGuardIds: ['orders.locked']));
        }),
      ],
    );
    runtime.initialize();
    await runtime.goRoute(
      const TestIntent<void>('orders.detail', RouteArgs('1')),
    );

    expect(
      () => runtime.popRoute(),
      throwsA(
        isA<CCPopGuardDeniedError>().having(
          (error) => error.code,
          'code',
          'flow_locked',
        ),
      ),
    );
    expect(runtime.activeRouteEntries, hasLength(1));
    await runtime.dispose();
  });

  test('foreign top entry bypasses managed Pop guards', () async {
    final calls = <String>[];
    final adapter = BackendEventNavigationAdapter();
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      globalPopGuards: [
        CCGlobalPopGuard(
          id: 'app.guard',
          guard: TestPopGuard(
            'global',
            calls,
            (_) => const CCPopDeny(code: 'should_not_run'),
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
    runtime.initialize();
    await runtime.goRoute(
      const TestIntent<void>('orders.detail', RouteArgs('1')),
    );
    adapter.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'foreign-popup',
      backendOperationId: 'foreign-popup-push',
      owner: CCBackendEntryOwner.foreign,
      sequence: 100,
    );
    adapter.consumeForeignMaybePop = true;

    final outcome = await runtime.maybePopOutcomeRoute();

    expect(outcome.handled, isTrue);
    expect(outcome.guardDeniedCode, isNull);
    expect(calls, isEmpty);
    expect(runtime.activeRouteEntries, hasLength(1));
    await runtime.dispose();
  });

  test(
    'managed Pop without Entry identity never removes Runtime top',
    () async {
      final adapter = UnidentifiedManagedPopAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      runtime.initialize();
      await runtime.goRoute(
        const TestIntent<void>('orders.detail', RouteArgs('1')),
      );

      final outcome = await runtime.maybePopOutcomeRoute();

      expect(outcome.handled, isTrue);
      expect(outcome.removedBackendEntryId, isNull);
      expect(runtime.activeRouteEntries, hasLength(1));
      expect(runtime.desynchronizedBackendHosts, {'window.main'});
      await runtime.dispose();
    },
  );

  test('Pop guards select only the active Host and Outlet partition', () async {
    final calls = <String>[];
    final adapter = BackendEventNavigationAdapter()..activePopOutlet = 'home';
    const homePlacement = CCRoutePlacement(
      shellId: 'tabs',
      navigatorOutlet: 'home',
    );
    const settingsPlacement = CCRoutePlacement(
      shellId: 'tabs',
      navigatorOutlet: 'settings',
    );
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      components: [
        routeComponent('shell', (registry) {
          registry.registerShell(
            CCShellDefinition(
              shellId: 'tabs',
              type: CCShellType.statefulBranches,
              outlets: const ['home', 'settings'],
              initialOutlet: 'home',
            ),
          );
          registry.registerRoutePopGuard(
            'shell.home',
            TestPopGuard(
              'home',
              calls,
              (_) => const CCPopDeny(code: 'home_blocked'),
            ),
          );
          registry.registerRoutePopGuard(
            'shell.settings',
            TestPopGuard('settings', calls, (_) => const CCPopAllow()),
          );
          registry.registerRoute(
            pathRoute(
              routeId: 'shell.home',
              path: '/home/:value',
              placement: homePlacement,
              popGuardIds: ['shell.home'],
            ),
          );
          registry.registerRoute(
            pathRoute(
              routeId: 'shell.settings',
              path: '/settings/:value',
              placement: settingsPlacement,
              popGuardIds: ['shell.settings'],
            ),
          );
        }),
      ],
    );
    runtime.initialize();

    await runtime.goRoute(const TestIntent<void>('shell.home', RouteArgs('1')));
    final home = runtime.activeRouteEntries.single;
    adapter.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'home-managed',
      navigationId: home.navigationId,
      routeId: home.routeId,
      owner: CCBackendEntryOwner.managed,
      sequence: 1,
      navigatorOutlet: 'home',
      shellId: 'tabs',
    );
    runtime.pushRoute<String>(
      const TestIntent<String>('shell.settings', RouteArgs('2')),
    );
    final settings = runtime.activeRouteEntries.last;
    adapter.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'settings-managed',
      navigationId: settings.navigationId,
      routeId: settings.routeId,
      owner: CCBackendEntryOwner.managed,
      sequence: 2,
      navigatorOutlet: 'settings',
      shellId: 'tabs',
    );

    final outcome = await runtime.maybePopOutcomeRoute();

    expect(outcome.guardDeniedCode, 'home_blocked');
    expect(outcome.hostId, 'default');
    expect(outcome.navigatorOutlet, 'home');
    expect(calls, ['home:shell.home:system']);
    expect(runtime.activeRouteEntries, hasLength(2));
    await runtime.dispose();
  });

  test('route Pop guards must be owned by the route component', () async {
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: CCMemoryNavigationAdapter(),
      components: [
        routeComponent(
          'auth',
          (registry) => registry.registerRoutePopGuard(
            'auth.guard',
            TestPopGuard('auth', <String>[], (_) => const CCPopAllow()),
          ),
        ),
        routeComponent(
          'orders',
          (registry) =>
              registry.registerRoute(pathRoute(popGuardIds: ['auth.guard'])),
        ),
      ],
    );

    expect(
      () => runtime.initialize(),
      throwsA(isA<CCRouteRegistrationError>()),
    );
    await runtime.dispose();
  });

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
    runtime.initialize();
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
      runtime.initialize();
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
    runtime.initialize();
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
    'rejectDuplicate terminates the rejected navigation observation',
    () async {
      final observed = <CCNavigationAspectEvent>[];
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        navigationConcurrencyPolicy:
            CCNavigationConcurrencyPolicy.rejectDuplicate,
        navigationAspects: [
          CCNavigationAspect(
            id: 'concurrency',
            onFound: observed.add,
            onLost: observed.add,
            onAfter: observed.add,
          ),
        ],
        components: [
          routeComponent(
            'orders',
            (registry) => registry.registerRoute(pathRoute()),
          ),
        ],
      );
      runtime.initialize();

      final first = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('2')),
      );
      await expectLater(
        runtime.pushRoute<String>(
          const TestIntent<String>('orders.detail', RouteArgs('2')),
        ),
        throwsA(isA<CCNavigationDuplicateError>()),
      );
      await Future<void>.delayed(Duration.zero);

      final failed = observed.where(
        (event) => event.errorType == 'CCNavigationDuplicateError',
      );
      expect(failed.map((event) => event.phase), [
        CCNavigationAspectPhase.lost,
        CCNavigationAspectPhase.after,
      ]);
      expect(
        failed.map((event) => event.request.navigationId).toSet(),
        hasLength(1),
      );

      runtime.popRoute(result: 'first');
      expect(await first, 'first');
      await runtime.dispose();
    },
  );

  test('singleFlight terminates the shared navigation observation', () async {
    final observed = <CCNavigationAspectEvent>[];
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: CCMemoryNavigationAdapter(),
      navigationConcurrencyPolicy: CCNavigationConcurrencyPolicy.singleFlight,
      navigationAspects: [
        CCNavigationAspect(
          id: 'concurrency',
          onFound: observed.add,
          onArrival: observed.add,
          onLost: observed.add,
          onAfter: observed.add,
        ),
      ],
      components: [
        routeComponent(
          'orders',
          (registry) => registry.registerRoute(pathRoute()),
        ),
      ],
    );
    runtime.initialize();

    final first = runtime.pushRoute<String>(
      const TestIntent<String>('orders.detail', RouteArgs('2')),
    );
    final second = runtime.pushRoute<String>(
      const TestIntent<String>('orders.detail', RouteArgs('2')),
    );
    runtime.popRoute(result: 'shared');
    expect(await first, 'shared');
    expect(await second, 'shared');
    await Future<void>.delayed(Duration.zero);

    final foundIds = observed
        .where((event) => event.phase == CCNavigationAspectPhase.found)
        .map((event) => event.request.navigationId)
        .toSet();
    final arrivalIds = observed
        .where((event) => event.phase == CCNavigationAspectPhase.arrival)
        .map((event) => event.request.navigationId)
        .toSet();
    final afterIds = observed
        .where((event) => event.phase == CCNavigationAspectPhase.after)
        .map((event) => event.request.navigationId)
        .toSet();
    expect(foundIds, hasLength(2));
    expect(arrivalIds, hasLength(1));
    expect(afterIds, foundIds);
    expect(
      observed.where((event) => event.phase == CCNavigationAspectPhase.lost),
      isEmpty,
    );
    await runtime.dispose();
  });

  test(
    'concurrency policies keep Extra-bearing navigations independent',
    () async {
      for (final policy in [
        CCNavigationConcurrencyPolicy.rejectDuplicate,
        CCNavigationConcurrencyPolicy.singleFlight,
      ]) {
        final adapter = CCMemoryNavigationAdapter();
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: adapter,
          navigationConcurrencyPolicy: policy,
          components: [
            routeComponent(
              'orders',
              (registry) => registry.registerRoute(pathRoute()),
            ),
          ],
        );
        runtime.initialize();

        final first = runtime.pushRoute<String>(
          TestIntent<String>(
            'orders.detail',
            RouteArgs('2', payload: Object()),
          ),
        );
        final second = runtime.pushRoute<String>(
          TestIntent<String>(
            'orders.detail',
            RouteArgs('2', payload: Object()),
          ),
        );
        expect(adapter.stack, hasLength(2), reason: policy.name);
        expect(runtime.activeRouteEntries, hasLength(2), reason: policy.name);

        runtime.popRoute(result: 'second');
        expect(await second, 'second', reason: policy.name);
        runtime.popRoute(result: 'first');
        expect(await first, 'first', reason: policy.name);
        await runtime.dispose();
      }
    },
  );

  test('interceptor callbacks cannot re-enter navigation', () async {
    late CCRouterRuntime runtime;
    late Future<void> reentry;
    late Future<void> reentryExpectation;
    var attempted = false;
    runtime = CCRouterRuntime.forTesting(
      navigationAdapter: CCMemoryNavigationAdapter(),
      globalInterceptors: [
        CCGlobalNavigationInterceptor(
          id: 'reentry',
          interceptor: TestNavigationInterceptor('reentry', (_) {
            if (!attempted) {
              attempted = true;
              reentry = runtime.goRoute(
                const TestIntent<void>('orders.detail', RouteArgs('43')),
              );
              reentryExpectation = expectLater(
                reentry,
                throwsA(isA<CCNavigationReentrancyError>()),
              );
            }
            return const CCNavigationProceed();
          }, []),
        ),
      ],
      components: [
        routeComponent(
          'orders',
          (registry) => registry.registerRoute(pathRoute()),
        ),
      ],
    );
    runtime.initialize();

    await runtime.goRoute(
      const TestIntent<void>('orders.detail', RouteArgs('42')),
    );
    await Future<void>.delayed(Duration.zero);
    await reentryExpectation;
    expect(runtime.activeRouteEntries.single.routeId, 'orders.detail');
    await runtime.dispose();
  });

  test('navigation listener tasks cannot re-enter navigation', () async {
    late CCRouterRuntime runtime;
    late Future<void> reentry;
    late Future<void> reentryExpectation;
    var attempted = false;
    runtime = CCRouterRuntime.forTesting(
      navigationAdapter: CCMemoryNavigationAdapter(),
      components: [
        routeComponent(
          'orders',
          (registry) => registry.registerRoute(pathRoute()),
        ),
      ],
    );
    runtime.initialize();
    runtime.addNavigationListener((event) {
      if (!attempted && event.phase == CCNavigationLifecyclePhase.requested) {
        attempted = true;
        reentry = Future<void>.microtask(
          () => runtime.goRoute(
            const TestIntent<void>('orders.detail', RouteArgs('43')),
          ),
        );
        reentryExpectation = expectLater(
          reentry,
          throwsA(isA<CCNavigationReentrancyError>()),
        );
      }
    });

    await runtime.goRoute(
      const TestIntent<void>('orders.detail', RouteArgs('42')),
    );
    await Future<void>.delayed(Duration.zero);
    await reentryExpectation;
    expect(runtime.activeRouteEntries.single.routeId, 'orders.detail');
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
      runtime.initialize();

      final pushed = runtime.pushRoute<String>(
        const TestIntent<String>('orders.detail', RouteArgs('42')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(runtime.pendingNavigations, hasLength(1));
      final pending = runtime.pendingNavigations.single;
      expect(pending.routeId, 'orders.detail');
      expect(pending.address.routePattern, '/orders/:value');
      expect(pending.address.hasPathParameters, isTrue);
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

  test('deferred dynamic Open preserves its selected stack behavior', () async {
    final adapter = CCMemoryNavigationAdapter();
    var authorized = false;
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: adapter,
      deepLinkIngressPolicy: CCDeepLinkIngressPolicy(allowRelativePaths: true),
      components: [
        routeComponent('orders', (registry) {
          registry.registerRouteInterceptor(
            'orders.auth',
            TestNavigationInterceptor('orders.auth', (_) {
              if (!authorized) return const CCNavigationDefer();
              return const CCNavigationProceed();
            }, []),
          );
          registry.registerRoute(
            pathRoute(routeId: 'home', path: '/home/:value'),
          );
          registry.registerRoute(
            pathRoute(
              deepLink: CCDeepLinkPolicy.enabled,
              interceptorIds: ['orders.auth'],
            ),
          );
        }),
      ],
    );
    runtime.initialize();
    await runtime.goRoute<void>(const TestIntent<void>('home', RouteArgs('1')));

    final opened = runtime.openRoute(
      Uri.parse('/orders/42'),
      origin: CCNavigationOrigin.externalNotification,
      mode: CCDeepLinkOpenMode.go,
    );
    await Future<void>.delayed(Duration.zero);
    final pending = runtime.pendingNavigations.single;
    expect(pending.openMode, CCDeepLinkOpenMode.go);
    expect(adapter.stack.single.routeId, 'home');

    authorized = true;
    await runtime.resumePendingNavigation(pending.navigationId);
    await opened;
    expect(adapter.stack, hasLength(1));
    expect(adapter.currentRequest?.routeId, 'orders.detail');
    expect(adapter.currentRequest?.openMode, CCDeepLinkOpenMode.go);
    expect(runtime.activeRouteEntries.single.routeId, 'orders.detail');
    await runtime.dispose();
  });

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
      runtime.initialize();
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
      runtime.initialize();
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
      await Future<void>.delayed(Duration.zero);
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
      timeoutRuntime.initialize();
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
      disposedRuntime.initialize();
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
    runtime.initialize();

    final result = runtime.pushRoute<String>(
      const TestIntent<String>('orders.detail', RouteArgs('42')),
    );
    runtime.popRoute(result: 42);
    await expectLater(result, throwsA(isA<CCRouteResultTypeError>()));
    expect(runtime.recentNavigationEvents.map((event) => event.phase), [
      CCNavigationLifecyclePhase.requested,
      CCNavigationLifecyclePhase.failed,
    ]);
    expect(runtime.activeRouteEntries, isEmpty);
    expect(
      runtime.recentNavigationFailures.single.context.stage,
      CCNavigationFailureStage.result,
    );
    expect(
      runtime.recentNavigationFailures.single.context.reason,
      CCNavigationFailureReason.resultTypeMismatch,
    );
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
    runtime.initialize();

    await expectLater(
      runtime.goRoute(const TestIntent<void>('orders.detail', RouteArgs('42'))),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    await runtime.dispose();
  });
}
