import 'package:ccrouter/ccrouter.dart';

import 'contracts.dart';
import 'order_component.dart';
import 'payment_component.dart';

Future<void> main() async {
  await CCRouter.initialize(
    components: [
      OrderComponentRegistrar.manifest,
      PaymentComponentRegistrar.manifest,
    ],
  );
  try {
    CCRouter.openSession(accountId: 'example-account');
    print(await CCRouter.command(const CreateOrder(100)));
    await CCRouter.closeSession();
    print(
      'components: ${CCRouter.registeredComponents.map((item) => item.id).join(', ')}',
    );
    print('traces: ${CCRouter.recentTraces.length}');
  } finally {
    await CCRouter.shutdown();
  }
}
