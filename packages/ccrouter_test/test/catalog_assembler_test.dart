import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CCFlutterRouteDestination destination({
  String routeId = 'orders.detail',
  List<CCRoutePattern> patterns = const [
    CCPathPattern('/orders/:orderId', primary: true),
    CCPathPattern('/order/:orderId'),
  ],
  CCRoutePresentation presentation = const CCPagePresentation(),
  CCRoutePlacement placement = const CCRoutePlacement.root(),
}) => CCFlutterRouteDestination(
  route: CCNavigationRoute(
    routeId: routeId,
    patterns: patterns,
    presentation: presentation,
    deepLink: CCDeepLinkPolicy.disabled,
    placement: placement,
  ),
  builder: (arguments) => Text(
    '${arguments.path['orderId']}:${arguments.query['tab']?.single}',
    textDirection: TextDirection.ltr,
  ),
);

void main() {
  test('catalog merges components and rejects duplicate route IDs', () {
    final orders = CCFlutterRouteCatalog([destination()]);
    final account = CCFlutterRouteCatalog([
      destination(
        routeId: 'account.profile',
        patterns: const [CCPathPattern('/profile', primary: true)],
      ),
    ]);

    final merged = CCFlutterRouteCatalog.merge([orders, account]);
    expect(merged.destinations, hasLength(2));
    expect(
      merged.destinationFor('account.profile')?.routeId,
      'account.profile',
    );
    expect(merged.destinationFor('missing'), isNull);
    expect(
      () => CCFlutterRouteCatalog([destination(), destination()]),
      throwsArgumentError,
    );
  });

  testWidgets('assembler renders primary and alias paths from one catalog', (
    tester,
  ) async {
    final assembly = CCGoRouterAssembler.assemble(
      catalog: CCFlutterRouteCatalog([destination()]),
    );
    expect(assembly.routes, hasLength(2));
    expect(assembly.bindings.single.routeId, 'orders.detail');
    expect(
      assembly.bindings.single.presentationType,
      CCGoRouterPresentationType.page,
    );

    final router = GoRouter(
      initialLocation: '/orders/42?tab=items',
      routes: assembly.routes,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('42:items'), findsOneWidget);

    router.go('/order/7?tab=summary');
    await tester.pumpAndSettle();
    expect(find.text('7:summary'), findsOneWidget);
  });

  test('assembler maps modal presentations into binding metadata', () {
    final sheet = CCGoRouterAssembler.assemble(
      catalog: CCFlutterRouteCatalog([
        destination(presentation: const CCModalBottomSheetPresentation()),
      ]),
    );
    expect(
      sheet.bindings.single.presentationType,
      CCGoRouterPresentationType.bottomSheet,
    );

    final dialog = CCGoRouterAssembler.assemble(
      catalog: CCFlutterRouteCatalog([
        destination(presentation: const CCDialogPresentation()),
      ]),
    );
    expect(
      dialog.bindings.single.presentationType,
      CCGoRouterPresentationType.dialog,
    );
  });

  test(
    'assembler requires overrides for backend-specific route structures',
    () {
      final nested = CCFlutterRouteCatalog([
        destination(placement: const CCRoutePlacement(shellId: 'home')),
      ]);
      expect(
        () => CCGoRouterAssembler.assemble(catalog: nested),
        throwsA(isA<CCNavigationAdapterError>()),
      );

      final regex = CCFlutterRouteCatalog([
        destination(
          patterns: const [
            CCPathPattern('/orders/:orderId', primary: true),
            CCRegexPattern(r'/legacy/(?<orderId>\d+)'),
          ],
        ),
      ]);
      expect(
        () => CCGoRouterAssembler.assemble(catalog: regex),
        throwsA(isA<CCNavigationAdapterError>()),
      );

      final customRoute = GoRoute(
        path: '/custom/:orderId',
        builder: (_, state) => Text(state.pathParameters['orderId']!),
      );
      final overridden = CCGoRouterAssembler.assemble(
        catalog: nested,
        overrides: {
          'orders.detail': CCGoRouterRouteOverride(
            binding: CCGoRouterRouteBinding(
              routeId: 'orders.detail',
              goRoute: customRoute,
            ),
            includeInRootRoutes: false,
          ),
        },
      );
      expect(overridden.routes, isEmpty);
      expect(overridden.bindings.single.goRoute, same(customRoute));
    },
  );
}
