import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _RouteService implements CCDisposable {
  _RouteService(this.id);

  final int id;
  bool disposed = false;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class _MissingRouteService {}

final class _RouteArguments {
  const _RouteArguments(this.id);

  final String id;
}

final class _RouteCodec implements CCRouteCodec<_RouteArguments> {
  const _RouteCodec();

  @override
  _RouteArguments decode(CCEncodedRouteArguments input) =>
      _RouteArguments(input.path['id']!);

  @override
  CCEncodedRouteArguments encode(_RouteArguments arguments) =>
      CCEncodedRouteArguments(path: {'id': arguments.id});
}

final class _RouteIntent implements CCRouteIntent<void> {
  const _RouteIntent(this.id);

  final String id;

  @override
  String get routeId => 'route_service.detail';

  @override
  Object get arguments => _RouteArguments(id);
}

CCRouteDefinition<_RouteArguments, void> _routeDefinition() =>
    CCRouteDefinition(
      routeId: 'route_service.detail',
      patterns: [const CCPathPattern('/route-service/:id', primary: true)],
      codec: const _RouteCodec(),
    );

final class _RouteServiceRegistrar implements CCComponentRegistrar {
  _RouteServiceRegistrar(this.created);

  final List<_RouteService> created;

  @override
  void register(CCRegistry registry) {
    registry.registerService<_RouteService>(
      CCServiceProvider(
        scope: CCServiceScope.route,
        factory: (_) {
          final service = _RouteService(created.length + 1);
          created.add(service);
          return service;
        },
      ),
    );
    registry.registerRoute(_routeDefinition());
  }
}

void main() {
  tearDown(CCRouter.shutdown);

  testWidgets('GoRouter page resolves and disposes its exact Route Service', (
    tester,
  ) async {
    final created = <_RouteService>[];
    CCRouter.initialize(
      components: [
        CCComponentManifest(
          id: 'route_service',
          version: '1.0.0',
          registrar: _RouteServiceRegistrar(created),
        ),
      ],
    );
    final destination = CCFlutterRouteDestination.fromDefinition(
      definition: _routeDefinition(),
      builder: (arguments) => Builder(
        builder: (context) {
          final service = CCRouter.routeService<_RouteService>(context);
          final missing = CCRouter.routeServiceOrNull<_MissingRouteService>(
            context,
          );
          return Text(
            '${arguments.path['id']}:service-${service.id}:$missing',
            key: const ValueKey('route-service-page'),
          );
        },
      ),
    );
    final catalog = CCFlutterRouteCatalog(
      [destination],
      componentVersions: const {'route_service': '1.0.0'},
    );
    final backend = CCGoRouterBackend.managed(
      catalog: catalog,
      hostRoutes: [GoRoute(path: '/', builder: (_, _) => const Text('home'))],
    );
    await tester.pumpWidget(
      CCRouterApp.managed(
        backend: backend,
        child: MaterialApp.router(routerConfig: backend.router),
      ),
    );
    await tester.pumpAndSettle();

    final pushed = CCRouter.navigator.push<void>(const _RouteIntent('42'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('route-service-page')), findsOneWidget);
    expect(find.text('42:service-1:null'), findsOneWidget);
    expect(created, hasLength(1));
    expect(created.single.disposed, isFalse);

    CCRouter.navigator.pop();
    await pushed;
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(created.single.disposed, isTrue);

    await tester.pumpWidget(const SizedBox());
    await CCRouter.shutdown();
  });
}
