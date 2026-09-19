// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

part of 'annotated_routes.dart';

// **************************************************************************
// _RouteGenerator
// **************************************************************************

/// Immutable arguments for route fixture.detail; URI values remain typed.
final class _DetailPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DetailPageRouteArguments({
    required this.id,
    this.search,
    this.tab = DetailTab.summary,
    this.enabled = false,
    this.ratio = 1.0,
    this.snapshot,
  });

  /// path parameter id for fixture.detail.
  final int id;

  /// query parameter text for fixture.detail.
  final String? search;

  /// query parameter tab for fixture.detail.
  final DetailTab tab;

  /// query parameter enabled for fixture.detail.
  final bool enabled;

  /// query parameter ratio for fixture.detail.
  final double ratio;

  /// extra parameter snapshot for fixture.detail.
  final Snapshot? snapshot;
}

/// A typed detail route.
/// Includes safe defaults.
abstract final class _DetailPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "fixture.detail";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<String> intent({
    required int id,
    String? search,
    DetailTab tab = DetailTab.summary,
    bool enabled = false,
    double ratio = 1.0,
    Snapshot? snapshot,
  }) => _DetailPageRouteIntent(
    _DetailPageRouteArguments(
      id: id,
      search: search,
      tab: tab,
      enabled: enabled,
      ratio: ratio,
      snapshot: snapshot,
    ),
  );

  /// Component-owned definition; registration does not select a backend.
  static final definition =
      CCRouteDefinition<_DetailPageRouteArguments, String>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/detail/:id",
            primary: true,
            constraints: const <String, String>{"id": "\\d+"},
          ),
          const CCPathPattern(
            "/legacy/:id",
            primary: false,
            constraints: const <String, String>{},
          ),
          const CCUriPattern(
            "sample://detail/:id",
            primary: false,
            constraints: const <String, String>{},
          ),
          const CCRegexPattern("/old/(?<id>\\d+)"),
        ],
        codec: const _DetailPageRouteCodec(),
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
          routeKind: CCRouteKind.page,
        ),
        interceptorIds: const ["fixture.auth"],
        description: "A typed detail route.\nIncludes safe defaults.",
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DetailPage build(_DetailPageRouteArguments arguments) => DetailPage(
    id: arguments.id,
    search: arguments.search,
    tab: arguments.tab,
    enabled: arguments.enabled,
    ratio: arguments.ratio,
    snapshot: arguments.snapshot,
  );
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DetailPageRouteIntent implements CCRouteIntent<String> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DetailPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DetailPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DetailPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DetailPageRouteCodec
    implements CCRouteCodec<_DetailPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DetailPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating a page.
  @override
  _DetailPageRouteArguments decode(CCEncodedRouteArguments input) {
    double _parse_ratio(String raw) {
      final value = double.tryParse(raw);
      if (value == null || !value.isFinite) {
        throw CCRouteParameterError(
          "Route \"fixture.detail\" parameter \"ratio\" must be finite.",
        );
      }
      return value;
    }

    final _raw_id = input.path["id"];
    final int _value_id = _raw_id == null
        ? throw CCRouteParameterError(
            "Route \"fixture.detail\" parameter \"id\" is invalid.",
          )
        : (int.tryParse(_raw_id) ??
              (throw CCRouteParameterError(
                "Route \"fixture.detail\" parameter \"id\" is invalid.",
              )));
    final _values_search = input.query["text"];
    if (_values_search != null && _values_search.length != 1)
      throw CCRouteParameterError(
        "Route \"fixture.detail\" parameter \"text\" is invalid.",
      );
    final _raw_search = _values_search?.single;
    final String? _value_search = _raw_search == null ? null : _raw_search;
    final _values_tab = input.query["tab"];
    if (_values_tab != null && _values_tab.length != 1)
      throw CCRouteParameterError(
        "Route \"fixture.detail\" parameter \"tab\" is invalid.",
      );
    final _raw_tab = _values_tab?.single;
    final DetailTab _value_tab = _raw_tab == null
        ? DetailTab.summary
        : switch (_raw_tab) {
            "summary" => DetailTab.summary,
            "items" => DetailTab.items,
            _ => throw CCRouteParameterError(
              "Route \"fixture.detail\" parameter \"tab\" is invalid.",
            ),
          };
    final _values_enabled = input.query["enabled"];
    if (_values_enabled != null && _values_enabled.length != 1)
      throw CCRouteParameterError(
        "Route \"fixture.detail\" parameter \"enabled\" is invalid.",
      );
    final _raw_enabled = _values_enabled?.single;
    final bool _value_enabled = _raw_enabled == null
        ? false
        : switch (_raw_enabled) {
            "true" => true,
            "false" => false,
            _ => throw CCRouteParameterError(
              "Route \"fixture.detail\" parameter \"enabled\" is invalid.",
            ),
          };
    final _values_ratio = input.query["ratio"];
    if (_values_ratio != null && _values_ratio.length != 1)
      throw CCRouteParameterError(
        "Route \"fixture.detail\" parameter \"ratio\" is invalid.",
      );
    final _raw_ratio = _values_ratio?.single;
    final double _value_ratio = _raw_ratio == null
        ? 1.0
        : _parse_ratio(_raw_ratio);
    final _value_snapshot = input.extra == null ? null : input.extra;
    if (_value_snapshot is! Snapshot?)
      throw CCRouteParameterError(
        "Route \"fixture.detail\" parameter \"snapshot\" is invalid.",
      );
    return _DetailPageRouteArguments(
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
  CCEncodedRouteArguments encode(_DetailPageRouteArguments arguments) {
    if (!arguments.ratio.isFinite)
      throw CCRouteParameterError(
        "Route \"fixture.detail\" parameter \"ratio\" must be finite.",
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

/// Immutable arguments for route fixture.internal; URI values remain typed.
final class _InternalPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _InternalPageRouteArguments();
}

/// Typed contract for fixture.internal.
abstract final class _InternalPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "fixture.internal";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _InternalPageRouteIntent(_InternalPageRouteArguments());

  /// Component-owned definition; registration does not select a backend.
  static final definition =
      CCRouteDefinition<_InternalPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/internal",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _InternalPageRouteCodec(),
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
          routeKind: CCRouteKind.page,
        ),
        interceptorIds: const [],
        description: null,
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static _InternalPage build(_InternalPageRouteArguments arguments) =>
      _InternalPage();
}

/// Private data-only Intent carrying this route's typed result contract.
final class _InternalPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _InternalPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _InternalPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _InternalPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _InternalPageRouteCodec
    implements CCRouteCodec<_InternalPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _InternalPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating a page.
  @override
  _InternalPageRouteArguments decode(CCEncodedRouteArguments input) {
    return _InternalPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_InternalPageRouteArguments arguments) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Immutable arguments for route fixture.positional; URI values remain typed.
final class _PositionalPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _PositionalPageRouteArguments({
    required this.value,
    this.input = 'default',
  });

  /// path parameter value for fixture.positional.
  final String value;

  /// query parameter input for fixture.positional.
  final String input;
}

/// Typed contract for fixture.positional.
abstract final class _PositionalPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "fixture.positional";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<int> intent({
    required String value,
    String input = 'default',
  }) => _PositionalPageRouteIntent(
    _PositionalPageRouteArguments(value: value, input: input),
  );

  /// Component-owned definition; registration does not select a backend.
  static final definition =
      CCRouteDefinition<_PositionalPageRouteArguments, int>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/position/:value",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _PositionalPageRouteCodec(),
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
          routeKind: CCRouteKind.page,
        ),
        interceptorIds: const [],
        description: null,
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static PositionalPage build(_PositionalPageRouteArguments arguments) =>
      PositionalPage(arguments.value, arguments.input);
}

/// Private data-only Intent carrying this route's typed result contract.
final class _PositionalPageRouteIntent implements CCRouteIntent<int> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _PositionalPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _PositionalPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _PositionalPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _PositionalPageRouteCodec
    implements CCRouteCodec<_PositionalPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _PositionalPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating a page.
  @override
  _PositionalPageRouteArguments decode(CCEncodedRouteArguments input) {
    final _raw_value = input.path["value"];
    final String _value_value = _raw_value == null
        ? throw CCRouteParameterError(
            "Route \"fixture.positional\" parameter \"value\" is invalid.",
          )
        : _raw_value;
    final _values_input = input.query["input"];
    if (_values_input != null && _values_input.length != 1)
      throw CCRouteParameterError(
        "Route \"fixture.positional\" parameter \"input\" is invalid.",
      );
    final _raw_input = _values_input?.single;
    final String _value_input = _raw_input == null ? 'default' : _raw_input;
    return _PositionalPageRouteArguments(
      value: _value_value,
      input: _value_input,
    );
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_PositionalPageRouteArguments arguments) {
    return CCEncodedRouteArguments(
      path: {"value": arguments.value},
      query: {
        "input": [arguments.input],
      },
      extra: null,
    );
  }
}

/// Immutable arguments for route fixture.extra; URI values remain typed.
final class _ExtraPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _ExtraPageRouteArguments({required this.snapshot});

  /// extra parameter snapshot for fixture.extra.
  final Snapshot snapshot;
}

/// Typed contract for fixture.extra.
abstract final class _ExtraPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "fixture.extra";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<bool> intent({required Snapshot snapshot}) =>
      _ExtraPageRouteIntent(_ExtraPageRouteArguments(snapshot: snapshot));

  /// Component-owned definition; registration does not select a backend.
  static final definition = CCRouteDefinition<_ExtraPageRouteArguments, bool>(
    routeId: id,
    patterns: const [
      const CCPathPattern(
        "/extra",
        primary: true,
        constraints: const <String, String>{},
      ),
    ],
    codec: const _ExtraPageRouteCodec(),
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
      routeKind: CCRouteKind.page,
    ),
    interceptorIds: const [],
    description: null,
  );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static ExtraPage build(_ExtraPageRouteArguments arguments) =>
      ExtraPage(snapshot: arguments.snapshot);
}

/// Private data-only Intent carrying this route's typed result contract.
final class _ExtraPageRouteIntent implements CCRouteIntent<bool> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _ExtraPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _ExtraPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _ExtraPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _ExtraPageRouteCodec
    implements CCRouteCodec<_ExtraPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _ExtraPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating a page.
  @override
  _ExtraPageRouteArguments decode(CCEncodedRouteArguments input) {
    final _value_snapshot = input.extra == null
        ? throw CCRouteParameterError(
            "Route \"fixture.extra\" parameter \"snapshot\" is invalid.",
          )
        : input.extra;
    if (_value_snapshot is! Snapshot)
      throw CCRouteParameterError(
        "Route \"fixture.extra\" parameter \"snapshot\" is invalid.",
      );
    return _ExtraPageRouteArguments(snapshot: _value_snapshot);
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_ExtraPageRouteArguments arguments) {
    return CCEncodedRouteArguments(
      path: {},
      query: {},
      extra: arguments.snapshot,
    );
  }
}

/// Immutable arguments for route fixture.prefixed; URI values remain typed.
final class _PrefixedPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _PrefixedPageRouteArguments({
    this.mode = types.Mode.normal,
    this.payload,
  });

  /// query parameter mode for fixture.prefixed.
  final types.Mode mode;

  /// extra parameter payload for fixture.prefixed.
  final types.Payload? payload;
}

/// Typed contract for fixture.prefixed.
abstract final class _PrefixedPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "fixture.prefixed";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<types.Result> intent({
    types.Mode mode = types.Mode.normal,
    types.Payload? payload,
  }) => _PrefixedPageRouteIntent(
    _PrefixedPageRouteArguments(mode: mode, payload: payload),
  );

  /// Component-owned definition; registration does not select a backend.
  static final definition =
      CCRouteDefinition<_PrefixedPageRouteArguments, types.Result>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/prefixed",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _PrefixedPageRouteCodec(),
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
          routeKind: CCRouteKind.page,
        ),
        interceptorIds: const [],
        description: null,
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static PrefixedPage build(_PrefixedPageRouteArguments arguments) =>
      PrefixedPage(mode: arguments.mode, payload: arguments.payload);
}

/// Private data-only Intent carrying this route's typed result contract.
final class _PrefixedPageRouteIntent implements CCRouteIntent<types.Result> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _PrefixedPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _PrefixedPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _PrefixedPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _PrefixedPageRouteCodec
    implements CCRouteCodec<_PrefixedPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _PrefixedPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating a page.
  @override
  _PrefixedPageRouteArguments decode(CCEncodedRouteArguments input) {
    final _values_mode = input.query["mode"];
    if (_values_mode != null && _values_mode.length != 1)
      throw CCRouteParameterError(
        "Route \"fixture.prefixed\" parameter \"mode\" is invalid.",
      );
    final _raw_mode = _values_mode?.single;
    final types.Mode _value_mode = _raw_mode == null
        ? types.Mode.normal
        : switch (_raw_mode) {
            "normal" => types.Mode.normal,
            "alternate" => types.Mode.alternate,
            _ => throw CCRouteParameterError(
              "Route \"fixture.prefixed\" parameter \"mode\" is invalid.",
            ),
          };
    final _value_payload = input.extra == null ? null : input.extra;
    if (_value_payload is! types.Payload?)
      throw CCRouteParameterError(
        "Route \"fixture.prefixed\" parameter \"payload\" is invalid.",
      );
    return _PrefixedPageRouteArguments(
      mode: _value_mode,
      payload: _value_payload,
    );
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_PrefixedPageRouteArguments arguments) {
    return CCEncodedRouteArguments(
      path: {},
      query: {
        "mode": [EnumName(arguments.mode).name],
      },
      extra: arguments.payload,
    );
  }
}
