import 'package:ccrouter/ccrouter.dart';

import 'ccrouter_generated/demo_payment_component.routes.g.dart';
import 'demo_payment_component.dart';

part 'ccrouter_generated/demo_payment_component_registrar.component.g.dart';

/// Registers the payment component without exposing Runtime internals.
@CCComponent(demoPaymentComponent)
final class _DemoPaymentComponentRegistrar implements CCComponentRegistrar {
  /// Creates the stateless generated component registrar.
  const _DemoPaymentComponentRegistrar();

  /// Registers payment-owned capabilities during Runtime assembly.
  @override
  void register(CCRegistry registry) {
    demoPaymentComponentGeneratedRoutes.register(registry);
  }
}
