import 'package:ccrouter/ccrouter.dart';

import 'ccrouter_generated/demo_navigation_lab_component.routes.g.dart';
import 'navigation_lab_component.dart';
import 'policy_pages.dart';

part 'ccrouter_generated/navigation_lab_component_registrar.component.g.dart';

@CCComponent(demoNavigationLabComponent)
final class _DemoNavigationLabComponentRegistrar
    implements CCComponentRegistrar {
  const _DemoNavigationLabComponentRegistrar();

  @override
  void register(CCRegistry registry) {
    registerDemoNavigationLabPolicies(registry);
    demoNavigationLabComponentGeneratedRoutes.register(registry);
  }
}
