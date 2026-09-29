// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

import 'package:ccrouter/ccrouter_generated.dart';
import 'package:demo_order_contracts/src/order_commands.dart' as command_type_0;

/// Typed Command entry points for component `demo_order_component`.
abstract final class DemoOrderCommands {
  /// Dispatches `demo_order.reserve` through its single owner.
  static Future<String> reserve(
    command_type_0.ReserveOrderCommand command, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => CCRouterGeneratedCommandBinding.invoke(
    command,
    commandId: "demo_order.reserve",
    callerComponentId: "demo_order_component",
    timeout: timeout,
    cancellation: cancellation,
  );
}
