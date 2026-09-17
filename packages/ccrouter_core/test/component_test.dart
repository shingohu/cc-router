import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:test/test.dart';

final class Registrar implements CCComponentRegistrar {
  Registrar(this.body);
  final void Function(CCRegistry) body;
  @override
  void register(CCRegistry registry) => body(registry);
}

CCComponentManifest component(
  String id, {
  List<String> dependencies = const [],
  List<String> optional = const [],
  void Function(CCRegistry)? register,
}) => CCComponentManifest(
  id: id,
  version: '0.1.0',
  dependencies: dependencies,
  optionalDependencies: optional,
  registrar: Registrar(register ?? (_) {}),
);

void main() {
  test('registrars receive a component-bound registry', () {
    CCRegistry? received;
    final runtime = CCRouterRuntime.forTesting(
      components: [
        component('orders', register: (registry) => received = registry),
      ],
    );

    expect(received, isNotNull);
    expect(received, isNot(same(runtime)));
    expect(received, isNot(isA<CCRouterRuntime>()));
  });

  test('registrars assemble in deterministic dependency order', () async {
    final order = <String>[];
    final runtime = CCRouterRuntime.forTesting(
      components: [
        component(
          'order',
          dependencies: ['payment'],
          register: (_) => order.add('order'),
        ),
        component(
          'payment',
          register: (runtime) {
            order.add('payment');
            runtime.registerService(
              CCServiceProvider<String>(factory: (_) => 'payment'),
            );
          },
        ),
      ],
    );
    await runtime.initialize();
    expect(order, ['payment', 'order']);
    expect(runtime.components.map((item) => item.id), order);
    expect(runtime.service<String>(), 'payment');
    await runtime.dispose();
  });

  test('missing dependencies fail before any registrar executes', () {
    var registered = false;
    expect(
      () => CCRouterRuntime.forTesting(
        components: [
          component('a', register: (_) => registered = true),
          component('b', dependencies: ['missing']),
        ],
      ),
      throwsA(isA<CCRegistrationError>()),
    );
    expect(registered, isFalse);
  });

  test('cycles, duplicate IDs and empty IDs fail assembly', () {
    expect(
      () => CCRouterRuntime.forTesting(
        components: [
          component('a', dependencies: ['b']),
          component('b', dependencies: ['a']),
        ],
      ),
      throwsA(isA<CCRegistrationError>()),
    );
    expect(
      () => CCRouterRuntime.forTesting(
        components: [component('a'), component('a')],
      ),
      throwsA(isA<CCRegistrationError>()),
    );
    expect(
      () => CCRouterRuntime.forTesting(components: [component('')]),
      throwsA(isA<CCRegistrationError>()),
    );
  });

  test(
    'absent optional components are allowed; present ones precede consumer',
    () async {
      final runtime = CCRouterRuntime.forTesting(
        components: [
          component('a', optional: ['b', 'missing']),
          component('b'),
        ],
      );
      expect(runtime.components.map((item) => item.id), ['b', 'a']);
      await runtime.dispose();
    },
  );

  test('cross-component duplicate capabilities fail assembly', () {
    void register(CCRegistry registry) => registry.registerService(
      CCServiceProvider<String>(factory: (_) => 'duplicate'),
    );
    expect(
      () => CCRouterRuntime.forTesting(
        components: [
          component('a', register: register),
          component('b', register: register),
        ],
      ),
      throwsA(isA<CCRegistrationError>()),
    );
  });

  test(
    'App service cannot capture Session service, including via Transient',
    () async {
      final runtime = CCRouterRuntime.forTesting();
      runtime.registerService(
        CCServiceProvider<int>(
          scope: CCServiceScope.session,
          factory: (_) => 1,
        ),
      );
      runtime.registerService(
        CCServiceProvider<String>(
          scope: CCServiceScope.transient,
          factory: (_) => '${runtime.service<int>()}',
        ),
      );
      runtime.registerService(
        CCServiceProvider<double>(
          factory: (_) => double.parse(runtime.service<String>()),
        ),
      );
      await runtime.initialize();
      runtime.openSession(accountId: 'account-a');
      expect(
        () => runtime.service<double>(),
        throwsA(isA<CCResolutionError>()),
      );
      await runtime.dispose();
    },
  );

  test(
    'dependency constructors give reverse dependency disposal order',
    () async {
      final order = <String>[];
      final runtime = CCRouterRuntime.forTesting();
      runtime.registerService(
        CCServiceProvider<Resource>(
          key: const CCServiceKey('dependency'),
          factory: (_) => Resource('dependency', order),
        ),
      );
      runtime.registerService(
        CCServiceProvider<Resource>(
          factory: (_) {
            runtime.service<Resource>(key: const CCServiceKey('dependency'));
            return Resource('consumer', order);
          },
        ),
      );
      await runtime.initialize();
      runtime.service<Resource>();
      await runtime.dispose();
      expect(order, ['consumer', 'dependency']);
    },
  );
}

final class Resource implements CCDisposable {
  Resource(this.id, this.order);
  final String id;
  final List<String> order;
  @override
  void dispose() => order.add(id);
}
