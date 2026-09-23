import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:test/test.dart';

final class TestPaymentService implements CCDisposable {
  TestPaymentService(this.value);

  final String value;
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
  }
}

final class PaymentRegistrar implements CCComponentRegistrar {
  const PaymentRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerService<TestPaymentService>(
      CCServiceProvider(factory: (_) => TestPaymentService('production')),
    );
  }
}

const paymentToken = CCServiceToken<TestPaymentService>('test.payment');

final class ContractPaymentRegistrar implements CCComponentRegistrar {
  const ContractPaymentRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerService<TestPaymentService>(
      CCServiceProvider(
        contract: paymentToken,
        key: const CCServiceKey<TestPaymentService>('primary'),
        factory: (_) => TestPaymentService('production'),
      ),
    );
  }
}

final class SessionPaymentRegistrar implements CCComponentRegistrar {
  const SessionPaymentRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerService<TestPaymentService>(
      CCServiceProvider(
        scope: CCServiceScope.session,
        factory: (_) => TestPaymentService('production'),
      ),
    );
  }
}

var productionInitializerCalls = 0;

final class ReadyPaymentRegistrar implements CCComponentRegistrar {
  const ReadyPaymentRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerService<TestPaymentService>(
      CCServiceProvider(
        factory: (_) => TestPaymentService('production'),
        initializer: (_, _) => productionInitializerCalls++,
      ),
    );
  }
}

void main() {
  test('test host overlays the static facade only inside its Zone', () async {
    final first = CCRouterTestHost(
      components: const [
        CCComponentManifest(
          id: 'first',
          version: '0.1.0',
          registrar: PaymentRegistrar(),
        ),
      ],
    );
    final second = CCRouterTestHost(
      components: const [
        CCComponentManifest(
          id: 'second',
          version: '0.1.0',
          registrar: PaymentRegistrar(),
        ),
      ],
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    first.initialize();
    second.initialize();

    expect(CCRouter.isInitialized, isFalse);
    final results = await Future.wait([
      first.run(() async {
        await Future<void>.delayed(Duration.zero);
        return CCRouter.registeredComponents.single.id;
      }),
      second.run(() async {
        await Future<void>.delayed(Duration.zero);
        return CCRouter.registeredComponents.single.id;
      }),
    ]);

    expect(results, ['first', 'second']);
    expect(CCRouter.isInitialized, isFalse);
  });

  test('test host overlay rejects production lifecycle ownership', () async {
    final host = CCRouterTestHost();
    addTearDown(host.dispose);
    host.initialize();

    expect(
      () => host.run(() => CCRouter.initialize(components: const [])),
      throwsA(isA<CCRouterAlreadyInitializedError>()),
    );
    await expectLater(host.run(CCRouter.shutdown), throwsA(isA<StateError>()));
  });

  test('test host owns an isolated Runtime and disposes its adapter', () async {
    final adapter = CCMemoryNavigationAdapter();
    final host = CCRouterTestHost(navigationAdapter: adapter);
    addTearDown(host.dispose);

    expect(host.isInitialized, isFalse);
    host.initialize();

    expect(host.isInitialized, isTrue);
    expect(adapter.isInitialized, isTrue);
    expect(host.runtime.isInitialized, isTrue);

    await host.dispose();
    await host.dispose();

    expect(host.isInitialized, isFalse);
    expect(adapter.isInitialized, isFalse);
  });

  test('test host rejects initialization after disposal', () async {
    final host = CCRouterTestHost();
    await host.dispose();

    expect(() => host.initialize(), throwsA(isA<StateError>()));
  });

  test('test host replaces a type-based provider and owns the fake', () async {
    final fake = TestPaymentService('fake');
    final host = CCRouterTestHost(
      components: const [
        CCComponentManifest(
          id: 'payment',
          version: '0.1.0',
          registrar: PaymentRegistrar(),
        ),
      ],
      overrides: [CCServiceOverride<TestPaymentService>.value(fake)],
    );
    addTearDown(host.dispose);

    host.initialize();
    expect(host.runtime.service<TestPaymentService>(), same(fake));
    await host.dispose();
    expect(fake.disposed, isTrue);
  });

  test('test host replaces a promoted keyed provider', () async {
    final host = CCRouterTestHost(
      components: const [
        CCComponentManifest(
          id: 'payment',
          version: '0.1.0',
          registrar: ContractPaymentRegistrar(),
        ),
      ],
      overrides: [
        CCServiceOverride<TestPaymentService>.factory(
          contract: paymentToken,
          key: const CCServiceKey<TestPaymentService>('primary'),
          create: (_) => TestPaymentService('fake'),
        ),
      ],
    );
    addTearDown(host.dispose);

    host.initialize();
    expect(
      host.runtime
          .service<TestPaymentService>(
            contract: paymentToken,
            key: const CCServiceKey<TestPaymentService>('primary'),
          )
          .value,
      'fake',
    );
  });

  test('override clears the production readiness initializer', () async {
    productionInitializerCalls = 0;
    final fake = TestPaymentService('fake');
    final host = CCRouterTestHost(
      components: const [
        CCComponentManifest(
          id: 'ready-payment',
          version: '0.1.0',
          registrar: ReadyPaymentRegistrar(),
        ),
      ],
      overrides: [CCServiceOverride<TestPaymentService>.value(fake)],
    );
    addTearDown(host.dispose);
    host.initialize();

    expect(host.runtime.service<TestPaymentService>(), same(fake));
    expect(await host.runtime.serviceAsync<TestPaymentService>(), same(fake));
    expect(productionInitializerCalls, 0);
  });

  test('override can install test-owned readiness', () async {
    productionInitializerCalls = 0;
    var testInitializerCalls = 0;
    final host = CCRouterTestHost(
      components: const [
        CCComponentManifest(
          id: 'ready-payment',
          version: '0.1.0',
          registrar: ReadyPaymentRegistrar(),
        ),
      ],
      overrides: [
        CCServiceOverride<TestPaymentService>.factory(
          create: (_) => TestPaymentService('fake'),
          initializer: (service, _) {
            expect(service.value, 'fake');
            testInitializerCalls++;
          },
        ),
      ],
    );
    addTearDown(host.dispose);
    host.initialize();

    expect(
      () => host.runtime.service<TestPaymentService>(),
      throwsA(isA<CCServiceNotReadyError>()),
    );
    expect(
      (await host.runtime.serviceAsync<TestPaymentService>()).value,
      'fake',
    );
    expect(testInitializerCalls, 1);
    expect(productionInitializerCalls, 0);
  });

  test('override keeps the original Session ownership boundary', () async {
    TestPaymentService? fake;
    final host = CCRouterTestHost(
      components: const [
        CCComponentManifest(
          id: 'payment',
          version: '0.1.0',
          registrar: SessionPaymentRegistrar(),
        ),
      ],
      overrides: [
        CCServiceOverride<TestPaymentService>.factory(
          create: (_) => fake = TestPaymentService('fake'),
        ),
      ],
    );
    addTearDown(host.dispose);

    host.initialize();
    expect(
      () => host.runtime.service<TestPaymentService>(),
      throwsA(isA<CCServiceScopeUnavailableError>()),
    );
    host.runtime.openSession(accountId: 'test-account');
    expect(host.runtime.service<TestPaymentService>().value, 'fake');
    await host.runtime.closeSession();
    expect(fake!.disposed, isTrue);
  });

  test('repeated override targets fail deterministically', () {
    expect(
      () => CCRouterTestHost(
        components: const [
          CCComponentManifest(
            id: 'payment',
            version: '0.1.0',
            registrar: PaymentRegistrar(),
          ),
        ],
        overrides: [
          CCServiceOverride<TestPaymentService>.value(
            TestPaymentService('one'),
          ),
          CCServiceOverride<TestPaymentService>.value(
            TestPaymentService('two'),
          ),
        ],
      ),
      throwsA(isA<CCRegistrationError>()),
    );
  });

  test('missing override target fails before the test host initializes', () {
    expect(
      () => CCRouterTestHost(
        overrides: [
          CCServiceOverride<TestPaymentService>.value(
            TestPaymentService('fake'),
          ),
        ],
      ),
      throwsA(isA<CCRegistrationError>()),
    );
  });
}
