/// Component-author integration surface for the order implementation package.
///
/// Business components import `demo_order_contracts.dart`; only the component
/// that owns the destination imports this library to bind its Flutter page.
library;

export 'demo_order_contracts.dart';
export 'src/order_detail_route_contract.dart' show OrderDetailRouteContract;
