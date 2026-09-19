import 'package:ccrouter/ccrouter.dart';

import 'ccrouter_generated/demo_order_component.routes.g.dart';
import 'demo_order_component.dart';

@CCComponent(demoOrderComponent)
final class _DemoOrderComponentRegistrar implements CCComponentRegistrar {
  const _DemoOrderComponentRegistrar();

  @override
  void register(CCRegistry registry) {
    demoOrderComponentGeneratedRoutes.register(registry);
  }
}

const demoOrderComponentManifest = CCComponentManifest.fromDescriptor(
  descriptor: demoOrderComponent,
  registrar: _DemoOrderComponentRegistrar(),
);
