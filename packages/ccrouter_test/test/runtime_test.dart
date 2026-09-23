import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:test/test.dart';

final class Counter implements CCDisposable {
  Counter(this.id, {this.onDispose});
  final String id;
  final FutureOr<void> Function()? onDispose;
  bool disposed = false;
  @override
  Future<void> dispose() async {
    disposed = true;
    await onDispose?.call();
  }
}

final class Add implements CCCommand<int> {
  Add(this.value);
  final int value;
}

final class Read implements CCQuery<int> {}

final class Run implements CCAction {}

final class Changed implements CCEvent {}

final class ReadyA {}

final class ReadyB {}

void main() {
  late CCRouterRuntime runtime;
  setUp(() => runtime = CCRouterRuntime.forTesting());
  tearDown(() => runtime.dispose());

  test(
    'Factory construction detects cycles without caching instances',
    () async {
      runtime.registerService(
        CCServiceProvider<Counter>(
          creationPolicy: CCServiceCreationPolicy.factory,
          factory: (_) => runtime.service<Counter>(),
        ),
      );
      runtime.initialize();
      expect(
        () => runtime.service<Counter>(),
        throwsA(isA<CCCircularServiceDependencyError>()),
      );
    },
  );

  test(
    'Factory constructed for a Session is disposed with that Session',
    () async {
      Counter? dependency;
      runtime.registerService(
        CCServiceProvider<Counter>(
          creationPolicy: CCServiceCreationPolicy.factory,
          factory: (_) => dependency = Counter('factory'),
        ),
      );
      runtime.registerService(
        CCServiceProvider<String>(
          scope: CCServiceScope.session,
          factory: (_) => runtime.service<Counter>().id,
        ),
      );
      runtime.initialize();
      runtime.openSession(accountId: 'account-a');
      runtime.service<String>();
      await runtime.closeSession();
      expect(dependency!.disposed, isTrue);
    },
  );

  test(
    'uninitialized APIs fail, initialize is idempotent, registry freezes',
    () async {
      expect(
        () => runtime.service<Counter>(),
        throwsA(isA<CCRouterNotInitializedError>()),
      );
      expect(
        () => runtime.hasService<Counter>(),
        throwsA(isA<CCRouterNotInitializedError>()),
      );
      runtime.initialize();
      runtime.initialize();
      expect(
        () => runtime.registerService(
          CCServiceProvider<Counter>(factory: (_) => Counter('a')),
        ),
        throwsA(isA<CCRegistrationError>()),
      );
    },
  );

  test(
    'default and named services are deterministic lazy singletons',
    () async {
      var creations = 0;
      const key = CCServiceKey<Counter>('named');
      runtime.registerService(
        CCServiceProvider<Counter>(key: key, factory: (_) => Counter('named')),
      );
      runtime.registerService(
        CCServiceProvider<Counter>(
          factory: (_) {
            creations++;
            return Counter('default');
          },
        ),
      );
      runtime.initialize();
      expect(creations, 0);
      expect(runtime.service<Counter>().id, 'default');
      expect(runtime.service<Counter>(), same(runtime.service<Counter>()));
      expect(creations, 1);
      expect(runtime.service<Counter>(key: key).id, 'named');
      expect(runtime.services<Counter>().map((item) => item.id), [
        'default',
        'named',
      ]);
    },
  );

  test('named provider can explicitly be the default', () async {
    const key = CCServiceKey<Counter>('preferred');
    runtime.registerService(
      CCServiceProvider<Counter>(
        key: key,
        isDefault: true,
        factory: (_) => Counter('preferred'),
      ),
    );
    runtime.initialize();
    expect(
      runtime.service<Counter>(),
      same(runtime.service<Counter>(key: key)),
    );
  });

  test(
    'stable service token and legacy type lookup share one instance',
    () async {
      const contract = CCServiceToken<Counter>('counter.service');
      runtime.registerService(
        CCServiceProvider<Counter>(
          contract: contract,
          factory: (_) => Counter('promoted'),
        ),
      );
      runtime.initialize();

      final legacy = runtime.service<Counter>();
      final promoted = runtime.service<Counter>(contract: contract);

      expect(promoted, same(legacy));
      expect(runtime.hasService<Counter>(contract: contract), isTrue);
      expect(runtime.services<Counter>(contract: contract), [same(legacy)]);
      expect(
        () => runtime.service<String>(
          contract: const CCServiceToken('counter.service'),
        ),
        throwsA(isA<CCServiceTypeMismatchError>()),
      );
    },
  );

  test('stable service contract IDs are globally unique and validated', () {
    final overlongId = 'a' * 129;
    runtime.registerService(
      CCServiceProvider<Counter>(
        contract: const CCServiceToken('shared.service'),
        factory: (_) => Counter('counter'),
      ),
    );
    expect(
      () => runtime.registerService(
        CCServiceProvider<String>(
          contract: const CCServiceToken('shared.service'),
          key: const CCServiceKey('different-key'),
          factory: (_) => 'duplicate',
        ),
      ),
      throwsA(isA<CCRegistrationError>()),
    );
    expect(
      () => runtime.registerService(
        CCServiceProvider<int>(
          contract: const CCServiceToken('Invalid service'),
          factory: (_) => 1,
        ),
      ),
      throwsA(isA<CCRegistrationError>()),
    );
    expect(
      () => runtime.registerService(
        CCServiceProvider<bool>(
          contract: CCServiceToken<bool>(overlongId),
          factory: (_) => true,
        ),
      ),
      throwsA(isA<CCRegistrationError>()),
    );
    expect(
      () => runtime.registerService(
        CCServiceProvider<double>(
          key: const CCServiceKey('Invalid key'),
          factory: (_) => 1,
        ),
      ),
      throwsA(isA<CCRegistrationError>()),
    );
  });

  test('duplicate service keys and multiple defaults fail', () {
    runtime.registerService(
      CCServiceProvider<Counter>(factory: (_) => Counter('a')),
    );
    expect(
      () => runtime.registerService(
        CCServiceProvider<Counter>(factory: (_) => Counter('b')),
      ),
      throwsA(isA<CCRegistrationError>()),
    );
    expect(
      () => runtime.registerService(
        CCServiceProvider<Counter>(
          key: const CCServiceKey('b'),
          isDefault: true,
          factory: (_) => Counter('b'),
        ),
      ),
      throwsA(isA<CCRegistrationError>()),
    );
  });

  test(
    'same key name for different service types does not share cache',
    () async {
      runtime.registerService(
        CCServiceProvider<String>(
          key: const CCServiceKey('same'),
          factory: (_) => 's',
        ),
      );
      runtime.registerService(
        CCServiceProvider<int>(
          key: const CCServiceKey('same'),
          factory: (_) => 42,
        ),
      );
      runtime.initialize();
      expect(runtime.service<String>(key: const CCServiceKey('same')), 's');
      expect(runtime.service<int>(key: const CCServiceKey('same')), 42);
    },
  );

  test('optional lookup only suppresses missing registration', () async {
    runtime.registerService(
      CCServiceProvider<Counter>(factory: (_) => throw StateError('factory')),
    );
    runtime.initialize();
    expect(runtime.serviceOrNull<String>(), isNull);
    expect(runtime.hasService<String>(), isFalse);
    expect(() => runtime.serviceOrNull<Counter>(), throwsStateError);
  });

  test('lazy Service readiness is single-flight per singleton', () async {
    var creations = 0;
    var initializations = 0;
    final gate = Completer<void>();
    runtime.registerService(
      CCServiceProvider<Counter>(
        factory: (_) {
          creations++;
          return Counter('ready');
        },
        initializer: (service, context) async {
          initializations++;
          expect(service.id, 'ready');
          expect(context.operation, 'serviceInitialize');
          await gate.future;
        },
      ),
    );
    runtime.initialize();

    expect(
      () => runtime.service<Counter>(),
      throwsA(isA<CCServiceNotReadyError>()),
    );
    expect(creations, 0);
    final first = runtime.serviceAsync<Counter>();
    final second = runtime.serviceAsync<Counter>();
    await Future<void>.delayed(Duration.zero);
    expect(creations, 1);
    expect(initializations, 1);
    gate.complete();
    final resolved = await Future.wait([first, second]);
    expect(resolved.first, same(resolved.last));
    expect(runtime.service<Counter>(), same(resolved.first));
    expect(
      runtime.recentTraces.where((trace) => trace.operation == 'serviceReady'),
      hasLength(2),
    );
  });

  test('Factory Service readiness runs for every async resolution', () async {
    var creations = 0;
    var initializations = 0;
    runtime.registerService(
      CCServiceProvider<Counter>(
        creationPolicy: CCServiceCreationPolicy.factory,
        factory: (_) => Counter('factory-${++creations}'),
        initializer: (_, _) => initializations++,
      ),
    );
    runtime.initialize();

    expect(
      () => runtime.service<Counter>(),
      throwsA(isA<CCServiceNotReadyError>()),
    );
    expect(creations, 0);
    final first = await runtime.serviceAsync<Counter>();
    final second = await runtime.serviceAsync<Counter>();
    expect(first, isNot(same(second)));
    expect(creations, 2);
    expect(initializations, 2);
  });

  test('all asynchronous Services preserve deterministic key order', () async {
    final initialized = <String>[];
    runtime.registerService(
      CCServiceProvider<Counter>(
        key: const CCServiceKey('z'),
        factory: (_) => Counter('z'),
        initializer: (service, _) => initialized.add(service.id),
      ),
    );
    runtime.registerService(
      CCServiceProvider<Counter>(
        key: const CCServiceKey('a'),
        factory: (_) => Counter('a'),
        initializer: (service, _) => initialized.add(service.id),
      ),
    );
    runtime.initialize();

    final services = await runtime.servicesAsync<Counter>();
    expect(services.map((service) => service.id), ['a', 'z']);
    expect(initialized, containsAll(['a', 'z']));
  });

  test('Service readiness failure is sanitized and stable', () async {
    var initializations = 0;
    runtime.registerService(
      CCServiceProvider<Counter>(
        factory: (_) => Counter('failure'),
        initializer: (_, _) {
          initializations++;
          throw StateError('private initialization details');
        },
      ),
    );
    runtime.initialize();

    for (var attempt = 0; attempt < 2; attempt++) {
      await expectLater(
        runtime.serviceAsync<Counter>(),
        throwsA(
          isA<CCServiceInitializationError>()
              .having((error) => error.causeType, 'causeType', 'StateError')
              .having(
                (error) => error.message,
                'message',
                isNot(contains('private initialization details')),
              ),
        ),
      );
    }
    expect(initializations, 1);
    expect(
      () => runtime.service<Counter>(),
      throwsA(isA<CCServiceNotReadyError>()),
    );
  });

  test('caller timeout does not poison shared Service readiness', () async {
    final pending = Completer<void>();
    late CCInvocationContext initializerContext;
    runtime.registerService(
      CCServiceProvider<Counter>(
        factory: (_) => Counter('timeout'),
        initializer: (_, context) {
          initializerContext = context;
          return pending.future;
        },
      ),
    );
    runtime.initialize();

    await expectLater(
      runtime.serviceAsync<Counter>(timeout: const Duration(milliseconds: 10)),
      throwsA(isA<CCInvocationTimeoutError>()),
    );
    expect(initializerContext.cancellation.isCancelled, isFalse);
    pending.complete();
    await Future<void>.delayed(Duration.zero);
    expect(runtime.service<Counter>().id, 'timeout');
  });

  test('Service readiness detects asynchronous dependency cycles', () async {
    runtime.registerService(
      CCServiceProvider<ReadyA>(
        factory: (_) => ReadyA(),
        initializer: (_, _) async {
          await runtime.serviceAsync<ReadyB>();
        },
      ),
    );
    runtime.registerService(
      CCServiceProvider<ReadyB>(
        factory: (_) => ReadyB(),
        initializer: (_, _) async {
          await runtime.serviceAsync<ReadyA>();
        },
      ),
    );
    runtime.initialize();

    await expectLater(
      runtime.serviceAsync<ReadyA>(),
      throwsA(isA<CCCircularServiceDependencyError>()),
    );
  });

  test('Session close cancels pending Service readiness', () async {
    final pending = Completer<void>();
    final started = Completer<CCInvocationContext>();
    late Counter service;
    runtime.registerService(
      CCServiceProvider<Counter>(
        scope: CCServiceScope.session,
        factory: (_) => service = Counter('session-ready'),
        initializer: (_, context) {
          started.complete(context);
          return pending.future;
        },
      ),
    );
    runtime.initialize();
    runtime.openSession(accountId: 'account-a');
    final resolving = runtime.serviceAsync<Counter>();
    final context = await started.future;

    final assertion = expectLater(
      resolving,
      throwsA(isA<CCInvocationCancelledError>()),
    );
    await runtime.closeSession();
    await assertion;
    expect(context.cancellation.isCancelled, isTrue);
    expect(service.disposed, isTrue);
    pending.complete();
  });

  test('optional async lookup suppresses only missing registration', () async {
    runtime.registerService(
      CCServiceProvider<Counter>(
        factory: (_) => Counter('failure'),
        initializer: (_, _) => throw StateError('failure'),
      ),
    );
    runtime.initialize();

    expect(await runtime.serviceOrNullAsync<String>(), isNull);
    await expectLater(
      runtime.serviceOrNullAsync<Counter>(),
      throwsA(isA<CCServiceInitializationError>()),
    );
  });

  test('missing service reports stable identity and requested key', () {
    runtime.initialize();
    expect(
      () => runtime.service<Counter>(key: const CCServiceKey('missing')),
      throwsA(
        isA<CCServiceNotFoundError>().having(
          (error) => error.key,
          'key',
          'missing',
        ),
      ),
    );
  });

  test(
    'circular construction is detected and failed construction can retry',
    () async {
      var circular = true;
      runtime.registerService(
        CCServiceProvider<Counter>(
          factory: (_) =>
              circular ? runtime.service<Counter>() : Counter('ready'),
        ),
      );
      runtime.initialize();
      expect(
        () => runtime.service<Counter>(),
        throwsA(isA<CCCircularServiceDependencyError>()),
      );
      circular = false;
      expect(runtime.service<Counter>().id, 'ready');
    },
  );

  test(
    'Session requires explicit open, closes services, and creates new instances',
    () async {
      runtime.registerService(
        CCServiceProvider<Counter>(
          scope: CCServiceScope.session,
          factory: (_) => Counter('session'),
        ),
      );
      runtime.initialize();
      expect(
        () => runtime.service<Counter>(),
        throwsA(
          isA<CCServiceScopeUnavailableError>().having(
            (error) => error.scope,
            'scope',
            CCServiceScope.session,
          ),
        ),
      );
      runtime.openSession(accountId: 'account-a');
      expect(runtime.session?.accountId, 'account-a');
      expect(runtime.session?.sessionId, contains('-session-'));
      final firstSessionId = runtime.session!.sessionId;
      final first = runtime.service<Counter>();
      expect(
        () => runtime.openSession(accountId: 'account-a'),
        throwsA(isA<CCResolutionError>()),
      );
      await runtime.closeSession();
      expect(first.disposed, isTrue);
      expect(runtime.session, isNull);
      runtime.openSession(accountId: 'account-a');
      expect(runtime.session?.sessionId, isNot(firstSessionId));
      expect(runtime.service<Counter>(), isNot(same(first)));
    },
  );

  test('Session IDs are unique across independent Runtime instances', () async {
    final first = CCRouterRuntime.forTesting(
      navigationAdapter: CCMemoryNavigationAdapter(),
    );
    final second = CCRouterRuntime.forTesting(
      navigationAdapter: CCMemoryNavigationAdapter(),
    );
    try {
      first.initialize();
      second.initialize();
      first.openSession(accountId: 'account-a');
      second.openSession(accountId: 'account-a');

      expect(first.session?.sessionId, isNotNull);
      expect(second.session?.sessionId, isNotNull);
      expect(first.session?.sessionId, isNot(second.session?.sessionId));
    } finally {
      await Future.wait([first.dispose(), second.dispose()]);
    }
  });

  test('Session requires a non-empty account identity', () async {
    runtime.initialize();
    expect(
      () => runtime.openSession(accountId: '  '),
      throwsA(isA<CCResolutionError>()),
    );
  });

  test('closing Session rejects new resolutions until disposal ends', () async {
    final disposed = Completer<void>();
    runtime.registerService(
      CCServiceProvider<Counter>(
        scope: CCServiceScope.session,
        factory: (_) => Counter('s', onDispose: () => disposed.future),
      ),
    );
    runtime.initialize();
    runtime.openSession(accountId: 'account-a');
    runtime.service<Counter>();
    final close = runtime.closeSession();
    expect(
      () => runtime.service<Counter>(),
      throwsA(isA<CCScopeClosedError>()),
    );
    expect(
      () => runtime.openSession(accountId: 'account-a'),
      throwsA(isA<CCResolutionError>()),
    );
    disposed.complete();
    await close;
  });

  test('factory instances are fresh and owned by App', () async {
    runtime.registerService(
      CCServiceProvider<Counter>(
        creationPolicy: CCServiceCreationPolicy.factory,
        factory: (_) => Counter('factory'),
      ),
    );
    runtime.initialize();
    final a = runtime.service<Counter>();
    final b = runtime.service<Counter>();
    expect(a, isNot(same(b)));
    await runtime.dispose();
    expect(a.disposed && b.disposed, isTrue);
  });

  test(
    'scopes dispose in reverse construction order and isolate failures',
    () async {
      final order = <String>[];
      final scope = CCScope('test');
      scope.own(Counter('a', onDispose: () => order.add('a')));
      scope.own(
        Counter(
          'b',
          onDispose: () {
            order.add('b');
            throw StateError('dispose');
          },
        ),
      );
      scope.own(Counter('c', onDispose: () => order.add('c')));
      await scope.close();
      await scope.close();
      expect(order, ['c', 'b', 'a']);
      expect(scope.disposalErrors, hasLength(1));
      expect(scope.state, CCScopeState.closed);
    },
  );

  test('scope disposal timeout does not block other instances', () async {
    final scope = CCScope('timeout');
    final a = scope.own(Counter('a'));
    scope.own(Counter('never', onDispose: () => Completer<void>().future));
    await scope.close(timeout: const Duration(milliseconds: 10));
    expect(a.disposed, isTrue);
    expect(scope.disposalErrors.single, isA<TimeoutException>());
  });

  test(
    'commands and queries return typed results and reject duplicates',
    () async {
      runtime.registerCommand<Add, int>((message, _) => message.value + 1);
      runtime.registerQuery<Read, int>((_, _) async => 7);
      expect(
        () => runtime.registerCommand<Add, int>((_, _) => 0),
        throwsA(isA<CCRegistrationError>()),
      );
      runtime.initialize();
      expect(await runtime.command(Add(4)), 5);
      expect(await runtime.query(Read()), 7);
    },
  );

  test('missing handler fails with a diagnostic trace', () async {
    runtime.initialize();
    await expectLater(
      runtime.command(Add(1)),
      throwsA(isA<CCResolutionError>()),
    );
    expect(runtime.recentTraces.single.status, 'failed');
  });

  test('timeout completes promptly and cancels downstream context', () async {
    late CCInvocationContext context;
    runtime.registerCommand<Add, int>((_, ctx) {
      context = ctx;
      return Completer<int>().future;
    });
    runtime.initialize();
    await expectLater(
      runtime.command(Add(1), timeout: const Duration(milliseconds: 20)),
      throwsA(isA<CCInvocationTimeoutError>()),
    );
    expect(context.cancellation.isCancelled, isTrue);
    expect(runtime.recentTraces.single.status, 'timedOut');
  });

  test('zero deadline does not invoke handler', () async {
    var calls = 0;
    runtime.registerCommand<Add, int>((_, _) => ++calls);
    runtime.initialize();
    await expectLater(
      runtime.command(Add(1), timeout: Duration.zero),
      throwsA(isA<CCInvocationTimeoutError>()),
    );
    expect(calls, 0);
  });

  test('cancellation works before and during invocation', () async {
    var calls = 0;
    runtime.registerCommand<Add, int>((_, _) {
      calls++;
      return Completer<int>().future;
    });
    runtime.initialize();
    final cancelled = CCCancellationToken()..cancel();
    await expectLater(
      runtime.command(Add(1), cancellation: cancelled),
      throwsA(isA<CCInvocationCancelledError>()),
    );
    expect(calls, 0);
    final token = CCCancellationToken();
    final call = runtime.command(Add(1), cancellation: token);
    token.cancel();
    await expectLater(call, throwsA(isA<CCInvocationCancelledError>()));
    expect(calls, 1);
  });

  test(
    'nested calls share trace and propagate deadline and cancellation',
    () async {
      late CCInvocationContext outer;
      late CCInvocationContext inner;
      runtime.registerQuery<Read, int>((_, ctx) {
        inner = ctx;
        return Completer<int>().future;
      });
      runtime.registerCommand<Add, int>((_, ctx) {
        outer = ctx;
        return runtime.query(Read());
      });
      runtime.initialize();
      final token = CCCancellationToken();
      final call = runtime.command(
        Add(1),
        cancellation: token,
        timeout: const Duration(seconds: 1),
      );
      token.cancel();
      await expectLater(call, throwsA(isA<CCInvocationCancelledError>()));
      await Future<void>.delayed(Duration.zero);
      expect(inner.traceId, outer.traceId);
      expect(inner.parentSpanId, outer.spanId);
      expect(inner.deadline, outer.deadline);
      expect(inner.cancellation.isCancelled, isTrue);
    },
  );

  test(
    'disposal cancels pending calls and a disposed Runtime cannot restart',
    () async {
      runtime.registerCommand<Add, int>((_, _) => Completer<int>().future);
      runtime.initialize();
      final call = runtime.command(Add(1));
      final assertion = expectLater(
        call,
        throwsA(isA<CCInvocationCancelledError>()),
      );
      await runtime.dispose();
      await assertion;
      expect(() => runtime.initialize(), throwsA(isA<CCScopeClosedError>()));
    },
  );

  test(
    'Action handlers execute by ID independent of registration order',
    () async {
      final order = <String>[];
      runtime.registerAction<Run>('z', (_, _) => order.add('z'));
      runtime.registerAction<Run>('a', (_, _) => order.add('a'));
      runtime.initialize();
      expect((await runtime.action(Run())).handled, 2);
      expect(order, ['a', 'z']);
    },
  );

  test(
    'Event subscribers are isolated and errors are bounded diagnostics',
    () async {
      var received = false;
      runtime.registerEvent<Changed>(
        'broken',
        (_, _) => throw StateError('private details'),
      );
      runtime.registerEvent<Changed>('healthy', (_, _) {
        received = true;
      });
      runtime.initialize();
      await runtime.event(Changed());
      expect(received, isTrue);
      expect(
        runtime.subscriberErrors.single.message,
        isNot(contains('private details')),
      );
    },
  );

  test('trace buffer is bounded and can be disabled', () async {
    final bounded = CCRouterRuntime.forTesting(traceCapacity: 1);
    bounded.registerQuery<Read, int>((_, _) => 1);
    bounded.initialize();
    await bounded.query(Read());
    await bounded.query(Read());
    expect(bounded.recentTraces, hasLength(1));
    await bounded.dispose();
    final disabled = CCRouterRuntime.forTesting(traceCapacity: 0);
    disabled.registerQuery<Read, int>((_, _) => 1);
    disabled.initialize();
    await disabled.query(Read());
    expect(disabled.recentTraces, isEmpty);
    await disabled.dispose();
  });
}
