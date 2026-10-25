// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import
import 'package:flutter/widgets.dart';
import 'package:ccrouter_ui/ccrouter_ui_generated.dart';
import "package:demo_navigation_lab/src/navigation_lab_component.dart" as ui_0;
import "package:demo_order_contracts/src/order_panel_fragment.dart" as ui_1;
import "package:demo_order_contracts/src/order_fragments.dart" as ui_2;

abstract final class DemoNavigationLabComponentFragments {
  static Widget orderPanel({
    Key? key,
    required ui_1.OrderPanelProps props,
    required ValueChanged<ui_1.OrderPanelAction> onAction,
    bool active = true,
  }) => CCUIGeneratedFragment<ui_1.OrderPanelProps, ui_1.OrderPanelAction>(
    key: key,
    props: props,
    onAction: onAction,
    active: active,
    requirement: const CCUIFragmentRequirement(
      consumer: "demo_navigation_lab_component",
      contract: const CCUIFragmentDescriptor(
        owner: "demo_order_component",
        id: "order.panel",
        version: "1.0.0",
        fingerprint:
            "b6dc30358b7f47719d5cb0f80b23711e54de0367fa7aeb732d67668a275f26ba",
      ),
      versionRange: "^1.0.0",
    ),
  );
  static Widget orderSummary({
    Key? key,
    required ui_2.OrderSummaryProps props,
    required ValueChanged<ui_2.OrderSummaryAction> onAction,
    bool active = true,
  }) => CCUIGeneratedFragment<ui_2.OrderSummaryProps, ui_2.OrderSummaryAction>(
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
    required ui_2.OrderRecommendationsProps props,
    required ValueChanged<ui_2.OrderRecommendationsAction> onAction,
    bool active = true,
  }) =>
      CCUIGeneratedFragment<
        ui_2.OrderRecommendationsProps,
        ui_2.OrderRecommendationsAction
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
            version: "2.0.0",
            fingerprint:
                "0fd30e583936c0c3b491f660086fe5dbdd9fd1088ddb55e5c84a6bf9c81e7b45",
          ),
          versionRange: "^2.0.0",
        ),
      );
}

final ccUIContributions = <CCUIFragmentContribution>[];
const ccUIRequirements = <CCUIFragmentRequirement>[
  CCUIFragmentRequirement(
    consumer: "demo_navigation_lab_component",
    contract: CCUIFragmentDescriptor(
      owner: "demo_order_component",
      id: "order.panel",
      version: "1.0.0",
      fingerprint:
          "b6dc30358b7f47719d5cb0f80b23711e54de0367fa7aeb732d67668a275f26ba",
    ),
    versionRange: "^1.0.0",
  ),
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
      version: "2.0.0",
      fingerprint:
          "0fd30e583936c0c3b491f660086fe5dbdd9fd1088ddb55e5c84a6bf9c81e7b45",
    ),
    versionRange: "^2.0.0",
  ),
];
