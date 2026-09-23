import 'package:ccrouter/ccrouter_generated.dart';
import 'package:flutter_test/flutter_test.dart';

abstract interface class _GreetingService {
  String greet();
}

final class _GreetingServiceImpl implements _GreetingService {
  @override
  String greet() => 'hello';
}

final class _Registrar implements CCComponentRegistrar {
  const _Registrar();

  @override
  void register(CCRegistry registry) {
    registry.registerService<_GreetingService>(
      CCServiceProvider(
        contract: _contract,
        factory: (_) => _GreetingServiceImpl(),
      ),
    );
  }
}

const _contract = CCServiceToken<_GreetingService>('fixture.greeting');

void main() {
  tearDown(() async {
    if (CCRouter.isInitialized) await CCRouter.shutdown();
  });

  test('generated-only binding delegates to the active Runtime', () async {
    CCRouter.initialize(
      components: const [
        CCComponentManifest(
          id: 'fixture',
          version: '0.1.0',
          registrar: _Registrar(),
        ),
      ],
    );

    final result =
        await CCRouterGeneratedServiceBinding.invoke<_GreetingService, String>(
          contract: _contract,
          methodId: 'greet',
          callerComponentId: 'consumer',
          call: (service, _) => service.greet(),
        );

    expect(result, 'hello');
    expect(CCRouter.recentTraces.single.operation, 'service');
    expect(CCRouter.recentTraces.single.target, 'fixture.greeting.greet');
  });
}
