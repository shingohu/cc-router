import 'package:ccrouter/ccrouter.dart';

import 'src/order_detail_page.dart';
import 'src/order_component.dart';

export 'src/order_detail_page.dart'
    show OrderDetailPageRoute, OrderDetailPageRouteArguments;

@CCComponent(orderComponent)
final class OrderComponentRegistrar implements CCComponentRegistrar {
  const OrderComponentRegistrar();

  static const manifest = CCComponentManifest.fromDescriptor(
    descriptor: orderComponent,
    registrar: OrderComponentRegistrar(),
  );

  @override
  void register(CCRegistry registry) {
    OrderDetailPageRoute.register(registry);
  }
}
