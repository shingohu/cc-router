import 'package:ccrouter/ccrouter.dart';

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
