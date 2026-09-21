// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';

/// Immutable arguments for route demo_navigation_lab.stack; URI values remain typed.
final class _DemoStackPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoStackPageRouteArguments({required this.level});

  /// path parameter level for demo_navigation_lab.stack.
  final int level;
}

/// 交互验证 Push、Replace、Pop、Go 与 Reset。
abstract final class _DemoStackPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.stack";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<String> intent({required int level}) =>
      _DemoStackPageRouteIntent(_DemoStackPageRouteArguments(level: level));

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoStackPageRouteArguments, String>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/stack/:level",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoStackPageRouteCodec(),
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
final class _DemoStackPageRouteIntent implements CCRouteIntent<String> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoStackPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoStackPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoStackPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoStackPageRouteCodec
    implements CCRouteCodec<_DemoStackPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoStackPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoStackPageRouteArguments decode(CCEncodedRouteArguments input) {
    final _raw_level = input.path["level"];
    final int _value_level = _raw_level == null
        ? throw CCRouteParameterError(
            "Route \"demo_navigation_lab.stack\" parameter \"level\" is invalid.",
          )
        : (int.tryParse(_raw_level) ??
              (throw CCRouteParameterError(
                "Route \"demo_navigation_lab.stack\" parameter \"level\" is invalid.",
              )));
    return _DemoStackPageRouteArguments(level: _value_level);
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoStackPageRouteArguments arguments) {
    return CCEncodedRouteArguments(
      path: {"level": arguments.level.toString()},
      query: {},
      extra: null,
    );
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoStackPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoStackPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<String> call({required int level}) =>
      _DemoStackPageRoute.intent(level: level);
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoStackPageRoute(CCRegistry registry) =>
    registry.registerRoute(_DemoStackPageRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ccrouterDescribeDemoStackPageRoute() =>
    _DemoStackPageRoute.definition;
