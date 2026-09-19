import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/annotated_routes.dart';
import 'fixtures/route_types.dart' as types;

void main() {
  final codec = detailCodec;

  test('generated arguments inject defaults and typed scalar values', () {
    final arguments = codec.decode(CCEncodedRouteArguments(path: {'id': '42'}));
    final page = buildDetailPage(arguments);
    expect(page.id, 42);
    expect(page.tab, DetailTab.summary);
    expect(page.enabled, isFalse);
    expect(page.ratio, 1.0);
    expect(page.search, isNull);
    expect(page.snapshot, isNull);

    const snapshot = Snapshot('cached');
    final intent = detailIntent(
      id: 42,
      search: '空 格&?/%',
      tab: DetailTab.items,
      enabled: true,
      ratio: 2.5,
      snapshot: snapshot,
    );
    final encoded = codec.encode(intent.arguments);
    final roundtrip = buildDetailPage(codec.decode(encoded));
    expect(roundtrip.search, '空 格&?/%');
    expect(roundtrip.tab, DetailTab.items);
    expect(roundtrip.enabled, isTrue);
    expect(roundtrip.ratio, 2.5);
    expect(roundtrip.snapshot, same(snapshot));
  });

  test('metadata keeps aliases, presentation and interceptor order', () {
    final definition = detailDefinition;
    expect(definition.patterns, hasLength(4));
    expect(definition.deepLink, CCDeepLinkPolicy.enabled);
    expect(definition.interceptorIds, ['fixture.auth']);
    final presentation = definition.presentation as CCPagePresentation;
    expect(presentation.transition, CCPageTransitionType.slideFromBottom);
    expect(presentation.opaque, isFalse);
    expect(internalIntent().routeId, 'fixture.internal');
  });

  test(
    'generated codec rejects malformed input without exposing raw values',
    () {
      final invalid = [
        CCEncodedRouteArguments(),
        CCEncodedRouteArguments(path: {'id': 'secret-id'}),
        CCEncodedRouteArguments(
          path: {'id': '1'},
          query: {
            'tab': ['secret-tab'],
          },
        ),
        CCEncodedRouteArguments(
          path: {'id': '1'},
          query: {
            'enabled': ['yes'],
          },
        ),
        CCEncodedRouteArguments(
          path: {'id': '1'},
          query: {
            'ratio': ['NaN'],
          },
        ),
        CCEncodedRouteArguments(
          path: {'id': '1'},
          query: {
            'ratio': ['Infinity'],
          },
        ),
        CCEncodedRouteArguments(
          path: {'id': '1'},
          query: {
            'text': ['a', 'b'],
          },
        ),
        CCEncodedRouteArguments(path: {'id': '1'}, query: {'text': []}),
        CCEncodedRouteArguments(path: {'id': '1'}, extra: 'wrong object'),
      ];
      for (final input in invalid) {
        expect(
          () => codec.decode(input),
          throwsA(
            isA<CCRouteParameterError>().having(
              (e) => e.message,
              'safe message',
              allOf(contains('fixture.detail'), isNot(contains('secret'))),
            ),
          ),
        );
      }
      expect(
        () => codec.encode(detailArguments(id: 1, ratio: double.nan)),
        throwsA(isA<CCRouteParameterError>()),
      );
    },
  );

  test(
    'required Extra and positional constructors preserve typed semantics',
    () {
      final extraRouteCodec = extraCodec;
      expect(
        () => extraRouteCodec.decode(CCEncodedRouteArguments()),
        throwsA(isA<CCRouteParameterError>()),
      );
      expect(
        () => extraRouteCodec.decode(CCEncodedRouteArguments(extra: 'wrong')),
        throwsA(isA<CCRouteParameterError>()),
      );
      const snapshot = Snapshot('required');
      expect(
        buildExtraPage(
          extraRouteCodec.decode(CCEncodedRouteArguments(extra: snapshot)),
        ).snapshot,
        same(snapshot),
      );
      final positional = buildPositionalPage(
        positionalCodec.decode(CCEncodedRouteArguments(path: {'value': '你好'})),
      );
      expect(positional.value, '你好');
      expect(positional.input, 'default');
    },
  );

  test(
    'prefixed enum, Extra and result types remain accessible in generated parts',
    () {
      const payload = types.Payload();
      final CCRouteIntent<types.Result> intent = prefixedIntent(
        mode: types.Mode.alternate,
        payload: payload,
      );
      final codec = prefixedCodec;
      final page = buildPrefixedPage(
        codec.decode(codec.encode(intent.arguments)),
      );
      expect(page.mode, types.Mode.alternate);
      expect(page.payload, same(payload));
    },
  );

  test(
    'generated registrar and intents navigate through Runtime and release entries',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final host = CCRouterTestHost(
        components: const [
          CCComponentManifest.fromDescriptor(
            descriptor: fixtureComponent,
            registrar: FixtureComponentRegistrar(),
          ),
        ],
        navigationAdapter: adapter,
      );
      addTearDown(host.dispose);
      host.initialize();
      await host.runtime.openRoute(Uri.parse('/position/base'));
      final pending = host.runtime.pushRoute<String>(
        detailIntent(id: 42, search: 'a/b &雪'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(host.runtime.activeRouteEntries.last.routeId, 'fixture.detail');
      host.runtime.popRoute(result: 'done');
      expect(await pending, 'done');
      expect(host.runtime.activeRouteEntries, hasLength(1));
      for (final uri in ['/legacy/7', 'sample://detail/7', '/old/7']) {
        expect(
          detailArgumentId(
            host.runtime.decodeRouteArguments(host.runtime.resolveRoute(uri)),
          ),
          7,
        );
        await host.runtime.openRoute(Uri.parse(uri));
        expect(host.runtime.activeRouteEntries.last.routeId, 'fixture.detail');
        host.runtime.popRoute();
      }
      await host.dispose();
      expect(host.runtime.activeRouteEntries, isEmpty);
    },
  );
}
