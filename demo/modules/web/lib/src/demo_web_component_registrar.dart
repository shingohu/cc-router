import 'package:ccrouter/ccrouter.dart';

import 'ccrouter_generated/component/demo_web_component.routes.g.dart';
import 'demo_web_component.dart';

part 'ccrouter_generated/component/demo_web_component_registrar.component.g.dart';

@CCComponent(demoWebComponent)
final class _DemoWebComponentRegistrar implements CCComponentRegistrar {
  const _DemoWebComponentRegistrar();

  @override
  void register(CCRegistry registry) {
    demoWebComponentGeneratedRoutes.register(registry);
  }
}
