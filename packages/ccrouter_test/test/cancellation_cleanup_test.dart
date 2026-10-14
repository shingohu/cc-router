import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:test/test.dart';

final class _Resource implements CCDisposable {
  _Resource({this.onDispose});

  final FutureOr<void> Function()? onDispose;
  int disposeCount = 0;

  @override
  Future<void> dispose() async {
    disposeCount++;
    await onDispose?.call();
  }
}

final class _Registrar implements CCComponentRegistrar {
  _Registrar(this.registerBody);

  final void Function(CCRegistry) registerBody;

  @override
  void register(CCRegistry registry) => registerBody(registry);
}

CCComponentManifest _component(void Function(CCRegistry) register) =>
    CCComponentManifest(
      id: 'cleanup',
      version: '1.0.0',
      registrar: _Registrar(register),
    );

final class _Arguments {
  const _Arguments();
}

final class _Codec implements CCRouteCodec<_Arguments> {
  const _Codec();

  @override
  _Arguments decode(CCRouteCodecValues input) => const _Arguments();

  @override
  CCRouteCodecValues encode(_Arguments arguments) => CCRouteCodecValues();
}

final class _Intent implements CCRouteIntent<void> {
  const _Intent();

  @override
  String get routeId => 'cleanup.page';

  @override
  Object get arguments => const _Arguments();
}

void main() {
  group('cancellation listener isolation', () {
    test(
      'notifies every listener before rethrowing the first failure',
      () async {
        final token = CCCancellationToken();
        final firstFailure = StateError('first listener');
        final firstStack = StackTrace.fromString(
          'original cancellation listener',
        );
        final notified = <int>[];
        token.addListener(() {
          notified.add(1);
          Error.throwWithStackTrace(firstFailure, firstStack);
        });
        token.addListener(() {
          notified.add(2);
          throw StateError('second listener');
        });
        token.addListener(() => notified.add(3));

        Object? caught;
        StackTrace? caughtStack;
        try {
          token.cancel();
        } catch (error, stackTrace) {
          caught = error;
          caughtStack = stackTrace;
        }

        expect(notified, [1, 2, 3]);
        expect(caught, same(firstFailure));
        expect(caughtStack.toString(), firstStack.toString());
        expect(token.isCancelled, isTrue);
        await token.whenCancelled;
        token.cancel();
        expect(notified, [1, 2, 3]);
      },
    );

    test(
      'removal and reentrant cancellation notify each admitted listener once',
      () {
        final token = CCCancellationToken();
        final notified = <String>[];
        final removeBefore = token.addListener(() => notified.add('removed'));
        removeBefore();
        late void Function() removeDuring;
        token.addListener(() {
          notified.add('first');
          token.cancel();
          removeDuring();
          token.addListener(() => notified.add('late'));
        });
        removeDuring = token.addListener(() => notified.add('second'));
        token.cancel();
        removeDuring();
        token.cancel();
        expect(notified, ['first', 'late', 'second']);
      },
    );
  });

  group('Scope cancellation cleanup', () {
    test('records cancellation errors and still disposes resources', () async {
      final scope = CCScope('cleanup');
      final cancellationFailure = StateError('scope cancellation');
      final disposalFailure = StateError('scope resource');
      final order = <String>[];
      final first = scope.own(_Resource(onDispose: () => order.add('first')));
      final last = scope.own(
        _Resource(
          onDispose: () {
            order.add('last');
            throw disposalFailure;
          },
        ),
      );
      scope.cancellation.addListener(() => throw cancellationFailure);
      scope.cancellation.addListener(() => order.add('cancelled'));

      final closing = scope.close();
      expect(scope.close(), same(closing));
      await closing;
      await scope.close();

      expect(order, ['cancelled', 'last', 'first']);
      expect(scope.disposalErrors, [cancellationFailure, disposalFailure]);
      expect(scope.state, CCScopeState.closed);
      expect(first.disposeCount, 1);
      expect(last.disposeCount, 1);
      expect(() => scope.own(_Resource()), throwsA(isA<CCScopeClosedError>()));
    });

    test(
      'reentrant close from cancellation shares the original operation',
      () async {
        final scope = CCScope('reentrant');
        final release = Completer<void>();
        final resource = scope.own(_Resource(onDispose: () => release.future));
        Future<void>? reentrant;
        scope.cancellation.addListener(() => reentrant = scope.close());

        final closing = scope.close();
        expect(reentrant, same(closing));
        expect(scope.state, CCScopeState.closing);
        release.complete();
        await closing;
        expect(resource.disposeCount, 1);
        expect(scope.state, CCScopeState.closed);
      },
    );
  });

  test(
    'Session cancellation failure still closes services and allows a new Session',
    () async {
      final created = <_Resource>[];
      final failure = StateError('session cancellation');
      var laterListenerCount = 0;
      final host = CCRouterTestHost(
        components: [
          _component((registry) {
            registry.registerService<_Resource>(
              CCServiceProvider(
                scope: CCServiceScope.session,
                factory: (context) {
                  context.cancellation.addListener(() => throw failure);
                  context.cancellation.addListener(() => laterListenerCount++);
                  final resource = _Resource();
                  created.add(resource);
                  return resource;
                },
              ),
            );
          }),
        ],
      );
      host.initialize();
      addTearDown(host.dispose);
      final runtime = host.runtime;
      runtime.openSession(accountId: 'first');
      final first = runtime.service<_Resource>();
      final firstScope = runtime.sessionScope!;
      await runtime.closeSession();

      expect(first.disposeCount, 1);
      expect(firstScope.disposalErrors, [failure]);
      expect(firstScope.state, CCScopeState.closed);
      expect(runtime.sessionScope, isNull);
      expect(runtime.appScope.state, CCScopeState.active);
      runtime.openSession(accountId: 'second');
      final second = runtime.service<_Resource>();
      expect(second, isNot(same(first)));
      await runtime.closeSession();
      expect(second.disposeCount, 1);
      expect(laterListenerCount, 2);
    },
  );

  test(
    'Route cancellation failure still pops, disposes its service, and completes its Future',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final failure = StateError('route cancellation');
      var laterListenerCount = 0;
      final host = CCRouterTestHost(
        navigationAdapter: adapter,
        components: [
          _component((registry) {
            registry.registerService<_Resource>(
              CCServiceProvider(
                scope: CCServiceScope.route,
                factory: (context) {
                  context.cancellation.addListener(() => throw failure);
                  context.cancellation.addListener(() => laterListenerCount++);
                  return _Resource();
                },
              ),
            );
            registry.registerRoute<_Arguments, void>(
              CCRouteDefinition(
                routeId: 'cleanup.page',
                patterns: const [CCPathPattern('/cleanup', primary: true)],
                codec: const _Codec(),
              ),
            );
          }),
        ],
      );
      host.initialize();
      addTearDown(host.dispose);
      final runtime = host.runtime;
      final disposed = Completer<void>();
      runtime.addRouteEntryListener((event) {
        if (event.entry.lifecycleState == CCRouteEntryLifecycleState.disposed) {
          disposed.complete();
        }
      });
      final pushed = runtime.pushRoute<void>(const _Intent());
      final resource = runtime.serviceForRoute<_Resource>(
        navigationId: runtime.activeRouteEntries.single.navigationId,
      );

      runtime.popRoute();
      await pushed;
      await disposed.future.timeout(const Duration(seconds: 1));

      expect(laterListenerCount, 1);
      expect(resource.disposeCount, 1);
      expect(runtime.activeRouteEntries, isEmpty);
      expect(runtime.activeBackendEntries, isEmpty);
      expect(adapter.stack, isEmpty);
      expect(runtime.appScope.state, CCScopeState.active);
    },
  );

  test(
    'Runtime reports cancellation failure after releasing every owned lifetime',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final resources = <CCServiceScope, _Resource>{};
      final cancellationFailure = StateError('app cancellation');
      final host = CCRouterTestHost(
        navigationAdapter: adapter,
        components: [
          _component((registry) {
            for (final scope in CCServiceScope.values) {
              registry.registerService<_Resource>(
                CCServiceProvider(
                  key: CCServiceKey<_Resource>(scope.name),
                  scope: scope,
                  factory: (_) => resources[scope] = _Resource(),
                ),
              );
            }
            registry.registerRoute<_Arguments, void>(
              CCRouteDefinition(
                routeId: 'cleanup.page',
                patterns: const [CCPathPattern('/cleanup', primary: true)],
                codec: const _Codec(),
              ),
            );
          }),
        ],
      );
      host.initialize();
      final runtime = host.runtime;
      runtime.service<_Resource>(key: const CCServiceKey('app'));
      runtime.openSession(accountId: 'account');
      final sessionScope = runtime.sessionScope!;
      runtime.service<_Resource>(key: const CCServiceKey('session'));
      final pushed = runtime.pushRoute<void>(const _Intent());
      runtime.serviceForRoute<_Resource>(
        navigationId: runtime.activeRouteEntries.single.navigationId,
        key: const CCServiceKey('route'),
      );
      final lifecycle = <CCRouteEntryLifecycleState>[];
      runtime.addRouteEntryListener(
        (event) => lifecycle.add(event.entry.lifecycleState),
      );
      runtime.appScope.cancellation.addListener(
        () => throw cancellationFailure,
      );
      Future<void>? reentrant;
      runtime.appScope.cancellation.addListener(
        () => reentrant = runtime.dispose(),
      );

      final disposing = runtime.dispose();
      await expectLater(disposing, throwsA(same(cancellationFailure)));
      expect(reentrant, same(disposing));
      expect(runtime.dispose(), same(disposing));
      await expectLater(runtime.dispose(), throwsA(same(cancellationFailure)));
      await pushed;

      expect(
        resources.values.map((resource) => resource.disposeCount),
        everyElement(1),
      );
      expect(runtime.appScope.state, CCScopeState.closed);
      expect(sessionScope.state, CCScopeState.closed);
      expect(runtime.sessionScope, isNull);
      expect(runtime.activeRouteEntries, isEmpty);
      expect(runtime.activeBackendEntries, isEmpty);
      expect(runtime.pendingNavigations, isEmpty);
      expect(lifecycle, contains(CCRouteEntryLifecycleState.disposed));
      expect(adapter.isInitialized, isFalse);
      expect(adapter.stack, isEmpty);
      expect(adapter.routes, isEmpty);
    },
  );

  test(
    'Facade rejects initialization and joins shutdown from a cancellation callback',
    () async {
      final release = Completer<void>();
      final resource = _Resource(onDispose: () => release.future);
      Object? initializeFailure;
      Future<void>? reentrant;
      var reentrantCompleted = false;
      late CCHostAssembly assembly;
      assembly = CCHostAssembly.fromComponents(
        components: [
          _component((registry) {
            registry.registerService<_Resource>(
              CCServiceProvider(
                factory: (context) {
                  context.cancellation.addListener(() {
                    try {
                      CCRouterHost.initialize(hostAssembly: assembly);
                    } catch (error) {
                      initializeFailure = error;
                    }
                    reentrant = CCRouterHost.shutdown();
                    unawaited(
                      reentrant!.then((_) => reentrantCompleted = true),
                    );
                  });
                  return resource;
                },
              ),
            );
          }),
        ],
      );
      CCRouterHost.initialize(hostAssembly: assembly);
      CCRouter.service<_Resource>();

      final shuttingDown = CCRouterHost.shutdown();
      await Future<void>.delayed(Duration.zero);
      final completedBeforeRelease = reentrantCompleted;
      release.complete();
      await shuttingDown;
      await reentrant;
      await CCRouterHost.shutdown();

      expect(initializeFailure, isA<CCRouterAlreadyInitializedError>());
      expect(completedBeforeRelease, isFalse);
      expect(reentrantCompleted, isTrue);
      expect(resource.disposeCount, 1);
      expect(CCRouter.isInitialized, isFalse);
      CCRouterHost.initialize(hostAssembly: assembly);
      await CCRouterHost.shutdown();
    },
  );
}
