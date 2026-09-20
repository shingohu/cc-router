import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Arguments {
  const _Arguments(this.value);

  final String value;
}

final class _ArgumentsCodec implements CCRouteCodec<_Arguments> {
  const _ArgumentsCodec();

  @override
  _Arguments decode(CCEncodedRouteArguments input) =>
      _Arguments(input.path['value']!);

  @override
  CCEncodedRouteArguments encode(_Arguments arguments) =>
      CCEncodedRouteArguments(path: {'value': arguments.value});
}

final class _Intent<R> implements CCRouteIntent<R> {
  const _Intent(this.routeId, this.arguments);

  @override
  final String routeId;

  @override
  final _Arguments arguments;
}

final class _Registrar implements CCComponentRegistrar {
  const _Registrar();

  @override
  void register(CCRegistry registry) {
    registry.registerRoute<_Arguments, String>(
      CCRouteDefinition<_Arguments, String>(
        routeId: 'shared.detail',
        patterns: [CCPathPattern('/shared/:value', primary: true)],
        codec: const _ArgumentsCodec(),
      ),
    );
    registry.registerRoute<_Arguments, String>(
      CCRouteDefinition<_Arguments, String>(
        routeId: 'secondary.detail',
        patterns: [CCPathPattern('/secondary/:value', primary: true)],
        codec: const _ArgumentsCodec(),
        placement: const CCRoutePlacement(hostId: 'window.secondary'),
      ),
    );
  }
}

final class _AdaptiveRegistrar implements CCComponentRegistrar {
  const _AdaptiveRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerRoute<_Arguments, String>(
      CCRouteDefinition<_Arguments, String>(
        routeId: 'workspace.list',
        patterns: [CCPathPattern('/list/:value', primary: true)],
        codec: const _ArgumentsCodec(),
        placement: const CCRoutePlacement(navigatorOutlet: 'list'),
      ),
    );
    registry.registerRoute<_Arguments, String>(
      CCRouteDefinition<_Arguments, String>(
        routeId: 'workspace.detail',
        patterns: [CCPathPattern('/detail/:value', primary: true)],
        codec: const _ArgumentsCodec(),
        placement: const CCRoutePlacement(navigatorOutlet: 'detail'),
      ),
    );
  }
}

final class _HostAdapter
    implements
        CCNavigationAdapter,
        CCNavigationAdapterHostBinding,
        CCNavigationAdapterCapabilitySource,
        CCNavigationPopCoordinator {
  _HostAdapter(this.hostId);

  @override
  final String hostId;

  final CCMemoryNavigationAdapter delegate = CCMemoryNavigationAdapter();

  final List<CCNavigationRequest> requests = [];

  List<String> initializedRouteIds = const [];

  bool disposed = false;

  @override
  CCNavigationAdapterCapabilities get capabilities => delegate.capabilities;

  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) {
    initializedRouteIds = routes.map((route) => route.routeId).toList();
    delegate.initialize(routes, shells: shells);
  }

  @override
  Future<Object?> navigate(CCNavigationRequest request) {
    requests.add(request);
    return delegate.navigate(request);
  }

  @override
  Future<bool> maybePop({Object? result}) => delegate.maybePop(result: result);

  @override
  Future<CCPopOutcome> maybePopOutcome({Object? result}) =>
      delegate.maybePopOutcome(result: result);

  @override
  void pop({Object? result}) => delegate.pop(result: result);

  @override
  CCPopOutcome popOutcome({Object? result}) =>
      delegate.popOutcome(result: result);

  @override
  bool canPop() => delegate.canPop();

  @override
  void dispose() {
    disposed = true;
    delegate.dispose();
  }
}

final class _FailingInitializeHostAdapter extends _HostAdapter {
  _FailingInitializeHostAdapter(super.hostId);

  int disposeCalls = 0;

  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) {
    throw const CCNavigationAdapterError('Synthetic initialization failure.');
  }

  @override
  void dispose() {
    disposeCalls++;
    super.dispose();
  }
}

final class _ThrowingDisposeHostAdapter extends _HostAdapter {
  _ThrowingDisposeHostAdapter(super.hostId);

  @override
  void dispose() {
    super.dispose();
    throw StateError('Synthetic disposal failure.');
  }
}

void main() {
  test(
    'routes and pops remain isolated across dynamically selected Hosts',
    () async {
      final primary = _HostAdapter('window.primary');
      final secondary = _HostAdapter('window.secondary');
      final registry = CCNavigationHostRegistry(
        defaultHostId: primary.hostId,
        adapters: {primary.hostId: primary, secondary.hostId: secondary},
      );
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: registry,
        components: const [
          CCComponentManifest(
            id: 'routes',
            version: '1.0.0',
            registrar: _Registrar(),
          ),
        ],
      );
      addTearDown(runtime.dispose);
      runtime.initialize();

      expect(primary.initializedRouteIds, ['shared.detail']);
      expect(secondary.initializedRouteIds, [
        'secondary.detail',
        'shared.detail',
      ]);

      await runtime.goRoute(
        const _Intent<void>('shared.detail', _Arguments('primary-root')),
      );
      expect(primary.requests.single.hostId, primary.hostId);

      registry.activateHost(secondary.hostId);
      await runtime.goRoute(
        const _Intent<void>('shared.detail', _Arguments('secondary-root')),
      );
      expect(secondary.requests.single.hostId, secondary.hostId);
      expect(runtime.activeRouteEntries, hasLength(2));
      expect(runtime.activeRouteEntries.map((entry) => entry.hostId), [
        primary.hostId,
        secondary.hostId,
      ]);

      registry.activateHost(primary.hostId);
      await runtime.goRoute(
        const _Intent<void>('secondary.detail', _Arguments('fixed-host')),
      );
      expect(secondary.requests.last.routeId, 'secondary.detail');
      expect(secondary.requests.last.hostId, secondary.hostId);
      expect(runtime.activeRouteEntries, hasLength(2));

      final primaryResult = runtime.pushRoute<String>(
        const _Intent<String>('shared.detail', _Arguments('primary-push')),
      );
      registry.activateHost(secondary.hostId);
      final secondaryResult = runtime.pushRoute<String>(
        const _Intent<String>('shared.detail', _Arguments('secondary-push')),
      );
      expect(runtime.activeRouteEntries, hasLength(4));

      runtime.popRoute(result: 'secondary-result');
      expect(await secondaryResult, 'secondary-result');
      expect(
        runtime.activeRouteEntries.where(
          (entry) => entry.hostId == secondary.hostId,
        ),
        hasLength(1),
      );
      expect(
        runtime.activeRouteEntries.where(
          (entry) => entry.hostId == primary.hostId,
        ),
        hasLength(2),
      );

      registry.activateHost(primary.hostId);
      runtime.popRoute(result: 'primary-result');
      expect(await primaryResult, 'primary-result');
    },
  );

  test('registers and unregisters a Host after initialization', () async {
    final primary = _HostAdapter('window.primary');
    final registry = CCNavigationHostRegistry(
      defaultHostId: primary.hostId,
      adapters: {primary.hostId: primary},
    );
    registry.initialize([
      CCNavigationRoute(
        routeId: 'shared.detail',
        patterns: [const CCPathPattern('/shared/:value', primary: true)],
        presentation: const CCPagePresentation(),
        deepLink: CCDeepLinkPolicy.disabled,
      ),
    ]);
    addTearDown(registry.dispose);

    final external = _HostAdapter('window.external');
    registry.registerHost(external.hostId, external);
    expect(registry.registeredHostIds, contains(external.hostId));
    expect(external.initializedRouteIds, ['shared.detail']);
    registry.activateHost(external.hostId);
    expect(registry.activeHostId, external.hostId);

    registry.unregisterHost(external.hostId);
    expect(external.disposed, isTrue);
    expect(registry.activeHostId, primary.hostId);
    expect(registry.registeredHostIds, {primary.hostId});
  });

  test(
    'failed synchronous Host registration is atomic and releases ownership',
    () {
      final primary = _HostAdapter('window.primary');
      final registry = CCNavigationHostRegistry(
        defaultHostId: primary.hostId,
        adapters: {primary.hostId: primary},
      );
      registry.initialize([
        CCNavigationRoute(
          routeId: 'shared.detail',
          patterns: [const CCPathPattern('/shared/:value', primary: true)],
          presentation: const CCPagePresentation(),
          deepLink: CCDeepLinkPolicy.disabled,
        ),
      ]);
      final failing = _FailingInitializeHostAdapter('window.failing');

      expect(
        () => registry.registerHost(failing.hostId, failing),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      expect(registry.registeredHostIds, isNot(contains(failing.hostId)));
      expect(failing.disposeCalls, 1);

      registry.dispose();
      registry.dispose();
      expect(primary.disposed, isTrue);
      expect(registry.registeredHostIds, isEmpty);
    },
  );

  test('registry releases every Host when one synchronous dispose fails', () {
    final failing = _ThrowingDisposeHostAdapter('window.failing');
    final healthy = _HostAdapter('window.healthy');
    final registry = CCNavigationHostRegistry(
      defaultHostId: failing.hostId,
      adapters: {failing.hostId: failing, healthy.hostId: healthy},
    );
    registry.initialize(const []);

    expect(() => registry.dispose(), throwsA(isA<StateError>()));
    expect(failing.disposed, isTrue);
    expect(healthy.disposed, isTrue);
    expect(registry.registeredHostIds, isEmpty);
  });

  test(
    'detaching a Host removes only its Entries and completes pending results',
    () async {
      final primary = _HostAdapter('window.primary');
      final secondary = _HostAdapter('window.secondary');
      final registry = CCNavigationHostRegistry(
        defaultHostId: primary.hostId,
        adapters: {primary.hostId: primary, secondary.hostId: secondary},
      );
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: registry,
        components: const [
          CCComponentManifest(
            id: 'routes',
            version: '1.0.0',
            registrar: _Registrar(),
          ),
        ],
      );
      addTearDown(runtime.dispose);
      runtime.initialize();

      await runtime.goRoute(
        const _Intent<void>('shared.detail', _Arguments('primary-root')),
      );
      registry.activateHost(secondary.hostId);
      await runtime.goRoute(
        const _Intent<void>('shared.detail', _Arguments('secondary-root')),
      );
      final secondaryResult = runtime.pushRoute<String>(
        const _Intent<String>('secondary.detail', _Arguments('pending')),
      );
      expect(runtime.activeRouteEntries, hasLength(3));

      registry.unregisterHost(secondary.hostId);

      expect(await secondaryResult, isNull);
      expect(secondary.disposed, isTrue);
      expect(registry.activeHostId, primary.hostId);
      expect(runtime.activeRouteEntries.map((entry) => entry.hostId), [
        primary.hostId,
      ]);
      expect(
        runtime.recentRouteEntryEvents
            .where((event) => event.entry.hostId == secondary.hostId)
            .where(
              (event) =>
                  event.entry.lifecycleState ==
                  CCRouteEntryLifecycleState.disposed,
            ),
        hasLength(2),
      );
      expect(
        runtime
            .backendEntriesFor(hostId: secondary.hostId)
            .every(
              (entry) =>
                  entry.lifecycleState == CCBackendEntryLifecycleState.removed,
            ),
        isTrue,
      );
    },
  );

  test('adaptive layout hides and restores retained Outlet stacks', () async {
    final primary = _HostAdapter('window.primary');
    final registry = CCNavigationHostRegistry(
      defaultHostId: primary.hostId,
      adapters: {primary.hostId: primary},
    );
    final runtime = CCRouterRuntime.forTesting(
      navigationAdapter: registry,
      components: const [
        CCComponentManifest(
          id: 'workspace',
          version: '1.0.0',
          registrar: _AdaptiveRegistrar(),
        ),
      ],
    );
    addTearDown(runtime.dispose);
    runtime.initialize();

    final listResult = runtime.pushRoute<String>(
      const _Intent<String>('workspace.list', _Arguments('all')),
    );
    final detailResult = runtime.pushRoute<String>(
      const _Intent<String>('workspace.detail', _Arguments('42')),
    );
    expect(runtime.activeRouteEntries.map((entry) => entry.lifecycleState), [
      CCRouteEntryLifecycleState.visible,
      CCRouteEntryLifecycleState.visible,
    ]);

    final outlets = CCAdaptiveOutletPolicy(
      primaryOutlet: 'list',
      secondaryOutlet: 'detail',
    );
    final compact = registry.updateWindowMetrics(
      CCWindowMetrics(
        hostId: primary.hostId,
        windowId: 'main',
        width: 500,
        height: 800,
      ),
      outletPolicy: outlets,
    );
    expect(compact.layout, CCAdaptiveLayoutKind.singlePane);
    expect(compact.activeOutlets, ['list']);
    expect(runtime.activeRouteEntries.map((entry) => entry.lifecycleState), [
      CCRouteEntryLifecycleState.visible,
      CCRouteEntryLifecycleState.hidden,
    ]);

    final expanded = registry.updateWindowMetrics(
      CCWindowMetrics(
        hostId: primary.hostId,
        windowId: 'main',
        width: 1200,
        height: 800,
      ),
      outletPolicy: outlets,
    );
    expect(expanded.layout, CCAdaptiveLayoutKind.splitPane);
    expect(runtime.activeRouteEntries.map((entry) => entry.lifecycleState), [
      CCRouteEntryLifecycleState.visible,
      CCRouteEntryLifecycleState.visible,
    ]);
    expect(runtime.activeRouteEntries, hasLength(2));
    await runtime.dispose();
    expect(await listResult, isNull);
    expect(await detailResult, isNull);
  });
}
