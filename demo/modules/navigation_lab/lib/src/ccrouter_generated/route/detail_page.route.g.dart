// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';

/// Immutable arguments for route demo_navigation_lab.detail; URI values remain typed.
final class _DemoDetailPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  _DemoDetailPageRouteArguments({
    required this.id,
    this.title = "类型安全详情",
    List<String> tags = const [],
  }) : tags = List.unmodifiable(tags);

  /// path parameter id for demo_navigation_lab.detail.
  final int id;

  /// query parameter title for demo_navigation_lab.detail.
  final String title;

  /// query parameter tags for demo_navigation_lab.detail.
  final List<String> tags;
}

/// 验证类型安全参数、Query 集合、多 Path、完整 URL、Scheme 与返回值。
abstract final class _DemoDetailPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.detail";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<String> intent({
    required int id,
    String title = "类型安全详情",
    List<String> tags = const [],
  }) => _DemoDetailPageRouteIntent(
    _DemoDetailPageRouteArguments(id: id, title: title, tags: tags),
  );

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoDetailPageRouteArguments, String>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/detail/:id",
            primary: true,
            constraints: const <String, String>{"id": "\\d+"},
          ),
          const CCPathPattern(
            "/lab/item/:id",
            primary: false,
            constraints: const <String, String>{},
          ),
          const CCUriPattern(
            "ccrouter://lab/detail/:id",
            primary: false,
            constraints: const <String, String>{},
          ),
          const CCUriPattern(
            "https://ccrouter.example/lab/detail/:id",
            primary: false,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoDetailPageRouteCodec(),
        deepLink: CCDeepLinkPolicy.enabled,
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
final class _DemoDetailPageRouteIntent implements CCRouteIntent<String> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoDetailPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoDetailPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoDetailPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoDetailPageRouteCodec
    implements CCRouteCodec<_DemoDetailPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoDetailPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoDetailPageRouteArguments decode(CCEncodedRouteArguments input) {
    final _raw_id = input.path["id"];
    final int _value_id = _raw_id == null
        ? throw CCRouteParameterError(
            "Route \"demo_navigation_lab.detail\" parameter \"id\" is invalid.",
          )
        : (int.tryParse(_raw_id) ??
              (throw CCRouteParameterError(
                "Route \"demo_navigation_lab.detail\" parameter \"id\" is invalid.",
              )));
    final _values_title = input.query["title"];
    if (_values_title != null && _values_title.length != 1)
      throw CCRouteParameterError(
        "Route \"demo_navigation_lab.detail\" parameter \"title\" is invalid.",
      );
    final _raw_title = _values_title?.single;
    final String _value_title = _raw_title == null ? "类型安全详情" : _raw_title;
    final _values_tags = input.query["tags"];
    if (_values_tags != null && _values_tags.isEmpty)
      throw CCRouteParameterError(
        "Route \"demo_navigation_lab.detail\" parameter \"tags\" is invalid.",
      );
    final List<String> _value_tags = _values_tags == null
        ? const []
        : List<String>.unmodifiable(_values_tags.map((raw_tags) => raw_tags));
    return _DemoDetailPageRouteArguments(
      id: _value_id,
      title: _value_title,
      tags: _value_tags,
    );
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoDetailPageRouteArguments arguments) {
    return CCEncodedRouteArguments(
      path: {"id": arguments.id.toString()},
      query: {
        "title": [arguments.title],
        if (arguments.tags.isNotEmpty)
          "tags": [for (final value in arguments.tags) value],
      },
      extra: null,
    );
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoDetailPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoDetailPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<String> call({
    required int id,
    String title = "类型安全详情",
    List<String> tags = const [],
  }) => _DemoDetailPageRoute.intent(id: id, title: title, tags: tags);
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoDetailPageRoute(CCRegistry registry) =>
    registry.registerRoute(_DemoDetailPageRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ccrouterDescribeDemoDetailPageRoute() =>
    _DemoDetailPageRoute.definition;
