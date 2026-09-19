// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

part of '../policy_pages.dart';

// **************************************************************************
// _RouteGenerator
// **************************************************************************

/// Immutable arguments for route demo_navigation_lab.proceed; URI values remain typed.
final class _DemoProceedPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoProceedPageRouteArguments();
}

/// 路由级拦截器放行示例。
abstract final class _DemoProceedPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.proceed";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _DemoProceedPageRouteIntent(_DemoProceedPageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoProceedPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/policy/proceed",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoProceedPageRouteCodec(),
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
        interceptorIds: const ["demo_navigation_lab.proceed"],
        popGuardIds: const [],
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoProceedPage build(_DemoProceedPageRouteArguments arguments) =>
      DemoProceedPage();
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DemoProceedPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoProceedPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoProceedPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoProceedPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoProceedPageRouteCodec
    implements CCRouteCodec<_DemoProceedPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoProceedPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoProceedPageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoProceedPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoProceedPageRouteArguments arguments) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoProceedPageRoute(CCRegistry registry) =>
    _DemoProceedPageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoProceedPageRoute() {
  final definition = _DemoProceedPageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoProceedPage ccrouterBuildDemoProceedPageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoProceedPageRoute.build(
  _DemoProceedPageRoute.definition.codec.decode(arguments),
);

/// Immutable arguments for route demo_navigation_lab.cancel; URI values remain typed.
final class _DemoCancelledPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoCancelledPageRouteArguments();
}

/// 路由级拦截器取消示例；页面正常情况下不会创建。
abstract final class _DemoCancelledPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.cancel";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _DemoCancelledPageRouteIntent(_DemoCancelledPageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoCancelledPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/policy/cancel",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoCancelledPageRouteCodec(),
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
        interceptorIds: const ["demo_navigation_lab.cancel"],
        popGuardIds: const [],
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoCancelledPage build(_DemoCancelledPageRouteArguments arguments) =>
      DemoCancelledPage();
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DemoCancelledPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoCancelledPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoCancelledPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoCancelledPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoCancelledPageRouteCodec
    implements CCRouteCodec<_DemoCancelledPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoCancelledPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoCancelledPageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoCancelledPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoCancelledPageRouteArguments arguments) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoCancelledPageRoute(CCRegistry registry) =>
    _DemoCancelledPageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoCancelledPageRoute() {
  final definition = _DemoCancelledPageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoCancelledPage ccrouterBuildDemoCancelledPageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoCancelledPageRoute.build(
  _DemoCancelledPageRoute.definition.codec.decode(arguments),
);

/// Immutable arguments for route demo_navigation_lab.redirect.source; URI values remain typed.
final class _DemoRedirectSourcePageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoRedirectSourcePageRouteArguments();
}

/// 路由级拦截器重定向源页面；页面正常情况下不会创建。
abstract final class _DemoRedirectSourcePageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.redirect.source";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() => _DemoRedirectSourcePageRouteIntent(
    _DemoRedirectSourcePageRouteArguments(),
  );

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoRedirectSourcePageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/policy/redirect-source",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoRedirectSourcePageRouteCodec(),
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
        interceptorIds: const ["demo_navigation_lab.redirect"],
        popGuardIds: const [],
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoRedirectSourcePage build(
    _DemoRedirectSourcePageRouteArguments arguments,
  ) => DemoRedirectSourcePage();
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DemoRedirectSourcePageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoRedirectSourcePageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoRedirectSourcePageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoRedirectSourcePageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoRedirectSourcePageRouteCodec
    implements CCRouteCodec<_DemoRedirectSourcePageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoRedirectSourcePageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoRedirectSourcePageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoRedirectSourcePageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(
    _DemoRedirectSourcePageRouteArguments arguments,
  ) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoRedirectSourcePageRoute(CCRegistry registry) =>
    _DemoRedirectSourcePageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoRedirectSourcePageRoute() {
  final definition = _DemoRedirectSourcePageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoRedirectSourcePage ccrouterBuildDemoRedirectSourcePageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoRedirectSourcePageRoute.build(
  _DemoRedirectSourcePageRoute.definition.codec.decode(arguments),
);

/// Immutable arguments for route demo_navigation_lab.redirect.target; URI values remain typed.
final class _DemoRedirectTargetPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoRedirectTargetPageRouteArguments();
}

/// 拦截器重定向后的目标页面。
abstract final class _DemoRedirectTargetPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.redirect.target";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() => _DemoRedirectTargetPageRouteIntent(
    _DemoRedirectTargetPageRouteArguments(),
  );

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoRedirectTargetPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/policy/redirect-target",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoRedirectTargetPageRouteCodec(),
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

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoRedirectTargetPage build(
    _DemoRedirectTargetPageRouteArguments arguments,
  ) => DemoRedirectTargetPage();
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DemoRedirectTargetPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoRedirectTargetPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoRedirectTargetPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoRedirectTargetPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoRedirectTargetPageRouteCodec
    implements CCRouteCodec<_DemoRedirectTargetPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoRedirectTargetPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoRedirectTargetPageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoRedirectTargetPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(
    _DemoRedirectTargetPageRouteArguments arguments,
  ) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoRedirectTargetPageRoute(CCRegistry registry) =>
    _DemoRedirectTargetPageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoRedirectTargetPageRoute() {
  final definition = _DemoRedirectTargetPageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoRedirectTargetPage ccrouterBuildDemoRedirectTargetPageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoRedirectTargetPageRoute.build(
  _DemoRedirectTargetPageRoute.definition.codec.decode(arguments),
);

/// Immutable arguments for route demo_navigation_lab.defer; URI values remain typed.
final class _DemoDeferredPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoDeferredPageRouteArguments();
}

/// 等待外部同意后恢复的 Deferred Navigation 示例。
abstract final class _DemoDeferredPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.defer";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _DemoDeferredPageRouteIntent(_DemoDeferredPageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoDeferredPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/policy/defer",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoDeferredPageRouteCodec(),
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
        interceptorIds: const ["demo_navigation_lab.defer"],
        popGuardIds: const [],
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoDeferredPage build(_DemoDeferredPageRouteArguments arguments) =>
      DemoDeferredPage();
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DemoDeferredPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoDeferredPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoDeferredPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoDeferredPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoDeferredPageRouteCodec
    implements CCRouteCodec<_DemoDeferredPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoDeferredPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoDeferredPageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoDeferredPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoDeferredPageRouteArguments arguments) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoDeferredPageRoute(CCRegistry registry) =>
    _DemoDeferredPageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoDeferredPageRoute() {
  final definition = _DemoDeferredPageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoDeferredPage ccrouterBuildDemoDeferredPageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoDeferredPageRoute.build(
  _DemoDeferredPageRoute.definition.codec.decode(arguments),
);

/// Immutable arguments for route demo_navigation_lab.timeout; URI values remain typed.
final class _DemoTimeoutPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoTimeoutPageRouteArguments();
}

/// 触发标准 Interceptor Timeout Error 的示例。
abstract final class _DemoTimeoutPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.timeout";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _DemoTimeoutPageRouteIntent(_DemoTimeoutPageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoTimeoutPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/policy/timeout",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoTimeoutPageRouteCodec(),
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
        interceptorIds: const ["demo_navigation_lab.timeout"],
        popGuardIds: const [],
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoTimeoutPage build(_DemoTimeoutPageRouteArguments arguments) =>
      DemoTimeoutPage();
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DemoTimeoutPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoTimeoutPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoTimeoutPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoTimeoutPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoTimeoutPageRouteCodec
    implements CCRouteCodec<_DemoTimeoutPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoTimeoutPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoTimeoutPageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoTimeoutPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoTimeoutPageRouteArguments arguments) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoTimeoutPageRoute(CCRegistry registry) =>
    _DemoTimeoutPageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoTimeoutPageRoute() {
  final definition = _DemoTimeoutPageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoTimeoutPage ccrouterBuildDemoTimeoutPageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoTimeoutPageRoute.build(
  _DemoTimeoutPageRoute.definition.codec.decode(arguments),
);

/// Immutable arguments for route demo_navigation_lab.guarded; URI values remain typed.
final class _DemoGuardedPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoGuardedPageRouteArguments();
}

/// 未保存状态下拒绝 CCRouter Pop 的路由。
abstract final class _DemoGuardedPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.guarded";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _DemoGuardedPageRouteIntent(_DemoGuardedPageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoGuardedPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/policy/guarded",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoGuardedPageRouteCodec(),
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
        popGuardIds: const ["demo_navigation_lab.dirty"],
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoGuardedPage build(_DemoGuardedPageRouteArguments arguments) =>
      DemoGuardedPage();
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DemoGuardedPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoGuardedPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoGuardedPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoGuardedPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoGuardedPageRouteCodec
    implements CCRouteCodec<_DemoGuardedPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoGuardedPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoGuardedPageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoGuardedPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoGuardedPageRouteArguments arguments) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoGuardedPageRoute(CCRegistry registry) =>
    _DemoGuardedPageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoGuardedPageRoute() {
  final definition = _DemoGuardedPageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoGuardedPage ccrouterBuildDemoGuardedPageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoGuardedPageRoute.build(
  _DemoGuardedPageRoute.definition.codec.decode(arguments),
);
