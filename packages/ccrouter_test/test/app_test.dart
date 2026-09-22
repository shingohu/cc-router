// ignore_for_file: deprecated_member_use

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _ContextRouteArgs {
  const _ContextRouteArgs(this.value);

  final String value;
}

final class _ContextRouteCodec implements CCRouteCodec<_ContextRouteArgs> {
  const _ContextRouteCodec();

  @override
  _ContextRouteArgs decode(CCEncodedRouteArguments input) =>
      _ContextRouteArgs(input.path['value']!);

  @override
  CCEncodedRouteArguments encode(_ContextRouteArgs arguments) =>
      CCEncodedRouteArguments(path: {'value': arguments.value});
}

final class _ContextRouteIntent implements CCRouteIntent<String> {
  const _ContextRouteIntent(this.value);

  final String value;

  @override
  String get routeId => 'context.detail';

  @override
  Object get arguments => _ContextRouteArgs(value);
}

final class _ContextRouteRegistrar implements CCComponentRegistrar {
  const _ContextRouteRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerRoute<_ContextRouteArgs, String>(
      CCRouteDefinition<_ContextRouteArgs, String>(
        routeId: 'context.detail',
        patterns: [const CCPathPattern('/context/:value', primary: true)],
        codec: const _ContextRouteCodec(),
      ),
    );
  }
}

void main() {
  tearDown(CCRouter.shutdown);

  test('navigation Host validates stable Host and Outlet identities', () {
    expect(() => CCNavigationHost(id: 'Host Main'), throwsArgumentError);
    expect(
      () => CCNavigationHost(
        navigatorKeys: {'Detail Pane': GlobalKey<NavigatorState>()},
      ),
      throwsArgumentError,
    );
    expect(
      CCNavigationHost(
        id: 'host.main-1',
        navigatorKeys: {'tab.settings': GlobalKey<NavigatorState>()},
      ).containsOutlet('tab.settings'),
      isTrue,
    );
  });

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

  testWidgets('Host resolves a call-site Context to its registered Outlet', (
    tester,
  ) async {
    final rootKey = GlobalKey<NavigatorState>();
    final detailKey = GlobalKey<NavigatorState>();
    final host = CCNavigationHost(
      navigatorKey: rootKey,
      navigatorKeys: {'detail': detailKey},
    );
    String? rootOutlet;
    String? detailOutlet;
    late BuildContext unboundContext;

    await tester.pumpWidget(
      CCRouterApp(
        host: host,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Navigator(
            key: rootKey,
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              pageBuilder: (context, _, _) => Builder(
                builder: (context) {
                  rootOutlet = host.resolveOutlet(context);
                  return Column(
                    children: [
                      SizedBox(
                        height: 20,
                        child: Navigator(
                          key: detailKey,
                          onGenerateRoute: (_) => PageRouteBuilder<void>(
                            pageBuilder: (_, _, _) => Builder(
                              builder: (context) {
                                detailOutlet = host.resolveOutlet(context);
                                return const SizedBox();
                              },
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 20,
                        child: Navigator(
                          onGenerateRoute: (_) => PageRouteBuilder<void>(
                            pageBuilder: (_, _, _) => Builder(
                              builder: (context) {
                                unboundContext = context;
                                return const SizedBox();
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(rootOutlet, 'root');
    expect(detailOutlet, 'detail');
    expect(
      () => host.resolveOutlet(unboundContext),
      throwsA(isA<CCNavigationOutletResolutionError>()),
    );
  });

  testWidgets('navigator Context targets the resolved Outlet', (tester) async {
    final rootKey = GlobalKey<NavigatorState>();
    final detailKey = GlobalKey<NavigatorState>();
    final host = CCNavigationHost(
      navigatorKey: rootKey,
      navigatorKeys: {'detail': detailKey},
    );
    final adapter = CCMemoryNavigationAdapter();
    CCRouter.initialize(
      components: const [
        CCComponentManifest(
          id: 'context-routing',
          version: '0.1.0',
          registrar: _ContextRouteRegistrar(),
        ),
      ],
    );
    CCRouterHostBinding.attachNavigationAdapter(adapter);
    late Future<String?> pending;

    await tester.pumpWidget(
      CCRouterApp(
        host: host,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Navigator(
            key: rootKey,
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              pageBuilder: (_, _, _) => SizedBox(
                height: 40,
                child: Navigator(
                  key: detailKey,
                  onGenerateRoute: (_) => PageRouteBuilder<void>(
                    pageBuilder: (_, _, _) => Builder(
                      builder: (context) {
                        pending = CCRouter.navigator.push(
                          const _ContextRouteIntent('42'),
                          context: context,
                        );
                        return const SizedBox();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(adapter.currentRequest?.placement.hostId, host.id);
    expect(adapter.currentRequest?.placement.navigatorOutlet, 'detail');
    adapter.pop(result: 'done');
    expect(await pending, 'done');
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
    final lifecycleStates = <AppLifecycleState>[];
    final host = CCNavigationHost(id: 'host.main');

    await tester.pumpWidget(
      CCRouterApp(
        host: host,
        onLifecycleChanged: lifecycleStates.add,
        child: const SizedBox(),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(lifecycleStates, [
      AppLifecycleState.paused,
      AppLifecycleState.resumed,
    ]);

    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(lifecycleStates, hasLength(2));
  });

  test('CCNavigationHost owns one immutable key per Outlet', () {
    final root = GlobalKey<NavigatorState>();
    final detail = GlobalKey<NavigatorState>();
    final host = CCNavigationHost(
      id: 'host.main',
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
    final host = CCNavigationHost(id: 'host.shared');

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
  });

  testWidgets('managed App attaches Backend without owning Runtime lifecycle', (
    tester,
  ) async {
    final backend = _TestAppBackend();
    var childBuilds = 0;
    CCRouter.initialize(components: backend.manifests);

    await tester.pumpWidget(
      CCRouterApp.managed(
        backend: backend,
        child: Builder(
          builder: (_) {
            childBuilds++;
            return const Text('ready', textDirection: TextDirection.ltr);
          },
        ),
      ),
    );
    await tester.pump();

    expect(CCRouter.isInitialized, isTrue);
    expect(find.text('ready'), findsOneWidget);
    expect(childBuilds, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(CCRouter.isInitialized, isTrue);
    expect(backend.disposed, isFalse);
    expect(backend.adapter.isInitialized, isTrue);

    await CCRouter.shutdown();
    expect(CCRouter.isInitialized, isFalse);
    expect(backend.disposed, isTrue);
    expect(backend.adapter.isInitialized, isFalse);
  });

  testWidgets('managed App reports missing explicit initialization safely', (
    tester,
  ) async {
    final backend = _TestAppBackend();

    await tester.pumpWidget(
      CCRouterApp.managed(
        backend: backend,
        child: const Text('must-not-build', textDirection: TextDirection.ltr),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isA<CCRouterNotInitializedError>());
    expect(find.text('Application failed to start.'), findsOneWidget);
    expect(find.text('must-not-build'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(backend.disposed, isTrue);
  });

  testWidgets('managed App rejects a generated component catalog drift', (
    tester,
  ) async {
    final backend = _TestAppBackend(
      manifests: const [
        CCComponentManifest(
          id: 'unexpected',
          version: '1.0.0',
          registrar: _EmptyRegistrar(),
        ),
      ],
    );
    CCRouter.initialize(components: const []);

    await tester.pumpWidget(
      CCRouterApp.managed(backend: backend, child: const SizedBox()),
    );
    await tester.pump();

    expect(tester.takeException(), isA<CCRegistrationError>());
    expect(find.text('Application failed to start.'), findsOneWidget);
    expect(CCRouter.isInitialized, isTrue);
    expect(backend.adapter.isInitialized, isFalse);
    expect(backend.disposed, isTrue);
  });

  testWidgets('compatibility App never owns an initialized Runtime', (
    tester,
  ) async {
    CCRouter.initialize(components: const []);
    expect(CCRouter.isInitialized, isTrue);

    await tester.pumpWidget(const CCRouterApp(child: SizedBox()));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(CCRouter.isInitialized, isTrue);
  });

  testWidgets('rejected managed App does not shut down attached Runtime', (
    tester,
  ) async {
    final activeBackend = _TestAppBackend(hostId: 'widget.active');
    final rejectedBackend = _TestAppBackend(hostId: 'widget.rejected');
    CCRouter.initialize(components: activeBackend.manifests);

    await tester.pumpWidget(
      CCRouterApp.managed(
        key: const ValueKey('active-backend'),
        backend: activeBackend,
        child: const SizedBox(),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      CCRouterApp.managed(
        key: const ValueKey('rejected-backend'),
        backend: rejectedBackend,
        child: const SizedBox(),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isA<CCNavigationAdapterError>());
    expect(CCRouter.isInitialized, isTrue);
    expect(activeBackend.disposed, isFalse);
    expect(rejectedBackend.disposed, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(CCRouter.isInitialized, isTrue);
  });
}

/// Test backend that records App-level disposal independently of its Adapter.
final class _TestAppBackend implements CCRouterAppBackend {
  /// Creates a backend with optional component [manifests].
  _TestAppBackend({
    Iterable<CCComponentManifest> manifests = const [],
    String hostId = 'test.managed',
  }) : manifests = List.unmodifiable(manifests),
       routeCatalog = CCFlutterRouteCatalog(
         const [],
         componentVersions: {
           for (final manifest in manifests) manifest.id: manifest.version,
         },
       ),
       host = CCNavigationHost(id: hostId);

  /// Component manifests installed explicitly by the test Host.
  final List<CCComponentManifest> manifests;

  @override
  /// Generated route catalog checked while the managed App attaches.
  final CCFlutterRouteCatalog routeCatalog;

  @override
  /// Navigation Host exposed to the widget tree.
  final CCNavigationHost host;

  /// In-memory Adapter whose lifecycle is owned by the Runtime.
  final CCMemoryNavigationAdapter adapter = CCMemoryNavigationAdapter();

  /// Whether App teardown released backend-owned resources.
  bool disposed = false;

  @override
  /// Adapter installed by managed Backend attachment.
  CCNavigationAdapter get navigationAdapter => adapter;

  @override
  /// Records release after Runtime disposal for ordering assertions.
  Future<void> dispose() async {
    expect(adapter.isInitialized, isFalse);
    disposed = true;
  }
}

/// No-op component Registrar used to create a mismatched generated catalog.
final class _EmptyRegistrar implements CCComponentRegistrar {
  /// Creates the no-op Registrar fixture.
  const _EmptyRegistrar();

  @override
  /// Registers no capabilities.
  void register(CCRegistry registry) {}
}
