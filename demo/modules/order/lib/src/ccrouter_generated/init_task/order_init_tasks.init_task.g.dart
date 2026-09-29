// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _InitTaskGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter.dart';
import 'package:demo_order/src/order_init_tasks.dart' as init_source;

/// Registers generated InitTask `demo_order.startup.foundation`.
void ccrouterRegisterInitializeDemoOrderFoundationInitTask(
  CCRegistry registry,
) {
  registry.registerInitTask(
    CCInitTaskDefinition(
      id: "demo_order.startup.foundation",
      dependsOn: const [],
      gate: CCInitTaskGate("appStarted"),
      failurePolicy: CCInitTaskFailurePolicy.critical,
      run: (_) => init_source.initializeDemoOrderFoundation(),
    ),
  );
}
