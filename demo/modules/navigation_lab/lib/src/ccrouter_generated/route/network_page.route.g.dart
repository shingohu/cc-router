// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';

/// Immutable arguments for route demo_navigation_lab.network; URI values remain typed.
final class _DemoNetworkPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoNetworkPageRouteArguments();
}

/// 动态 API 环境、Header、授权和网络拦截器示例。
abstract final class _DemoNetworkPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.network";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _DemoNetworkPageRouteIntent(_DemoNetworkPageRouteArguments());
}

/// Generated definition bridge for registration and page binding.
///
/// This symbol is intentionally kept out of stable Consumer barrels.
/// Business code creates [_DemoNetworkPageRoute] intents. Generated owner glue uses
/// this binding to register and decode the route.
abstract final class _DemoNetworkPageRouteContractBinding {
  /// The typed route definition consumed by generated owner glue.
  static final definition =
      CCRouteDefinition<_DemoNetworkPageRouteArguments, void>(
        routeId: _DemoNetworkPageRoute.id,
        patterns: const [
          const CCPathPattern(
            "/lab/network",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoNetworkPageRouteCodec(),
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
final class _DemoNetworkPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoNetworkPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoNetworkPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoNetworkPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoNetworkPageRouteCodec
    implements CCRouteCodec<_DemoNetworkPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoNetworkPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoNetworkPageRouteArguments decode(CCRouteCodecValues input) {
    return _DemoNetworkPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCRouteCodecValues encode(_DemoNetworkPageRouteArguments arguments) {
    return CCRouteCodecValues(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoNetworkPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoNetworkPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _DemoNetworkPageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoNetworkPageRoute(CCRegistry registry) =>
    registry.registerRoute(_DemoNetworkPageRouteContractBinding.definition);

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<_DemoNetworkPageRouteArguments, void>
ccrouterDescribeDemoNetworkPageRoute() =>
    _DemoNetworkPageRouteContractBinding.definition;
