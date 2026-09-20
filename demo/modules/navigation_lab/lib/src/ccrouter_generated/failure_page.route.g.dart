// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

part of '../failure_page.dart';

// **************************************************************************
// _RouteGenerator
// **************************************************************************

/// Immutable arguments for route demo_navigation_lab.failure; URI values remain typed.
final class _DemoFailurePageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoFailurePageRouteArguments({
    required this.stage,
    required this.errorType,
  });

  /// query parameter stage for demo_navigation_lab.failure.
  final String stage;

  /// query parameter errorType for demo_navigation_lab.failure.
  final String errorType;
}

/// 展示标准导航失败经 Host Failure Policy 恢复后的安全页面。
abstract final class _DemoFailurePageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.failure";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent({
    required String stage,
    required String errorType,
  }) => _DemoFailurePageRouteIntent(
    _DemoFailurePageRouteArguments(stage: stage, errorType: errorType),
  );

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoFailurePageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/failure",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoFailurePageRouteCodec(),
        deepLink: CCDeepLinkPolicy.disabled,
        presentation: const CCPagePresentation(
          routeType: CCPageRouteType.platformDefault,
          transition: CCPageTransitionType.fade,
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
  static DemoFailurePage build(_DemoFailurePageRouteArguments arguments) =>
      DemoFailurePage(stage: arguments.stage, errorType: arguments.errorType);
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DemoFailurePageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoFailurePageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoFailurePageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoFailurePageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoFailurePageRouteCodec
    implements CCRouteCodec<_DemoFailurePageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoFailurePageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoFailurePageRouteArguments decode(CCEncodedRouteArguments input) {
    final _values_stage = input.query["stage"];
    if (_values_stage != null && _values_stage.length != 1)
      throw CCRouteParameterError(
        "Route \"demo_navigation_lab.failure\" parameter \"stage\" is invalid.",
      );
    final _raw_stage = _values_stage?.single;
    final String _value_stage = _raw_stage == null
        ? throw CCRouteParameterError(
            "Route \"demo_navigation_lab.failure\" parameter \"stage\" is invalid.",
          )
        : _raw_stage;
    final _values_errorType = input.query["errorType"];
    if (_values_errorType != null && _values_errorType.length != 1)
      throw CCRouteParameterError(
        "Route \"demo_navigation_lab.failure\" parameter \"errorType\" is invalid.",
      );
    final _raw_errorType = _values_errorType?.single;
    final String _value_errorType = _raw_errorType == null
        ? throw CCRouteParameterError(
            "Route \"demo_navigation_lab.failure\" parameter \"errorType\" is invalid.",
          )
        : _raw_errorType;
    return _DemoFailurePageRouteArguments(
      stage: _value_stage,
      errorType: _value_errorType,
    );
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoFailurePageRouteArguments arguments) {
    return CCEncodedRouteArguments(
      path: {},
      query: {
        "stage": [arguments.stage],
        "errorType": [arguments.errorType],
      },
      extra: null,
    );
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoFailurePageRoute(CCRegistry registry) =>
    _DemoFailurePageRoute.register(registry);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ccrouterDescribeDemoFailurePageRoute() =>
    _DemoFailurePageRoute.definition;

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoFailurePage ccrouterBuildDemoFailurePageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoFailurePageRoute.build(
  _DemoFailurePageRoute.definition.codec.decode(arguments),
);
