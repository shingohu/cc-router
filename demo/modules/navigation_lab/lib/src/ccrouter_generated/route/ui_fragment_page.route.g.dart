// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';

/// Immutable arguments for route demo_navigation_lab.ui_fragments; URI values remain typed.
final class _UIFragmentLabPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _UIFragmentLabPageRouteArguments();
}

/// 跨组件 UI Fragment、保活、输入更新与资源释放验证。
abstract final class _UIFragmentLabPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.ui_fragments";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _UIFragmentLabPageRouteIntent(_UIFragmentLabPageRouteArguments());
}

/// Generated definition bridge for registration and page binding.
///
/// This symbol is intentionally kept out of stable Consumer barrels.
/// Business code creates [_UIFragmentLabPageRoute] intents. Generated owner glue uses
/// this binding to register and decode the route.
abstract final class _UIFragmentLabPageRouteContractBinding {
  /// The typed route definition consumed by generated owner glue.
  static final definition =
      CCRouteDefinition<_UIFragmentLabPageRouteArguments, void>(
        routeId: _UIFragmentLabPageRoute.id,
        patterns: const [
          const CCPathPattern(
            "/ui-fragments",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _UIFragmentLabPageRouteCodec(),
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
final class _UIFragmentLabPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _UIFragmentLabPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _UIFragmentLabPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _UIFragmentLabPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _UIFragmentLabPageRouteCodec
    implements CCRouteCodec<_UIFragmentLabPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _UIFragmentLabPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _UIFragmentLabPageRouteArguments decode(CCRouteCodecValues input) {
    return _UIFragmentLabPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCRouteCodecValues encode(_UIFragmentLabPageRouteArguments arguments) {
    return CCRouteCodecValues(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedUIFragmentLabPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedUIFragmentLabPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _UIFragmentLabPageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterUIFragmentLabPageRoute(CCRegistry registry) =>
    registry.registerRoute(_UIFragmentLabPageRouteContractBinding.definition);

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<_UIFragmentLabPageRouteArguments, void>
ccrouterDescribeUIFragmentLabPageRoute() =>
    _UIFragmentLabPageRouteContractBinding.definition;
