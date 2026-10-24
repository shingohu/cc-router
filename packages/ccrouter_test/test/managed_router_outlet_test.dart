import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Args {
  const _Args(this.value);

  final String value;
}

final class _Codec implements CCRouteCodec<_Args> {
  const _Codec();

  @override
  _Args decode(CCRouteCodecValues input) =>
      _Args(input.path['value'] ?? 'home');

  @override
  CCRouteCodecValues encode(_Args arguments) =>
      CCRouteCodecValues(path: {'value': arguments.value});
}

final class _Intent implements CCRouteIntent<String> {
  const _Intent(this.routeId, this.value);

  @override
  final String routeId;

  final String value;

  @override
  Object get arguments => _Args(value);
}

CCRouteDefinition<_Args, String> _route(
  String routeId,
  String path, {
  CCRoutePlacement placement = const CCRoutePlacement.root(),
}) => CCRouteDefinition(
  routeId: routeId,
  patterns: [CCPathPattern(path, primary: true)],
  codec: const _Codec(),
  placement: placement,
);

const _left = 'pane.left';
const _right = 'pane.right';
const _shellId = 'workspace.shell';
const _shellHome = 'workspace.home';
const _shellActivity = 'workspace.activity';

final class _OutletResource implements CCDisposable {
  int disposeCount = 0;
  @override
  void dispose() => disposeCount++;
}

final class _OutletRegistrar implements CCComponentRegistrar {
  const _OutletRegistrar({required this.includeShell});

  final bool includeShell;

  @override
  void register(CCRegistry registry) {
    registry.registerService<_OutletResource>(
      CCServiceProvider(
        scope: CCServiceScope.route,
        factory: (_) => _OutletResource(),
      ),
    );
    registry.registerRoute(_route('outlet.root', '/'));
    registry.registerRoute(
      _route(
        'outlet.left.seed',
        '/left/:value',
        placement: const CCRoutePlacement(navigatorOutlet: _left),
      ),
    );
    registry.registerRoute(
      _route(
        'outlet.right.seed',
        '/right/:value',
        placement: const CCRoutePlacement(navigatorOutlet: _right),
      ),
    );
    registry.registerRoute(_route('outlet.detail', '/detail/:value'));
    if (!includeShell) return;
    registry.registerShell(
      CCShellDefinition(
        shellId: _shellId,
        type: CCShellType.statefulBranches,
        outlets: const [_shellHome, _shellActivity],
        initialOutlet: _shellHome,
      ),
    );
    registry.registerRoute(
      _route(
        'shell.home',
        '/workspace/home/:value',
        placement: const CCRoutePlacement(
          shellId: _shellId,
          navigatorOutlet: _shellHome,
        ),
      ),
    );
    registry.registerRoute(
      _route(
        'shell.home.detail',
        '/workspace/home-detail/:value',
        placement: const CCRoutePlacement(
          shellId: _shellId,
          navigatorOutlet: _shellHome,
        ),
      ),
    );
    registry.registerRoute(
      _route(
        'shell.activity',
        '/workspace/activity/:value',
        placement: const CCRoutePlacement(
          shellId: _shellId,
          navigatorOutlet: _shellActivity,
        ),
      ),
    );
  }
}

void _ignore(Future<Object?> future) {
  unawaited(future.then<void>((_) {}, onError: (_, _) {}));
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
  test(
    'Managed Shells reject root and shared Outlet ownership before mount',
    () {
      for (final rootOutlet in [true, false]) {
        final adapter = CCManagedNavigationAdapter(
          catalog: CCFlutterRouteCatalog(const []),
          host: CCNavigationHost(
            id: 'default',
            navigatorKeys: {_left: GlobalKey<NavigatorState>()},
          ),
          shellBindings: [
            CCManagedShellBinding(
              shellId: 'first',
              builder: (_, _) => const SizedBox(),
            ),
            if (!rootOutlet)
              CCManagedShellBinding(
                shellId: 'second',
                builder: (_, _) => const SizedBox(),
              ),
          ],
        );
        addTearDown(adapter.dispose);
        expect(
          () => adapter.initialize(
            const [],
            shells: [
              CCNavigationShell(
                shellId: 'first',
                type: CCShellType.singleNavigator,
                outlets: [rootOutlet ? 'root' : _left],
                initialOutlet: rootOutlet ? 'root' : _left,
              ),
              if (!rootOutlet)
                CCNavigationShell(
                  shellId: 'second',
                  type: CCShellType.singleNavigator,
                  outlets: [_left],
                  initialOutlet: _left,
                ),
            ],
          ),
          throwsA(isA<CCNavigationAdapterError>()),
        );
      }
    },
  );

  tearDown(CCRouterHost.shutdown);

  testWidgets(
    'MultiHost layout remains authoritative across Managed navigation',
    (tester) async {
      const primary = 'window.primary';
      const secondary = 'window.secondary';
      final contexts = <String, BuildContext>{};
      final resources = <String, _OutletResource>{};
      final lifecycle = <String>[];
      final catalog = CCFlutterRouteCatalog(
        [
          for (final definition in [
            _route('outlet.root', '/'),
            _route(
              'outlet.left.seed',
              '/left/:value',
              placement: const CCRoutePlacement(navigatorOutlet: _left),
            ),
            _route(
              'outlet.right.seed',
              '/right/:value',
              placement: const CCRoutePlacement(navigatorOutlet: _right),
            ),
            _route('outlet.detail', '/detail/:value'),
          ])
            CCFlutterRouteDestination.fromDefinition(
              definition: definition,
              builder: (values) => Builder(
                builder: (context) {
                  final value = values.path['value'] ?? 'home';
                  contexts[value] = context;
                  resources[value] = CCRouter.routeService<_OutletResource>(
                    context,
                  );
                  return CCPageLifecycleListener(
                    onPageShow: () => lifecycle.add('$value:show'),
                    onPageHide: () => lifecycle.add('$value:hide'),
                    child: Text('layout-$value'),
                  );
                },
              ),
            ),
        ],
        componentVersions: const {'outlet': '1.0.0'},
      );
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(
          components: const [
            CCComponentManifest(
              id: 'outlet',
              version: '1.0.0',
              registrar: _OutletRegistrar(includeShell: false),
            ),
          ],
          routeCatalog: catalog,
        ),
      );
      final backend = CCManagedMultiHostBackend.managed(
        defaultHostId: primary,
        hostFactories: {
          for (final hostId in [primary, secondary])
            hostId: (config) => CCManagedRouterBackend(
              routeCatalog: config.catalog,
              host: CCNavigationHost(
                id: config.hostId,
                navigatorKeys: {
                  _left: GlobalKey<NavigatorState>(),
                  _right: GlobalKey<NavigatorState>(),
                },
              ),
              initializeFromRouteInformation: config.isDefaultHost,
            ),
        },
      );
      await tester.pumpWidget(
        CCRouterApp.managed(
          backend: backend,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                for (final hostId in [primary, secondary])
                  Expanded(
                    child: Builder(
                      builder: (_) {
                        final app = MaterialApp.router(
                          routerConfig: backend.backendFor(hostId).routerConfig,
                          builder: (_, root) => Row(
                            children: [
                              Expanded(child: root!),
                              for (final outlet in [_left, _right])
                                Expanded(
                                  child: CCManagedOutlet(
                                    backend: backend.backendFor(hostId),
                                    outlet: outlet,
                                  ),
                                ),
                            ],
                          ),
                        );
                        return hostId == primary
                            ? app
                            : CCRouterApp(
                                host: backend.hostFor(hostId),
                                child: app,
                              );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final results = <Future<String?>>[];
      var completed = 0;
      for (final hostId in [primary, secondary]) {
        backend.adapter.activateHost(hostId);
        for (final side in ['left', 'right']) {
          results.add(
            CCRouter.navigator
                .push<String>(_Intent('outlet.$side.seed', '$hostId-$side'))
                .then((value) {
                  completed++;
                  return value;
                }),
          );
          await tester.pumpAndSettle();
        }
        backend.adapter.setActiveOutlets(
          hostId: hostId,
          outlets: [_left, _right],
        );
      }
      await tester.pumpAndSettle();
      final before = CCRouter.activeRouteEntries;
      final rightResource = resources['$primary-right']!;
      final visible = [_left];
      backend.adapter.setActiveOutlets(hostId: primary, outlets: visible);
      visible.add(_right);
      await tester.pumpAndSettle();
      final child = backend.backendFor(primary).adapter;
      expect(child.visibleOutlets, {_left});
      expect(backend.adapter.activeHostId, secondary);
      expect(
        CCRouter.activeRouteEntries
            .firstWhere(
              (entry) =>
                  entry.hostId == primary &&
                  entry.placement.navigatorOutlet == _right,
            )
            .lifecycleState,
        CCRouteEntryLifecycleState.hidden,
      );

      expect(
        lifecycle.where((event) => event.startsWith('$primary-right:')).last,
        '$primary-right:hide',
      );
      final popup = DialogRoute<void>(
        context: contexts['$primary-left']!,
        builder: (_) => const Dialog(child: Text('layout-popup')),
      );
      final rootNavigator = backend.hostFor(primary).navigatorKey.currentState!;
      unawaited(rootNavigator.push(popup));
      await tester.pumpAndSettle();
      expect(child.visibleOutlets, {'root'});
      expect(
        lifecycle.where((event) => event.startsWith('$primary-left:')).last,
        '$primary-left:hide',
      );
      // A layout update while covered retains the selected set behind the popup.
      backend.adapter.setActiveOutlets(hostId: primary, outlets: [_left]);
      await tester.pumpAndSettle();
      expect(child.visibleOutlets, {'root'});
      rootNavigator.removeRoute(popup);
      await tester.pumpAndSettle();
      expect(child.visibleOutlets, {_left});
      expect(
        lifecycle.where((event) => event.startsWith('$primary-left:')).last,
        '$primary-left:show',
      );

      final hiddenResult = CCRouter.navigator.push<String>(
        const _Intent('outlet.detail', 'hidden-detail'),
        context: contexts['$primary-right'],
      );
      await tester.pumpAndSettle();
      expect(child.visibleOutlets, {_left});
      final hidden = CCRouter.activeRouteEntries.last;
      expect(hidden.hostId, primary);
      expect(hidden.lifecycleState, CCRouteEntryLifecycleState.hidden);
      expect(backend.backendFor(secondary).adapter.visibleOutlets, {
        _left,
        _right,
      });
      for (final invalid in <List<String>>[
        [],
        [_left, _left],
        [' '],
        ['missing'],
      ]) {
        expect(
          () => backend.adapter.setActiveOutlets(
            hostId: primary,
            outlets: invalid,
          ),
          throwsA(anyOf(isA<ArgumentError>(), isA<CCNavigationAdapterError>())),
        );
        expect(child.visibleOutlets, {_left});
      }
      expect(rightResource.disposeCount, 0);
      expect(completed, 0);
      backend.adapter.setActiveOutlets(
        hostId: primary,
        outlets: [_left, _right],
      );
      await tester.pumpAndSettle();
      expect(
        CCRouter.activeRouteEntries.last.lifecycleState,
        CCRouteEntryLifecycleState.visible,
      );
      expect(
        CCRouter.activeRouteEntries
            .take(before.length)
            .map((entry) => entry.routeEntryId),
        before.map((entry) => entry.routeEntryId),
      );
      expect(resources['$primary-right'], same(rightResource));
      CCRouter.navigator.pop(
        context: contexts['hidden-detail'],
        result: 'hidden-done',
      );
      await tester.pumpAndSettle();
      expect(await hiddenResult, 'hidden-done');
      expect(resources['hidden-detail']!.disposeCount, 1);
      expect(rightResource.disposeCount, 0);
      expect(tester.takeException(), isNull);
      final pendingErrors = [
        for (final result in results)
          expectLater(result, throwsA(isA<CCNavigationAdapterError>())),
      ];
      await CCRouterHost.shutdown();
      await Future.wait(pendingErrors);
      expect(completed, 0);
      expect(rightResource.disposeCount, 1);
    },
  );

  testWidgets(
    'context routes identical Intent to the exact left or right Outlet',
    (tester) async {
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(
          components: const [
            CCComponentManifest(
              id: 'outlet',
              version: '1.0.0',
              registrar: _OutletRegistrar(includeShell: false),
            ),
          ],
        ),
      );
      final routes = [
        _route('outlet.root', '/'),
        _route(
          'outlet.left.seed',
          '/left/:value',
          placement: const CCRoutePlacement(navigatorOutlet: _left),
        ),
        _route(
          'outlet.right.seed',
          '/right/:value',
          placement: const CCRoutePlacement(navigatorOutlet: _right),
        ),
        _route('outlet.detail', '/detail/:value'),
      ];
      final backend = CCManagedRouterBackend(
        host: CCNavigationHost(
          navigatorKeys: {
            _left: GlobalKey<NavigatorState>(),
            _right: GlobalKey<NavigatorState>(),
          },
        ),
        routeCatalog: CCFlutterRouteCatalog(
          [
            for (final definition in routes)
              CCFlutterRouteDestination.fromDefinition(
                definition: definition,
                builder: (values) => Builder(
                  builder: (context) {
                    final value = values.path['value'] ?? 'home';
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('page-$value'),
                        if (value == 'left' || value == 'right')
                          ElevatedButton(
                            key: ValueKey<String>('open-$value'),
                            onPressed: () => _ignore(
                              CCRouter.navigator.push<String>(
                                _Intent('outlet.detail', '$value-detail'),
                                context: context,
                              ),
                            ),
                            child: Text('open-$value'),
                          ),
                      ],
                    );
                  },
                ),
              ),
          ],
          componentVersions: const {'outlet': '1.0.0'},
        ),
      );
      await tester.pumpWidget(
        CCRouterApp.managed(
          backend: backend,
          child: MaterialApp.router(
            routerConfig: backend.routerConfig,
            builder: (context, root) => Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  Expanded(child: root ?? const SizedBox.shrink()),
                  Expanded(
                    child: CCManagedOutlet(backend: backend, outlet: _left),
                  ),
                  Expanded(
                    child: CCManagedOutlet(backend: backend, outlet: _right),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      _ignore(
        CCRouter.navigator.push<String>(
          const _Intent('outlet.left.seed', 'left'),
        ),
      );
      _ignore(
        CCRouter.navigator.push<String>(
          const _Intent('outlet.right.seed', 'right'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('open-right')));
      await tester.pumpAndSettle();

      expect(find.text('page-right-detail'), findsOneWidget);
      expect(find.text('page-left'), findsOneWidget);
      expect(
        backend.routerConfig.routerDelegate.currentConfiguration!.uri.path,
        '/detail/right-detail',
      );
      expect(
        backend.adapter.requests
            .where((request) => request.uri.path == '/detail/right-detail')
            .single
            .placement
            .navigatorOutlet,
        _right,
      );

      await tester.tap(find.byKey(const ValueKey<String>('open-left')));
      await tester.pumpAndSettle();
      expect(find.text('page-left-detail'), findsOneWidget);
      expect(
        backend.routerConfig.routerDelegate.currentConfiguration!.uri.path,
        '/detail/left-detail',
      );
      expect(
        backend.adapter.requests
            .where((request) => request.uri.path == '/detail/left-detail')
            .single
            .placement
            .navigatorOutlet,
        _left,
      );
      expect(backend.adapter.visibleOutlets, containsAll({_left, _right}));
    },
  );

  testWidgets('managed pages follow top route lifecycle changes', (
    tester,
  ) async {
    CCRouterHost.initialize(
      hostAssembly: CCHostAssembly.fromComponents(
        components: const [
          CCComponentManifest(
            id: 'outlet',
            version: '1.0.0',
            registrar: _OutletRegistrar(includeShell: false),
          ),
        ],
      ),
    );
    final definitions = [
      _route('outlet.root', '/'),
      _route(
        'outlet.left.seed',
        '/left/:value',
        placement: const CCRoutePlacement(navigatorOutlet: _left),
      ),
      _route(
        'outlet.right.seed',
        '/right/:value',
        placement: const CCRoutePlacement(navigatorOutlet: _right),
      ),
      _route('outlet.detail', '/detail/:value'),
    ];
    final lifecycleEvents = <String>[];
    final backend = CCManagedRouterBackend(
      host: CCNavigationHost(
        navigatorKeys: {
          _left: GlobalKey<NavigatorState>(),
          _right: GlobalKey<NavigatorState>(),
        },
      ),
      routeCatalog: CCFlutterRouteCatalog(
        [
          for (final definition in definitions)
            CCFlutterRouteDestination.fromDefinition(
              definition: definition,
              builder: (values) {
                final value = values.path['value'] ?? 'home';
                return CCPageLifecycleListener(
                  onPageShow: () => lifecycleEvents.add('$value:show'),
                  onPageHide: () => lifecycleEvents.add('$value:hide'),
                  child: Material(child: Text('lifecycle-$value')),
                );
              },
            ),
        ],
        componentVersions: const {'outlet': '1.0.0'},
      ),
    );
    await tester.pumpWidget(
      CCRouterApp.managed(
        backend: backend,
        child: MaterialApp.router(routerConfig: backend.routerConfig),
      ),
    );
    await tester.pumpAndSettle();
    expect(lifecycleEvents, ['home:show']);

    _ignore(
      CCRouter.navigator.push<String>(const _Intent('outlet.detail', 'detail')),
    );
    await tester.pumpAndSettle();
    expect(lifecycleEvents, ['home:show', 'home:hide', 'detail:show']);

    CCRouter.navigator.pop();
    await tester.pumpAndSettle();
    expect(lifecycleEvents, [
      'home:show',
      'home:hide',
      'detail:show',
      'detail:hide',
      'home:show',
    ]);
  });

  testWidgets(
    'stateful Shell preserves branches and closes inactive identity',
    (tester) async {
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(
          components: const [
            CCComponentManifest(
              id: 'outlet',
              version: '1.0.0',
              registrar: _OutletRegistrar(includeShell: true),
            ),
          ],
        ),
      );
      final definitions = [
        _route('outlet.root', '/'),
        _route(
          'outlet.left.seed',
          '/left/:value',
          placement: const CCRoutePlacement(navigatorOutlet: _left),
        ),
        _route(
          'outlet.right.seed',
          '/right/:value',
          placement: const CCRoutePlacement(navigatorOutlet: _right),
        ),
        _route('outlet.detail', '/detail/:value'),
        _route(
          'shell.home',
          '/workspace/home/:value',
          placement: const CCRoutePlacement(
            shellId: _shellId,
            navigatorOutlet: _shellHome,
          ),
        ),
        _route(
          'shell.home.detail',
          '/workspace/home-detail/:value',
          placement: const CCRoutePlacement(
            shellId: _shellId,
            navigatorOutlet: _shellHome,
          ),
        ),
        _route(
          'shell.activity',
          '/workspace/activity/:value',
          placement: const CCRoutePlacement(
            shellId: _shellId,
            navigatorOutlet: _shellActivity,
          ),
        ),
      ];
      final handles = <String, CCRouteEntryHandle>{};
      final resources = <String, _OutletResource>{};
      final lifecycleEvents = <String>[];
      CCManagedShellScope? shellScope;
      final backend = CCManagedRouterBackend(
        host: CCNavigationHost(
          navigatorKeys: {
            _left: GlobalKey<NavigatorState>(),
            _right: GlobalKey<NavigatorState>(),
            _shellHome: GlobalKey<NavigatorState>(),
            _shellActivity: GlobalKey<NavigatorState>(),
          },
        ),
        shellBindings: [
          CCManagedShellBinding(
            shellId: _shellId,
            builder: (context, shell) {
              shellScope = shell;
              return Material(
                child: Column(
                  children: [
                    Row(
                      children: [
                        TextButton(
                          key: const ValueKey<String>('tab-home'),
                          onPressed: () => shell.activateOutlet(_shellHome),
                          child: const Text('Home'),
                        ),
                        TextButton(
                          key: const ValueKey<String>('tab-activity'),
                          onPressed: () => shell.activateOutlet(_shellActivity),
                          child: const Text('Activity'),
                        ),
                      ],
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: shell.outlets.indexOf(shell.activeOutlet),
                        children: [
                          for (final outlet in shell.outlets)
                            shell.navigatorFor(outlet),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        initialLocation: '/workspace/home/home',
        enablePredictiveBack: true,
        routeCatalog: CCFlutterRouteCatalog(
          [
            for (final definition in definitions)
              CCFlutterRouteDestination.fromDefinition(
                definition: definition,
                builder: (values) => Builder(
                  builder: (context) {
                    final value = values.path['value'] ?? 'root';
                    resources[value] = CCRouter.routeService<_OutletResource>(
                      context,
                    );
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final handle = CCRouter.routeEntryHandleOf(context);
                      if (handle != null) handles[value] = handle;
                    });
                    return CCPageLifecycleListener(
                      onPageShow: () => lifecycleEvents.add('$value:show'),
                      onPageHide: () => lifecycleEvents.add('$value:hide'),
                      child: Material(
                        child: Center(child: Text('shell-$value')),
                      ),
                    );
                  },
                ),
              ),
          ],
          componentVersions: const {'outlet': '1.0.0'},
        ),
      );
      await tester.pumpWidget(
        CCRouterApp.managed(
          backend: backend,
          child: MaterialApp.router(routerConfig: backend.routerConfig),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('shell-home'), findsOneWidget);
      expect(shellScope!.hasEntries(_shellHome), isTrue);
      expect(shellScope!.hasEntries(_shellActivity), isFalse);
      expect(
        () => shellScope!.hasEntries('workspace.unknown'),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      expect(lifecycleEvents, contains('home:show'));
      _ignore(
        CCRouter.navigator.push<String>(
          const _Intent('shell.home.detail', 'home-detail'),
        ),
      );
      await tester.pumpAndSettle();
      final entryCountBeforePopup = CCRouter.activeRouteEntries.length;
      _ignore(
        CCRouter.navigator.push<String>(
          const _Intent('outlet.detail', 'root-cover'),
        ),
      );
      await tester.pumpAndSettle();
      CCRouter.navigator.pop();
      expect(
        backend.adapter.predictiveBackBridge!.activePredictiveBackOutlet,
        _shellHome,
      );
      await tester.pumpAndSettle();
      final popup = showDialog<void>(
        context: tester.element(find.text('shell-home-detail')),
        builder: (_) => const AlertDialog(content: Text('root-popup')),
      );
      await tester.pumpAndSettle();
      expect(find.text('root-popup'), findsOneWidget);

      expect(await CCRouter.navigator.maybePop(), isTrue);
      await tester.pumpAndSettle();
      await popup;
      expect(find.text('root-popup'), findsNothing);
      expect(find.text('shell-home-detail'), findsOneWidget);
      expect(CCRouter.activeRouteEntries, hasLength(entryCountBeforePopup));

      final predictivePhases = <CCPredictiveBackPhase>[];
      final removePredictiveListener = backend.adapter.predictiveBackBridge!
          .addPredictiveBackListener(
            (event) => predictivePhases.add(event.phase),
          );
      await _predictiveBackEvent(tester, 'startBackGesture');
      final transientPopup = showDialog<void>(
        context: tester.element(find.text('shell-home-detail')),
        builder: (_) =>
            const AlertDialog(content: Text('transient-root-popup')),
      );
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('transient-root-popup'))).pop();
      await tester.pumpAndSettle();
      await transientPopup;
      await _predictiveBackEvent(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('shell-home-detail'), findsOneWidget);
      expect(CCRouter.activeRouteEntries, hasLength(entryCountBeforePopup));
      expect(predictivePhases, [
        CCPredictiveBackPhase.started,
        CCPredictiveBackPhase.cancelled,
      ]);
      removePredictiveListener();

      _ignore(
        CCRouter.navigator.push<String>(
          const _Intent('shell.activity', 'activity'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('shell-activity'), findsOneWidget);
      expect(shellScope!.hasEntries(_shellActivity), isTrue);
      expect(
        lifecycleEvents.where((event) => event.startsWith('home-detail:')).last,
        'home-detail:hide',
      );
      expect(
        lifecycleEvents.where((event) => event.startsWith('activity:')).last,
        'activity:show',
      );
      await tester.tap(find.byKey(const ValueKey<String>('tab-home')));
      await tester.pumpAndSettle();
      expect(find.text('shell-home-detail'), findsOneWidget);
      expect(backend.adapter.focusedOutlet, _shellHome);
      expect(
        lifecycleEvents.where((event) => event.startsWith('activity:')).last,
        'activity:hide',
      );
      expect(
        lifecycleEvents.where((event) => event.startsWith('home-detail:')).last,
        'home-detail:show',
      );

      backend.adapter.updateVisibleOutlets([_shellHome, _shellActivity]);
      await tester.pumpAndSettle();
      final eventCount = CCRouter.recentRouteVisibilityEvents.length;
      shellScope!.activateOutlet(_shellActivity);
      await tester.pumpAndSettle();
      expect(backend.adapter.visibleOutlets, {_shellHome, _shellActivity});
      expect(
        CCRouter.recentRouteVisibilityEvents
            .skip(eventCount)
            .where(
              (event) =>
                  event.entry.routeEntryId ==
                      handles['home-detail']?.routeEntryId &&
                  event.phase == CCRouteVisibilityPhase.didHide,
            ),
        isEmpty,
      );
      shellScope!.activateOutlet(_shellHome);
      backend.adapter.updateVisibleOutlets([_shellHome]);
      await tester.pumpAndSettle();

      expect(
        (await CCRouter.navigator.close(handles['activity']!)).status,
        CCRouteCloseStatus.closed,
      );
      await tester.pumpAndSettle();
      expect(find.text('shell-home-detail'), findsOneWidget);
      expect(
        CCRouter.activeRouteEntries
            .where((entry) => entry.placement.shellId == _shellId)
            .map((entry) => entry.address.routePattern),
        ['/workspace/home/:value', '/workspace/home-detail/:value'],
      );

      await CCRouter.navigator.close(handles['home-detail']!);
      await tester.pumpAndSettle();
      final homeContext = tester.element(find.text('shell-home'));
      final scoped = CCRouter.navigatorOf(homeContext);
      final scopedResult = scoped.push<String>(
        const _Intent('outlet.detail', 'scoped-child'),
      );
      await tester.pumpAndSettle();
      expect(find.text('shell-scoped-child'), findsOneWidget);
      expect(
        CCRouter.activeRouteEntries.last.placement.navigatorOutlet,
        _shellHome,
      );
      scoped.pop(result: 'scoped-done');
      await tester.pumpAndSettle();
      expect(await scopedResult, 'scoped-done');
      expect(resources['scoped-child']!.disposeCount, 1);
      final childResult = CCRouter.navigator.push<String>(
        const _Intent('outlet.detail', 'context-child'),
        context: homeContext,
      );
      String? returnedResult;
      unawaited(childResult.then<void>((value) => returnedResult = value));
      await tester.pumpAndSettle();
      final childHandle = handles['context-child'];
      expect(resources['home']!.disposeCount, 0);
      expect(
        (await CCRouter.navigator.close(handles['home']!)).status,
        CCRouteCloseStatus.closed,
      );
      await tester.pumpAndSettle();
      expect(find.text('shell-context-child'), findsOneWidget);
      expect(
        CCRouter.routeEntryHandleOf(
          tester.element(find.text('shell-context-child')),
        ),
        same(childHandle),
      );
      expect(resources['home']!.disposeCount, 1);
      expect(resources['context-child']!.disposeCount, 0);
      expect(returnedResult, isNull);
      expect(shellScope!.hasEntries(_shellHome), isTrue);
      final childContext = tester.element(find.text('shell-context-child'));
      final localNavigator = backend.host
          .navigatorKeyFor(_shellHome)
          .currentState!;
      final rootNavigator = backend.host.navigatorKey.currentState!;
      final localPopup = DialogRoute<void>(
        context: childContext,
        builder: (_) => const Dialog(child: Text('last-shell-local-popup')),
      );
      final rootPopup = DialogRoute<void>(
        context: childContext,
        builder: (_) => const Dialog(child: Text('last-shell-root-popup')),
      );
      unawaited(localNavigator.push(localPopup));
      await tester.pumpAndSettle();
      unawaited(rootNavigator.push(rootPopup));
      await tester.pumpAndSettle();
      await CCRouter.navigator.close(childHandle!, result: 'child-done');
      await tester.pumpAndSettle();
      expect(returnedResult, 'child-done');
      expect(resources['context-child']!.disposeCount, 1);
      expect(
        find.text('shell-context-child', skipOffstage: false),
        findsNothing,
      );
      expect(find.text('last-shell-root-popup'), findsOneWidget);
      rootNavigator.removeRoute(rootPopup);
      await tester.pumpAndSettle();
      expect(find.text('last-shell-local-popup'), findsOneWidget);
      localNavigator.removeRoute(localPopup);
      await tester.pumpAndSettle();
      _ignore(
        CCRouter.navigator.push<String>(
          const _Intent('outlet.root', 'after-shell'),
        ),
      );
      await tester.pumpAndSettle();
      expect(rootNavigator.widget.pages, hasLength(1));
      expect(rootNavigator.canPop(), isFalse);
      expect(resources['context-child']!.disposeCount, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
