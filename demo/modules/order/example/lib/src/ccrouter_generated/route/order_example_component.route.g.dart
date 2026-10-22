// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';

/// Immutable arguments for route demo_order_example.home; URI values remain typed.
final class _OrderExampleHomePageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _OrderExampleHomePageRouteArguments();
}

/// Standalone Order component development home.
abstract final class _OrderExampleHomePageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_order_example.home";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _OrderExampleHomePageRouteIntent(_OrderExampleHomePageRouteArguments());
}

/// Generated definition bridge for registration and page binding.
///
/// This symbol is intentionally kept out of stable Consumer barrels.
/// Business code creates [_OrderExampleHomePageRoute] intents. Generated owner glue uses
/// this binding to register and decode the route.
abstract final class _OrderExampleHomePageRouteContractBinding {
  /// The typed route definition consumed by generated owner glue.
  static final definition =
      CCRouteDefinition<_OrderExampleHomePageRouteArguments, void>(
        routeId: _OrderExampleHomePageRoute.id,
        patterns: const [
          const CCPathPattern(
            "/",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _OrderExampleHomePageRouteCodec(),
        deepLink: CCDeepLinkPolicy.disabled,
        presentation: const CCPagePresentation(
          routeType: CCPageRouteType.platformDefault,
          transition: CCPageTransitionType.none,
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
final class _OrderExampleHomePageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _OrderExampleHomePageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _OrderExampleHomePageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _OrderExampleHomePageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _OrderExampleHomePageRouteCodec
    implements CCRouteCodec<_OrderExampleHomePageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _OrderExampleHomePageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _OrderExampleHomePageRouteArguments decode(CCRouteCodecValues input) {
    return _OrderExampleHomePageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCRouteCodecValues encode(_OrderExampleHomePageRouteArguments arguments) {
    return CCRouteCodecValues(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedOrderExampleHomePageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedOrderExampleHomePageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _OrderExampleHomePageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterOrderExampleHomePageRoute(CCRegistry registry) => registry
    .registerRoute(_OrderExampleHomePageRouteContractBinding.definition);

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<_OrderExampleHomePageRouteArguments, void>
ccrouterDescribeOrderExampleHomePageRoute() =>
    _OrderExampleHomePageRouteContractBinding.definition;
