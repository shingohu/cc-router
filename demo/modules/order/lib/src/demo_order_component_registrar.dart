import 'package:ccrouter/ccrouter.dart';

import 'demo_order_component.dart';
import 'order_detail_page.dart';

@CCComponent(demoOrderComponent)
final class _DemoOrderComponentRegistrar implements CCComponentRegistrar {
  const _DemoOrderComponentRegistrar();

  @override
  void register(CCRegistry registry) {
    OrderDetailPageRoute.register(registry);
  }
}

const demoOrderComponentManifest = CCComponentManifest.fromDescriptor(
  descriptor: demoOrderComponent,
  registrar: _DemoOrderComponentRegistrar(),
);
