// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _RouteContractGenerator
// **************************************************************************

import 'package:ccrouter_contracts/ccrouter_contracts.dart';

/// Immutable arguments for route order.detail; URI values remain typed.
final class OrderDetailRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const OrderDetailRouteArguments({
    required this.orderId,
    this.tab = "summary",
  });

  /// path parameter orderId for order.detail.
  final int orderId;

  /// query parameter tab for order.detail.
  final String tab;
}

/// 订单详情，确认后返回订单编号。
abstract final class OrderDetailRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "order.detail";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<String> intent({
    required int orderId,
    String tab = "summary",
  }) => _OrderDetailRouteIntent(
    OrderDetailRouteArguments(orderId: orderId, tab: tab),
  );

  /// Component-owned definition; business callers should use [intent].
  static final definition =
      CCRouteDefinition<OrderDetailRouteArguments, String>(
        routeId: id,
        patterns: const [
          const CCPathPattern(
            "/orders/:orderId",
            primary: true,
            constraints: const <String, String>{},
          ),
          const CCPathPattern(
            "/order/:orderId",
            primary: false,
            constraints: const <String, String>{},
          ),
        ],
        codec: const _OrderDetailRouteCodec(),
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
final class _OrderDetailRouteIntent implements CCRouteIntent<String> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _OrderDetailRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => OrderDetailRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final OrderDetailRouteArguments arguments;
}

/// Private boundary conversion; raw input is never included in error messages.
final class _OrderDetailRouteCodec
    implements CCRouteCodec<OrderDetailRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _OrderDetailRouteCodec();

  /// Rejects missing, repeated or malformed values before creating arguments.
  @override
  OrderDetailRouteArguments decode(CCEncodedRouteArguments input) {
    final _raw_orderId = input.path["orderId"];
    final int _value_orderId = _raw_orderId == null
        ? throw CCRouteParameterError(
            "Route \"order.detail\" parameter \"orderId\" is invalid.",
          )
        : (int.tryParse(_raw_orderId) ??
              (throw CCRouteParameterError(
                "Route \"order.detail\" parameter \"orderId\" is invalid.",
              )));
    final _values_tab = input.query["tab"];
    if (_values_tab != null && _values_tab.length != 1)
      throw CCRouteParameterError(
        "Route \"order.detail\" parameter \"tab\" is invalid.",
      );
    final _raw_tab = _values_tab?.single;
    final String _value_tab = _raw_tab == null ? "summary" : _raw_tab;
    return OrderDetailRouteArguments(orderId: _value_orderId, tab: _value_tab);
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(OrderDetailRouteArguments arguments) {
    return CCEncodedRouteArguments(
      path: {"orderId": arguments.orderId.toString()},
      query: {
        "tab": [arguments.tab],
      },
      extra: null,
    );
  }
}
