// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';

/// Immutable arguments for route demo_navigation_lab.presentation.fade; URI values remain typed.
final class _DemoFadePageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoFadePageRouteArguments();
}

/// Typed contract for demo_navigation_lab.presentation.fade.
abstract final class _DemoFadePageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.presentation.fade";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _DemoFadePageRouteIntent(_DemoFadePageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoFadePageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/presentation/fade",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoFadePageRouteCodec(),
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
final class _DemoFadePageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoFadePageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoFadePageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoFadePageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoFadePageRouteCodec
    implements CCRouteCodec<_DemoFadePageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoFadePageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoFadePageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoFadePageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoFadePageRouteArguments arguments) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoFadePageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoFadePageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _DemoFadePageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoFadePageRoute(CCRegistry registry) =>
    registry.registerRoute(_DemoFadePageRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ccrouterDescribeDemoFadePageRoute() =>
    _DemoFadePageRoute.definition;

/// Immutable arguments for route demo_navigation_lab.presentation.scale; URI values remain typed.
final class _DemoScalePageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoScalePageRouteArguments();
}

/// Typed contract for demo_navigation_lab.presentation.scale.
abstract final class _DemoScalePageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.presentation.scale";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _DemoScalePageRouteIntent(_DemoScalePageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoScalePageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/presentation/scale",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoScalePageRouteCodec(),
        deepLink: CCDeepLinkPolicy.disabled,
        presentation: const CCPagePresentation(
          routeType: CCPageRouteType.platformDefault,
          transition: CCPageTransitionType.scale,
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
final class _DemoScalePageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoScalePageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoScalePageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoScalePageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoScalePageRouteCodec
    implements CCRouteCodec<_DemoScalePageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoScalePageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoScalePageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoScalePageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoScalePageRouteArguments arguments) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoScalePageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoScalePageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _DemoScalePageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoScalePageRoute(CCRegistry registry) =>
    registry.registerRoute(_DemoScalePageRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ccrouterDescribeDemoScalePageRoute() =>
    _DemoScalePageRoute.definition;

/// Immutable arguments for route demo_navigation_lab.presentation.cupertino; URI values remain typed.
final class _DemoCupertinoPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoCupertinoPageRouteArguments();
}

/// Typed contract for demo_navigation_lab.presentation.cupertino.
abstract final class _DemoCupertinoPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.presentation.cupertino";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _DemoCupertinoPageRouteIntent(_DemoCupertinoPageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoCupertinoPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/presentation/cupertino",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoCupertinoPageRouteCodec(),
        deepLink: CCDeepLinkPolicy.disabled,
        presentation: const CCPagePresentation(
          routeType: CCPageRouteType.cupertino,
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
final class _DemoCupertinoPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoCupertinoPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoCupertinoPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoCupertinoPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoCupertinoPageRouteCodec
    implements CCRouteCodec<_DemoCupertinoPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoCupertinoPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoCupertinoPageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoCupertinoPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoCupertinoPageRouteArguments arguments) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoCupertinoPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoCupertinoPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _DemoCupertinoPageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoCupertinoPageRoute(CCRegistry registry) =>
    registry.registerRoute(_DemoCupertinoPageRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ccrouterDescribeDemoCupertinoPageRoute() =>
    _DemoCupertinoPageRoute.definition;

/// Immutable arguments for route demo_navigation_lab.presentation.bottom_page; URI values remain typed.
final class _DemoBottomPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoBottomPageRouteArguments();
}

/// 普通全屏 Page 从底部滑入，不是 BottomSheet。
abstract final class _DemoBottomPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.presentation.bottom_page";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _DemoBottomPageRouteIntent(_DemoBottomPageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoBottomPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/presentation/bottom-page",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoBottomPageRouteCodec(),
        deepLink: CCDeepLinkPolicy.disabled,
        presentation: const CCPagePresentation(
          routeType: CCPageRouteType.platformDefault,
          transition: CCPageTransitionType.slideFromBottom,
          opaque: true,
          fullscreenDialog: true,
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
final class _DemoBottomPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoBottomPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoBottomPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoBottomPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoBottomPageRouteCodec
    implements CCRouteCodec<_DemoBottomPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoBottomPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoBottomPageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoBottomPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoBottomPageRouteArguments arguments) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoBottomPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoBottomPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _DemoBottomPageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoBottomPageRoute(CCRegistry registry) =>
    registry.registerRoute(_DemoBottomPageRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ccrouterDescribeDemoBottomPageRoute() =>
    _DemoBottomPageRoute.definition;

/// Immutable arguments for route demo_navigation_lab.presentation.transparent; URI values remain typed.
final class _DemoTransparentPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoTransparentPageRouteArguments();
}

/// 用于海报分享预览的透明全屏 Page。
abstract final class _DemoTransparentPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.presentation.transparent";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _DemoTransparentPageRouteIntent(_DemoTransparentPageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoTransparentPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/presentation/transparent",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoTransparentPageRouteCodec(),
        deepLink: CCDeepLinkPolicy.disabled,
        presentation: const CCPagePresentation(
          routeType: CCPageRouteType.platformDefault,
          transition: CCPageTransitionType.slideFromBottom,
          opaque: false,
          fullscreenDialog: true,
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
final class _DemoTransparentPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoTransparentPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoTransparentPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoTransparentPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoTransparentPageRouteCodec
    implements CCRouteCodec<_DemoTransparentPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoTransparentPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoTransparentPageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoTransparentPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoTransparentPageRouteArguments arguments) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoTransparentPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoTransparentPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _DemoTransparentPageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoTransparentPageRoute(CCRegistry registry) =>
    registry.registerRoute(_DemoTransparentPageRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic>
ccrouterDescribeDemoTransparentPageRoute() =>
    _DemoTransparentPageRoute.definition;

/// Immutable arguments for route demo_navigation_lab.presentation.dialog; URI values remain typed.
final class _DemoDialogPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoDialogPageRouteArguments();
}

/// Typed contract for demo_navigation_lab.presentation.dialog.
abstract final class _DemoDialogPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.presentation.dialog";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<String> intent() =>
      _DemoDialogPageRouteIntent(_DemoDialogPageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoDialogPageRouteArguments, String>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/presentation/dialog",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoDialogPageRouteCodec(),
        deepLink: CCDeepLinkPolicy.disabled,
        presentation: const CCDialogPresentation(
          routeType: CCDialogRouteType.material,
          barrierDismissible: true,
          useSafeArea: true,
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
final class _DemoDialogPageRouteIntent implements CCRouteIntent<String> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoDialogPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoDialogPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoDialogPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoDialogPageRouteCodec
    implements CCRouteCodec<_DemoDialogPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoDialogPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoDialogPageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoDialogPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoDialogPageRouteArguments arguments) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoDialogPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoDialogPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<String> call() => _DemoDialogPageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoDialogPageRoute(CCRegistry registry) =>
    registry.registerRoute(_DemoDialogPageRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic> ccrouterDescribeDemoDialogPageRoute() =>
    _DemoDialogPageRoute.definition;

/// Immutable arguments for route demo_navigation_lab.presentation.sheet; URI values remain typed.
final class _DemoBottomSheetPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoBottomSheetPageRouteArguments();
}

/// Typed contract for demo_navigation_lab.presentation.sheet.
abstract final class _DemoBottomSheetPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.presentation.sheet";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<String> intent() =>
      _DemoBottomSheetPageRouteIntent(_DemoBottomSheetPageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoBottomSheetPageRouteArguments, String>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/presentation/sheet",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoBottomSheetPageRouteCodec(),
        deepLink: CCDeepLinkPolicy.disabled,
        presentation: const CCModalBottomSheetPresentation(
          isDismissible: true,
          enableDrag: true,
          isScrollControlled: true,
          showDragHandle: true,
          useSafeArea: true,
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
final class _DemoBottomSheetPageRouteIntent implements CCRouteIntent<String> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoBottomSheetPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoBottomSheetPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoBottomSheetPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoBottomSheetPageRouteCodec
    implements CCRouteCodec<_DemoBottomSheetPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoBottomSheetPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoBottomSheetPageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoBottomSheetPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoBottomSheetPageRouteArguments arguments) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoBottomSheetPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoBottomSheetPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<String> call() => _DemoBottomSheetPageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoBottomSheetPageRoute(CCRegistry registry) =>
    registry.registerRoute(_DemoBottomSheetPageRoute.definition);

/// Package-internal route definition bridge used by Host generation.
CCRouteDefinition<dynamic, dynamic>
ccrouterDescribeDemoBottomSheetPageRoute() =>
    _DemoBottomSheetPageRoute.definition;
