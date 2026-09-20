// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

part of '../home_page.dart';

// **************************************************************************
// _RouteGenerator
// **************************************************************************

/// Immutable arguments for route demo_navigation_lab.home; URI values remain typed.
final class _DemoNavigationHomePageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoNavigationHomePageRouteArguments();
}

/// CCRouter 全功能交互验证首页。
abstract final class _DemoNavigationHomePageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.home";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() => _DemoNavigationHomePageRouteIntent(
    _DemoNavigationHomePageRouteArguments(),
  );

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoNavigationHomePageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoNavigationHomePageRouteCodec(),
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

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoNavigationHomePage build(
    _DemoNavigationHomePageRouteArguments arguments,
  ) => DemoNavigationHomePage();
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DemoNavigationHomePageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoNavigationHomePageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoNavigationHomePageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoNavigationHomePageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoNavigationHomePageRouteCodec
    implements CCRouteCodec<_DemoNavigationHomePageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoNavigationHomePageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoNavigationHomePageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoNavigationHomePageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(
    _DemoNavigationHomePageRouteArguments arguments,
  ) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoNavigationHomePageRoute(CCRegistry registry) =>
    _DemoNavigationHomePageRoute.register(registry);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic>
ccrouterDescribeDemoNavigationHomePageRoute() =>
    _DemoNavigationHomePageRoute.definition;

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoNavigationHomePage ccrouterBuildDemoNavigationHomePageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoNavigationHomePageRoute.build(
  _DemoNavigationHomePageRoute.definition.codec.decode(arguments),
);
