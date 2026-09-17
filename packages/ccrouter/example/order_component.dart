import 'package:ccrouter/ccrouter.dart';

import 'contracts.dart';

final class OrderComponentRegistrar implements CCComponentRegistrar {
  const OrderComponentRegistrar();

  static const manifest = CCComponentManifest(
    id: 'order',
    version: '0.1.0',
    dependencies: ['payment'],
    registrar: OrderComponentRegistrar(),
  );

  @override
  void register(CCRegistry registry) {
    registry.registerCommand<CreateOrder, String>((command, context) async {
      final payment = CCRouter.service<PaymentService>();
      return 'order:${await payment.pay(command.amount)}';
    });
  }
}
