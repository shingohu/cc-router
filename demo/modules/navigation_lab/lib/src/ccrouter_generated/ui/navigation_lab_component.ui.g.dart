// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import
import 'package:flutter/widgets.dart';
import 'package:ccrouter_ui/ccrouter_ui_generated.dart';
import "package:demo_navigation_lab/src/navigation_lab_component.dart" as ui_0;
import "package:demo_order_contracts/src/order_fragments.dart" as ui_1;

abstract final class DemoNavigationLabComponentFragments {
  static Widget orderSummary({
    Key? key,
    required ui_1.OrderSummaryProps props,
    required ValueChanged<ui_1.OrderSummaryAction> onAction,
    bool active = true,
  }) => CCUIGeneratedFragment<ui_1.OrderSummaryProps, ui_1.OrderSummaryAction>(
    key: key,
    props: props,
    onAction: onAction,
    active: active,
    requirement: const CCUIFragmentRequirement(
      consumer: "demo_navigation_lab_component",
      contract: const CCUIFragmentDescriptor(
        owner: "demo_order_component",
        id: "order.summary",
        version: "1.0.0",
        fingerprint:
            "61967f68b1e2278a9d01482a9c28957ef5b734e03b4b7b1770e9a1ee7e1fdbbb",
      ),
      versionRange: "^1.0.0",
    ),
  );
  static Widget orderRecommendations({
    Key? key,
    required ui_1.OrderRecommendationsProps props,
    required ValueChanged<ui_1.OrderRecommendationsAction> onAction,
    bool active = true,
  }) =>
      CCUIGeneratedFragment<
        ui_1.OrderRecommendationsProps,
        ui_1.OrderRecommendationsAction
      >(
        key: key,
        props: props,
        onAction: onAction,
        active: active,
        requirement: const CCUIFragmentRequirement(
          consumer: "demo_navigation_lab_component",
          contract: const CCUIFragmentDescriptor(
            owner: "demo_order_component",
            id: "order.recommendations",
            version: "1.0.0",
            fingerprint:
                "981dd30de35264dbec8ff547af3cd8af2c3f2eb680958b7c0b7626a395e9dc30",
          ),
          versionRange: "^1.0.0",
        ),
      );
}

final ccUIContributions = <CCUIFragmentContribution>[];
const ccUIRequirements = <CCUIFragmentRequirement>[
  CCUIFragmentRequirement(
    consumer: "demo_navigation_lab_component",
    contract: CCUIFragmentDescriptor(
      owner: "demo_order_component",
      id: "order.summary",
      version: "1.0.0",
      fingerprint:
          "61967f68b1e2278a9d01482a9c28957ef5b734e03b4b7b1770e9a1ee7e1fdbbb",
    ),
    versionRange: "^1.0.0",
  ),
  CCUIFragmentRequirement(
    consumer: "demo_navigation_lab_component",
    contract: CCUIFragmentDescriptor(
      owner: "demo_order_component",
      id: "order.recommendations",
      version: "1.0.0",
      fingerprint:
          "981dd30de35264dbec8ff547af3cd8af2c3f2eb680958b7c0b7626a395e9dc30",
    ),
    versionRange: "^1.0.0",
  ),
];
