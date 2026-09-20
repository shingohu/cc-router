// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';

/// Immutable arguments for route demo_navigation_lab.lifecycle; URI values remain typed.
final class _DemoLifecyclePageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoLifecyclePageRouteArguments();
}

/// 同时验证 CCPageLifecycleMixin 与 Listener 的页面和 App 生命周期。
abstract final class _DemoLifecyclePageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.lifecycle";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _DemoLifecyclePageRouteIntent(_DemoLifecyclePageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoLifecyclePageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/lifecycle",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoLifecyclePageRouteCodec(),
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
final class _DemoLifecyclePageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoLifecyclePageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoLifecyclePageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoLifecyclePageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoLifecyclePageRouteCodec
    implements CCRouteCodec<_DemoLifecyclePageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoLifecyclePageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoLifecyclePageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoLifecyclePageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoLifecyclePageRouteArguments arguments) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoLifecyclePageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoLifecyclePageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _DemoLifecyclePageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoLifecyclePageRoute(CCRegistry registry) =>
    registry.registerRoute(_DemoLifecyclePageRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ccrouterDescribeDemoLifecyclePageRoute() =>
    _DemoLifecyclePageRoute.definition;
