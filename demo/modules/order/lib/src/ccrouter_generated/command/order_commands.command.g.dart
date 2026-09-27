// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _CommandGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter_generated.dart';
import 'package:demo_order/src/order_commands.dart' as command_source;
import 'package:demo_order_contracts/src/order_commands.dart' as command_type_0;

/// Registers generated Command `demo_order.reserve`.
void ccrouterRegisterHandleReserveOrderCommand(CCRegistry registry) {
  registry.registerCommand<command_type_0.ReserveOrderCommand, String>(
    command_source.handleReserveOrder,
    commandId: "demo_order.reserve",
  );
}
