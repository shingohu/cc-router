import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_test/src/ccrouter_generated/binding/multiple_extra_fixture.route_binding.g.dart'
    as route_binding;
import 'package:ccrouter_test/src/ccrouter_generated/contract/multiple_extra_contract_fixture.route.contract.g.dart'
    as public_contract;
import 'package:ccrouter_test/src/ccrouter_generated/route/multiple_extra_fixture.route.g.dart'
    as route_contract;
import 'package:ccrouter_test/src/generated_route_types.dart';
import 'package:ccrouter_test/src/multiple_extra_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _ExtraRegistrar implements CCComponentRegistrar {
  _ExtraRegistrar(this.definitions);

  final List<CCRouteDefinition<dynamic, dynamic>> definitions;

  @override
  void register(CCRegistry registry) {
    for (final definition in definitions) {
      registry.registerRoute(definition);
    }
  }
}

void main() {
  const snapshot = GeneratedExtraSnapshot({
    'section': [GeneratedSnapshot('secret-payload')],
  });

  test(
    'multiple Extras preserve DTO identity and keep URI fields separate',
    () {
      final codec = route_contract
          .ccrouterDescribeGeneratedMultiExtraPageRoute()
          .codec;
      final intent =
          const route_contract.CCGeneratedGeneratedMultiExtraPageRouteFactory()(
            id: 'score-1',
            tab: 'notes',
            snapshot: snapshot,
            revision: null,
          );
      final encoded = codec.encode(intent.arguments as dynamic);
      expect(encoded.path, {'id': 'score-1'});
      expect(encoded.query, {
        'tab': ['notes'],
      });
      expect(encoded.extra, isNotNull);
      expect(encoded.extra, isNot(same(snapshot)));
      final decoded = codec.decode(encoded);
      expect(decoded.snapshot, same(snapshot));
      expect(decoded.revision, isNull);
      expect(decoded.enabled, isTrue);
      final page = route_binding.ccrouterBuildGeneratedMultiExtraPageRoute(
        encoded,
      );
      expect(page.id, 'score-1');
      expect(page.tab, 'notes');
      expect(page.snapshot, same(snapshot));
      expect(page.snapshot.sections['section']!.single.label, 'secret-payload');
      expect(page.revision, isNull);
      expect(page.enabled, isTrue);
    },
  );

  test('missing required Extra and foreign envelopes fail with safe errors', () {
    final codec = route_contract
        .ccrouterDescribeGeneratedMultiExtraPageRoute()
        .codec;
    final foreignCodec = route_contract
        .ccrouterDescribeGeneratedOptionalExtrasPageRoute()
        .codec;
    final foreign = foreignCodec.encode(
      const route_contract.CCGeneratedGeneratedOptionalExtrasPageRouteFactory()(
            snapshot: snapshot,
          ).arguments
          as dynamic,
    );
    for (final extra in [null, 'secret-payload', foreign.extra]) {
      expect(
        () => codec.decode(
          CCRouteCodecValues(path: {'id': 'score-1'}, extra: extra),
        ),
        throwsA(
          isA<CCRouteParameterError>().having(
            (error) => error.message,
            'sanitized route error',
            allOf(
              contains('generated_route_fixture.multi-extra'),
              isNot(contains('secret-payload')),
            ),
          ),
        ),
      );
    }
  });

  test('all-null optional Extras retain absence and non-null fields round-trip', () {
    final codec = route_contract
        .ccrouterDescribeGeneratedOptionalExtrasPageRoute()
        .codec;
    final absent = codec.decode(CCRouteCodecValues());
    expect(absent.snapshot, isNull);
    expect(absent.revision, isNull);
    expect(codec.encode(absent).extra, isNull);
    final explicitNull =
        const route_contract.CCGeneratedGeneratedOptionalExtrasPageRouteFactory()(
          snapshot: null,
          revision: null,
        );
    expect(codec.encode(explicitNull.arguments as dynamic).extra, isNull);
    for (final intent in [
      const route_contract.CCGeneratedGeneratedOptionalExtrasPageRouteFactory()(
        snapshot: snapshot,
      ),
      const route_contract.CCGeneratedGeneratedOptionalExtrasPageRouteFactory()(
        revision: 0,
      ),
    ]) {
      final encoded = codec.encode(intent.arguments as dynamic);
      expect(encoded.extra, isNotNull);
      final page = route_binding.ccrouterBuildGeneratedOptionalExtrasPageRoute(
        encoded,
      );
      expect(page.snapshot, same((intent.arguments as dynamic).snapshot));
      expect(page.revision, (intent.arguments as dynamic).revision);
    }
  });

  test('non-null defaults never replace explicit null inside an envelope', () {
    final codec = route_contract
        .ccrouterDescribeGeneratedDefaultExtrasPageRoute()
        .codec;
    final defaults = codec.decode(CCRouteCodecValues());
    expect(defaults.label, 'fallback');
    expect(defaults.revision, 3);
    // Non-null Extra defaults retain the same parent reconstruction limit as a single Extra.
    expect(codec.encode(defaults).extra, isNotNull);
    final intent =
        const route_contract.CCGeneratedGeneratedDefaultExtrasPageRouteFactory()(
          label: null,
          revision: null,
        );
    final encoded = codec.encode(intent.arguments as dynamic);
    expect(encoded.extra, isNotNull);
    final page = route_binding.ccrouterBuildGeneratedDefaultExtrasPageRoute(
      encoded,
    );
    expect(page.label, isNull);
    expect(page.revision, isNull);
  });

  test('Pure Dart public contracts retain typed collection identity', () {
    final items = ['one', 'two'];
    final intent = public_contract.GeneratedMultiExtrasRoute.intent(
      items: items,
    );
    final codec = public_contract
        .GeneratedMultiExtrasRouteContractBinding
        .definition
        .codec;
    final encoded = codec.encode(intent.arguments as dynamic);
    final decoded = codec.decode(encoded);
    expect(decoded.items, same(items));
    expect(decoded.label, isNull);
    final page = route_binding.ccrouterBuildGeneratedContractExtrasPageRoute(
      encoded,
    );
    expect(page.items, same(items));
    expect(page.label, isNull);
    expect(encoded.path, isEmpty);
    expect(encoded.query, isEmpty);
    expect(
      () => codec.decode(CCRouteCodecValues()),
      throwsA(isA<CCRouteParameterError>()),
    );
    expect(
      () => codec.decode(CCRouteCodecValues(extra: snapshot)),
      throwsA(isA<CCRouteParameterError>()),
    );
  });

  for (final operation in ['go', 'reset', 'uri']) {
    testWidgets('$operation reconstructs a parent with absent optional Extras', (
      tester,
    ) async {
      addTearDown(CCRouterHost.shutdown);
      final parent = route_contract
          .ccrouterDescribeGeneratedOptionalExtrasPageRoute();
      final child = route_contract
          .ccrouterDescribeGeneratedExtrasChildPageRoute();
      final catalog = CCFlutterRouteCatalog(
        [
          CCFlutterRouteDestination.fromDefinition(
            definition: parent,
            builder:
                route_binding.ccrouterBuildGeneratedOptionalExtrasPageRoute,
          ),
          CCFlutterRouteDestination.fromDefinition(
            definition: child,
            builder: route_binding.ccrouterBuildGeneratedExtrasChildPageRoute,
          ),
        ],
        componentVersions: const {'generated_route_fixture': '1.0.0'},
      );
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(
          components: [
            CCComponentManifest(
              id: 'generated_route_fixture',
              version: '1.0.0',
              registrar: _ExtraRegistrar([parent, child]),
            ),
          ],
          routeCatalog: catalog,
        ),
      );
      final backend = CCManagedRouterBackend(
        routeCatalog: catalog,
        initialLocation: operation == 'uri'
            ? '/generated/optional-extras/child'
            : '/generated/optional-extras',
      );
      await tester.pumpWidget(
        CCRouterApp.managed(
          backend: backend,
          child: MaterialApp.router(routerConfig: backend.routerConfig),
        ),
      );
      await tester.pumpAndSettle();
      final intent =
          const route_contract.CCGeneratedGeneratedExtrasChildPageRouteFactory()();
      if (operation == 'go') await CCRouter.navigator.go(intent);
      if (operation == 'reset') await CCRouter.navigator.reset(intent);
      await tester.pumpAndSettle();
      expect(CCRouter.activeRouteEntries.map((entry) => entry.routeId), [
        'generated_route_fixture.optional-extras',
        'generated_route_fixture.extras-child',
      ]);
      expect(backend.adapter.requests.first.extra, isNull);
      expect(find.text('extras-child'), findsOneWidget);
      await CCRouter.navigator.maybePop();
      await tester.pumpAndSettle();
      final page = tester.widget<GeneratedOptionalExtrasPage>(
        find.byType(GeneratedOptionalExtrasPage),
      );
      expect(page.snapshot, isNull);
      expect(page.revision, isNull);
    });
  }
}
