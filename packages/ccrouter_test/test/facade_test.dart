// ignore_for_file: deprecated_member_use

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:test/test.dart';

final class ReadOnce implements CCCommand<String> {}

final class NotifyFacade implements CCCommand<void> {}

final class FacadeChanged implements CCEvent {}

final class CommandRegistrar implements CCComponentRegistrar {
  const CommandRegistrar(this.value);

  final String value;

  @override
  void register(CCRegistry registry) {
    registry.registerInitializationTask(
      CCInitializationTask(id: 'facade.prepare', run: (_) {}),
    );
    registry.registerCommand<ReadOnce, String>((_, _) => value);
    registry.registerCommand<NotifyFacade, void>(
      (_, _) => CCRouter.event(FacadeChanged()),
    );
    registry.registerEvent<FacadeChanged>('facade.changed', (_, _) {});
  }
}

const facadeMessageService = CCServiceToken<String>('facade.message');

final class ServiceRegistrar implements CCComponentRegistrar {
  const ServiceRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerService<String>(
      CCServiceProvider(
        contract: facadeMessageService,
        factory: (_) => 'promoted',
      ),
    );
  }
}

final class FailingRegistrar implements CCComponentRegistrar {
  const FailingRegistrar();

  @override
  void register(CCRegistry registry) {
    throw StateError('registration failed');
  }
}

final class FacadeRouteArgs {
  const FacadeRouteArgs(this.value);

  final String value;
}

final class FacadeRouteCodec implements CCRouteCodec<FacadeRouteArgs> {
  const FacadeRouteCodec();

  @override
  FacadeRouteArgs decode(CCEncodedRouteArguments input) =>
      FacadeRouteArgs(input.path['value']!);

  @override
  CCEncodedRouteArguments encode(FacadeRouteArgs arguments) =>
      CCEncodedRouteArguments(path: {'value': arguments.value});
}

final class FacadeRouteIntent implements CCRouteIntent<String> {
  const FacadeRouteIntent(this.value);

  final String value;

  @override
  String get routeId => 'facade.detail';

  @override
  Object get arguments => FacadeRouteArgs(value);
}

final class FacadeRouteRegistrar implements CCComponentRegistrar {
  const FacadeRouteRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerRoute<FacadeRouteArgs, String>(
      CCRouteDefinition<FacadeRouteArgs, String>(
        routeId: 'facade.detail',
        patterns: [const CCPathPattern('/facade/:value', primary: true)],
        codec: const FacadeRouteCodec(),
      ),
    );
  }
}

CCComponentManifest component(String id, String value) => CCComponentManifest(
  id: id,
  version: '0.1.0',
  registrar: CommandRegistrar(value),
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
    CCRouter.initialize(components: [component('default', 'owned')]);
    expect(CCRouter.isInitialized, isTrue);
    expect(await CCRouter.command(ReadOnce()), 'owned');
    expect(CCRouter.recentTraces.single.context.targetComponentId, 'default');
    await CCRouter.command(NotifyFacade());
    final subscriberTrace = CCRouter.recentTraces.singleWhere(
      (trace) => trace.operation == 'eventSubscriber',
    );
    expect(subscriberTrace.context.callerComponentId, 'default');
    expect(subscriberTrace.context.targetComponentId, 'default');
    expect(
      CCRouter.initializationTasks.single.state,
      CCInitializationTaskState.pending,
    );
    await CCRouter.runInitialization();
    final initializationTrace = CCRouter.recentTraces.singleWhere(
      (trace) => trace.operation == 'initializationTask',
    );
    expect(initializationTrace.context.targetComponentId, 'default');
    expect(
      CCRouter.initializationTasks.single.state,
      CCInitializationTaskState.succeeded,
    );
    expect(CCRouter.registeredComponents.single.id, 'default');

    await CCRouter.shutdown();
    await CCRouter.shutdown();

    expect(CCRouter.isInitialized, isFalse);
    expect(
      () => CCRouter.command(ReadOnce()),
      throwsA(isA<CCRouterNotInitializedError>()),
    );
  });

  test('reinitialization is rejected until shutdown completes', () async {
    CCRouter.initialize(components: [component('a', 'a')]);
    expect(
      () => CCRouter.initialize(components: const []),
      throwsA(isA<CCRouterAlreadyInitializedError>()),
    );

    await CCRouter.shutdown();
    CCRouter.initialize(components: [component('b', 'b')]);
    expect(await CCRouter.command(ReadOnce()), 'b');
  });

  test('facade resolves a promoted service through its stable token', () async {
    CCRouter.initialize(
      components: const [
        CCComponentManifest(
          id: 'facade-services',
          version: '0.1.0',
          registrar: ServiceRegistrar(),
        ),
      ],
    );

    expect(CCRouter.service(contract: facadeMessageService), 'promoted');
    expect(CCRouter.hasService(contract: facadeMessageService), isTrue);
    expect(CCRouter.services(contract: facadeMessageService), ['promoted']);
  });

  test('Session records account identity and is cleared on close', () async {
    CCRouter.initialize(components: const []);
    final metadata = <String, Object?>{'tenant': 'cn'};
    CCRouter.openSession(accountId: 'user-42', metadata: metadata);
    metadata['tenant'] = 'changed';

    expect(CCRouter.session?.accountId, 'user-42');
    expect(CCRouter.session?.metadata['tenant'], 'cn');
    expect(CCRouter.session?.sessionId, contains('-session-'));
    expect(
      () => CCRouter.session!.metadata['tenant'] = 'changed',
      throwsUnsupportedError,
    );

    await CCRouter.closeSession();
    expect(CCRouter.session, isNull);
  });

  test(
    'navigator executes typed and dynamic routes through the adapter',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      CCRouter.initialize(
        components: const [
          CCComponentManifest(
            id: 'facade-routes',
            version: '0.1.0',
            registrar: FacadeRouteRegistrar(),
          ),
        ],
      );
      CCRouterHostBinding.attachNavigationAdapter(adapter);

      final result = CCRouter.navigator.push(
        const FacadeRouteIntent('42'),
        source: const CCNavigationSource.feature('facade_test'),
      );
      expect(adapter.currentRequest?.uri.toString(), '/facade/42');
      expect(CCRouter.navigator.canPop(), isTrue);

      CCRouter.navigator.pop(result: 'done');
      expect(await result, 'done');

      await CCRouter.navigator.open(Uri.parse('/facade/43'));
      expect(adapter.currentRequest?.routeId, 'facade.detail');
      expect(
        (adapter.currentRequest?.arguments as FacadeRouteArgs).value,
        '43',
      );

      await CCRouter.shutdown();
      expect(adapter.isInitialized, isFalse);
    },
  );

  test('failed component registration leaves no partial Runtime', () async {
    expect(
      () => CCRouter.initialize(
        components: const [
          CCComponentManifest(
            id: 'failing',
            version: '0.1.0',
            registrar: FailingRegistrar(),
          ),
        ],
      ),
      throwsA(isA<StateError>()),
    );

    expect(CCRouter.isInitialized, isFalse);
    expect(
      () => CCRouter.registeredComponents,
      throwsA(isA<CCRouterNotInitializedError>()),
    );
  });
}
