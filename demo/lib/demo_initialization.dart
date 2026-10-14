import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:demo_navigation_lab/demo_navigation_lab.dart';
import 'package:demo_navigation_lab/demo_navigation_lab_host.dart';
import 'package:flutter/widgets.dart';

/// Binds component requests to the application's selected startup Gates.
Widget withDemoInitializationActions(Widget child) => DemoInitializationActions(
  onPrivacyGranted: () async {
    await CCRouterHost.runInitTasks(gate: CCInitTaskGate.privacyGranted);
  },
  onTimeoutLabRequested: () async {
    await CCRouterHost.runInitTasks(gate: DemoInitializationGates.timeoutLab);
  },
  child: child,
);
