// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';

/// Immutable arguments for route demo_navigation_lab.failure; URI values remain typed.
final class _DemoFailurePageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoFailurePageRouteArguments({
    required this.stage,
    required this.reason,
    required this.errorType,
    this.initialRouteId,
    this.routeId,
  });

  /// query parameter stage for demo_navigation_lab.failure.
  final String stage;

  /// query parameter reason for demo_navigation_lab.failure.
  final String reason;

  /// query parameter errorType for demo_navigation_lab.failure.
  final String errorType;

  /// query parameter initialRouteId for demo_navigation_lab.failure.
  final String? initialRouteId;

  /// query parameter routeId for demo_navigation_lab.failure.
  final String? routeId;
}

/// 展示标准导航失败经 Host Failure Policy 恢复后的安全页面。
abstract final class _DemoFailurePageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.failure";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent({
    required String stage,
    required String reason,
    required String errorType,
    String? initialRouteId,
    String? routeId,
  }) => _DemoFailurePageRouteIntent(
    _DemoFailurePageRouteArguments(
      stage: stage,
      reason: reason,
      errorType: errorType,
      initialRouteId: initialRouteId,
      routeId: routeId,
    ),
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
    final _values_reason = input.query["reason"];
    if (_values_reason != null && _values_reason.length != 1)
      throw CCRouteParameterError(
        "Route \"demo_navigation_lab.failure\" parameter \"reason\" is invalid.",
      );
    final _raw_reason = _values_reason?.single;
    final String _value_reason = _raw_reason == null
        ? throw CCRouteParameterError(
            "Route \"demo_navigation_lab.failure\" parameter \"reason\" is invalid.",
          )
        : _raw_reason;
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
    final _values_initialRouteId = input.query["initialRouteId"];
    if (_values_initialRouteId != null && _values_initialRouteId.length != 1)
      throw CCRouteParameterError(
        "Route \"demo_navigation_lab.failure\" parameter \"initialRouteId\" is invalid.",
      );
    final _raw_initialRouteId = _values_initialRouteId?.single;
    final String? _value_initialRouteId = _raw_initialRouteId == null
        ? null
        : _raw_initialRouteId;
    final _values_routeId = input.query["routeId"];
    if (_values_routeId != null && _values_routeId.length != 1)
      throw CCRouteParameterError(
        "Route \"demo_navigation_lab.failure\" parameter \"routeId\" is invalid.",
      );
    final _raw_routeId = _values_routeId?.single;
    final String? _value_routeId = _raw_routeId == null ? null : _raw_routeId;
    return _DemoFailurePageRouteArguments(
      stage: _value_stage,
      reason: _value_reason,
      errorType: _value_errorType,
      initialRouteId: _value_initialRouteId,
      routeId: _value_routeId,
    );
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoFailurePageRouteArguments arguments) {
    return CCEncodedRouteArguments(
      path: {},
      query: {
        "stage": [arguments.stage],
        "reason": [arguments.reason],
        "errorType": [arguments.errorType],
        if (arguments.initialRouteId != null)
          "initialRouteId": [arguments.initialRouteId!],
        if (arguments.routeId != null) "routeId": [arguments.routeId!],
      },
      extra: null,
    );
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoFailurePageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoFailurePageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call({
    required String stage,
    required String reason,
    required String errorType,
    String? initialRouteId,
    String? routeId,
  }) => _DemoFailurePageRoute.intent(
    stage: stage,
    reason: reason,
    errorType: errorType,
    initialRouteId: initialRouteId,
    routeId: routeId,
  );
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoFailurePageRoute(CCRegistry registry) =>
    registry.registerRoute(_DemoFailurePageRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ccrouterDescribeDemoFailurePageRoute() =>
    _DemoFailurePageRoute.definition;
