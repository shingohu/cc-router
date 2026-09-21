/// Component-author integration surface for the order implementation package.
///
/// Business components import `demo_order_contracts.dart`; only the component
/// that owns the destination imports this library to bind its Flutter page.
library;

export 'src/ccrouter_generated/contract/order_detail_route_contract.route.contract.g.dart'
    show OrderDetailRoute, OrderDetailRouteArguments;
export 'src/order_detail_route_contract.dart'
    show demoOrderComponent, OrderDetailRouteContract;
