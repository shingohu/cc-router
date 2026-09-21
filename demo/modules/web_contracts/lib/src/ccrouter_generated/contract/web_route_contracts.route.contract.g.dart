// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteContractGenerator
// **************************************************************************

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:demo_web_contracts/web_request.dart' as contract_type_0;

/// Immutable arguments for route demo_web.public; URI values remain typed.
final class DemoPublicWebRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const DemoPublicWebRouteArguments({required this.target});

  /// query parameter url for demo_web.public.
  final contract_type_0.DemoPublicWebTarget target;
}

/// Loads one allowlisted public HTTPS URL in the shared Web container.
abstract final class DemoPublicWebRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_web.public";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent({
    required contract_type_0.DemoPublicWebTarget target,
  }) => _DemoPublicWebRouteIntent(DemoPublicWebRouteArguments(target: target));

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<DemoPublicWebRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/web",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoPublicWebRouteCodec(),
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
final class _DemoPublicWebRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoPublicWebRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => DemoPublicWebRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final DemoPublicWebRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoPublicWebRouteCodec
    implements CCRouteCodec<DemoPublicWebRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoPublicWebRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  DemoPublicWebRouteArguments decode(CCEncodedRouteArguments input) {
    final _values_target = input.query["url"];
    if (_values_target != null && _values_target.isEmpty)
      throw CCRouteParameterError(
        "Route \"demo_web.public\" parameter \"url\" is invalid.",
      );
    final contract_type_0.DemoPublicWebTarget _value_target =
        _values_target == null
        ? throw CCRouteParameterError(
            "Route \"demo_web.public\" parameter \"url\" is invalid.",
          )
        : (() {
            try {
              return const contract_type_0.DemoPublicWebTargetCodec().decode(
                List<String>.unmodifiable(_values_target),
              );
            } catch (_) {
              throw CCRouteParameterError(
                "Route \"demo_web.public\" parameter \"url\" is invalid.",
              );
            }
          })();
    return DemoPublicWebRouteArguments(target: _value_target);
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(DemoPublicWebRouteArguments arguments) {
    return CCEncodedRouteArguments(
      path: {},
      query: {
        "url": (() {
          try {
            final values = const contract_type_0.DemoPublicWebTargetCodec()
                .encode(arguments.target);
            if (values.isEmpty) throw const FormatException();
            return List<String>.unmodifiable(values);
          } catch (_) {
            throw CCRouteParameterError(
              "Route \"demo_web.public\" parameter \"url\" is invalid.",
            );
          }
        })(),
      },
      extra: null,
    );
  }
}

/// Immutable arguments for route demo_web.private; URI values remain typed.
final class DemoPrivateWebRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const DemoPrivateWebRouteArguments({required this.request});

  /// extra parameter request for demo_web.private.
  final contract_type_0.DemoPrivateWebRequest request;
}

/// Loads a sensitive process-local request without URI serialization.
abstract final class DemoPrivateWebRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "demo_web.private";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<void> intent({
    required contract_type_0.DemoPrivateWebRequest request,
  }) => _DemoPrivateWebRouteIntent(
    DemoPrivateWebRouteArguments(request: request),
  );

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<DemoPrivateWebRouteArguments, void>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/web/private",
            primary: true,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _DemoPrivateWebRouteCodec(),
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
final class _DemoPrivateWebRouteIntent implements CCRouteIntent<void> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _DemoPrivateWebRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => DemoPrivateWebRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final DemoPrivateWebRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _DemoPrivateWebRouteCodec
    implements CCRouteCodec<DemoPrivateWebRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _DemoPrivateWebRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  DemoPrivateWebRouteArguments decode(CCEncodedRouteArguments input) {
    final _value_request = input.extra == null
        ? throw CCRouteParameterError(
            "Route \"demo_web.private\" parameter \"request\" is invalid.",
          )
        : input.extra;
    if (_value_request is! contract_type_0.DemoPrivateWebRequest)
      throw CCRouteParameterError(
        "Route \"demo_web.private\" parameter \"request\" is invalid.",
      );
    return DemoPrivateWebRouteArguments(request: _value_request);
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(DemoPrivateWebRouteArguments arguments) {
    return CCEncodedRouteArguments(
      path: {},
      query: {},
      extra: arguments.request,
    );
  }
}
