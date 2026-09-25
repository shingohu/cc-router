// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';

/// Immutable arguments for route demo_navigation_lab.capabilities; URI values remain typed.
final class _DemoCapabilitiesPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoCapabilitiesPageRouteArguments();
}

/// Command、Event、初始化任务与 Service 生命周期交互实验页。
abstract final class _DemoCapabilitiesPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.capabilities";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _DemoCapabilitiesPageRouteIntent(_DemoCapabilitiesPageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoCapabilitiesPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/capabilities",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoCapabilitiesPageRouteCodec(),
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
final class _DemoCapabilitiesPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoCapabilitiesPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoCapabilitiesPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoCapabilitiesPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoCapabilitiesPageRouteCodec
    implements CCRouteCodec<_DemoCapabilitiesPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoCapabilitiesPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoCapabilitiesPageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoCapabilitiesPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(
    _DemoCapabilitiesPageRouteArguments arguments,
  ) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoCapabilitiesPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoCapabilitiesPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _DemoCapabilitiesPageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoCapabilitiesPageRoute(CCRegistry registry) =>
    registry.registerRoute(_DemoCapabilitiesPageRoute.definition);

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<_DemoCapabilitiesPageRouteArguments, void>
ccrouterDescribeDemoCapabilitiesPageRoute() =>
    _DemoCapabilitiesPageRoute.definition;
