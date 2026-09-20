// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

part of '../query_codec_fixture.dart';

// **************************************************************************
// _RouteGenerator
// **************************************************************************

/// Immutable arguments for route query_codec_fixture.detail; URI values remain typed.
final class _QueryCodecFixturePageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  _QueryCodecFixturePageRouteArguments({
    required List<String> tags,
    required Set<int> ids,
    List<QueryCodecFixtureState>? states,
    this.filter,
  }) : tags = List.unmodifiable(tags),
       ids = Set.unmodifiable(ids),
       states = states == null ? null : List.unmodifiable(states);

  /// query parameter tags for query_codec_fixture.detail.
  final List<String> tags;

  /// query parameter ids for query_codec_fixture.detail.
  final Set<int> ids;

  /// query parameter states for query_codec_fixture.detail.
  final List<QueryCodecFixtureState>? states;

  /// query parameter filter for query_codec_fixture.detail.
  final QueryCodecFixtureFilter? filter;
}

/// Typed contract for query_codec_fixture.detail.
abstract final class _QueryCodecFixturePageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "query_codec_fixture.detail";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent({
    required List<String> tags,
    required Set<int> ids,
    List<QueryCodecFixtureState>? states,
    QueryCodecFixtureFilter? filter,
  }) => _QueryCodecFixturePageRouteIntent(
    _QueryCodecFixturePageRouteArguments(
      tags: tags,
      ids: ids,
      states: states,
      filter: filter,
    ),
  );

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_QueryCodecFixturePageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/query-codec-fixture",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _QueryCodecFixturePageRouteCodec(),
        deepLink: CCDeepLinkPolicy.disabled,
        presentation: const CCPagePresentation(
          routeType: CCPageRouteType.platformDefault,
          transition: CCPageTransitionType.platformDefault,
          opaque: true,
          fullscreenDialog: false,
        ),
        placement: const CCRoutePlacement(
          hostId: "default",
          parentRouteId: null,
          shellId: null,
          navigatorOutlet: "root",
        ),
        interceptorIds: const [],
        popGuardIds: const [],
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static QueryCodecFixturePage build(
    _QueryCodecFixturePageRouteArguments arguments,
  ) => QueryCodecFixturePage(
    tags: arguments.tags,
    ids: arguments.ids,
    states: arguments.states,
    filter: arguments.filter,
  );
}

/// Private data-only Intent carrying this route's typed result contract.
final class _QueryCodecFixturePageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _QueryCodecFixturePageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _QueryCodecFixturePageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _QueryCodecFixturePageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _QueryCodecFixturePageRouteCodec
    implements CCRouteCodec<_QueryCodecFixturePageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _QueryCodecFixturePageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _QueryCodecFixturePageRouteArguments decode(CCEncodedRouteArguments input) {
    final _values_tags = input.query["tags"];
    if (_values_tags != null && _values_tags.isEmpty)
      throw CCRouteParameterError(
        "Route \"query_codec_fixture.detail\" parameter \"tags\" is invalid.",
      );
    final List<String> _value_tags = _values_tags == null
        ? throw CCRouteParameterError(
            "Route \"query_codec_fixture.detail\" parameter \"tags\" is invalid.",
          )
        : List<String>.unmodifiable(_values_tags.map((raw_tags) => raw_tags));
    final _values_ids = input.query["ids"];
    if (_values_ids != null && _values_ids.isEmpty)
      throw CCRouteParameterError(
        "Route \"query_codec_fixture.detail\" parameter \"ids\" is invalid.",
      );
    final Set<int> _value_ids = _values_ids == null
        ? throw CCRouteParameterError(
            "Route \"query_codec_fixture.detail\" parameter \"ids\" is invalid.",
          )
        : Set<int>.unmodifiable(
            _values_ids.map(
              (raw_ids) =>
                  (int.tryParse(raw_ids) ??
                  (throw CCRouteParameterError(
                    "Route \"query_codec_fixture.detail\" parameter \"ids\" is invalid.",
                  ))),
            ),
          );
    final _values_states = input.query["states"];
    if (_values_states != null && _values_states.isEmpty)
      throw CCRouteParameterError(
        "Route \"query_codec_fixture.detail\" parameter \"states\" is invalid.",
      );
    final List<QueryCodecFixtureState>? _value_states = _values_states == null
        ? null
        : List<QueryCodecFixtureState>.unmodifiable(
            _values_states.map(
              (raw_states) => switch (raw_states) {
                "pending" => QueryCodecFixtureState.pending,
                "completed" => QueryCodecFixtureState.completed,
                _ => throw CCRouteParameterError(
                  "Route \"query_codec_fixture.detail\" parameter \"states\" is invalid.",
                ),
              },
            ),
          );
    final _values_filter = input.query["filter"];
    if (_values_filter != null && _values_filter.isEmpty)
      throw CCRouteParameterError(
        "Route \"query_codec_fixture.detail\" parameter \"filter\" is invalid.",
      );
    final QueryCodecFixtureFilter? _value_filter = _values_filter == null
        ? null
        : (() {
            try {
              return const QueryCodecFixtureFilterCodec().decode(
                List<String>.unmodifiable(_values_filter),
              );
            } catch (_) {
              throw CCRouteParameterError(
                "Route \"query_codec_fixture.detail\" parameter \"filter\" is invalid.",
              );
            }
          })();
    return _QueryCodecFixturePageRouteArguments(
      tags: _value_tags,
      ids: _value_ids,
      states: _value_states,
      filter: _value_filter,
    );
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(
    _QueryCodecFixturePageRouteArguments arguments,
  ) {
    if (arguments.tags.isEmpty)
      throw CCRouteParameterError(
        "Route \"query_codec_fixture.detail\" parameter \"tags\" cannot encode an empty collection.",
      );
    if (arguments.ids.isEmpty)
      throw CCRouteParameterError(
        "Route \"query_codec_fixture.detail\" parameter \"ids\" cannot encode an empty collection.",
      );
    if (arguments.states != null && arguments.states!.isEmpty)
      throw CCRouteParameterError(
        "Route \"query_codec_fixture.detail\" parameter \"states\" cannot encode an empty collection.",
      );
    return CCEncodedRouteArguments(
      path: {},
      query: {
        "tags": [for (final value in arguments.tags) value],
        "ids": (() {
          final values = <String>[
            for (final value in arguments.ids) value.toString(),
          ];
          values.sort();
          return values;
        })(),
        if (arguments.states != null)
          "states": [
            for (final value in arguments.states!) EnumName(value).name,
          ],
        if (arguments.filter != null)
          "filter": (() {
            try {
              final values = const QueryCodecFixtureFilterCodec().encode(
                arguments.filter!,
              );
              if (values.isEmpty) throw const FormatException();
              return List<String>.unmodifiable(values);
            } catch (_) {
              throw CCRouteParameterError(
                "Route \"query_codec_fixture.detail\" parameter \"filter\" is invalid.",
              );
            }
          })(),
      },
      extra: null,
    );
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterQueryCodecFixturePageRoute(CCRegistry registry) =>
    _QueryCodecFixturePageRoute.register(registry);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic>
ccrouterDescribeQueryCodecFixturePageRoute() =>
    _QueryCodecFixturePageRoute.definition;

/// Package-internal page factory bridge used by generated Flutter catalogs.
QueryCodecFixturePage ccrouterBuildQueryCodecFixturePageRoute(
  CCEncodedRouteArguments arguments,
) => _QueryCodecFixturePageRoute.build(
  _QueryCodecFixturePageRoute.definition.codec.decode(arguments),
);
