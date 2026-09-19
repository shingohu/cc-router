import 'package:ccrouter/ccrouter.dart';

part 'ccrouter_generated/query_codec_fixture.route.g.dart';

/// Component identity used only by generated Query codec regression tests.
const queryCodecFixtureComponent = CCComponentDescriptor(
  id: 'query_codec_fixture',
  version: '1.0.0',
);

/// Enum values used to verify repeated enum Query conversion.
enum QueryCodecFixtureState {
  /// First stable wire value.
  pending,

  /// Second stable wire value.
  completed,
}

/// Complex shareable value encoded through an explicit Query codec.
final class QueryCodecFixtureFilter {
  /// Creates the immutable filter used by generated codec tests.
  const QueryCodecFixtureFilter(this.value);

  /// Stable non-secret wire value.
  final String value;
}

/// Stateless complex Query codec used to exercise generated isolation logic.
final class QueryCodecFixtureFilterCodec
    implements CCRouteQueryCodec<QueryCodecFixtureFilter> {
  /// Creates the stateless codec required by the route generator.
  const QueryCodecFixtureFilterCodec();

  /// Decodes exactly one value and exposes controlled failures to the wrapper.
  @override
  QueryCodecFixtureFilter decode(List<String> values) {
    if (values.length != 1 || values.single == 'decode-secret') {
      throw const FormatException('decode-secret');
    }
    return QueryCodecFixtureFilter(values.single);
  }

  /// Encodes one value and deliberately exposes an empty-output test branch.
  @override
  List<String> encode(QueryCodecFixtureFilter value) =>
      value.value == 'empty' ? const [] : [value.value];
}

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

/// Exposes the generated codec only to the dedicated test package.
CCRouteCodec<dynamic> get queryCodecFixtureCodec =>
    _QueryCodecFixturePageRoute.definition.codec;

/// Creates generated typed arguments without exposing their private class.
Object queryCodecFixtureArguments({
  required List<String> tags,
  required Set<int> ids,
  List<QueryCodecFixtureState>? states,
  QueryCodecFixtureFilter? filter,
}) => _QueryCodecFixturePageRoute.intent(
  tags: tags,
  ids: ids,
  states: states,
  filter: filter,
).arguments;

/// Builds the fixture page from generated typed arguments during tests.
QueryCodecFixturePage buildQueryCodecFixturePage(Object arguments) =>
    _QueryCodecFixturePageRoute.build(
      arguments as _QueryCodecFixturePageRouteArguments,
    );
