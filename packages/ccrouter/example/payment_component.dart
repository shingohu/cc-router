import 'package:ccrouter/ccrouter.dart';

import 'contracts.dart';

final class PaymentComponentRegistrar implements CCComponentRegistrar {
  const PaymentComponentRegistrar();

  static const manifest = CCComponentManifest(
    id: 'payment',
    version: '0.1.0',
    registrar: PaymentComponentRegistrar(),
  );

  @override
  void register(CCRegistry registry) {
    registry.registerService<PaymentService>(
      CCServiceProvider(
        scope: CCServiceScope.session,
        factory: (_) => _PaymentService(),
      ),
    );
  }
}

final class _PaymentService implements PaymentService, CCDisposable {
  bool _disposed = false;

  @override
  Future<String> pay(int amount) async {
    if (_disposed) throw StateError('Payment service has been disposed.');
    return 'paid:$amount';
  }

  @override
  void dispose() => _disposed = true;
}
