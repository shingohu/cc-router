// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

part of '../order_detail_page.dart';

// **************************************************************************
// _RouteGenerator
// **************************************************************************

/// Immutable arguments for route order.detail; URI values remain typed.
final class OrderDetailPageRouteArguments {
  /// Creates arguments without navigating or retaining a backend context.
  const OrderDetailPageRouteArguments({
    required this.orderId,
    this.tab = 'summary',
  });

  /// path parameter orderId for order.detail.
  final int orderId;

  /// query parameter tab for order.detail.
  final String tab;
}

/// 订单详情，确认后返回订单编号。
abstract final class OrderDetailPageRoute {
  /// Stable identity used by registration, diagnostics and typed navigation.
  static const id = "order.detail";

  /// Creates a typed Intent; navigate through CCRouter.navigator.
  static CCRouteIntent<String> intent({
    required int orderId,
    String tab = 'summary',
  }) => _OrderDetailPageRouteIntent(
    OrderDetailPageRouteArguments(orderId: orderId, tab: tab),
  );

  /// Component-owned definition; registration does not select a backend.
  static final definition =
      CCRouteDefinition<OrderDetailPageRouteArguments, String>(
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
        codec: const _OrderDetailPageRouteCodec(),
        visibility: CCRouteVisibility.exported,
        visibleTo: const <String>{},
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
          routeKind: CCRouteKind.page,
        ),
        interceptorIds: const [],
        description: "订单详情，确认后返回订单编号。",
      );

  /// Called by the owning component registrar, never by a business caller.
  static void register(CCRegistry registry) =>
      registry.registerRoute(definition);

  /// Injects already decoded arguments into the page without backend coupling.
  static OrderDetailPage build(OrderDetailPageRouteArguments arguments) =>
      OrderDetailPage(orderId: arguments.orderId, tab: arguments.tab);
}

/// Private data-only Intent carrying this route's typed result contract.
final class _OrderDetailPageRouteIntent implements CCRouteIntent<String> {
  /// Captures immutable typed arguments for later Runtime validation.
  const _OrderDetailPageRouteIntent(this.arguments);

  /// Stable identity of the owned destination.
  @override
  String get routeId => OrderDetailPageRoute.id;

  /// Typed payload consumed only by the matching route codec.
  @override
  final OrderDetailPageRouteArguments arguments;
}

/// Package-internal bridge used by the generated component route index.
///
/// Keep this symbol out of public package barrels. It exists so a component
/// registrar can register library-private routes without exposing their
/// typed contracts to business code.
void ccrouterRegisterOrderDetailPageRoute(CCRegistry registry) =>
    OrderDetailPageRoute.register(registry);

/// Private boundary conversion; raw input is never included in error messages.
final class _OrderDetailPageRouteCodec
    implements CCRouteCodec<OrderDetailPageRouteArguments> {
  /// Stateless codec shared by the component's route definition.
  const _OrderDetailPageRouteCodec();

  /// Rejects missing, repeated or malformed values before creating a page.
  @override
  OrderDetailPageRouteArguments decode(CCEncodedRouteArguments input) {
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
    final String _value_tab = _raw_tab == null ? 'summary' : _raw_tab;
    return OrderDetailPageRouteArguments(
      orderId: _value_orderId,
      tab: _value_tab,
    );
  }

  /// Encodes unescaped scalar values; Runtime owns URI escaping exactly once.
  @override
  CCEncodedRouteArguments encode(OrderDetailPageRouteArguments arguments) {
    return CCEncodedRouteArguments(
      path: {"orderId": arguments.orderId.toString()},
      query: {
        "tab": [arguments.tab],
      },
      extra: null,
    );
  }
}
