import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:demo_navigation_lab/demo_navigation_lab.dart';
import 'package:flutter/material.dart';

import 'ccrouter_demo.dart';
import 'demo_router_backend.dart';
import 'demo_initialization.dart';
import 'platform_deep_link_bridge.dart';

Future<void> main() => runDemo();

/// Shares startup with the opt-in predictive-back verification entry point.
Future<void> runDemo({
  bool enablePredictiveBack = false,
  bool useManagedBackend = false,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  CCRouterHost.initialize(
    hostAssembly: ccrouterGeneratedHostAssembly,
    deepLinkIngressPolicy: demoDeepLinkIngressPolicy,
    globalInterceptors: const [
      CCGlobalNavigationInterceptor(
        id: DemoHostIds.globalNavigationInterceptor,
        interceptor: DemoGlobalNavigationInterceptor(),
      ),
    ],
    navigationFailurePolicy: const DemoNavigationFailurePolicy(),
    navigationAspects: [
      demoNavigationAspect,
      demoNavigationAnalytics.createAspect(),
    ],
    telemetryContextProvider: const DemoNavigationTelemetryProvider(),
    diagnostics: CCDiagnosticsConfig(
      sink: demoDiagnosticsSink,
      defaultMinimumLevel: CCDiagnosticLevel.debug,
      policies: const [
        CCDiagnosticCategoryPolicy(
          category: CCDiagnosticCategory.navigation,
          minimumLevel: CCDiagnosticLevel.debug,
        ),
        CCDiagnosticCategoryPolicy(
          category: CCDiagnosticCategory.event,
          minimumLevel: CCDiagnosticLevel.info,
        ),
      ],
    ),
  );
  await CCRouterHost.runInitTasks(gate: CCInitTaskGate.appStarted);
  runApp(
    CCRouterDemoApp(
      enablePredictiveBack: enablePredictiveBack,
      useManagedBackend: useManagedBackend,
    ),
  );
}

final class CCRouterDemoApp extends StatelessWidget {
  const CCRouterDemoApp({
    this.initialLocation = '/',
    this.listenForPlatformLinks = true,
    this.platformLinkStream,
    this.enablePredictiveBack = false,
    this.useManagedBackend = false,
    super.key,
  });

  final String initialLocation;
  final bool listenForPlatformLinks;
  final Stream<Uri>? platformLinkStream;
  final bool enablePredictiveBack;

  /// Enables the new Runtime Managed Backend for A/B migration checks.
  ///
  /// The default remains the GoRouter compatibility path so existing Demo
  /// coverage and integrations can migrate Host by Host.
  final bool useManagedBackend;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00796B)),
      useMaterial3: true,
    );
    final app = useManagedBackend
        ? _buildManagedApp(theme)
        : _buildGoRouterApp(theme);
    return withDemoInitializationActions(
      listenForPlatformLinks
          ? DemoPlatformDeepLinkBridge(
              linkStream: platformLinkStream,
              child: app,
            )
          : app,
    );
  }

  Widget _buildManagedApp(ThemeData theme) {
    final backend = createDemoManagedRouterBackend(
      catalog: ccrouterGeneratedHostAssembly.routeCatalog,
      initialLocation: initialLocation,
      enablePredictiveBack: enablePredictiveBack,
    );
    backend.adapter.predictiveBackBridge?.addPredictiveBackListener((event) {
      if (event.phase != CCPredictiveBackPhase.updated) {
        demoNavigationLabStore.record('Predictive back · ${event.phase.name}');
      }
    });
    return CCRouterApp.managed(
      backend: backend,
      onLifecycleChanged: _recordLifecycle,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'CCRouter Lab',
        theme: theme,
        routerConfig: backend.routerConfig,
      ),
    );
  }

  Widget _buildGoRouterApp(ThemeData theme) => CCGoRouterApp(
    initialLocation: initialLocation,
    enablePredictiveBack: enablePredictiveBack,
    backendFactory: (configuration) {
      final backend = createDemoRouterBackend(
        catalog: configuration.catalog,
        initialLocation: configuration.initialLocation,
        enablePredictiveBack: configuration.enablePredictiveBack,
      );
      backend.adapter.predictiveBackBridge?.addPredictiveBackListener((event) {
        if (event.phase != CCPredictiveBackPhase.updated) {
          demoNavigationLabStore.record(
            'Predictive back · ${event.phase.name}',
          );
        }
      });
      return backend;
    },
    onLifecycleChanged: _recordLifecycle,
    debugShowCheckedModeBanner: false,
    title: 'CCRouter Lab',
    theme: theme,
  );

  void _recordLifecycle(AppLifecycleState state) {
    demoNavigationLabStore.record('App lifecycle · ${state.name}');
    final now = DateTime.now();
    if (state == AppLifecycleState.resumed) {
      demoNavigationAnalytics.onForeground(now);
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      demoNavigationAnalytics.onBackground(now);
    }
  }
}
