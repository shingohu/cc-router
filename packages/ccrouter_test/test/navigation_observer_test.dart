import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/managed_test_home.dart';

final class _Registrar implements CCComponentRegistrar {
  const _Registrar(this.placement);
  final CCRoutePlacement placement;
  @override
  void register(CCRegistry registry) {
    registry.registerRoute(testHomeDefinition(placement: placement));
    if (placement.shellId != null)
      registry.registerShell(
        CCShellDefinition(
          shellId: 'workspace',
          type: CCShellType.singleNavigator,
          outlets: const ['content'],
          initialOutlet: 'content',
        ),
      );
  }
}

void main() {
  tearDown(CCRouterHost.shutdown);
  for (final nested in [false, true]) {
    testWidgets(
      'real Navigator events stay on their Host and Outlet: nested=$nested',
      (tester) async {
        final outlet = nested ? 'content' : 'root';
        final placement = nested
            ? const CCRoutePlacement(
                shellId: 'workspace',
                navigatorOutlet: 'content',
              )
            : const CCRoutePlacement.root();
        CCRouterHost.initialize(
          hostAssembly: CCHostAssembly.fromComponents(
            components: [
              CCComponentManifest(
                id: 'fixture',
                version: '1.0.0',
                registrar: _Registrar(placement),
              ),
            ],
          ),
        );
        final host = CCNavigationHost(
          id: 'window.main',
          navigatorKeys: nested
              ? {'content': GlobalKey<NavigatorState>()}
              : const {},
        );
        final backend = CCManagedRouterBackend(
          host: host,
          routeCatalog: CCFlutterRouteCatalog(
            [testHomeDestination(placement: placement)],
            componentVersions: const {'fixture': '1.0.0'},
          ),
          shellBindings: nested
              ? [
                  CCManagedShellBinding(
                    shellId: 'workspace',
                    builder: (_, shell) => shell.navigatorFor('content'),
                  ),
                ]
              : const [],
        );
        await tester.pumpWidget(
          CCRouterApp.managed(
            backend: backend,
            child: MaterialApp.router(routerConfig: backend.routerConfig),
          ),
        );
        await tester.pumpAndSettle();
        final events = <CCNavigationBackendEvent>[];
        backend.adapter.addBackendEventListener(events.add);
        final navigator = host.navigatorKeyFor(outlet).currentState!;
        final result = navigator.push<void>(
          MaterialPageRoute<void>(builder: (_) => const Text('detail')),
        );
        await tester.pumpAndSettle();
        final replacement = navigator.pushReplacement<void, void>(
          MaterialPageRoute<void>(builder: (_) => const Text('replacement')),
        );
        await tester.pumpAndSettle();
        navigator.pop();
        await tester.pumpAndSettle();
        await result;
        await replacement;
        final foreign = events
            .where((event) => event.owner == CCBackendEntryOwner.foreign)
            .toList();
        expect(
          foreign.where(
            (event) => event.kind == CCNavigationBackendEventKind.push,
          ),
          hasLength(2),
        );
        expect(
          foreign.where(
            (event) => event.kind == CCNavigationBackendEventKind.remove,
          ),
          hasLength(1),
        );
        expect(
          foreign.where(
            (event) => event.kind == CCNavigationBackendEventKind.pop,
          ),
          hasLength(1),
        );
        expect(
          foreign.every(
            (event) =>
                event.hostId == host.id && event.navigatorOutlet == outlet,
          ),
          isTrue,
        );
        expect(CCRouter.activeRouteEntries.single.routeId, 'fixture.home');
      },
    );
  }
}
