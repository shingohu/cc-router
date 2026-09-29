// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

import 'package:ccrouter/ccrouter_generated.dart';
import 'package:demo_navigation_lab/src/component_capabilities.dart'
    as command_type_0;
import 'package:demo_order_contracts/demo_order_contracts.dart'
    as command_type_1;

/// Typed Command entry points for component `demo_navigation_lab_component`.
abstract final class DemoNavigationLabCommands {
  /// Dispatches `demo_navigation_lab.create_receipt` through its single owner.
  static Future<String> demoCreateReceipt(
    command_type_0.DemoCreateReceiptCommand command, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => CCRouterGeneratedCommandBinding.invoke(
    command,
    commandId: "demo_navigation_lab.create_receipt",
    callerComponentId: "demo_navigation_lab_component",
    timeout: timeout,
    cancellation: cancellation,
  );

  /// Dispatches `demo_navigation_lab.fail` through its single owner.
  static Future<void> demoFail(
    command_type_0.DemoFailCommand command, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => CCRouterGeneratedCommandBinding.invoke(
    command,
    commandId: "demo_navigation_lab.fail",
    callerComponentId: "demo_navigation_lab_component",
    timeout: timeout,
    cancellation: cancellation,
  );

  /// Dispatches `demo_navigation_lab.refresh_cache` through its single owner.
  static Future<void> demoRefreshCache(
    command_type_0.DemoRefreshCacheCommand command, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => CCRouterGeneratedCommandBinding.invoke(
    command,
    commandId: "demo_navigation_lab.refresh_cache",
    callerComponentId: "demo_navigation_lab_component",
    timeout: timeout,
    cancellation: cancellation,
  );

  /// Dispatches `demo_navigation_lab.wait` through its single owner.
  static Future<void> demoWait(
    command_type_0.DemoWaitCommand command, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => CCRouterGeneratedCommandBinding.invoke(
    command,
    commandId: "demo_navigation_lab.wait",
    callerComponentId: "demo_navigation_lab_component",
    timeout: timeout,
    cancellation: cancellation,
  );

  /// Dispatches `demo_order.reserve` through its single owner.
  static Future<String> reserve(
    command_type_1.ReserveOrderCommand command, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => CCRouterGeneratedCommandBinding.invoke(
    command,
    commandId: "demo_order.reserve",
    callerComponentId: "demo_navigation_lab_component",
    timeout: timeout,
    cancellation: cancellation,
  );
}
