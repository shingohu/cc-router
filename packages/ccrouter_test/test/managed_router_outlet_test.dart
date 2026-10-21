import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/material.dart';
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

final class _OutletRegistrar implements CCComponentRegistrar {
  const _OutletRegistrar({required this.includeShell});

  final bool includeShell;

  @override
  void register(CCRegistry registry) {
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

void main() {
  tearDown(CCRouterHost.shutdown);

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
            builder: (context, shell) => Material(
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
            ),
          ),
        ],
        initialLocation: '/workspace/home/home',
        routeCatalog: CCFlutterRouteCatalog(
          [
            for (final definition in definitions)
              CCFlutterRouteDestination.fromDefinition(
                definition: definition,
                builder: (values) => Builder(
                  builder: (context) {
                    final value = values.path['value'] ?? 'root';
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final handle = CCRouter.routeEntryHandleOf(context);
                      if (handle != null) handles[value] = handle;
                    });
                    return Material(child: Center(child: Text('shell-$value')));
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
      _ignore(
        CCRouter.navigator.push<String>(
          const _Intent('shell.home.detail', 'home-detail'),
        ),
      );
      await tester.pumpAndSettle();
      _ignore(
        CCRouter.navigator.push<String>(
          const _Intent('shell.activity', 'activity'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('shell-activity'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('tab-home')));
      await tester.pumpAndSettle();
      expect(find.text('shell-home-detail'), findsOneWidget);
      expect(backend.adapter.focusedOutlet, _shellHome);

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
    },
  );
}
