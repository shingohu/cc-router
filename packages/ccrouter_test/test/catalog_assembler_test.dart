import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Codec implements CCRouteCodec<String> {
  const _Codec();
  @override
  String decode(CCRouteCodecValues input) => input.path['id']!;
  @override
  CCRouteCodecValues encode(String value) =>
      CCRouteCodecValues(path: {'id': value});
}

CCRouteDefinition<String, String> _definition({
  String routeId = 'orders.detail',
  CCRoutePresentation presentation = const CCPagePresentation(),
}) => CCRouteDefinition(
  routeId: routeId,
  patterns: [
    const CCPathPattern('/orders/:id', primary: true),
    const CCPathPattern('/order/:id'),
    const CCRegexPattern(r'/legacy/(?<id>\d+)'),
  ],
  codec: const _Codec(),
  presentation: presentation,
);
CCFlutterRouteDestination _destination({
  String routeId = 'orders.detail',
  CCRoutePresentation presentation = const CCPagePresentation(),
}) => CCFlutterRouteDestination.fromDefinition(
  definition: _definition(routeId: routeId, presentation: presentation),
  builder: (values) =>
      Text('${values.path['id']}:${values.query['tab']?.single}'),
);

final class _Registrar implements CCComponentRegistrar {
  @override
  void register(CCRegistry registry) => registry.registerRoute(_definition());
}

void main() {
  tearDown(CCRouterHost.shutdown);
  test('catalog merges components and rejects duplicate route IDs', () {
    final catalog = CCFlutterRouteCatalog.merge([
      CCFlutterRouteCatalog([_destination()]),
      CCFlutterRouteCatalog([_destination(routeId: 'other')]),
    ]);
    expect(catalog.destinations, hasLength(2));
    expect(catalog.destinationFor('other')?.routeId, 'other');
    expect(catalog.destinationFor('missing'), isNull);
    expect(
      () => CCFlutterRouteCatalog([_destination(), _destination()]),
      throwsArgumentError,
    );
  });
  testWidgets('Managed renders primary, alias and Regex from one catalog', (
    tester,
  ) async {
    final catalog = CCFlutterRouteCatalog(
      [_destination()],
      componentVersions: const {'orders': '1.0.0'},
    );
    CCRouterHost.initialize(
      hostAssembly: CCHostAssembly.fromComponents(
        components: [
          CCComponentManifest(
            id: 'orders',
            version: '1.0.0',
            registrar: _Registrar(),
          ),
        ],
        routeCatalog: catalog,
      ),
    );
    await tester.pumpWidget(
      const CCManagedRouterApp(initialLocation: '/orders/42?tab=items'),
    );
    await tester.pumpAndSettle();
    expect(find.text('42:items'), findsOneWidget);
    for (final path in ['/order/7?tab=summary', '/legacy/7?tab=summary']) {
      await CCRouter.navigator.open(Uri.parse(path));
      await tester.pumpAndSettle();
      expect(find.text('7:summary'), findsOneWidget);
      expect(CCRouter.activeRouteEntries.last.routeId, 'orders.detail');
      CCRouter.navigator.pop();
      await tester.pumpAndSettle();
    }
  });
  test('catalog preserves sheet/dialog presentations without overrides', () {
    for (final presentation in <CCRoutePresentation>[
      const CCModalBottomSheetPresentation(),
      const CCDialogPresentation(),
    ]) {
      final catalog = CCFlutterRouteCatalog([
        _destination(presentation: presentation),
      ]);
      expect(
        catalog.destinations.single.route.presentation,
        same(presentation),
      );
      final backend = CCManagedRouterBackend(
        routeCatalog: catalog,
        initializeFromRouteInformation: false,
      );
      backend.adapter.initialize([catalog.destinations.single.route]);
      expect(backend.adapter.capabilities.supportsModalRoutes, isTrue);
      backend.adapter.dispose();
      addTearDown(backend.dispose);
    }
  });
}
