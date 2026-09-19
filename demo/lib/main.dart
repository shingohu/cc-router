import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:demo_navigation_lab/demo_navigation_lab.dart';
import 'package:flutter/material.dart';

import 'ccrouter_generated/ccrouter_host.routes.g.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  CCRouter.initialize(
    components: ccrouterGeneratedComponentManifests,
    globalInterceptors: const [
      CCGlobalNavigationInterceptor(
        id: 'demo.global.policy',
        interceptor: DemoGlobalNavigationInterceptor(),
      ),
    ],
    navigationFailurePolicy: const DemoNavigationFailurePolicy(),
    navigationAspects: [demoNavigationAspect],
    telemetryContextProvider: const DemoNavigationTelemetryProvider(),
  );
  runApp(const CCRouterDemoApp());
}

final class CCRouterDemoApp extends StatefulWidget {
  const CCRouterDemoApp({super.key});

  @override
  State<CCRouterDemoApp> createState() => _CCRouterDemoAppState();
}

final class _CCRouterDemoAppState extends State<CCRouterDemoApp> {
  late final CCGoRouterBackend _backend;

  @override
  void initState() {
    super.initState();
    _backend = CCGoRouterBackend.managed(
      catalog: ccrouterGeneratedRouteCatalog,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CCRouterApp.managed(
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
  }
}
