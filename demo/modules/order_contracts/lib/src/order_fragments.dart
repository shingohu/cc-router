import 'package:ccrouter_contracts/ccrouter_ui_contracts.dart';

import 'order_detail_route_contract.dart';

/// Small immutable input; the UI implementation remains in the order component.
final class OrderSummaryProps {
  const OrderSummaryProps({required this.orderId});
  final int orderId;
}

/// A decides whether opening detail should navigate or update its own content.
enum OrderSummaryAction { openDetails }

@CCUIFragmentContract<OrderSummaryProps, OrderSummaryAction>(
  componentId: demoOrderComponentId,
  id: 'order.summary',
  version: '1.0.0',
)
abstract final class OrderSummaryFragmentContract {}

final class OrderRecommendationsProps {
  const OrderRecommendationsProps({required this.category});
  final String category;
}

/// One selection result loaded privately by B, delivered to the calling instance.
final class OrderRecommendationsAction {
  const OrderRecommendationsAction({required this.selectedId});
  final String selectedId;
}

@CCUIFragmentContract<OrderRecommendationsProps, OrderRecommendationsAction>(
  componentId: demoOrderComponentId,
  id: 'order.recommendations',
  version: '2.0.0',
)
abstract final class OrderRecommendationsFragmentContract {}
