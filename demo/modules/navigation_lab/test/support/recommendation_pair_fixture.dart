import 'package:demo_navigation_lab/src/ccrouter_generated/demo_navigation_lab_component.ui.api.g.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';
import 'package:flutter/material.dart';

/// Composes two instances through A's own generated UI Client for Host tests.
///
/// This fixture stays under A's test directory so the integration test can use
/// the real Host assembly without exporting A's generated Client to business.
Widget createRecommendationPairFixture({
  required String category,
  required ValueChanged<OrderRecommendationsAction> onFirstAction,
  required ValueChanged<OrderRecommendationsAction> onSecondAction,
  bool active = true,
}) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: [
        DemoNavigationLabComponentFragments.orderRecommendations(
          key: const ValueKey('first'),
          props: OrderRecommendationsProps(category: category),
          active: active,
          onAction: onFirstAction,
        ),
        DemoNavigationLabComponentFragments.orderRecommendations(
          key: const ValueKey('second'),
          props: const OrderRecommendationsProps(category: '新品'),
          onAction: onSecondAction,
        ),
      ],
    ),
  ),
);
