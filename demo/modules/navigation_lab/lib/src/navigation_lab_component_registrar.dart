import 'package:ccrouter/ccrouter.dart';

import 'ccrouter_generated/component/demo_navigation_lab_component.routes.g.dart';
import 'navigation_lab_component.dart';
import 'policy_pages.dart';
import 'shell_contract.dart';

part 'ccrouter_generated/component/navigation_lab_component_registrar.component.g.dart';

@CCComponent(demoNavigationLabComponent)
final class _DemoNavigationLabComponentRegistrar
    implements CCComponentRegistrar {
  const _DemoNavigationLabComponentRegistrar();

  @override
  void register(CCRegistry registry) {
    registerDemoNavigationLabPolicies(registry);
    registry.registerShell(demoSingleShellDefinition);
    registry.registerShell(demoWorkspaceShellDefinition);
    demoNavigationLabComponentGeneratedRoutes.register(registry);
  }
}
