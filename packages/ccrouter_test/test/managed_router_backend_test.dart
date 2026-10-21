import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/material.dart';
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

Future<_Harness> _mount(WidgetTester tester) async {
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

void _ignoreResult(Future<Object?> result) {
  unawaited(result.then<void>((_) {}, onError: (_, _) {}));
}

void main() {
  tearDown(CCRouterHost.shutdown);

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
