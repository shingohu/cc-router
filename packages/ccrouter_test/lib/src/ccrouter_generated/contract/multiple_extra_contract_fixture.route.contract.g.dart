// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteContractGenerator
// **************************************************************************

import 'package:ccrouter_contracts/ccrouter_contracts.dart';

/// Immutable arguments for route generated_route_fixture.contract-extras; URI values remain typed.
final class GeneratedMultiExtrasRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const GeneratedMultiExtrasRouteArguments({required this.items, this.label});

  /// extra parameter items for generated_route_fixture.contract-extras.
  final List<String> items;

  /// extra parameter label for generated_route_fixture.contract-extras.
  final String? label;
}

/// Typed contract for generated_route_fixture.contract-extras.
abstract final class GeneratedMultiExtrasRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "generated_route_fixture.contract-extras";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent({
    required List<String> items,
    String? label,
  }) => _GeneratedMultiExtrasRouteIntent(
    GeneratedMultiExtrasRouteArguments(items: items, label: label),
  );
}

/// Generated definition bridge for registration and page binding.
///
/// This symbol is intentionally kept out of stable Consumer barrels.
/// Business code creates [GeneratedMultiExtrasRoute] intents. Generated owner glue uses
/// this binding to register and decode the route.
abstract final class GeneratedMultiExtrasRouteContractBinding {
  /// The typed route definition consumed by generated owner glue.
  static final definition =
      CCRouteDefinition<GeneratedMultiExtrasRouteArguments, void>(
        routeId: GeneratedMultiExtrasRoute.id,
        patterns: const [
          const CCPathPattern(
            "/generated/contract-extras",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _GeneratedMultiExtrasRouteCodec(),
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
final class _GeneratedMultiExtrasRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _GeneratedMultiExtrasRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => GeneratedMultiExtrasRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final GeneratedMultiExtrasRouteArguments arguments;
}

/// Route-specific process-local envelope; never serialized into a URI.
final class _GeneratedMultiExtrasRouteCodecExtra {
  /// Retains typed field references without copying caller-owned objects.
  const _GeneratedMultiExtrasRouteCodecExtra({
    required this.items,
    required this.label,
  });

  /// Process-local items supplied to route generated_route_fixture.contract-extras.
  final List<String> items;

  /// Process-local label supplied to route generated_route_fixture.contract-extras.
  final String? label;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _GeneratedMultiExtrasRouteCodec
    implements CCRouteCodec<GeneratedMultiExtrasRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _GeneratedMultiExtrasRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  GeneratedMultiExtrasRouteArguments decode(CCRouteCodecValues input) {
    final _extra = switch (input.extra) {
      null => null,
      final _GeneratedMultiExtrasRouteCodecExtra value => value,
      _ => throw CCRouteParameterError(
        "Route \"generated_route_fixture.contract-extras\" Extra envelope is invalid.",
      ),
    };
    if (_extra == null)
      throw CCRouteParameterError(
        "Route \"generated_route_fixture.contract-extras\" requires its typed Extra envelope.",
      );
    final List<String> _value_items = _extra.items;
    final String? _value_label = _extra.label;
    return GeneratedMultiExtrasRouteArguments(
      items: _value_items,
      label: _value_label,
    );
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCRouteCodecValues encode(GeneratedMultiExtrasRouteArguments arguments) {
    return CCRouteCodecValues(
      path: {},
      query: {},
      extra: _GeneratedMultiExtrasRouteCodecExtra(
        items: arguments.items,
        label: arguments.label,
      ),
    );
  }
}
