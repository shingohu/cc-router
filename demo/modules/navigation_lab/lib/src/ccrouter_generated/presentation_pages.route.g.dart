// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

part of '../presentation_pages.dart';

// **************************************************************************
// _RouteGenerator
// **************************************************************************

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

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoFadePage build(_DemoFadePageRouteArguments arguments) =>
      DemoFadePage();
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

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoFadePageRoute(CCRegistry registry) =>
    _DemoFadePageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoFadePageRoute() {
  final definition = _DemoFadePageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoFadePage ccrouterBuildDemoFadePageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoFadePageRoute.build(
  _DemoFadePageRoute.definition.codec.decode(arguments),
);

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

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoScalePage build(_DemoScalePageRouteArguments arguments) =>
      DemoScalePage();
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

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoScalePageRoute(CCRegistry registry) =>
    _DemoScalePageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoScalePageRoute() {
  final definition = _DemoScalePageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoScalePage ccrouterBuildDemoScalePageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoScalePageRoute.build(
  _DemoScalePageRoute.definition.codec.decode(arguments),
);

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

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoCupertinoPage build(_DemoCupertinoPageRouteArguments arguments) =>
      DemoCupertinoPage();
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

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoCupertinoPageRoute(CCRegistry registry) =>
    _DemoCupertinoPageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoCupertinoPageRoute() {
  final definition = _DemoCupertinoPageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoCupertinoPage ccrouterBuildDemoCupertinoPageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoCupertinoPageRoute.build(
  _DemoCupertinoPageRoute.definition.codec.decode(arguments),
);

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

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoBottomPage build(_DemoBottomPageRouteArguments arguments) =>
      DemoBottomPage();
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

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoBottomPageRoute(CCRegistry registry) =>
    _DemoBottomPageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoBottomPageRoute() {
  final definition = _DemoBottomPageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoBottomPage ccrouterBuildDemoBottomPageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoBottomPageRoute.build(
  _DemoBottomPageRoute.definition.codec.decode(arguments),
);

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

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoTransparentPage build(
    _DemoTransparentPageRouteArguments arguments,
  ) => DemoTransparentPage();
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

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoTransparentPageRoute(CCRegistry registry) =>
    _DemoTransparentPageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoTransparentPageRoute() {
  final definition = _DemoTransparentPageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoTransparentPage ccrouterBuildDemoTransparentPageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoTransparentPageRoute.build(
  _DemoTransparentPageRoute.definition.codec.decode(arguments),
);

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

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoDialogPage build(_DemoDialogPageRouteArguments arguments) =>
      DemoDialogPage();
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

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoDialogPageRoute(CCRegistry registry) =>
    _DemoDialogPageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoDialogPageRoute() {
  final definition = _DemoDialogPageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoDialogPage ccrouterBuildDemoDialogPageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoDialogPageRoute.build(
  _DemoDialogPageRoute.definition.codec.decode(arguments),
);

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

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoBottomSheetPage build(
    _DemoBottomSheetPageRouteArguments arguments,
  ) => DemoBottomSheetPage();
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

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoBottomSheetPageRoute(CCRegistry registry) =>
    _DemoBottomSheetPageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoBottomSheetPageRoute() {
  final definition = _DemoBottomSheetPageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoBottomSheetPage ccrouterBuildDemoBottomSheetPageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoBottomSheetPageRoute.build(
  _DemoBottomSheetPageRoute.definition.codec.decode(arguments),
);
