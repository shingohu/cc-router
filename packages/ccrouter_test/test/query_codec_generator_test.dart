import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_test/src/query_codec_fixture_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'generated repeated Query values round-trip with stable wire output',
    () {
      final codec = queryCodecFixtureCodec;
      final tags = ['first', 'second'];
      final ids = {20, 3};
      final states = [
        QueryCodecFixtureState.completed,
        QueryCodecFixtureState.pending,
      ];
      final arguments = queryCodecFixtureArguments(
        tags: tags,
        ids: ids,
        states: states,
        filter: const QueryCodecFixtureFilter('active'),
      );
      tags.add('late');
      ids.add(99);
      states.add(QueryCodecFixtureState.completed);
      final encoded = codec.encode(arguments);

      expect(encoded.query['tags'], ['first', 'second']);
      expect(encoded.query['ids'], ['20', '3']);
      expect(encoded.query['states'], ['completed', 'pending']);
      expect(encoded.query['filter'], ['active']);

      final page = buildQueryCodecFixturePage(codec.decode(encoded));
      expect(page.tags, ['first', 'second']);
      expect(page.ids, {20, 3});
      expect(page.states, [
        QueryCodecFixtureState.completed,
        QueryCodecFixtureState.pending,
      ]);
      expect(page.filter?.value, 'active');
      expect(() => page.tags.add('third'), throwsUnsupportedError);
      expect(() => page.ids.add(4), throwsUnsupportedError);

      final deduplicated = buildQueryCodecFixturePage(
        codec.decode(
          CCEncodedRouteArguments(
            query: const {
              'tags': ['tag'],
              'ids': ['3', '3', '20'],
            },
          ),
        ),
      );
      expect(deduplicated.ids, {3, 20});
    },
  );

  test(
    'generated repeated Query decode rejects missing and malformed values',
    () {
      final codec = queryCodecFixtureCodec;
      final invalid = [
        CCEncodedRouteArguments(),
        CCEncodedRouteArguments(
          query: const {
            'tags': [],
            'ids': ['1'],
          },
        ),
        CCEncodedRouteArguments(
          query: const {
            'tags': ['tag'],
            'ids': ['not-an-int'],
          },
        ),
        CCEncodedRouteArguments(
          query: const {
            'tags': ['tag'],
            'ids': ['1'],
            'states': ['unknown-secret'],
          },
        ),
        CCEncodedRouteArguments(
          query: const {
            'tags': ['tag'],
            'ids': ['1'],
            'filter': ['decode-secret'],
          },
        ),
      ];

      for (final input in invalid) {
        expect(
          () => codec.decode(input),
          throwsA(
            isA<CCRouteParameterError>().having(
              (error) => error.message,
              'sanitized message',
              allOf(
                contains('query_codec_fixture.detail'),
                isNot(contains('unknown-secret')),
                isNot(contains('decode-secret')),
              ),
            ),
          ),
        );
      }
    },
  );

  test('generated Query encode rejects values with no URI representation', () {
    final codec = queryCodecFixtureCodec;

    expect(
      () => codec.encode(queryCodecFixtureArguments(tags: const [], ids: {1})),
      throwsA(isA<CCRouteParameterError>()),
    );
    expect(
      () => codec.encode(
        queryCodecFixtureArguments(tags: const ['tag'], ids: const {}),
      ),
      throwsA(isA<CCRouteParameterError>()),
    );
    expect(
      () => codec.encode(
        queryCodecFixtureArguments(
          tags: const ['tag'],
          ids: const {1},
          states: const [],
        ),
      ),
      throwsA(isA<CCRouteParameterError>()),
    );
    expect(
      () => codec.encode(
        queryCodecFixtureArguments(
          tags: const ['tag'],
          ids: const {1},
          filter: const QueryCodecFixtureFilter('empty'),
        ),
      ),
      throwsA(
        isA<CCRouteParameterError>().having(
          (error) => error.message,
          'sanitized message',
          isNot(contains('empty')),
        ),
      ),
    );
  });
}
