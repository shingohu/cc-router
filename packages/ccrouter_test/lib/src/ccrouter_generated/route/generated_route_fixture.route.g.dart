// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_test/src/generated_route_types.dart' as route_type_0;

/// Immutable arguments for route generated_route_fixture.detail; URI values remain typed.
final class _GeneratedDetailPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _GeneratedDetailPageRouteArguments({
    required this.id,
    this.search,
    this.tab = route_type_0.GeneratedDetailTab.summary,
    this.enabled = false,
    this.ratio = 1.0,
    this.snapshot,
  });

  /// path parameter id for generated_route_fixture.detail.
  final int id;

  /// query parameter text for generated_route_fixture.detail.
  final String? search;

  /// query parameter tab for generated_route_fixture.detail.
  final route_type_0.GeneratedDetailTab tab;

  /// query parameter enabled for generated_route_fixture.detail.
  final bool enabled;

  /// query parameter ratio for generated_route_fixture.detail.
  final double ratio;

  /// extra parameter snapshot for generated_route_fixture.detail.
  final route_type_0.GeneratedSnapshot? snapshot;
}

/// Generated route fixture with safe defaults.
abstract final class _GeneratedDetailPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "generated_route_fixture.detail";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<String> intent({
    required int id,
    String? search,
    route_type_0.GeneratedDetailTab tab =
        route_type_0.GeneratedDetailTab.summary,
    bool enabled = false,
    double ratio = 1.0,
    route_type_0.GeneratedSnapshot? snapshot,
  }) => _GeneratedDetailPageRouteIntent(
    _GeneratedDetailPageRouteArguments(
      id: id,
      search: search,
      tab: tab,
      enabled: enabled,
      ratio: ratio,
      snapshot: snapshot,
    ),
  );

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_GeneratedDetailPageRouteArguments, String>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/generated/detail/:id",
            primary: true,
            constraints: const <String, String>{"id": "\\d+"},
          ),
          const CCPathPattern(
            "/generated/legacy/:id",
            primary: false,
            constraints: const <String, String>{},
          ),
          const CCUriPattern(
            "generated://detail/:id",
            primary: false,
            constraints: const <String, String>{},
          ),
          const CCRegexPattern("/generated/old/(?<id>\\d+)"),
        ],
        codec: const _GeneratedDetailPageRouteCodec(),
        deepLink: CCDeepLinkPolicy.enabled,
        presentation: const CCPagePresentation(
          routeType: CCPageRouteType.platformDefault,
          transition: CCPageTransitionType.slideFromBottom,
          opaque: false,
          fullscreenDialog: false,
        ),
        placement: const CCRoutePlacement(
          hostId: "default",
          parentRouteId: null,
          shellId: null,
          navigatorOutlet: "root",
        ),
        interceptorIds: const ["generated_route_fixture.auth"],
        popGuardIds: const [],
      );
}

/// Private data-only Intent carrying this route's typed result contract.
final class _GeneratedDetailPageRouteIntent implements CCRouteIntent<String> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _GeneratedDetailPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _GeneratedDetailPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _GeneratedDetailPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _GeneratedDetailPageRouteCodec
    implements CCRouteCodec<_GeneratedDetailPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _GeneratedDetailPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _GeneratedDetailPageRouteArguments decode(CCEncodedRouteArguments input) {
    double _parse_ratio(String raw) {
      final value = double.tryParse(raw);
      if (value == null || !value.isFinite) {
        throw CCRouteParameterError(
          "Route \"generated_route_fixture.detail\" parameter \"ratio\" must be finite.",
        );
      }
      return value;
    }

    final _raw_id = input.path["id"];
    final int _value_id = _raw_id == null
        ? throw CCRouteParameterError(
            "Route \"generated_route_fixture.detail\" parameter \"id\" is invalid.",
          )
        : (int.tryParse(_raw_id) ??
              (throw CCRouteParameterError(
                "Route \"generated_route_fixture.detail\" parameter \"id\" is invalid.",
              )));
    final _values_search = input.query["text"];
    if (_values_search != null && _values_search.length != 1)
      throw CCRouteParameterError(
        "Route \"generated_route_fixture.detail\" parameter \"text\" is invalid.",
      );
    final _raw_search = _values_search?.single;
    final String? _value_search = _raw_search == null ? null : _raw_search;
    final _values_tab = input.query["tab"];
    if (_values_tab != null && _values_tab.length != 1)
      throw CCRouteParameterError(
        "Route \"generated_route_fixture.detail\" parameter \"tab\" is invalid.",
      );
    final _raw_tab = _values_tab?.single;
    final route_type_0.GeneratedDetailTab _value_tab = _raw_tab == null
        ? route_type_0.GeneratedDetailTab.summary
        : switch (_raw_tab) {
            "summary" => route_type_0.GeneratedDetailTab.summary,
            "items" => route_type_0.GeneratedDetailTab.items,
            _ => throw CCRouteParameterError(
              "Route \"generated_route_fixture.detail\" parameter \"tab\" is invalid.",
            ),
          };
    final _values_enabled = input.query["enabled"];
    if (_values_enabled != null && _values_enabled.length != 1)
      throw CCRouteParameterError(
        "Route \"generated_route_fixture.detail\" parameter \"enabled\" is invalid.",
      );
    final _raw_enabled = _values_enabled?.single;
    final bool _value_enabled = _raw_enabled == null
        ? false
        : switch (_raw_enabled) {
            "true" => true,
            "false" => false,
            _ => throw CCRouteParameterError(
              "Route \"generated_route_fixture.detail\" parameter \"enabled\" is invalid.",
            ),
          };
    final _values_ratio = input.query["ratio"];
    if (_values_ratio != null && _values_ratio.length != 1)
      throw CCRouteParameterError(
        "Route \"generated_route_fixture.detail\" parameter \"ratio\" is invalid.",
      );
    final _raw_ratio = _values_ratio?.single;
    final double _value_ratio = _raw_ratio == null
        ? 1.0
        : _parse_ratio(_raw_ratio);
    final _value_snapshot = input.extra == null ? null : input.extra;
    if (_value_snapshot is! route_type_0.GeneratedSnapshot?)
      throw CCRouteParameterError(
        "Route \"generated_route_fixture.detail\" parameter \"snapshot\" is invalid.",
      );
    return _GeneratedDetailPageRouteArguments(
      id: _value_id,
      search: _value_search,
      tab: _value_tab,
      enabled: _value_enabled,
      ratio: _value_ratio,
      snapshot: _value_snapshot,
    );
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_GeneratedDetailPageRouteArguments arguments) {
    if (!arguments.ratio.isFinite)
      throw CCRouteParameterError(
        "Route \"generated_route_fixture.detail\" parameter \"ratio\" must be finite.",
      );
    return CCEncodedRouteArguments(
      path: {"id": arguments.id.toString()},
      query: {
        if (arguments.search != null) "text": [arguments.search!],
        "tab": [EnumName(arguments.tab).name],
        "enabled": [arguments.enabled.toString()],
        "ratio": [arguments.ratio.toString()],
      },
      extra: arguments.snapshot,
    );
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedGeneratedDetailPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedGeneratedDetailPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<String> call({
    required int id,
    String? search,
    route_type_0.GeneratedDetailTab tab =
        route_type_0.GeneratedDetailTab.summary,
    bool enabled = false,
    double ratio = 1.0,
    route_type_0.GeneratedSnapshot? snapshot,
  }) => _GeneratedDetailPageRoute.intent(
    id: id,
    search: search,
    tab: tab,
    enabled: enabled,
    ratio: ratio,
    snapshot: snapshot,
  );
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterGeneratedDetailPageRoute(CCRegistry registry) =>
    registry.registerRoute(_GeneratedDetailPageRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic>
ccrouterDescribeGeneratedDetailPageRoute() =>
    _GeneratedDetailPageRoute.definition;

/// Immutable arguments for route generated_route_fixture.internal; URI values remain typed.
final class _GeneratedInternalPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _GeneratedInternalPageRouteArguments();
}

/// Typed contract for generated_route_fixture.internal.
abstract final class _GeneratedInternalPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "generated_route_fixture.internal";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _GeneratedInternalPageRouteIntent(_GeneratedInternalPageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_GeneratedInternalPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/generated/internal",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _GeneratedInternalPageRouteCodec(),
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
}

/// Private data-only Intent carrying this route's typed result contract.
final class _GeneratedInternalPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _GeneratedInternalPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _GeneratedInternalPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _GeneratedInternalPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _GeneratedInternalPageRouteCodec
    implements CCRouteCodec<_GeneratedInternalPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _GeneratedInternalPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _GeneratedInternalPageRouteArguments decode(CCEncodedRouteArguments input) {
    return _GeneratedInternalPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(
    _GeneratedInternalPageRouteArguments arguments,
  ) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedGeneratedInternalPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedGeneratedInternalPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _GeneratedInternalPageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterGeneratedInternalPageRoute(CCRegistry registry) =>
    registry.registerRoute(_GeneratedInternalPageRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic>
ccrouterDescribeGeneratedInternalPageRoute() =>
    _GeneratedInternalPageRoute.definition;

/// Immutable arguments for route generated_route_fixture.positional; URI values remain typed.
final class _GeneratedPositionalPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _GeneratedPositionalPageRouteArguments({
    required this.value,
    this.input = "default",
  });

  /// path parameter value for generated_route_fixture.positional.
  final String value;

  /// query parameter input for generated_route_fixture.positional.
  final String input;
}

/// Typed contract for generated_route_fixture.positional.
abstract final class _GeneratedPositionalPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "generated_route_fixture.positional";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<int> intent({
    required String value,
    String input = "default",
  }) => _GeneratedPositionalPageRouteIntent(
    _GeneratedPositionalPageRouteArguments(value: value, input: input),
  );

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_GeneratedPositionalPageRouteArguments, int>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/generated/position/:value",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _GeneratedPositionalPageRouteCodec(),
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
}

/// Private data-only Intent carrying this route's typed result contract.
final class _GeneratedPositionalPageRouteIntent implements CCRouteIntent<int> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _GeneratedPositionalPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _GeneratedPositionalPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _GeneratedPositionalPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _GeneratedPositionalPageRouteCodec
    implements CCRouteCodec<_GeneratedPositionalPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _GeneratedPositionalPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _GeneratedPositionalPageRouteArguments decode(CCEncodedRouteArguments input) {
    final _raw_value = input.path["value"];
    final String _value_value = _raw_value == null
        ? throw CCRouteParameterError(
            "Route \"generated_route_fixture.positional\" parameter \"value\" is invalid.",
          )
        : _raw_value;
    final _values_input = input.query["input"];
    if (_values_input != null && _values_input.length != 1)
      throw CCRouteParameterError(
        "Route \"generated_route_fixture.positional\" parameter \"input\" is invalid.",
      );
    final _raw_input = _values_input?.single;
    final String _value_input = _raw_input == null ? "default" : _raw_input;
    return _GeneratedPositionalPageRouteArguments(
      value: _value_value,
      input: _value_input,
    );
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(
    _GeneratedPositionalPageRouteArguments arguments,
  ) {
    return CCEncodedRouteArguments(
      path: {"value": arguments.value},
      query: {
        "input": [arguments.input],
      },
      extra: null,
    );
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedGeneratedPositionalPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedGeneratedPositionalPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<int> call({required String value, String input = "default"}) =>
      _GeneratedPositionalPageRoute.intent(value: value, input: input);
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterGeneratedPositionalPageRoute(CCRegistry registry) =>
    registry.registerRoute(_GeneratedPositionalPageRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic>
ccrouterDescribeGeneratedPositionalPageRoute() =>
    _GeneratedPositionalPageRoute.definition;

/// Immutable arguments for route generated_route_fixture.extra; URI values remain typed.
final class _GeneratedExtraPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _GeneratedExtraPageRouteArguments({required this.snapshot});

  /// extra parameter snapshot for generated_route_fixture.extra.
  final route_type_0.GeneratedSnapshot snapshot;
}

/// Typed contract for generated_route_fixture.extra.
abstract final class _GeneratedExtraPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "generated_route_fixture.extra";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<bool> intent({
    required route_type_0.GeneratedSnapshot snapshot,
  }) => _GeneratedExtraPageRouteIntent(
    _GeneratedExtraPageRouteArguments(snapshot: snapshot),
  );

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_GeneratedExtraPageRouteArguments, bool>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/generated/extra",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _GeneratedExtraPageRouteCodec(),
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
}

/// Private data-only Intent carrying this route's typed result contract.
final class _GeneratedExtraPageRouteIntent implements CCRouteIntent<bool> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _GeneratedExtraPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _GeneratedExtraPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _GeneratedExtraPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _GeneratedExtraPageRouteCodec
    implements CCRouteCodec<_GeneratedExtraPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _GeneratedExtraPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _GeneratedExtraPageRouteArguments decode(CCEncodedRouteArguments input) {
    final _value_snapshot = input.extra == null
        ? throw CCRouteParameterError(
            "Route \"generated_route_fixture.extra\" parameter \"snapshot\" is invalid.",
          )
        : input.extra;
    if (_value_snapshot is! route_type_0.GeneratedSnapshot)
      throw CCRouteParameterError(
        "Route \"generated_route_fixture.extra\" parameter \"snapshot\" is invalid.",
      );
    return _GeneratedExtraPageRouteArguments(snapshot: _value_snapshot);
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_GeneratedExtraPageRouteArguments arguments) {
    return CCEncodedRouteArguments(
      path: {},
      query: {},
      extra: arguments.snapshot,
    );
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedGeneratedExtraPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedGeneratedExtraPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<bool> call({
    required route_type_0.GeneratedSnapshot snapshot,
  }) => _GeneratedExtraPageRoute.intent(snapshot: snapshot);
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterGeneratedExtraPageRoute(CCRegistry registry) =>
    registry.registerRoute(_GeneratedExtraPageRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ccrouterDescribeGeneratedExtraPageRoute() =>
    _GeneratedExtraPageRoute.definition;

/// Immutable arguments for route generated_route_fixture.prefixed; URI values remain typed.
final class _GeneratedPrefixedPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _GeneratedPrefixedPageRouteArguments({
    this.mode = route_type_0.GeneratedRouteMode.normal,
    this.payload,
  });

  /// query parameter mode for generated_route_fixture.prefixed.
  final route_type_0.GeneratedRouteMode mode;

  /// extra parameter payload for generated_route_fixture.prefixed.
  final route_type_0.GeneratedRoutePayload? payload;
}

/// Typed contract for generated_route_fixture.prefixed.
abstract final class _GeneratedPrefixedPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "generated_route_fixture.prefixed";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<route_type_0.GeneratedRouteResult> intent({
    route_type_0.GeneratedRouteMode mode =
        route_type_0.GeneratedRouteMode.normal,
    route_type_0.GeneratedRoutePayload? payload,
  }) => _GeneratedPrefixedPageRouteIntent(
    _GeneratedPrefixedPageRouteArguments(mode: mode, payload: payload),
  );

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<
        _GeneratedPrefixedPageRouteArguments,
        route_type_0.GeneratedRouteResult
      >(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/generated/prefixed",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _GeneratedPrefixedPageRouteCodec(),
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
}

/// Private data-only Intent carrying this route's typed result contract.
final class _GeneratedPrefixedPageRouteIntent
    implements CCRouteIntent<route_type_0.GeneratedRouteResult> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _GeneratedPrefixedPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _GeneratedPrefixedPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _GeneratedPrefixedPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _GeneratedPrefixedPageRouteCodec
    implements CCRouteCodec<_GeneratedPrefixedPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _GeneratedPrefixedPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _GeneratedPrefixedPageRouteArguments decode(CCEncodedRouteArguments input) {
    final _values_mode = input.query["mode"];
    if (_values_mode != null && _values_mode.length != 1)
      throw CCRouteParameterError(
        "Route \"generated_route_fixture.prefixed\" parameter \"mode\" is invalid.",
      );
    final _raw_mode = _values_mode?.single;
    final route_type_0.GeneratedRouteMode _value_mode = _raw_mode == null
        ? route_type_0.GeneratedRouteMode.normal
        : switch (_raw_mode) {
            "normal" => route_type_0.GeneratedRouteMode.normal,
            "alternate" => route_type_0.GeneratedRouteMode.alternate,
            _ => throw CCRouteParameterError(
              "Route \"generated_route_fixture.prefixed\" parameter \"mode\" is invalid.",
            ),
          };
    final _value_payload = input.extra == null ? null : input.extra;
    if (_value_payload is! route_type_0.GeneratedRoutePayload?)
      throw CCRouteParameterError(
        "Route \"generated_route_fixture.prefixed\" parameter \"payload\" is invalid.",
      );
    return _GeneratedPrefixedPageRouteArguments(
      mode: _value_mode,
      payload: _value_payload,
    );
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(
    _GeneratedPrefixedPageRouteArguments arguments,
  ) {
    return CCEncodedRouteArguments(
      path: {},
      query: {
        "mode": [EnumName(arguments.mode).name],
      },
      extra: arguments.payload,
    );
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedGeneratedPrefixedPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedGeneratedPrefixedPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<route_type_0.GeneratedRouteResult> call({
    route_type_0.GeneratedRouteMode mode =
        route_type_0.GeneratedRouteMode.normal,
    route_type_0.GeneratedRoutePayload? payload,
  }) => _GeneratedPrefixedPageRoute.intent(mode: mode, payload: payload);
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterGeneratedPrefixedPageRoute(CCRegistry registry) =>
    registry.registerRoute(_GeneratedPrefixedPageRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic>
ccrouterDescribeGeneratedPrefixedPageRoute() =>
    _GeneratedPrefixedPageRoute.definition;
