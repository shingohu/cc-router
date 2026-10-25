import 'package:ccrouter_contracts/ccrouter_ui_contracts.dart';

import 'order_detail_route_contract.dart';

part 'order_panel_targets.dart';

/// Immutable input, independent of the sealed output protocol.
final class OrderPanelProps {
  const OrderPanelProps();
}

/// Different local intents retain their own payload shape.
sealed class OrderPanelAction {
  const OrderPanelAction();
}

final class OrderPanelSettingsRequested extends OrderPanelAction {
  const OrderPanelSettingsRequested();
}

final class OrderPanelTargetSelected extends OrderPanelAction {
  const OrderPanelTargetSelected(this.target);
  final OrderPanelTarget target;
}

@CCUIFragmentContract<OrderPanelProps, OrderPanelAction>(
  componentId: demoOrderComponentId,
  id: 'order.panel',
  version: '1.0.0',
)
abstract final class OrderPanelFragmentContract {}
