import 'package:ccrouter/ccrouter_generated.dart';
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:flutter_test/flutter_test.dart';

abstract interface class _GreetingService {
  String greet();
}

final class _GreetingServiceImpl implements _GreetingService {
  @override
  String greet() => 'hello';
}

var _initializations = 0;

final class _Registrar implements CCComponentRegistrar {
  const _Registrar();

  @override
  void register(CCRegistry registry) {
    registry.registerService<_GreetingService>(
      CCServiceProvider(
        contractToken: _contract,
        factory: (_) => _GreetingServiceImpl(),
        initializer: (_, _) async {
          _initializations++;
        },
      ),
    );
  }
}

final class _EmptyRegistrar implements CCComponentRegistrar {
  const _EmptyRegistrar();

  @override
  void register(CCRegistry registry) {}
}

const _contract = CCServiceToken<_GreetingService>('fixture.greeting');

void main() {
  test('generated-only binding delegates to the active Runtime', () async {
    _initializations = 0;
    final host = CCRouterTestHost(
      components: const [
        CCComponentManifest(
          id: 'fixture',
          version: '0.1.0',
          registrar: _Registrar(),
        ),
        CCComponentManifest(
          id: 'consumer',
          version: '0.1.0',
          dependencies: ['fixture'],
          registrar: _EmptyRegistrar(),
        ),
      ],
    );
    addTearDown(host.dispose);
    host.initialize();

    await host.run(() async {
      expect(
        () => CCRouter.service<_GreetingService>(),
        throwsA(isA<CCServiceNotReadyError>()),
      );
      expect(
        () =>
            CCRouterGeneratedServiceBinding.invokeSync<
              _GreetingService,
              String
            >(
              methodId: 'greet',
              callerComponentId: 'consumer',
              call: (service, _) => service.greet(),
            ),
        throwsA(isA<CCServiceNotReadyError>()),
      );

      final result =
          await CCRouterGeneratedServiceBinding.invoke<
            _GreetingService,
            String
          >(
            methodId: 'greet',
            callerComponentId: 'consumer',
            call: (service, _) => service.greet(),
          );

      expect(result, 'hello');
      expect(_initializations, 1);
      expect(
        CCRouterGeneratedServiceBinding.invokeSync<_GreetingService, String>(
          methodId: 'greet',
          callerComponentId: 'consumer',
          call: (service, _) => service.greet(),
        ),
        'hello',
      );
      final traces = CCRouter.recentTraces
          .where((trace) => trace.operation == 'service')
          .toList();
      expect(traces, hasLength(3));
      expect(traces.first.status, 'failed');
      expect(traces.first.errorType, 'CCServiceNotReadyError');
      expect(traces.last.status, 'succeeded');
      expect(traces.last.target, 'fixture.greeting.greet');
    });

    expect(CCRouter.isInitialized, isFalse);
  });

  test('generated binding rejects forged component attribution', () async {
    final host = CCRouterTestHost(
      components: const [
        CCComponentManifest(
          id: 'fixture',
          version: '0.1.0',
          registrar: _Registrar(),
        ),
        CCComponentManifest(
          id: 'unrelated',
          version: '0.1.0',
          registrar: _EmptyRegistrar(),
        ),
      ],
    );
    addTearDown(host.dispose);
    host.initialize();

    await host.run(() async {
      expect(
        () => CCRouterGeneratedServiceBinding.invoke<_GreetingService, String>(
          methodId: 'greet',
          callerComponentId: 'missing',
          call: (service, _) => service.greet(),
        ),
        throwsA(isA<CCResolutionError>()),
      );
      expect(
        () => CCRouterGeneratedServiceBinding.invoke<_GreetingService, String>(
          methodId: 'greet',
          callerComponentId: 'unrelated',
          call: (service, _) => service.greet(),
        ),
        throwsA(isA<CCResolutionError>()),
      );
    });
  });
}
