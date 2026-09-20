import 'package:ccrouter/ccrouter.dart';

export 'query_codec_types.dart';

import 'query_codec_types.dart';

/// Component identity used only by generated Query codec regression tests.
const queryCodecFixtureComponent = CCComponentDescriptor(
  id: 'query_codec_fixture',
  version: '1.0.0',
);

/// Destination schema used to compile and execute generated Query conversion.
@CCRoute<void>(
  component: queryCodecFixtureComponent,
  id: 'query_codec_fixture.detail',
  pattern: CCPathPattern('/query-codec-fixture'),
)
final class QueryCodecFixturePage {
  /// Creates the fixture with repeated and custom Query values.
  const QueryCodecFixturePage({
    @CCQueryParam() required this.tags,
    @CCQueryParam() required this.ids,
    @CCQueryParam() this.states,
    @CCQueryParam(codec: QueryCodecFixtureFilterCodec) this.filter,
  });

  /// Ordered repeated text values.
  final List<String> tags;

  /// Unordered repeated integer values.
  final Set<int> ids;

  /// Optional repeated enum values.
  final List<QueryCodecFixtureState>? states;

  /// Optional complex Query value.
  final QueryCodecFixtureFilter? filter;
}
