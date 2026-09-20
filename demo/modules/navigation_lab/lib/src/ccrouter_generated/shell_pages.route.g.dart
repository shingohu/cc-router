// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

part of '../shell_pages.dart';

// **************************************************************************
// _RouteGenerator
// **************************************************************************

/// Immutable arguments for route demo_navigation_lab.shell.feed; URI values remain typed.
final class _DemoShellFeedPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoShellFeedPageRouteArguments();
}

/// ShellRoute 共享框架中的内容首页。
abstract final class _DemoShellFeedPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.shell.feed";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _DemoShellFeedPageRouteIntent(_DemoShellFeedPageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoShellFeedPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/shell/feed",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoShellFeedPageRouteCodec(),
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
          shellId: "demo_navigation_lab.single_shell",
          navigatorOutlet: "shell.content",
        ),
        interceptorIds: const [],
        popGuardIds: const [],
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoShellFeedPage build(_DemoShellFeedPageRouteArguments arguments) =>
      DemoShellFeedPage();
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DemoShellFeedPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoShellFeedPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoShellFeedPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoShellFeedPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoShellFeedPageRouteCodec
    implements CCRouteCodec<_DemoShellFeedPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoShellFeedPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoShellFeedPageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoShellFeedPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoShellFeedPageRouteArguments arguments) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoShellFeedPageRoute(CCRegistry registry) =>
    _DemoShellFeedPageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoShellFeedPageRoute() {
  final definition = _DemoShellFeedPageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoShellFeedPage ccrouterBuildDemoShellFeedPageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoShellFeedPageRoute.build(
  _DemoShellFeedPageRoute.definition.codec.decode(arguments),
);

/// Immutable arguments for route demo_navigation_lab.shell.detail; URI values remain typed.
final class _DemoShellDetailPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoShellDetailPageRouteArguments({required this.item});

  /// path parameter item for demo_navigation_lab.shell.detail.
  final int item;
}

/// ShellRoute 嵌套子路由。
abstract final class _DemoShellDetailPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.shell.detail";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent({required int item}) =>
      _DemoShellDetailPageRouteIntent(
        _DemoShellDetailPageRouteArguments(item: item),
      );

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoShellDetailPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/shell/feed/:item",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoShellDetailPageRouteCodec(),
        deepLink: CCDeepLinkPolicy.disabled,
        presentation: const CCPagePresentation(
          routeType: CCPageRouteType.platformDefault,
          transition: CCPageTransitionType.platformDefault,
          opaque: true,
          fullscreenDialog: false,
        ),
        placement: const CCRoutePlacement(
          hostId: "default",
          parentRouteId: "demo_navigation_lab.shell.feed",
          shellId: "demo_navigation_lab.single_shell",
          navigatorOutlet: "shell.content",
        ),
        interceptorIds: const [],
        popGuardIds: const [],
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoShellDetailPage build(
    _DemoShellDetailPageRouteArguments arguments,
  ) => DemoShellDetailPage(item: arguments.item);
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DemoShellDetailPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoShellDetailPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoShellDetailPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoShellDetailPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoShellDetailPageRouteCodec
    implements CCRouteCodec<_DemoShellDetailPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoShellDetailPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoShellDetailPageRouteArguments decode(CCEncodedRouteArguments input) {
    final _raw_item = input.path["item"];
    final int _value_item = _raw_item == null
        ? throw CCRouteParameterError(
            "Route \"demo_navigation_lab.shell.detail\" parameter \"item\" is invalid.",
          )
        : (int.tryParse(_raw_item) ??
              (throw CCRouteParameterError(
                "Route \"demo_navigation_lab.shell.detail\" parameter \"item\" is invalid.",
              )));
    return _DemoShellDetailPageRouteArguments(item: _value_item);
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoShellDetailPageRouteArguments arguments) {
    return CCEncodedRouteArguments(
      path: {"item": arguments.item.toString()},
      query: {},
      extra: null,
    );
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoShellDetailPageRoute(CCRegistry registry) =>
    _DemoShellDetailPageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoShellDetailPageRoute() {
  final definition = _DemoShellDetailPageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoShellDetailPage ccrouterBuildDemoShellDetailPageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoShellDetailPageRoute.build(
  _DemoShellDetailPageRoute.definition.codec.decode(arguments),
);

/// Immutable arguments for route demo_navigation_lab.shell.settings; URI values remain typed.
final class _DemoShellSettingsPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoShellSettingsPageRouteArguments();
}

/// ShellRoute 共享框架中的设置页。
abstract final class _DemoShellSettingsPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.shell.settings";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _DemoShellSettingsPageRouteIntent(_DemoShellSettingsPageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoShellSettingsPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/shell/settings",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoShellSettingsPageRouteCodec(),
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
          shellId: "demo_navigation_lab.single_shell",
          navigatorOutlet: "shell.content",
        ),
        interceptorIds: const [],
        popGuardIds: const [],
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoShellSettingsPage build(
    _DemoShellSettingsPageRouteArguments arguments,
  ) => DemoShellSettingsPage();
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DemoShellSettingsPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoShellSettingsPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoShellSettingsPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoShellSettingsPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoShellSettingsPageRouteCodec
    implements CCRouteCodec<_DemoShellSettingsPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoShellSettingsPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoShellSettingsPageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoShellSettingsPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(
    _DemoShellSettingsPageRouteArguments arguments,
  ) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoShellSettingsPageRoute(CCRegistry registry) =>
    _DemoShellSettingsPageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoShellSettingsPageRoute() {
  final definition = _DemoShellSettingsPageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoShellSettingsPage ccrouterBuildDemoShellSettingsPageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoShellSettingsPageRoute.build(
  _DemoShellSettingsPageRoute.definition.codec.decode(arguments),
);

/// Immutable arguments for route demo_navigation_lab.workspace.home; URI values remain typed.
final class _DemoWorkspaceHomePageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoWorkspaceHomePageRouteArguments();
}

/// StatefulShellRoute 首页分支。
abstract final class _DemoWorkspaceHomePageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.workspace.home";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() =>
      _DemoWorkspaceHomePageRouteIntent(_DemoWorkspaceHomePageRouteArguments());

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoWorkspaceHomePageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/workspace/home",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoWorkspaceHomePageRouteCodec(),
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
          shellId: "demo_navigation_lab.workspace_shell",
          navigatorOutlet: "workspace.home",
        ),
        interceptorIds: const [],
        popGuardIds: const [],
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoWorkspaceHomePage build(
    _DemoWorkspaceHomePageRouteArguments arguments,
  ) => DemoWorkspaceHomePage();
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DemoWorkspaceHomePageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoWorkspaceHomePageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoWorkspaceHomePageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoWorkspaceHomePageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoWorkspaceHomePageRouteCodec
    implements CCRouteCodec<_DemoWorkspaceHomePageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoWorkspaceHomePageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoWorkspaceHomePageRouteArguments decode(CCEncodedRouteArguments input) {
    return _DemoWorkspaceHomePageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(
    _DemoWorkspaceHomePageRouteArguments arguments,
  ) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoWorkspaceHomePageRoute(CCRegistry registry) =>
    _DemoWorkspaceHomePageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoWorkspaceHomePageRoute() {
  final definition = _DemoWorkspaceHomePageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoWorkspaceHomePage ccrouterBuildDemoWorkspaceHomePageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoWorkspaceHomePageRoute.build(
  _DemoWorkspaceHomePageRoute.definition.codec.decode(arguments),
);

/// Immutable arguments for route demo_navigation_lab.workspace.detail; URI values remain typed.
final class _DemoWorkspaceDetailPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoWorkspaceDetailPageRouteArguments({required this.item});

  /// path parameter item for demo_navigation_lab.workspace.detail.
  final int item;
}

/// StatefulShellRoute 首页分支的可 Deep Link 子路由。
abstract final class _DemoWorkspaceDetailPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.workspace.detail";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent({required int item}) =>
      _DemoWorkspaceDetailPageRouteIntent(
        _DemoWorkspaceDetailPageRouteArguments(item: item),
      );

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoWorkspaceDetailPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/workspace/home/:item",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoWorkspaceDetailPageRouteCodec(),
        deepLink: CCDeepLinkPolicy.enabled,
        presentation: const CCPagePresentation(
          routeType: CCPageRouteType.platformDefault,
          transition: CCPageTransitionType.platformDefault,
          opaque: true,
          fullscreenDialog: false,
        ),
        placement: const CCRoutePlacement(
          hostId: "default",
          parentRouteId: "demo_navigation_lab.workspace.home",
          shellId: "demo_navigation_lab.workspace_shell",
          navigatorOutlet: "workspace.home",
        ),
        interceptorIds: const [],
        popGuardIds: const [],
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoWorkspaceDetailPage build(
    _DemoWorkspaceDetailPageRouteArguments arguments,
  ) => DemoWorkspaceDetailPage(item: arguments.item);
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DemoWorkspaceDetailPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoWorkspaceDetailPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoWorkspaceDetailPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoWorkspaceDetailPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoWorkspaceDetailPageRouteCodec
    implements CCRouteCodec<_DemoWorkspaceDetailPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoWorkspaceDetailPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoWorkspaceDetailPageRouteArguments decode(CCEncodedRouteArguments input) {
    final _raw_item = input.path["item"];
    final int _value_item = _raw_item == null
        ? throw CCRouteParameterError(
            "Route \"demo_navigation_lab.workspace.detail\" parameter \"item\" is invalid.",
          )
        : (int.tryParse(_raw_item) ??
              (throw CCRouteParameterError(
                "Route \"demo_navigation_lab.workspace.detail\" parameter \"item\" is invalid.",
              )));
    return _DemoWorkspaceDetailPageRouteArguments(item: _value_item);
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(
    _DemoWorkspaceDetailPageRouteArguments arguments,
  ) {
    return CCEncodedRouteArguments(
      path: {"item": arguments.item.toString()},
      query: {},
      extra: null,
    );
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoWorkspaceDetailPageRoute(CCRegistry registry) =>
    _DemoWorkspaceDetailPageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoWorkspaceDetailPageRoute() {
  final definition = _DemoWorkspaceDetailPageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoWorkspaceDetailPage ccrouterBuildDemoWorkspaceDetailPageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoWorkspaceDetailPageRoute.build(
  _DemoWorkspaceDetailPageRoute.definition.codec.decode(arguments),
);

/// Immutable arguments for route demo_navigation_lab.workspace.activity; URI values remain typed.
final class _DemoWorkspaceActivityPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoWorkspaceActivityPageRouteArguments();
}

/// StatefulShellRoute 活动分支。
abstract final class _DemoWorkspaceActivityPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.workspace.activity";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() => _DemoWorkspaceActivityPageRouteIntent(
    _DemoWorkspaceActivityPageRouteArguments(),
  );

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoWorkspaceActivityPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/workspace/activity",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoWorkspaceActivityPageRouteCodec(),
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
          shellId: "demo_navigation_lab.workspace_shell",
          navigatorOutlet: "workspace.activity",
        ),
        interceptorIds: const [],
        popGuardIds: const [],
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoWorkspaceActivityPage build(
    _DemoWorkspaceActivityPageRouteArguments arguments,
  ) => DemoWorkspaceActivityPage();
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DemoWorkspaceActivityPageRouteIntent
    implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoWorkspaceActivityPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoWorkspaceActivityPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoWorkspaceActivityPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoWorkspaceActivityPageRouteCodec
    implements CCRouteCodec<_DemoWorkspaceActivityPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoWorkspaceActivityPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoWorkspaceActivityPageRouteArguments decode(
    CCEncodedRouteArguments input,
  ) {
    return _DemoWorkspaceActivityPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(
    _DemoWorkspaceActivityPageRouteArguments arguments,
  ) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoWorkspaceActivityPageRoute(CCRegistry registry) =>
    _DemoWorkspaceActivityPageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoWorkspaceActivityPageRoute() {
  final definition = _DemoWorkspaceActivityPageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoWorkspaceActivityPage ccrouterBuildDemoWorkspaceActivityPageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoWorkspaceActivityPageRoute.build(
  _DemoWorkspaceActivityPageRoute.definition.codec.decode(arguments),
);

/// Immutable arguments for route demo_navigation_lab.workspace.profile; URI values remain typed.
final class _DemoWorkspaceProfilePageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoWorkspaceProfilePageRouteArguments();
}

/// StatefulShellRoute 个人分支。
abstract final class _DemoWorkspaceProfilePageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.workspace.profile";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() => _DemoWorkspaceProfilePageRouteIntent(
    _DemoWorkspaceProfilePageRouteArguments(),
  );

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoWorkspaceProfilePageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/workspace/profile",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoWorkspaceProfilePageRouteCodec(),
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
          shellId: "demo_navigation_lab.workspace_shell",
          navigatorOutlet: "workspace.profile",
        ),
        interceptorIds: const [],
        popGuardIds: const [],
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static DemoWorkspaceProfilePage build(
    _DemoWorkspaceProfilePageRouteArguments arguments,
  ) => DemoWorkspaceProfilePage();
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DemoWorkspaceProfilePageRouteIntent
    implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoWorkspaceProfilePageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoWorkspaceProfilePageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoWorkspaceProfilePageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoWorkspaceProfilePageRouteCodec
    implements CCRouteCodec<_DemoWorkspaceProfilePageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoWorkspaceProfilePageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoWorkspaceProfilePageRouteArguments decode(
    CCEncodedRouteArguments input,
  ) {
    return _DemoWorkspaceProfilePageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(
    _DemoWorkspaceProfilePageRouteArguments arguments,
  ) {
    return CCEncodedRouteArguments(path: {}, query: {}, extra: null);
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoWorkspaceProfilePageRoute(CCRegistry registry) =>
    _DemoWorkspaceProfilePageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoWorkspaceProfilePageRoute() {
  final definition = _DemoWorkspaceProfilePageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoWorkspaceProfilePage ccrouterBuildDemoWorkspaceProfilePageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoWorkspaceProfilePageRoute.build(
  _DemoWorkspaceProfilePageRoute.definition.codec.decode(arguments),
);

/// Immutable arguments for route demo_navigation_lab.extra; URI values remain typed.
final class _DemoExtraPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoExtraPageRouteArguments({required this.payload});

  /// extra parameter payload for demo_navigation_lab.extra.
  final DemoExtraPayload payload;
}

/// 展示仅在进程内传递的类型安全 Extra 对象。
abstract final class _DemoExtraPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.extra";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent({required DemoExtraPayload payload}) =>
      _DemoExtraPageRouteIntent(_DemoExtraPageRouteArguments(payload: payload));

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<_DemoExtraPageRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/lab/extra",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoExtraPageRouteCodec(),
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
  static DemoExtraPage build(_DemoExtraPageRouteArguments arguments) =>
      DemoExtraPage(arguments.payload);
}

/// Private data-only Intent carrying this route's typed result contract.
final class _DemoExtraPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoExtraPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _DemoExtraPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _DemoExtraPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoExtraPageRouteCodec
    implements CCRouteCodec<_DemoExtraPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoExtraPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _DemoExtraPageRouteArguments decode(CCEncodedRouteArguments input) {
    final _value_payload = input.extra == null
        ? throw CCRouteParameterError(
            "Route \"demo_navigation_lab.extra\" parameter \"payload\" is invalid.",
          )
        : input.extra;
    if (_value_payload is! DemoExtraPayload)
      throw CCRouteParameterError(
        "Route \"demo_navigation_lab.extra\" parameter \"payload\" is invalid.",
      );
    return _DemoExtraPageRouteArguments(payload: _value_payload);
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(_DemoExtraPageRouteArguments arguments) {
    return CCEncodedRouteArguments(
      path: {},
      query: {},
      extra: arguments.payload,
    );
  }
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoExtraPageRoute(CCRegistry registry) =>
    _DemoExtraPageRoute.register(registry);

/// Package-internal adapter-neutral metadata bridge used by Host generation.
CCNavigationRoute ccrouterDescribeDemoExtraPageRoute() {
  final definition = _DemoExtraPageRoute.definition;
  return CCNavigationRoute(
    routeId: definition.routeId,
    patterns: definition.patterns,
    presentation: definition.presentation,
    deepLink: definition.deepLink,
    placement: definition.placement,
  );
}

/// Package-internal page factory bridge used by generated Flutter catalogs.
DemoExtraPage ccrouterBuildDemoExtraPageRoute(
  CCEncodedRouteArguments arguments,
) => _DemoExtraPageRoute.build(
  _DemoExtraPageRoute.definition.codec.decode(arguments),
);
