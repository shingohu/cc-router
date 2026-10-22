import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Arguments {
  const _Arguments(this.id);

  final String id;
}

final class _Codec implements CCRouteCodec<_Arguments> {
  const _Codec();

  @override
  _Arguments decode(CCRouteCodecValues input) =>
      _Arguments(input.path['id'] ?? 'home');

  @override
  CCRouteCodecValues encode(_Arguments arguments) => arguments.id == 'home'
      ? CCRouteCodecValues()
      : CCRouteCodecValues(path: {'id': arguments.id});
}

final class _Intent implements CCRouteIntent<String> {
  const _Intent(this.id);

  final String id;

  @override
  String get routeId => id == 'home' ? 'managed.home' : 'managed.detail';

  @override
  Object get arguments => _Arguments(id);
}

CCRouteDefinition<_Arguments, String> _homeDefinition() => CCRouteDefinition(
  routeId: 'managed.home',
  patterns: [const CCPathPattern('/', primary: true)],
  codec: const _Codec(),
);

CCRouteDefinition<_Arguments, String> _detailDefinition() => CCRouteDefinition(
  routeId: 'managed.detail',
  patterns: [const CCPathPattern('/detail/:id', primary: true)],
  codec: const _Codec(),
);

final class _RouteResource implements CCDisposable {
  bool disposed = false;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class _Registrar implements CCComponentRegistrar {
  @override
  void register(CCRegistry registry) {
    registry.registerRoute(_homeDefinition());
    registry.registerRoute(_detailDefinition());
    registry.registerService<_RouteResource>(
      CCServiceProvider(
        scope: CCServiceScope.route,
        factory: (_) => _RouteResource(),
      ),
    );
  }
}

final class _TogglePopGuard implements CCPopGuard {
  bool allow = false;

  final List<CCPopTrigger> triggers = [];

  @override
  CCPopGuardDecision evaluate(CCPopGuardContext context) {
    triggers.add(context.trigger);
    return allow
        ? const CCPopAllow()
        : const CCPopDeny(code: 'managed_test_denied');
  }
}

final class _Harness {
  const _Harness({
    required this.backend,
    required this.contexts,
    required this.resources,
  });

  final CCManagedRouterBackend backend;
  final Map<String, BuildContext> contexts;
  final Map<String, _RouteResource> resources;

  CCRouteEntryHandle handle(String id) =>
      CCRouter.routeEntryHandleOf(contexts[id]!)!;
}

Future<_Harness> _mount(
  WidgetTester tester, {
  List<CCGlobalPopGuard> globalPopGuards = const [],
}) async {
  CCRouterHost.initialize(
    hostAssembly: CCHostAssembly.fromComponents(
      components: [
        CCComponentManifest(
          id: 'managed',
          version: '1.0.0',
          registrar: _Registrar(),
        ),
      ],
    ),
    globalPopGuards: globalPopGuards,
  );
  final contexts = <String, BuildContext>{};
  final resources = <String, _RouteResource>{};

  CCFlutterRouteDestination destination(
    CCRouteDefinition<_Arguments, String> definition,
  ) => CCFlutterRouteDestination.fromDefinition(
    definition: definition,
    builder: (values) => Builder(
      builder: (context) {
        final id = values.path['id'] ?? 'home';
        contexts[id] = context;
        resources[id] = CCRouter.routeService<_RouteResource>(context);
        return Text('managed-$id');
      },
    ),
  );

  final backend = CCManagedRouterBackend(
    routeCatalog: CCFlutterRouteCatalog(
      [destination(_homeDefinition()), destination(_detailDefinition())],
      componentVersions: const {'managed': '1.0.0'},
    ),
  );
  await tester.pumpWidget(
    CCRouterApp.managed(
      backend: backend,
      child: MaterialApp.router(routerConfig: backend.routerConfig),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(backend: backend, contexts: contexts, resources: resources);
}

Future<void> _mountConvenienceApp(
  WidgetTester tester, {
  ThemeData? theme,
}) async {
  final catalog = CCFlutterRouteCatalog(
    [
      CCFlutterRouteDestination.fromDefinition(
        definition: _homeDefinition(),
        builder: (_) => const Text('managed-convenience-home'),
      ),
      CCFlutterRouteDestination.fromDefinition(
        definition: _detailDefinition(),
        builder: (values) => Text('managed-convenience-${values.path['id']}'),
      ),
    ],
    componentVersions: const {'managed': '1.0.0'},
  );
  CCRouterHost.initialize(
    hostAssembly: CCHostAssembly.fromComponents(
      components: [
        CCComponentManifest(
          id: 'managed',
          version: '1.0.0',
          registrar: _Registrar(),
        ),
      ],
      routeCatalog: catalog,
    ),
  );
  await tester.pumpWidget(
    CCManagedRouterApp(
      initialLocation: '/detail/convenience',
      debugShowCheckedModeBanner: false,
      theme: theme,
    ),
  );
  await tester.pumpAndSettle();
}

void _ignoreResult(Future<Object?> result) {
  unawaited(result.then<void>((_) {}, onError: (_, _) {}));
}

Future<void> _predictiveBackEvent(WidgetTester tester, String method) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(
        method,
        method == 'startBackGesture'
            ? <String, Object>{
                'touchOffset': <double>[5, 300],
                'progress': 0.0,
                'swipeEdge': 0,
              }
            : null,
      ),
    ),
    (_) {},
  );
  await tester.pump();
}

void main() {
  tearDown(CCRouterHost.shutdown);

  testWidgets('Managed Router App requires an initialized Host', (
    tester,
  ) async {
    await tester.pumpWidget(const CCManagedRouterApp());

    expect(
      tester.takeException(),
      isA<FlutterError>().having(
        (error) => error.message,
        'message',
        contains('Call CCRouterHost.initialize'),
      ),
    );
  });

  testWidgets('Managed Router App builds a Backend from the Host Catalog', (
    tester,
  ) async {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    );
    await _mountConvenienceApp(tester, theme: theme);

    expect(find.text('managed-convenience-convenience'), findsOneWidget);
    expect(CCRouter.activeRouteEntries, hasLength(1));
    expect(CCRouter.activeRouteEntries.single.routeId, 'managed.detail');
    expect(
      Theme.of(
        tester.element(find.text('managed-convenience-convenience')),
      ).colorScheme.primary,
      theme.colorScheme.primary,
    );
  });

  testWidgets('initial location enters Runtime and renders a managed Page', (
    tester,
  ) async {
    final harness = await _mount(tester);

    expect(find.text('managed-home'), findsOneWidget);
    expect(CCRouter.activeRouteEntries, hasLength(1));
    expect(CCRouter.activeRouteEntries.single.routeId, 'managed.home');
    expect(
      harness.handle('home'),
      same(CCRouter.activeRouteEntries.single.handle),
    );
    expect(
      CCRouter.activeBackendEntries.single.owner,
      CCBackendEntryOwner.managed,
    );
  });

  testWidgets('push and Pop preserve the typed result exactly once', (
    tester,
  ) async {
    await _mount(tester);

    final result = CCRouter.navigator.push<String>(const _Intent('A'));
    await tester.pumpAndSettle();
    expect(find.text('managed-A'), findsOneWidget);

    CCRouter.navigator.pop(result: 'accepted');
    await tester.pumpAndSettle();
    expect(await result, 'accepted');
    expect(find.text('managed-home'), findsOneWidget);
    expect(CCRouter.activeRouteEntries, hasLength(1));
  });

  testWidgets('close removes a covered entry and leaves its covering page', (
    tester,
  ) async {
    final harness = await _mount(tester);
    final a = CCRouter.navigator.push<String>(const _Intent('A'));
    await tester.pumpAndSettle();
    final target = harness.handle('A');
    final b = CCRouter.navigator.push<String>(const _Intent('B'));
    await tester.pumpAndSettle();

    final outcome = await CCRouter.navigator.close(target, result: 'closed-A');
    await tester.pumpAndSettle();

    expect(outcome.status, CCRouteCloseStatus.closed);
    expect(await a, 'closed-A');
    expect(find.text('managed-A'), findsNothing);
    expect(find.text('managed-B'), findsOneWidget);
    expect(CCRouter.activeRouteEntries.map((entry) => entry.routeId), [
      'managed.home',
      'managed.detail',
    ]);

    CCRouter.navigator.pop(result: 'closed-B');
    await tester.pumpAndSettle();
    expect(await b, 'closed-B');
  });

  testWidgets('exact close does not consume a foreign PopupRoute', (
    tester,
  ) async {
    final harness = await _mount(tester);
    final result = CCRouter.navigator.push<String>(const _Intent('A'));
    await tester.pumpAndSettle();
    final target = harness.handle('A');
    final popup = showDialog<void>(
      context: harness.contexts['A']!,
      builder: (_) => const AlertDialog(content: Text('foreign-popup')),
    );
    await tester.pumpAndSettle();

    expect(
      (await CCRouter.navigator.close(target, result: 'under-popup')).status,
      CCRouteCloseStatus.closed,
    );
    await tester.pumpAndSettle();

    expect(await result, 'under-popup');
    expect(find.text('foreign-popup'), findsOneWidget);
    Navigator.of(tester.element(find.text('foreign-popup'))).pop();
    await popup;
    await tester.pumpAndSettle();
    expect(find.text('managed-home'), findsOneWidget);
  });

  testWidgets('Go replaces only after old Route Scope is released', (
    tester,
  ) async {
    final harness = await _mount(tester);
    final homeResource = harness.resources['home']!;

    await CCRouter.navigator.go(const _Intent('A'));
    await tester.pumpAndSettle();

    expect(find.text('managed-home'), findsNothing);
    expect(find.text('managed-A'), findsOneWidget);
    expect(homeResource.disposed, isTrue);
    expect(CCRouter.activeRouteEntries.single.routeId, 'managed.detail');
  });

  testWidgets(
    'Managed Stack preserves transaction semantics across operations',
    (tester) async {
      final harness = await _mount(tester);

      final first = CCRouter.navigator.push<String>(const _Intent('A'));
      await tester.pumpAndSettle();
      final second = CCRouter.navigator.push<String>(const _Intent('B'));
      await tester.pumpAndSettle();

      final replacement = CCRouter.navigator.replace<String>(
        const _Intent('C'),
      );
      await tester.pumpAndSettle();
      expect(await second, isNull);
      expect(CCRouter.activeRouteEntries.map((entry) => entry.routeId), [
        'managed.home',
        'managed.detail',
        'managed.detail',
      ]);

      await CCRouter.navigator.go(const _Intent('A'));
      await tester.pumpAndSettle();
      expect(await replacement, isNull);
      expect(CCRouter.activeRouteEntries.single.routeId, 'managed.detail');

      await CCRouter.navigator.reset(const _Intent('home'));
      await tester.pumpAndSettle();
      expect(await first, isNull);
      expect(CCRouter.activeRouteEntries.single.routeId, 'managed.home');

      await CCRouter.navigator.open(Uri.parse('/detail/opened'));
      await tester.pumpAndSettle();
      expect(
        harness.backend.adapter.requests.map((request) => request.uri.path),
        ['/', '/detail/opened'],
      );
    },
  );

  testWidgets('Host shutdown releases Managed Stack resources and results', (
    tester,
  ) async {
    final guard = _TogglePopGuard();
    final harness = await _mount(
      tester,
      globalPopGuards: [
        CCGlobalPopGuard(id: 'managed.shutdown.guard', guard: guard),
      ],
    );
    final pending = CCRouter.navigator.push<String>(const _Intent('A'));
    await tester.pumpAndSettle();
    final resource = harness.resources['A']!;
    final route = ModalRoute.of(tester.element(find.text('managed-A')))!;
    expect(route.popGestureEnabled, isFalse);
    final pendingError = expectLater(
      pending,
      throwsA(isA<CCNavigationAdapterError>()),
    );

    await CCRouterHost.shutdown();

    await pendingError;
    expect(resource.disposed, isTrue);
    expect(route.popDisposition, RoutePopDisposition.pop);
    expect(CCRouter.isInitialized, isFalse);
  });

  testWidgets('browser history configuration uses Runtime Go semantics', (
    tester,
  ) async {
    final harness = await _mount(tester);

    await harness.backend.routerConfig.routerDelegate.setNewRoutePath(
      CCManagedRouteConfiguration(
        uri: Uri.parse('/detail/history'),
        trustedHistory: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('managed-history'), findsOneWidget);
    expect(CCRouter.activeRouteEntries.single.routeId, 'managed.detail');
    expect(
      CCRouter.activeRouteEntries.single.address.routePattern,
      '/detail/:id',
    );
  });

  test('dispose fails pending result and rejects further work', () async {
    final catalog = CCFlutterRouteCatalog([
      CCFlutterRouteDestination.fromDefinition(
        definition: _detailDefinition(),
        builder: (_) => const SizedBox.shrink(),
      ),
    ]);
    final adapter = CCManagedNavigationAdapter(
      catalog: catalog,
      host: CCNavigationHost(),
    );
    adapter.initialize([catalog.destinations.single.route]);
    final pending = adapter.navigate(
      CCNavigationRequest(
        navigationId: 'pending',
        operation: CCNavigationOperation.push,
        routeId: 'managed.detail',
        uri: Uri.parse('/detail/pending'),
        arguments: const _Arguments('pending'),
        presentation: const CCPagePresentation(),
        origin: CCNavigationOrigin.internal,
        openMode: null,
      ),
    );
    _ignoreResult(pending);

    adapter.dispose();

    await expectLater(pending, throwsA(isA<CCNavigationAdapterError>()));
    expect(adapter.requests, isEmpty);
    expect(() => adapter.canPop(), throwsA(isA<CCNavigationAdapterError>()));
    adapter.dispose();
  });

  test(
    'native Managed MultiHost keeps child RouterConfig and stack ownership isolated',
    () {
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(
          components: [
            CCComponentManifest(
              id: 'managed',
              version: '1.0.0',
              registrar: _Registrar(),
            ),
          ],
        ),
      );
      final catalog = CCRouterHostBinding.routeCatalog;
      final backend = CCManagedMultiHostBackend.managed(
        defaultHostId: 'primary',
        hostFactories: {
          'primary': (config) => CCManagedRouterBackend(
            routeCatalog: config.catalog,
            host: CCNavigationHost(id: config.hostId),
          ),
          'secondary': (config) => CCManagedRouterBackend(
            routeCatalog: config.catalog,
            host: CCNavigationHost(id: config.hostId),
          ),
        },
      );

      expect(backend.hostIds, {'primary', 'secondary'});
      expect(identical(backend.routeCatalog, catalog), isTrue);
      expect(
        backend.routerConfigFor('primary'),
        isNot(same(backend.routerConfigFor('secondary'))),
      );
      expect(backend.hostFor('primary').id, 'primary');
      expect(backend.hostFor('secondary').id, 'secondary');
      expect(backend.adapter.activeHostId, 'primary');

      backend.navigationAdapter.dispose();
      return backend.dispose();
    },
  );

  test('native Managed MultiHost rolls back already-created children', () {
    CCRouterHost.initialize(
      hostAssembly: CCHostAssembly.fromComponents(
        components: [
          CCComponentManifest(
            id: 'managed',
            version: '1.0.0',
            registrar: _Registrar(),
          ),
        ],
      ),
    );
    final created = <CCManagedRouterBackend>[];
    expect(
      () => CCManagedMultiHostBackend.managed(
        defaultHostId: 'primary',
        hostFactories: {
          'primary': (config) {
            final backend = CCManagedRouterBackend(
              routeCatalog: config.catalog,
              host: CCNavigationHost(id: config.hostId),
            );
            created.add(backend);
            return backend;
          },
          'secondary': (config) {
            final backend = CCManagedRouterBackend(
              routeCatalog: config.catalog,
              host: CCNavigationHost(id: 'wrong-host'),
            );
            created.add(backend);
            return backend;
          },
        },
      ),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    expect(created, hasLength(2));
    for (final backend in created) {
      expect(
        () => backend.navigationAdapter.canPop(),
        throwsA(isA<CCNavigationAdapterError>()),
      );
    }
  });

  testWidgets('Managed predictive-back is opt-in and releases its bridge', (
    tester,
  ) async {
    final harness = await _mount(tester);
    final adapter = harness.backend.navigationAdapter;
    expect(adapter.predictiveBackBridge, isNull);
    expect(adapter.capabilities.supportsPredictiveBack, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await CCRouterHost.shutdown();
    final catalog = CCFlutterRouteCatalog(
      [
        CCFlutterRouteDestination.fromDefinition(
          definition: _homeDefinition(),
          builder: (_) => const Text('predictive-home'),
        ),
        CCFlutterRouteDestination.fromDefinition(
          definition: _detailDefinition(),
          builder: (_) => const Text('predictive-detail'),
        ),
      ],
      componentVersions: const {'managed': '1.0.0'},
    );
    CCRouterHost.initialize(
      hostAssembly: CCHostAssembly.fromComponents(
        components: [
          CCComponentManifest(
            id: 'managed',
            version: '1.0.0',
            registrar: _Registrar(),
          ),
        ],
        routeCatalog: catalog,
      ),
    );
    final predictive = CCManagedRouterBackend(
      routeCatalog: catalog,
      enablePredictiveBack: true,
    );
    await tester.pumpWidget(
      CCRouterApp.managed(
        key: const ValueKey('predictive-managed-app'),
        backend: predictive,
        child: MaterialApp.router(routerConfig: predictive.routerConfig),
      ),
    );
    await tester.pumpAndSettle();
    expect(predictive.adapter.predictiveBackBridge, isNotNull);
    expect(
      predictive.adapter.predictiveBackBridge,
      isA<CCPredictiveBackCoordinator>(),
    );
    expect(predictive.adapter.capabilities.supportsPredictiveBack, isTrue);
    final phases = <CCPredictiveBackPhase>[];
    final removeListener = predictive.adapter.predictiveBackBridge!
        .addPredictiveBackListener((event) => phases.add(event.phase));
    predictive.adapter.predictiveBackBridge!.started();
    predictive.adapter.predictiveBackBridge!.updated(.5);
    predictive.adapter.predictiveBackBridge!.cancelled(.5);
    removeListener();
    expect(phases, [
      CCPredictiveBackPhase.started,
      CCPredictiveBackPhase.updated,
      CCPredictiveBackPhase.cancelled,
    ]);
    await CCRouterHost.shutdown();
    expect(predictive.adapter.predictiveBackBridge!.isActive, isFalse);
  });

  testWidgets('Managed PopGuard retains non-interactive system fallback', (
    tester,
  ) async {
    final guard = _TogglePopGuard();
    _RouteResource? detailResource;
    final catalog = CCFlutterRouteCatalog(
      [
        CCFlutterRouteDestination.fromDefinition(
          definition: _homeDefinition(),
          builder: (_) => const Text('guarded-home'),
        ),
        CCFlutterRouteDestination.fromDefinition(
          definition: _detailDefinition(),
          builder: (_) => Builder(
            builder: (context) {
              detailResource ??= CCRouter.routeService<_RouteResource>(context);
              return const Text('guarded-detail');
            },
          ),
        ),
      ],
      componentVersions: const {'managed': '1.0.0'},
    );
    CCRouterHost.initialize(
      hostAssembly: CCHostAssembly.fromComponents(
        components: [
          CCComponentManifest(
            id: 'managed',
            version: '1.0.0',
            registrar: _Registrar(),
          ),
        ],
        routeCatalog: catalog,
      ),
      globalPopGuards: [
        CCGlobalPopGuard(id: 'managed.test.guard', guard: guard),
      ],
    );
    final backend = CCManagedRouterBackend(
      routeCatalog: catalog,
      enablePredictiveBack: true,
    );
    await tester.pumpWidget(
      CCRouterApp.managed(
        backend: backend,
        child: MaterialApp.router(routerConfig: backend.routerConfig),
      ),
    );
    await tester.pumpAndSettle();
    var completionCount = 0;
    final pending = CCRouter.navigator.push<String>(const _Intent('guarded'))
      ..then<void>((_) => completionCount += 1);
    await tester.pumpAndSettle();

    final phases = <CCPredictiveBackPhase>[];
    backend.adapter.predictiveBackBridge!.addPredictiveBackListener(
      (event) => phases.add(event.phase),
    );
    final route = ModalRoute.of(tester.element(find.text('guarded-detail')))!;
    expect(route.popGestureEnabled, isFalse);

    await _predictiveBackEvent(tester, 'startBackGesture');
    await _predictiveBackEvent(tester, 'commitBackGesture');
    await tester.pumpAndSettle();

    expect(find.text('guarded-detail'), findsOneWidget);
    expect(CCRouter.activeRouteEntries, hasLength(2));
    expect(phases, isEmpty);
    expect(guard.triggers, [CCPopTrigger.system]);
    expect(completionCount, 0);
    expect(detailResource?.disposed, isFalse);

    guard.allow = true;
    await _predictiveBackEvent(tester, 'startBackGesture');
    await _predictiveBackEvent(tester, 'commitBackGesture');
    await tester.pumpAndSettle();

    expect(find.text('guarded-detail'), findsNothing);
    expect(find.text('guarded-home'), findsOneWidget);
    expect(CCRouter.activeRouteEntries, hasLength(1));
    expect(phases, isEmpty);
    expect(guard.triggers, [CCPopTrigger.system, CCPopTrigger.system]);
    expect(await pending, isNull);
    expect(completionCount, 1);
    expect(detailResource?.disposed, isTrue);
  });

  test(
    'initialization fails closed for missing destinations and named Outlet',
    () {
      final catalog = CCFlutterRouteCatalog([
        CCFlutterRouteDestination.fromDefinition(
          definition: _detailDefinition(),
          builder: (_) => const SizedBox.shrink(),
        ),
      ]);
      final missing = CCManagedNavigationAdapter(
        catalog: catalog,
        host: CCNavigationHost(),
      );
      expect(
        () => missing.initialize([
          CCFlutterRouteDestination.fromDefinition(
            definition: _homeDefinition(),
            builder: (_) => const SizedBox.shrink(),
          ).route,
        ]),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      missing.dispose();

      final namedDefinition = CCRouteDefinition<_Arguments, String>(
        routeId: 'managed.named',
        patterns: [const CCPathPattern('/named/:id', primary: true)],
        codec: const _Codec(),
        placement: const CCRoutePlacement(
          shellId: 'managed.shell',
          navigatorOutlet: 'managed.outlet',
        ),
      );
      final namedCatalog = CCFlutterRouteCatalog([
        CCFlutterRouteDestination.fromDefinition(
          definition: namedDefinition,
          builder: (_) => const SizedBox.shrink(),
        ),
      ]);
      final named = CCManagedNavigationAdapter(
        catalog: namedCatalog,
        host: CCNavigationHost(
          navigatorKeys: {'managed.outlet': GlobalKey<NavigatorState>()},
        ),
      );
      expect(
        () => named.initialize(
          [namedCatalog.destinations.single.route],
          shells: [
            CCNavigationShell(
              shellId: 'managed.shell',
              type: CCShellType.singleNavigator,
              outlets: ['managed.outlet'],
              initialOutlet: 'managed.outlet',
            ),
          ],
        ),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      named.dispose();
    },
  );
}
