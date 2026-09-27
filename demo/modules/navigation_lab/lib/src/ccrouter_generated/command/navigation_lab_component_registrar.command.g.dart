// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// ignore_for_file: type=lint, unused_element

// **************************************************************************
// _CommandGenerator
// **************************************************************************

import 'package:ccrouter/ccrouter_generated.dart';
import 'package:demo_navigation_lab/src/navigation_lab_component_registrar.dart'
    as command_source;
import 'package:demo_navigation_lab/src/component_capabilities.dart'
    as command_type_0;

/// Registers generated Command `demo_navigation_lab.create_receipt`.
void ccrouterRegisterHandleDemoCreateReceiptCommand(CCRegistry registry) {
  registry.registerCommand<command_type_0.DemoCreateReceiptCommand, String>(
    (command, _) => command_source.handleDemoCreateReceipt(command),
    commandId: "demo_navigation_lab.create_receipt",
  );
}

/// Registers generated Command `demo_navigation_lab.fail`.
void ccrouterRegisterHandleDemoFailCommand(CCRegistry registry) {
  registry.registerCommand<command_type_0.DemoFailCommand, void>(
    (command, _) => command_source.handleDemoFail(command),
    commandId: "demo_navigation_lab.fail",
  );
}

/// Registers generated Command `demo_navigation_lab.refresh_cache`.
void ccrouterRegisterHandleDemoRefreshCacheCommand(CCRegistry registry) {
  registry.registerCommand<command_type_0.DemoRefreshCacheCommand, void>(
    (command, _) => command_source.handleDemoRefreshCache(command),
    commandId: "demo_navigation_lab.refresh_cache",
  );
}

/// Registers generated Command `demo_navigation_lab.wait`.
void ccrouterRegisterHandleDemoWaitCommand(CCRegistry registry) {
  registry.registerCommand<command_type_0.DemoWaitCommand, void>(
    command_source.handleDemoWait,
    commandId: "demo_navigation_lab.wait",
  );
}
