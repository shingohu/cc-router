import 'dart:async';

import 'package:ccrouter/ccrouter_host.dart' show CCPredictiveBackPhase;
// ignore: deprecated_member_use
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:demo_navigation_lab/demo_navigation_lab.dart';
import 'package:flutter/material.dart';

import 'demo_initialization.dart';
import 'demo_router_backend.dart';
import 'main.dart'
    show createDemoTheme, recordDemoLifecycle, runDemoApplication;
import 'platform_deep_link_bridge.dart';

/// Starts the frozen GoRouter compatibility Host for migration comparison.
Future<void> runGoRouterCompatibilityDemo({
  bool enablePredictiveBack = false,
}) => runDemoApplication(
  CCGoRouterCompatibilityDemoApp(enablePredictiveBack: enablePredictiveBack),
);

/// Explicit compatibility application retained only for migration regression.
final class CCGoRouterCompatibilityDemoApp extends StatelessWidget {
  /// Creates the compatibility Host with the shared Demo feature surface.
  const CCGoRouterCompatibilityDemoApp({
    this.initialLocation = '/',
    this.listenForPlatformLinks = true,
    this.platformLinkStream,
    this.enablePredictiveBack = false,
    super.key,
  });

  /// Trusted startup location passed to the compatibility Backend.
  final String initialLocation;

  /// Whether the Host subscribes to platform Deep Links.
  final bool listenForPlatformLinks;

  /// Optional platform-link stream used by tests and custom launchers.
  final Stream<Uri>? platformLinkStream;

  /// Enables the compatibility predictive-back bridge.
  final bool enablePredictiveBack;

  @override
  Widget build(BuildContext context) {
    final app = CCGoRouterApp(
      initialLocation: initialLocation,
      enablePredictiveBack: enablePredictiveBack,
      backendFactory: (configuration) {
        final backend = createDemoRouterBackend(
          catalog: configuration.catalog,
          initialLocation: configuration.initialLocation,
          enablePredictiveBack: configuration.enablePredictiveBack,
        );
        backend.adapter.predictiveBackBridge?.addPredictiveBackListener((
          event,
        ) {
          if (event.phase != CCPredictiveBackPhase.updated) {
            demoNavigationLabStore.record(
              'Predictive back · ${event.phase.name}',
            );
          }
        });
        return backend;
      },
      onLifecycleChanged: recordDemoLifecycle,
      debugShowCheckedModeBanner: false,
      title: 'CCRouter Lab · GoRouter Compatibility',
      theme: createDemoTheme(),
    );
    return withDemoInitializationActions(
      listenForPlatformLinks
          ? DemoPlatformDeepLinkBridge(
              linkStream: platformLinkStream,
              child: app,
            )
          : app,
    );
  }
}
