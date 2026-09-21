import 'package:ccrouter/ccrouter.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';

import 'ccrouter_generated/component/demo_order_component.routes.g.dart';
import 'demo_order_component.dart';
import 'order_summary_service.dart';

part 'ccrouter_generated/component/demo_order_component_registrar.component.g.dart';

@CCComponent(demoOrderComponent)
final class _DemoOrderComponentRegistrar implements CCComponentRegistrar {
  const _DemoOrderComponentRegistrar();

  @override
  void register(CCRegistry registry) {
    demoOrderComponentGeneratedRoutes.register(registry);
    registry.registerService<OrderSummaryService>(
      CCServiceProvider(
        contract: demoOrderSummaryService,
        factory: (_) => const DemoOrderSummaryService(),
      ),
    );
  }
}
