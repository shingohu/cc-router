import 'package:ccrouter/ccrouter.dart';
import 'package:test/test.dart';

final class Read implements CCQuery<String> {}

final class QueryRegistrar implements CCComponentRegistrar {
  const QueryRegistrar(this.value);

  final String value;

  @override
  void register(CCRegistry registry) {
    registry.registerQuery<Read, String>((_, _) => value);
  }
}

CCComponentManifest component(String id, String value) => CCComponentManifest(
  id: id,
  version: '0.1.0',
  registrar: QueryRegistrar(value),
);

void main() {
  tearDown(CCRouter.shutdown);

  test('facade fails before initialization', () {
    expect(CCRouter.isInitialized, isFalse);
    expect(
      () => CCRouter.service<String>(),
      throwsA(isA<CCRouterNotInitializedError>()),
    );
  });

  test('facade creates, owns, and shuts down the default Runtime', () async {
    await CCRouter.initialize(components: [component('default', 'owned')]);
    expect(CCRouter.isInitialized, isTrue);
    expect(await CCRouter.query(Read()), 'owned');
    expect(CCRouter.registeredComponents.single.id, 'default');

    await CCRouter.shutdown();
    await CCRouter.shutdown();

    expect(CCRouter.isInitialized, isFalse);
    expect(
      () => CCRouter.query(Read()),
      throwsA(isA<CCRouterNotInitializedError>()),
    );
  });

  test('reinitialization is rejected until shutdown completes', () async {
    await CCRouter.initialize(components: [component('a', 'a')]);
    await expectLater(
      CCRouter.initialize(components: [component('b', 'b')]),
      throwsA(isA<CCRouterAlreadyInitializedError>()),
    );

    await CCRouter.shutdown();
    await CCRouter.initialize(components: [component('b', 'b')]);
    expect(await CCRouter.query(Read()), 'b');
  });

  test('Session records account identity and is cleared on close', () async {
    await CCRouter.initialize(components: const []);
    final metadata = <String, Object?>{'tenant': 'cn'};
    CCRouter.openSession(accountId: 'user-42', metadata: metadata);
    metadata['tenant'] = 'changed';

    expect(CCRouter.session?.accountId, 'user-42');
    expect(CCRouter.session?.metadata['tenant'], 'cn');
    expect(CCRouter.session?.sessionId, startsWith('session-'));
    expect(
      () => CCRouter.session!.metadata['tenant'] = 'changed',
      throwsUnsupportedError,
    );

    await CCRouter.closeSession();
    expect(CCRouter.session, isNull);
  });
}
