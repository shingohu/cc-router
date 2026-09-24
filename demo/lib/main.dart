import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:demo_navigation_lab/demo_navigation_lab.dart';
import 'package:flutter/material.dart';

import 'ccrouter_demo.dart';
import 'demo_router_backend.dart';
import 'platform_deep_link_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  CCRouter.initialize(
    components: ccrouterGeneratedComponentManifests,
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
  await CCRouter.runInitialization();
  runApp(const CCRouterDemoApp());
}

final class CCRouterDemoApp extends StatefulWidget {
  const CCRouterDemoApp({
    this.initialLocation = '/',
    this.listenForPlatformLinks = true,
    this.platformLinkStream,
    super.key,
  });

  final String initialLocation;
  final bool listenForPlatformLinks;
  final Stream<Uri>? platformLinkStream;

  @override
  State<CCRouterDemoApp> createState() => _CCRouterDemoAppState();
}

final class _CCRouterDemoAppState extends State<CCRouterDemoApp> {
  late final CCGoRouterBackend _backend;

  @override
  void initState() {
    super.initState();
    _backend = createDemoRouterBackend(
      catalog: ccrouterGeneratedRouteCatalog,
      initialLocation: widget.initialLocation,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = CCRouterApp.managed(
      backend: _backend,
      onLifecycleChanged: (state) =>
          demoNavigationLabStore.record('App lifecycle · ${state.name}'),
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'CCRouter Lab',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00796B)),
          useMaterial3: true,
        ),
        routerConfig: _backend.router,
      ),
    );
    if (!widget.listenForPlatformLinks) return app;
    return DemoPlatformDeepLinkBridge(
      linkStream: widget.platformLinkStream,
      child: app,
    );
  }
}
