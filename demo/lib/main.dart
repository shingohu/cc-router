import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:demo_navigation_lab/demo_navigation_lab.dart';
import 'package:flutter/material.dart';

import 'ccrouter_demo.dart';
import 'demo_managed_router_backend.dart';
import 'demo_initialization.dart';
import 'platform_deep_link_bridge.dart';

Future<void> main() => runDemo();

/// Shares startup with the opt-in predictive-back verification entry point.
Future<void> runDemo({bool enablePredictiveBack = false}) => runDemoApplication(
  CCRouterDemoApp(enablePredictiveBack: enablePredictiveBack),
);

/// Initializes the shared Demo Runtime before mounting one Host application.
Future<void> runDemoApplication(Widget application) async {
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
  runApp(application);
}

/// Default Demo application backed by the native Managed Stack.
final class CCRouterDemoApp extends StatefulWidget {
  const CCRouterDemoApp({
    this.initialLocation = '/',
    this.listenForPlatformLinks = true,
    this.platformLinkStream,
    this.enablePredictiveBack = false,
    super.key,
  });

  final String initialLocation;
  final bool listenForPlatformLinks;
  final Stream<Uri>? platformLinkStream;
  final bool enablePredictiveBack;

  @override
  State<CCRouterDemoApp> createState() => _CCRouterDemoAppState();
}

/// Retains one stable Backend factory for the Managed Host lifetime.
final class _CCRouterDemoAppState extends State<CCRouterDemoApp> {
  late final CCManagedRouterBackendFactory _backendFactory = _createBackend;

  /// Creates the Demo's Shell/Outlet topology from the initialized Catalog.
  CCManagedRouterBackend _createBackend(
    CCManagedRouterBackendConfiguration configuration,
  ) {
    final backend = createDemoManagedRouterBackend(
      catalog: configuration.catalog,
      initialLocation: configuration.initialLocation ?? '/',
      enablePredictiveBack: configuration.enablePredictiveBack,
      initializeFromRouteInformation:
          configuration.initializeFromRouteInformation,
    );
    backend.adapter.predictiveBackBridge?.addPredictiveBackListener((event) {
      if (event.phase != CCPredictiveBackPhase.updated) {
        demoNavigationLabStore.record('Predictive back · ${event.phase.name}');
      }
    });
    return backend;
  }

  @override
  Widget build(BuildContext context) {
    final app = CCManagedRouterApp(
      backendFactory: _backendFactory,
      initialLocation: widget.initialLocation,
      enablePredictiveBack: widget.enablePredictiveBack,
      onLifecycleChanged: recordDemoLifecycle,
      debugShowCheckedModeBanner: false,
      title: 'CCRouter Lab',
      theme: createDemoTheme(),
    );
    return withDemoInitializationActions(
      widget.listenForPlatformLinks
          ? DemoPlatformDeepLinkBridge(
              linkStream: widget.platformLinkStream,
              child: app,
            )
          : app,
    );
  }
}

/// Creates the visual theme shared by Managed and compatibility launchers.
ThemeData createDemoTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00796B)),
  useMaterial3: true,
);

/// Forwards Flutter lifecycle changes to Demo diagnostics and analytics.
void recordDemoLifecycle(AppLifecycleState state) {
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
