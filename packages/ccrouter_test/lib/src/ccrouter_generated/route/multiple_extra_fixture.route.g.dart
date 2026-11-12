// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_test/src/multiple_extra_fixture.dart' as route_source;

/// Immutable arguments for route generated_route_fixture.multi-extra; URI values remain typed.
final class _GeneratedMultiExtraPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _GeneratedMultiExtraPageRouteArguments({
    required this.id,
    this.tab = "summary",
    required this.snapshot,
    this.revision = 3,
    this.enabled = true,
  });

  /// path parameter id for generated_route_fixture.multi-extra.
  final String id;

  /// query parameter tab for generated_route_fixture.multi-extra.
  final String tab;

  /// extra parameter snapshot for generated_route_fixture.multi-extra.
  final route_source.GeneratedExtraSnapshot snapshot;

  /// extra parameter revision for generated_route_fixture.multi-extra.
  final int? revision;

  /// extra parameter enabled for generated_route_fixture.multi-extra.
  final bool enabled;
}

/// Typed contract for generated_route_fixture.multi-extra.
abstract final class _GeneratedMultiExtraPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "generated_route_fixture.multi-extra";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent({
    required String id,
    String tab = "summary",
    required route_source.GeneratedExtraSnapshot snapshot,
    int? revision = 3,
    bool enabled = true,
  }) => _GeneratedMultiExtraPageRouteIntent(
    _GeneratedMultiExtraPageRouteArguments(
      id: id,
      tab: tab,
      snapshot: snapshot,
      revision: revision,
      enabled: enabled,
    ),
  );
}

/// Generated definition bridge for registration and page binding.
///
/// This symbol is intentionally kept out of stable Consumer barrels.
/// Business code creates [_GeneratedMultiExtraPageRoute] intents. Generated owner glue uses
/// this binding to register and decode the route.
abstract final class _GeneratedMultiExtraPageRouteContractBinding {
  /// The typed route definition consumed by generated owner glue.
  static final definition =
      CCRouteDefinition<_GeneratedMultiExtraPageRouteArguments, void>(
        routeId: _GeneratedMultiExtraPageRoute.id,
        patterns: const [
          const CCPathPattern(
            "/generated/multi-extra/:id",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _GeneratedMultiExtraPageRouteCodec(),
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
final class _GeneratedMultiExtraPageRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _GeneratedMultiExtraPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _GeneratedMultiExtraPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _GeneratedMultiExtraPageRouteArguments arguments;
}

/// Route-specific process-local envelope; never serialized into a URI.
final class _GeneratedMultiExtraPageRouteCodecExtra {
  /// Retains typed field references without copying caller-owned objects.
  const _GeneratedMultiExtraPageRouteCodecExtra({
    required this.snapshot,
    required this.revision,
    required this.enabled,
  });

  /// Process-local snapshot supplied to route generated_route_fixture.multi-extra.
  final route_source.GeneratedExtraSnapshot snapshot;

  /// Process-local revision supplied to route generated_route_fixture.multi-extra.
  final int? revision;

  /// Process-local enabled supplied to route generated_route_fixture.multi-extra.
  final bool enabled;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _GeneratedMultiExtraPageRouteCodec
    implements CCRouteCodec<_GeneratedMultiExtraPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _GeneratedMultiExtraPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _GeneratedMultiExtraPageRouteArguments decode(CCRouteCodecValues input) {
    final _extra = switch (input.extra) {
      null => null,
      final _GeneratedMultiExtraPageRouteCodecExtra value => value,
      _ => throw CCRouteParameterError(
        "Route \"generated_route_fixture.multi-extra\" Extra envelope is invalid.",
      ),
    };
    if (_extra == null)
      throw CCRouteParameterError(
        "Route \"generated_route_fixture.multi-extra\" requires its typed Extra envelope.",
      );
    final _raw_id = input.path["id"];
    final String _value_id = _raw_id == null
        ? throw CCRouteParameterError(
            "Route \"generated_route_fixture.multi-extra\" parameter \"id\" is invalid.",
          )
        : _raw_id;
    final _values_tab = input.query["tab"];
    if (_values_tab != null && _values_tab.length != 1)
      throw CCRouteParameterError(
        "Route \"generated_route_fixture.multi-extra\" parameter \"tab\" is invalid.",
      );
    final _raw_tab = _values_tab?.single;
    final String _value_tab = _raw_tab == null ? "summary" : _raw_tab;
    final route_source.GeneratedExtraSnapshot _value_snapshot = _extra.snapshot;
    final int? _value_revision = _extra.revision;
    final bool _value_enabled = _extra.enabled;
    return _GeneratedMultiExtraPageRouteArguments(
      id: _value_id,
      tab: _value_tab,
      snapshot: _value_snapshot,
      revision: _value_revision,
      enabled: _value_enabled,
    );
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCRouteCodecValues encode(_GeneratedMultiExtraPageRouteArguments arguments) {
    return CCRouteCodecValues(
      path: {"id": arguments.id},
      query: {
        "tab": [arguments.tab],
      },
      extra: _GeneratedMultiExtraPageRouteCodecExtra(
        snapshot: arguments.snapshot,
        revision: arguments.revision,
        enabled: arguments.enabled,
      ),
    );
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedGeneratedMultiExtraPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedGeneratedMultiExtraPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call({
    required String id,
    String tab = "summary",
    required route_source.GeneratedExtraSnapshot snapshot,
    int? revision = 3,
    bool enabled = true,
  }) => _GeneratedMultiExtraPageRoute.intent(
    id: id,
    tab: tab,
    snapshot: snapshot,
    revision: revision,
    enabled: enabled,
  );
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterGeneratedMultiExtraPageRoute(CCRegistry registry) =>
    registry.registerRoute(
      _GeneratedMultiExtraPageRouteContractBinding.definition,
    );

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<_GeneratedMultiExtraPageRouteArguments, void>
ccrouterDescribeGeneratedMultiExtraPageRoute() =>
    _GeneratedMultiExtraPageRouteContractBinding.definition;

/// Immutable arguments for route generated_route_fixture.optional-extras; URI values remain typed.
final class _GeneratedOptionalExtrasPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _GeneratedOptionalExtrasPageRouteArguments({
    this.snapshot,
    this.revision = null,
  });

  /// extra parameter snapshot for generated_route_fixture.optional-extras.
  final route_source.GeneratedExtraSnapshot? snapshot;

  /// extra parameter revision for generated_route_fixture.optional-extras.
  final int? revision;
}

/// Typed contract for generated_route_fixture.optional-extras.
abstract final class _GeneratedOptionalExtrasPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "generated_route_fixture.optional-extras";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent({
    route_source.GeneratedExtraSnapshot? snapshot,
    int? revision = null,
  }) => _GeneratedOptionalExtrasPageRouteIntent(
    _GeneratedOptionalExtrasPageRouteArguments(
      snapshot: snapshot,
      revision: revision,
    ),
  );
}

/// Generated definition bridge for registration and page binding.
///
/// This symbol is intentionally kept out of stable Consumer barrels.
/// Business code creates [_GeneratedOptionalExtrasPageRoute] intents. Generated owner glue uses
/// this binding to register and decode the route.
abstract final class _GeneratedOptionalExtrasPageRouteContractBinding {
  /// The typed route definition consumed by generated owner glue.
  static final definition =
      CCRouteDefinition<_GeneratedOptionalExtrasPageRouteArguments, void>(
        routeId: _GeneratedOptionalExtrasPageRoute.id,
        patterns: const [
          const CCPathPattern(
            "/generated/optional-extras",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _GeneratedOptionalExtrasPageRouteCodec(),
        deepLink: CCDeepLinkPolicy.enabled,
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
final class _GeneratedOptionalExtrasPageRouteIntent
    implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _GeneratedOptionalExtrasPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _GeneratedOptionalExtrasPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _GeneratedOptionalExtrasPageRouteArguments arguments;
}

/// Route-specific process-local envelope; never serialized into a URI.
final class _GeneratedOptionalExtrasPageRouteCodecExtra {
  /// Retains typed field references without copying caller-owned objects.
  const _GeneratedOptionalExtrasPageRouteCodecExtra({
    required this.snapshot,
    required this.revision,
  });

  /// Process-local snapshot supplied to route generated_route_fixture.optional-extras.
  final route_source.GeneratedExtraSnapshot? snapshot;

  /// Process-local revision supplied to route generated_route_fixture.optional-extras.
  final int? revision;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _GeneratedOptionalExtrasPageRouteCodec
    implements CCRouteCodec<_GeneratedOptionalExtrasPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _GeneratedOptionalExtrasPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _GeneratedOptionalExtrasPageRouteArguments decode(CCRouteCodecValues input) {
    final _extra = switch (input.extra) {
      null => null,
      final _GeneratedOptionalExtrasPageRouteCodecExtra value => value,
      _ => throw CCRouteParameterError(
        "Route \"generated_route_fixture.optional-extras\" Extra envelope is invalid.",
      ),
    };
    final route_source.GeneratedExtraSnapshot? _value_snapshot =
        _extra?.snapshot;
    final int? _value_revision = _extra?.revision;
    return _GeneratedOptionalExtrasPageRouteArguments(
      snapshot: _value_snapshot,
      revision: _value_revision,
    );
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCRouteCodecValues encode(
    _GeneratedOptionalExtrasPageRouteArguments arguments,
  ) {
    return CCRouteCodecValues(
      path: {},
      query: {},
      extra: arguments.snapshot == null && arguments.revision == null
          ? null
          : _GeneratedOptionalExtrasPageRouteCodecExtra(
              snapshot: arguments.snapshot,
              revision: arguments.revision,
            ),
    );
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedGeneratedOptionalExtrasPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedGeneratedOptionalExtrasPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call({
    route_source.GeneratedExtraSnapshot? snapshot,
    int? revision = null,
  }) => _GeneratedOptionalExtrasPageRoute.intent(
    snapshot: snapshot,
    revision: revision,
  );
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterGeneratedOptionalExtrasPageRoute(CCRegistry registry) =>
    registry.registerRoute(
      _GeneratedOptionalExtrasPageRouteContractBinding.definition,
    );

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<_GeneratedOptionalExtrasPageRouteArguments, void>
ccrouterDescribeGeneratedOptionalExtrasPageRoute() =>
    _GeneratedOptionalExtrasPageRouteContractBinding.definition;

/// Immutable arguments for route generated_route_fixture.extras-child; URI values remain typed.
final class _GeneratedExtrasChildPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _GeneratedExtrasChildPageRouteArguments();
}

/// Typed contract for generated_route_fixture.extras-child.
abstract final class _GeneratedExtrasChildPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "generated_route_fixture.extras-child";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent() => _GeneratedExtrasChildPageRouteIntent(
    _GeneratedExtrasChildPageRouteArguments(),
  );
}

/// Generated definition bridge for registration and page binding.
///
/// This symbol is intentionally kept out of stable Consumer barrels.
/// Business code creates [_GeneratedExtrasChildPageRoute] intents. Generated owner glue uses
/// this binding to register and decode the route.
abstract final class _GeneratedExtrasChildPageRouteContractBinding {
  /// The typed route definition consumed by generated owner glue.
  static final definition =
      CCRouteDefinition<_GeneratedExtrasChildPageRouteArguments, void>(
        routeId: _GeneratedExtrasChildPageRoute.id,
        patterns: const [
          const CCPathPattern(
            "/generated/optional-extras/child",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _GeneratedExtrasChildPageRouteCodec(),
        deepLink: CCDeepLinkPolicy.disabled,
        presentation: const CCPagePresentation(
          routeType: CCPageRouteType.platformDefault,
          transition: CCPageTransitionType.platformDefault,
          opaque: true,
          fullscreenDialog: false,
        ),
        placement: const CCRoutePlacement(
          hostId: "default",
          parentRouteId: "generated_route_fixture.optional-extras",
          shellId: null,
          navigatorOutlet: "root",
        ),
        interceptorIds: const [],
        popGuardIds: const [],
      );
}

/// Private data-only Intent carrying this route's typed result contract.
final class _GeneratedExtrasChildPageRouteIntent
    implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _GeneratedExtrasChildPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _GeneratedExtrasChildPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _GeneratedExtrasChildPageRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _GeneratedExtrasChildPageRouteCodec
    implements CCRouteCodec<_GeneratedExtrasChildPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _GeneratedExtrasChildPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _GeneratedExtrasChildPageRouteArguments decode(CCRouteCodecValues input) {
    return _GeneratedExtrasChildPageRouteArguments();
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCRouteCodecValues encode(_GeneratedExtrasChildPageRouteArguments arguments) {
    return CCRouteCodecValues(path: {}, query: {}, extra: null);
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedGeneratedExtrasChildPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedGeneratedExtrasChildPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call() => _GeneratedExtrasChildPageRoute.intent();
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterGeneratedExtrasChildPageRoute(CCRegistry registry) =>
    registry.registerRoute(
      _GeneratedExtrasChildPageRouteContractBinding.definition,
    );

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<_GeneratedExtrasChildPageRouteArguments, void>
ccrouterDescribeGeneratedExtrasChildPageRoute() =>
    _GeneratedExtrasChildPageRouteContractBinding.definition;

/// Immutable arguments for route generated_route_fixture.default-extras; URI values remain typed.
final class _GeneratedDefaultExtrasPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const _GeneratedDefaultExtrasPageRouteArguments({
    this.label = "fallback",
    this.revision = 3,
  });

  /// extra parameter label for generated_route_fixture.default-extras.
  final String? label;

  /// extra parameter revision for generated_route_fixture.default-extras.
  final int? revision;
}

/// Typed contract for generated_route_fixture.default-extras.
abstract final class _GeneratedDefaultExtrasPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "generated_route_fixture.default-extras";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent({
    String? label = "fallback",
    int? revision = 3,
  }) => _GeneratedDefaultExtrasPageRouteIntent(
    _GeneratedDefaultExtrasPageRouteArguments(label: label, revision: revision),
  );
}

/// Generated definition bridge for registration and page binding.
///
/// This symbol is intentionally kept out of stable Consumer barrels.
/// Business code creates [_GeneratedDefaultExtrasPageRoute] intents. Generated owner glue uses
/// this binding to register and decode the route.
abstract final class _GeneratedDefaultExtrasPageRouteContractBinding {
  /// The typed route definition consumed by generated owner glue.
  static final definition =
      CCRouteDefinition<_GeneratedDefaultExtrasPageRouteArguments, void>(
        routeId: _GeneratedDefaultExtrasPageRoute.id,
        patterns: const [
          const CCPathPattern(
            "/generated/default-extras",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _GeneratedDefaultExtrasPageRouteCodec(),
        deepLink: CCDeepLinkPolicy.enabled,
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
final class _GeneratedDefaultExtrasPageRouteIntent
    implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _GeneratedDefaultExtrasPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => _GeneratedDefaultExtrasPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final _GeneratedDefaultExtrasPageRouteArguments arguments;
}

/// Route-specific process-local envelope; never serialized into a URI.
final class _GeneratedDefaultExtrasPageRouteCodecExtra {
  /// Retains typed field references without copying caller-owned objects.
  const _GeneratedDefaultExtrasPageRouteCodecExtra({
    required this.label,
    required this.revision,
  });

  /// Process-local label supplied to route generated_route_fixture.default-extras.
  final String? label;

  /// Process-local revision supplied to route generated_route_fixture.default-extras.
  final int? revision;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _GeneratedDefaultExtrasPageRouteCodec
    implements CCRouteCodec<_GeneratedDefaultExtrasPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _GeneratedDefaultExtrasPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  _GeneratedDefaultExtrasPageRouteArguments decode(CCRouteCodecValues input) {
    final _extra = switch (input.extra) {
      null => null,
      final _GeneratedDefaultExtrasPageRouteCodecExtra value => value,
      _ => throw CCRouteParameterError(
        "Route \"generated_route_fixture.default-extras\" Extra envelope is invalid.",
      ),
    };
    final String? _value_label = _extra == null ? "fallback" : _extra.label;
    final int? _value_revision = _extra == null ? 3 : _extra.revision;
    return _GeneratedDefaultExtrasPageRouteArguments(
      label: _value_label,
      revision: _value_revision,
    );
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCRouteCodecValues encode(
    _GeneratedDefaultExtrasPageRouteArguments arguments,
  ) {
    return CCRouteCodecValues(
      path: {},
      query: {},
      extra: _GeneratedDefaultExtrasPageRouteCodecExtra(
        label: arguments.label,
        revision: arguments.revision,
      ),
    );
  }
}

/// Package-internal typed factory surfaced by the generated component API.
final class CCGeneratedGeneratedDefaultExtrasPageRouteFactory {
  /// Creates the stateless factory used by generated static route members.
  const CCGeneratedGeneratedDefaultExtrasPageRouteFactory();

  /// Creates an immutable Intent without performing navigation.
  CCRouteIntent<void> call({String? label = "fallback", int? revision = 3}) =>
      _GeneratedDefaultExtrasPageRoute.intent(label: label, revision: revision);
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing owner APIs.
void ccrouterRegisterGeneratedDefaultExtrasPageRoute(CCRegistry registry) =>
    registry.registerRoute(
      _GeneratedDefaultExtrasPageRouteContractBinding.definition,
    );

/// Typed route definition bridge shared by Host generation and page binding.
///
/// Retaining the generated argument type lets the isolated Flutter binding
/// access decoded fields without dynamic calls. Host aggregation may erase the
/// type only after page construction has been bound.
CCRouteDefinition<_GeneratedDefaultExtrasPageRouteArguments, void>
ccrouterDescribeGeneratedDefaultExtrasPageRoute() =>
    _GeneratedDefaultExtrasPageRouteContractBinding.definition;
