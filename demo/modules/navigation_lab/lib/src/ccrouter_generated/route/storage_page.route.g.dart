// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';

/// Immutable arguments for route demo_navigation_lab.storage; URI values remain typed.
final class _DemoStoragePageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoStoragePageRouteArguments();
}

/// 基本类型、JSON Map 和受控存储命名空间示例。
abstract final class _DemoStoragePageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.storage";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _DemoStoragePageRouteIntent(_DemoStoragePageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoStoragePageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/storage",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoStoragePageRouteCodec(),
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
final class _DemoStoragePageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoStoragePageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoStoragePageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoStoragePageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoStoragePageRouteCodec
    implements CCRouteCodec<_DemoStoragePageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoStoragePageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoStoragePageRouteArguments decode(CCRouteCodecValues input) {
    return _DemoStoragePageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCRouteCodecValues encode(_DemoStoragePageRouteArguments arguments) {
    return CCRouteCodecValues(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoStoragePageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoStoragePageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _DemoStoragePageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoStoragePageRoute(CCRegistry registry) =>
    registry.registerRoute(_DemoStoragePageRoute.definition);

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<_DemoStoragePageRouteArguments, void>
ccrouterDescribeDemoStoragePageRoute() => _DemoStoragePageRoute.definition;
