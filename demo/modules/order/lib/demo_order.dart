import 'package:ccrouter/ccrouter.dart';

import 'src/order_detail_page.dart';

export 'src/order_detail_page.dart'
    show OrderDetailPageRoute, OrderDetailPageRouteArguments;

final class OrderComponentRegistrar implements CCComponentRegistrar {
  const OrderComponentRegistrar();

  static const manifest = CCComponentManifest(
    id: 'order',
    version: '0.1.0',
    registrar: OrderComponentRegistrar(),
  );

  @override
  void register(CCRegistry registry) {
    OrderDetailPageRoute.register(registry);
  }
}
