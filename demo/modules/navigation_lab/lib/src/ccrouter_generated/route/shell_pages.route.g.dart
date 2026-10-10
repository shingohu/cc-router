// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';
import 'package:demo_navigation_lab/src/shell_contract.dart' as route_type_0;

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
}

/// Generated definition bridge for registration and page binding.
///
/// This symbol is intentionally kept out of stable Consumer barrels.
/// Business code creates [_DemoShellFeedPageRoute] intents. Generated owner glue uses
/// this binding to register and decode the route.
abstract final class _DemoShellFeedPageRouteContractBinding {
  /// The typed route definition consumed by generated owner glue.
  static final definition =
      CCRouteDefinition<_DemoShellFeedPageRouteArguments, void>(
        routeId: _DemoShellFeedPageRoute.id,
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
  _DemoShellFeedPageRouteArguments decode(CCRouteCodecValues input) {
    return _DemoShellFeedPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCRouteCodecValues encode(_DemoShellFeedPageRouteArguments arguments) {
    return CCRouteCodecValues(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoShellFeedPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoShellFeedPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _DemoShellFeedPageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoShellFeedPageRoute(CCRegistry registry) =>
    registry.registerRoute(_DemoShellFeedPageRouteContractBinding.definition);

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<_DemoShellFeedPageRouteArguments, void>
ccrouterDescribeDemoShellFeedPageRoute() =>
    _DemoShellFeedPageRouteContractBinding.definition;

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
}

/// Generated definition bridge for registration and page binding.
///
/// This symbol is intentionally kept out of stable Consumer barrels.
/// Business code creates [_DemoShellDetailPageRoute] intents. Generated owner glue uses
/// this binding to register and decode the route.
abstract final class _DemoShellDetailPageRouteContractBinding {
  /// The typed route definition consumed by generated owner glue.
  static final definition =
      CCRouteDefinition<_DemoShellDetailPageRouteArguments, void>(
        routeId: _DemoShellDetailPageRoute.id,
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
  _DemoShellDetailPageRouteArguments decode(CCRouteCodecValues input) {
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
  CCRouteCodecValues encode(_DemoShellDetailPageRouteArguments arguments) {
    return CCRouteCodecValues(
      path: {"item": arguments.item.toString()},
      query: {},
      extra: null,
    );
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoShellDetailPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoShellDetailPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call({required int item}) =>
      _DemoShellDetailPageRoute.intent(item: item);
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoShellDetailPageRoute(CCRegistry registry) =>
    registry.registerRoute(_DemoShellDetailPageRouteContractBinding.definition);

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<_DemoShellDetailPageRouteArguments, void>
ccrouterDescribeDemoShellDetailPageRoute() =>
    _DemoShellDetailPageRouteContractBinding.definition;

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
}

/// Generated definition bridge for registration and page binding.
///
/// This symbol is intentionally kept out of stable Consumer barrels.
/// Business code creates [_DemoShellSettingsPageRoute] intents. Generated owner glue uses
/// this binding to register and decode the route.
abstract final class _DemoShellSettingsPageRouteContractBinding {
  /// The typed route definition consumed by generated owner glue.
  static final definition =
      CCRouteDefinition<_DemoShellSettingsPageRouteArguments, void>(
        routeId: _DemoShellSettingsPageRoute.id,
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
  _DemoShellSettingsPageRouteArguments decode(CCRouteCodecValues input) {
    return _DemoShellSettingsPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCRouteCodecValues encode(_DemoShellSettingsPageRouteArguments arguments) {
    return CCRouteCodecValues(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoShellSettingsPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoShellSettingsPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _DemoShellSettingsPageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoShellSettingsPageRoute(CCRegistry registry) => registry
    .registerRoute(_DemoShellSettingsPageRouteContractBinding.definition);

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<_DemoShellSettingsPageRouteArguments, void>
ccrouterDescribeDemoShellSettingsPageRoute() =>
    _DemoShellSettingsPageRouteContractBinding.definition;

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
}

/// Generated definition bridge for registration and page binding.
///
/// This symbol is intentionally kept out of stable Consumer barrels.
/// Business code creates [_DemoWorkspaceHomePageRoute] intents. Generated owner glue uses
/// this binding to register and decode the route.
abstract final class _DemoWorkspaceHomePageRouteContractBinding {
  /// The typed route definition consumed by generated owner glue.
  static final definition =
      CCRouteDefinition<_DemoWorkspaceHomePageRouteArguments, void>(
        routeId: _DemoWorkspaceHomePageRoute.id,
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
  _DemoWorkspaceHomePageRouteArguments decode(CCRouteCodecValues input) {
    return _DemoWorkspaceHomePageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCRouteCodecValues encode(_DemoWorkspaceHomePageRouteArguments arguments) {
    return CCRouteCodecValues(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoWorkspaceHomePageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoWorkspaceHomePageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _DemoWorkspaceHomePageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoWorkspaceHomePageRoute(CCRegistry registry) => registry
    .registerRoute(_DemoWorkspaceHomePageRouteContractBinding.definition);

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<_DemoWorkspaceHomePageRouteArguments, void>
ccrouterDescribeDemoWorkspaceHomePageRoute() =>
    _DemoWorkspaceHomePageRouteContractBinding.definition;

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
}

/// Generated definition bridge for registration and page binding.
///
/// This symbol is intentionally kept out of stable Consumer barrels.
/// Business code creates [_DemoWorkspaceDetailPageRoute] intents. Generated owner glue uses
/// this binding to register and decode the route.
abstract final class _DemoWorkspaceDetailPageRouteContractBinding {
  /// The typed route definition consumed by generated owner glue.
  static final definition =
      CCRouteDefinition<_DemoWorkspaceDetailPageRouteArguments, void>(
        routeId: _DemoWorkspaceDetailPageRoute.id,
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
  _DemoWorkspaceDetailPageRouteArguments decode(CCRouteCodecValues input) {
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
  CCRouteCodecValues encode(_DemoWorkspaceDetailPageRouteArguments arguments) {
    return CCRouteCodecValues(
      path: {"item": arguments.item.toString()},
      query: {},
      extra: null,
    );
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoWorkspaceDetailPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoWorkspaceDetailPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call({required int item}) =>
      _DemoWorkspaceDetailPageRoute.intent(item: item);
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoWorkspaceDetailPageRoute(CCRegistry registry) =>
    registry.registerRoute(
      _DemoWorkspaceDetailPageRouteContractBinding.definition,
    );

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<_DemoWorkspaceDetailPageRouteArguments, void>
ccrouterDescribeDemoWorkspaceDetailPageRoute() =>
    _DemoWorkspaceDetailPageRouteContractBinding.definition;

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
}

/// Generated definition bridge for registration and page binding.
///
/// This symbol is intentionally kept out of stable Consumer barrels.
/// Business code creates [_DemoWorkspaceActivityPageRoute] intents. Generated owner glue uses
/// this binding to register and decode the route.
abstract final class _DemoWorkspaceActivityPageRouteContractBinding {
  /// The typed route definition consumed by generated owner glue.
  static final definition =
      CCRouteDefinition<_DemoWorkspaceActivityPageRouteArguments, void>(
        routeId: _DemoWorkspaceActivityPageRoute.id,
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
  _DemoWorkspaceActivityPageRouteArguments decode(CCRouteCodecValues input) {
    return _DemoWorkspaceActivityPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCRouteCodecValues encode(
    _DemoWorkspaceActivityPageRouteArguments arguments,
  ) {
    return CCRouteCodecValues(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoWorkspaceActivityPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoWorkspaceActivityPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _DemoWorkspaceActivityPageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoWorkspaceActivityPageRoute(CCRegistry registry) =>
    registry.registerRoute(
      _DemoWorkspaceActivityPageRouteContractBinding.definition,
    );

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<_DemoWorkspaceActivityPageRouteArguments, void>
ccrouterDescribeDemoWorkspaceActivityPageRoute() =>
    _DemoWorkspaceActivityPageRouteContractBinding.definition;

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
}

/// Generated definition bridge for registration and page binding.
///
/// This symbol is intentionally kept out of stable Consumer barrels.
/// Business code creates [_DemoWorkspaceProfilePageRoute] intents. Generated owner glue uses
/// this binding to register and decode the route.
abstract final class _DemoWorkspaceProfilePageRouteContractBinding {
  /// The typed route definition consumed by generated owner glue.
  static final definition =
      CCRouteDefinition<_DemoWorkspaceProfilePageRouteArguments, void>(
        routeId: _DemoWorkspaceProfilePageRoute.id,
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
  _DemoWorkspaceProfilePageRouteArguments decode(CCRouteCodecValues input) {
    return _DemoWorkspaceProfilePageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCRouteCodecValues encode(_DemoWorkspaceProfilePageRouteArguments arguments) {
    return CCRouteCodecValues(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoWorkspaceProfilePageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoWorkspaceProfilePageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _DemoWorkspaceProfilePageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoWorkspaceProfilePageRoute(CCRegistry registry) =>
    registry.registerRoute(
      _DemoWorkspaceProfilePageRouteContractBinding.definition,
    );

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<_DemoWorkspaceProfilePageRouteArguments, void>
ccrouterDescribeDemoWorkspaceProfilePageRoute() =>
    _DemoWorkspaceProfilePageRouteContractBinding.definition;

/// Immutable arguments for route demo_navigation_lab.extra; URI values remain typed.
final class _DemoExtraPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _DemoExtraPageRouteArguments({required this.payload});

  /// extra parameter payload for demo_navigation_lab.extra.
  final route_type_0.DemoExtraPayload payload;
}

/// 展示仅在进程内传递的类型安全 Extra 对象。
abstract final class _DemoExtraPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_navigation_lab.extra";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent({
    required route_type_0.DemoExtraPayload payload,
  }) =>
      _DemoExtraPageRouteIntent(_DemoExtraPageRouteArguments(payload: payload));
}

/// Generated definition bridge for registration and page binding.
///
/// This symbol is intentionally kept out of stable Consumer barrels.
/// Business code creates [_DemoExtraPageRoute] intents. Generated owner glue uses
/// this binding to register and decode the route.
abstract final class _DemoExtraPageRouteContractBinding {
  /// The typed route definition consumed by generated owner glue.
  static final definition =
      CCRouteDefinition<_DemoExtraPageRouteArguments, void>(
        routeId: _DemoExtraPageRoute.id,
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
  _DemoExtraPageRouteArguments decode(CCRouteCodecValues input) {
    final _value_payload = input.extra == null
        ? throw CCRouteParameterError(
            "Route \"demo_navigation_lab.extra\" parameter \"payload\" is invalid.",
          )
        : input.extra;
    if (_value_payload is! route_type_0.DemoExtraPayload)
      throw CCRouteParameterError(
        "Route \"demo_navigation_lab.extra\" parameter \"payload\" is invalid.",
      );
    return _DemoExtraPageRouteArguments(payload: _value_payload);
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCRouteCodecValues encode(_DemoExtraPageRouteArguments arguments) {
    return CCRouteCodecValues(path: {}, query: {}, extra: arguments.payload);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedDemoExtraPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedDemoExtraPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call({required route_type_0.DemoExtraPayload payload}) =>
      _DemoExtraPageRoute.intent(payload: payload);
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterDemoExtraPageRoute(CCRegistry registry) =>
    registry.registerRoute(_DemoExtraPageRouteContractBinding.definition);

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<_DemoExtraPageRouteArguments, void>
ccrouterDescribeDemoExtraPageRoute() =>
    _DemoExtraPageRouteContractBinding.definition;
