import 'package:demo_navigation_lab/src/ccrouter_generated/demo_navigation_lab_component.ui.api.g.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';
import 'package:flutter/material.dart';

/// Uses the consumer-owned generated Client and the real Host assembly.
Widget createOrderPanelFixture({
  required ValueChanged<OrderPanelAction> onAction,
  bool active = true,
}) => MaterialApp(
  home: Scaffold(
    body: DemoNavigationLabComponentFragments.orderPanel(
      props: const OrderPanelProps(),
      active: active,
      onAction: onAction,
    ),
  ),
);
