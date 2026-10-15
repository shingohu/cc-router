// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import
import 'package:flutter/widgets.dart';
import 'package:ccrouter_ui/ccrouter_ui_generated.dart';
import "package:demo_order/src/order_fragment_renderers.dart" as ui_0;
import "package:demo_order_contracts/src/order_fragments.dart" as ui_1;

final ccUIContributions = <CCUIFragmentContribution>[
  CCUIRenderer<ui_1.OrderSummaryProps, ui_1.OrderSummaryAction>(
    contract: const CCUIFragmentDescriptor(
      owner: "demo_order_component",
      id: "order.summary",
      version: "1.0.0",
      fingerprint:
          "61967f68b1e2278a9d01482a9c28957ef5b734e03b4b7b1770e9a1ee7e1fdbbb",
    ),
    renderer: ui_0.renderOrderSummary,
  ),
  CCUIRenderer<ui_1.OrderRecommendationsProps, ui_1.OrderRecommendationsAction>(
    contract: const CCUIFragmentDescriptor(
      owner: "demo_order_component",
      id: "order.recommendations",
      version: "1.0.0",
      fingerprint:
          "981dd30de35264dbec8ff547af3cd8af2c3f2eb680958b7c0b7626a395e9dc30",
    ),
    renderer: ui_0.renderOrderRecommendations,
  ),
];
const ccUIRequirements = <CCUIFragmentRequirement>[];
