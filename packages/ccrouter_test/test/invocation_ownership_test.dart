import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

import 'reentrant_lifecycle_regression_test.dart' as routes;
import 'review_repros/completed_invocation/repro.dart' as fixture;

class _Owner implements CCDisposable {
  int disposals = 0;
  @override
  void dispose() => disposals++;
}

class _Write implements CCCommand<void> {}

class _Changed implements CCEvent {}

const _ownerToken = CCServiceToken<_Owner>('probe.owner');
const _key = CCServiceKey<fixture.AccountResource>('named');

CCRouterRuntime _runtime(CCServiceScope scope) {
  final runtime = CCRouterRuntime.forTesting(
    navigationAdapter: CCMemoryNavigationAdapter(),
    components: [
      CCComponentManifest(
        id: 'probe',
        version: '1.0.0',
        registrar: routes.Registrar(
          extra: (registry) => registry.registerService<_Owner>(
            CCServiceProvider(
              contractToken: _ownerToken,
              scope: scope,
              factory: (_) => _Owner(),
            ),
          ),
        ),
      ),
    ],
  );
  addTearDown(runtime.dispose);
  return runtime;
}

Future<String?> _start(CCRouterRuntime runtime, CCServiceScope scope) async {
  runtime.initialize();
  if (scope == CCServiceScope.session) {
    runtime.openSession(accountId: 'old');
    return null;
  }
  await runtime.goRoute(const routes.Intent());
  return runtime.activeRouteEntries.single.navigationId;
}

Future<void> _retire(CCRouterRuntime runtime, CCServiceScope scope) async {
  if (scope == CCServiceScope.session) {
    await runtime.closeSession();
    runtime.openSession(accountId: 'new');
  } else {
    await runtime.goRoute(const routes.Intent());
  }
}

Future<void> _launch(
  CCRouterRuntime runtime,
  String? navigationId,
  void Function(CCInvocationContext) launch, {
  bool nested = false,
}) => runtime.invokeService<_Owner, void>(
  contractToken: _ownerToken,
  methodId: 'launch',
  navigationId: navigationId,
  call: (_, context) async {
    if (!nested) {
      launch(context);
      return;
    }
    await runtime.invokeService<fixture.AppLauncher, void>(
      contractToken: fixture.appLauncherToken,
      methodId: 'launch',
      call: (_, childContext) => launch(childContext),
    );
  },
);

void _registerAppLauncher(CCRouterRuntime runtime) {
  runtime.registerService(
    CCServiceProvider<fixture.AppLauncher>(
      contractToken: fixture.appLauncherToken,
      factory: (_) => fixture.AppLauncher(),
    ),
  );
}

Future<(Zone, WeakReference<_Owner>)> _captureZone(
  CCRouterRuntime runtime,
  String? navigationId,
) async {
  late WeakReference<_Owner> owner;
  late Zone retained;
  await runtime.invokeService<_Owner, void>(
    contractToken: _ownerToken,
    methodId: 'capture',
    navigationId: navigationId,
    call: (service, _) {
      owner = WeakReference(service);
      return runtime.invokeService<fixture.AppLauncher, void>(
        contractToken: fixture.appLauncherToken,
        methodId: 'capture',
        call: (_, _) => retained = Zone.current,
      );
    },
  );
  return (retained, owner);
}

void main() {
  for (final scope in [CCServiceScope.session, CCServiceScope.route]) {
    for (final kind in ['command', 'event']) {
      test('returned $scope cannot enter a late $kind handler', () async {
        final runtime = _runtime(scope);
        var calls = 0;
        runtime.registerCommand<_Write, void>((_, _) => calls++);
        runtime.registerEvent<_Changed>('probe.observe', (_, _) => calls++);
        Future<void> dispatch() => kind == 'command'
            ? runtime.command(_Write())
            : runtime.event(_Changed());
        final id = await _start(runtime, scope);
        final release = Completer<void>();
        late Future<Object?> late;
        await _launch(runtime, id, (_) {
          late = fixture.observe(() async {
            await release.future;
            return dispatch();
          });
        });
        await _retire(runtime, scope);
        release.complete();
        expect(await late, isA<CCInvocationCancelledError>());
        expect(calls, 0);
        await dispatch();
        expect(calls, 1);
      });
    }

    for (final nested in [false, true]) {
      for (final optional in [false, true]) {
        for (final policy in CCServiceCreationPolicy.values) {
          for (final cached in [false, true]) {
            test('returned $scope nested=$nested optional=$optional '
                '$policy cached=$cached fences keyed lookup', () async {
              final runtime = _runtime(scope);
              _registerAppLauncher(runtime);
              final resources = <fixture.AccountResource>[];
              runtime.registerService(
                CCServiceProvider<fixture.AccountResource>(
                  key: _key,
                  isDefault: true,
                  scope: scope == CCServiceScope.session
                      ? CCServiceScope.session
                      : CCServiceScope.app,
                  creationPolicy: policy,
                  factory: (_) {
                    final resource = fixture.AccountResource(
                      runtime.session?.accountId ?? 'app',
                    );
                    resources.add(resource);
                    return resource;
                  },
                ),
              );
              final id = await _start(runtime, scope);
              if (cached) runtime.service<fixture.AccountResource>();
              final release = Completer<void>();
              late Future<Object?> late;
              await _launch(runtime, id, (_) {
                late = fixture.observe(() async {
                  await release.future;
                  return optional
                      ? runtime.serviceOrNull<fixture.AccountResource>(
                          key: _key,
                        )
                      : runtime.service<fixture.AccountResource>(key: _key);
                });
              }, nested: nested);
              await _retire(runtime, scope);
              if (cached) runtime.service<fixture.AccountResource>();
              final before = resources.length;
              release.complete();
              expect(
                await late.timeout(const Duration(seconds: 2)),
                isA<CCInvocationCancelledError>(),
              );
              expect(resources, hasLength(before));
              // The lookup is denied by the old origin, not by the target's
              // availability: an independent caller must still succeed.
              expect(
                runtime.service<fixture.AccountResource>().account,
                scope == CCServiceScope.session ? 'new' : 'app',
              );
              await runtime.dispose();
              expect(
                resources.every((resource) => resource.disposals == 1),
                isTrue,
              );
            });
          }
        }
      }
    }

    for (final readiness in [false, true]) {
      for (final closeOrigin in [false, true]) {
        test('App child of returned $scope readiness=$readiness '
            'close=$closeOrigin retains pending cancellation', () async {
          final runtime = _runtime(scope);
          final startChild = Completer<void>();
          final release = Completer<void>();
          final started = Completer<CCInvocationContext>();
          final lateLookup = Completer<Object?>();
          var methodCalls = 0;
          runtime.registerService(
            CCServiceProvider<fixture.AccountResource>(
              factory: (_) => fixture.AccountResource('app'),
            ),
          );
          Future<void> delayed(CCInvocationContext context) async {
            started.complete(context);
            await release.future;
            lateLookup.complete(
              await fixture.observe(
                () => runtime.service<fixture.AccountResource>(),
              ),
            );
          }

          runtime.registerService(
            CCServiceProvider<fixture.AppLauncher>(
              contractToken: fixture.appLauncherToken,
              factory: (_) => fixture.AppLauncher(),
              initializer: readiness ? (_, context) => delayed(context) : null,
            ),
          );
          final id = await _start(runtime, scope);
          late Future<Object?> child;
          await _launch(runtime, id, (_) {
            child = fixture.observe(() async {
              await startChild.future;
              return runtime.invokeService<fixture.AppLauncher, void>(
                contractToken: fixture.appLauncherToken,
                methodId: 'load',
                call: (_, context) async {
                  methodCalls++;
                  if (!readiness) await delayed(context);
                },
              );
            });
          });
          startChild.complete();
          final context = await started.future;
          if (closeOrigin) {
            await _retire(runtime, scope);
            // App readiness itself survives; the waiting child does not.
            expect(context.cancellation.isCancelled, !readiness);
            expect(
              await child.timeout(const Duration(seconds: 2)),
              isA<CCInvocationCancelledError>(),
            );
          }
          release.complete();
          final outcome = await lateLookup.future;
          if (closeOrigin && !readiness) {
            expect(outcome, isA<CCInvocationCancelledError>());
          } else {
            expect(outcome, isA<fixture.AccountResource>());
          }
          if (!closeOrigin) expect(await child, isNull);
          expect(methodCalls, closeOrigin && readiness ? 0 : 1);
          expect(
            await runtime.invokeService<fixture.AppLauncher, int>(
              contractToken: fixture.appLauncherToken,
              methodId: 'fresh',
              call: (_, _) => 42,
            ),
            42,
          );
        });
      }
    }

    test('retained nested Zone releases closed $scope Service', () async {
      final runtime = _runtime(scope);
      _registerAppLauncher(runtime);
      final id = await _start(runtime, scope);
      final retained = await _captureZone(runtime, id);
      await _retire(runtime, scope);
      await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
      expect(retained.$2.target, isNull);
      expect(
        () => retained.$1.run(() => runtime.service<fixture.AppLauncher>()),
        throwsA(isA<CCInvocationCancelledError>()),
      );
      expect(
        runtime.service<fixture.AppLauncher>(),
        isA<fixture.AppLauncher>(),
      );
    });
  }

  for (final source in ['factory', 'initializer']) {
    test('shared App $source outlives its closed Session caller', () async {
      final runtime = _runtime(CCServiceScope.session);
      final release = Completer<void>();
      late Future<Object?> late;
      void launch() {
        late = fixture.observe(() async {
          await release.future;
          return runtime.service<fixture.AccountResource>();
        });
      }

      runtime.registerService(
        CCServiceProvider<fixture.AccountResource>(
          factory: (_) => fixture.AccountResource('app'),
        ),
      );
      runtime.registerService(
        CCServiceProvider<fixture.AppLauncher>(
          factory: (_) {
            if (source == 'factory') launch();
            return fixture.AppLauncher();
          },
          initializer: source == 'initializer' ? (_, _) => launch() : null,
        ),
      );
      await _start(runtime, CCServiceScope.session);
      await runtime.invokeService<_Owner, void>(
        contractToken: _ownerToken,
        methodId: 'initializeShared',
        call: (_, _) async {
          await runtime.serviceAsync<fixture.AppLauncher>();
        },
      );
      await _retire(runtime, CCServiceScope.session);
      release.complete();
      expect(await late, isA<fixture.AccountResource>());
    });
  }

  for (final policy in CCServiceCreationPolicy.values) {
    test(
      '$policy initializer preserves its intended caller lifetime',
      () async {
        final runtime = _runtime(CCServiceScope.session);
        final release = Completer<void>();
        late Future<Object?> late;
        runtime.registerService(
          CCServiceProvider<fixture.AccountResource>(
            factory: (_) => fixture.AccountResource('app'),
          ),
        );
        runtime.registerService(
          CCServiceProvider<fixture.AppLauncher>(
            creationPolicy: policy,
            factory: (_) => fixture.AppLauncher(),
            initializer: (_, _) {
              late = fixture.observe(() async {
                await release.future;
                return runtime.service<fixture.AccountResource>();
              });
            },
          ),
        );
        await _start(runtime, CCServiceScope.session);
        await runtime.invokeService<_Owner, void>(
          contractToken: _ownerToken,
          methodId: 'initialize',
          call: (_, _) async =>
              await runtime.serviceAsync<fixture.AppLauncher>(),
        );
        await _retire(runtime, CCServiceScope.session);
        release.complete();
        expect(
          await late,
          policy == CCServiceCreationPolicy.singleton
              ? isA<fixture.AccountResource>()
              : isA<CCInvocationCancelledError>(),
        );
      },
    );

    test('root factory shutdown $policy preserves cleanup error', () async {
      final runtime = CCRouterRuntime.forTesting();
      final resource = fixture.AccountResource('app');
      final failure = StateError('shutdown notification failure');
      late Future<Object?> closing;
      runtime.registerService(
        CCServiceProvider<fixture.AccountResource>(
          creationPolicy: policy,
          factory: (context) {
            context.cancellation.addListener(() => throw failure);
            closing = fixture.observe(runtime.dispose);
            return resource;
          },
        ),
      );
      runtime.initialize();
      expect(
        () => runtime.service<fixture.AccountResource>(),
        throwsA(isA<CCInvocationCancelledError>()),
      );
      expect(await closing, same(failure));
      expect(resource.disposals, 1);
    });
  }

  test('an old Runtime Zone does not fence an independent Runtime', () async {
    final first = _runtime(CCServiceScope.session);
    final second = CCRouterRuntime.forTesting();
    addTearDown(second.dispose);
    second.registerService(
      CCServiceProvider<fixture.AccountResource>(
        factory: (_) => fixture.AccountResource('independent'),
      ),
    );
    second.initialize();
    await _start(first, CCServiceScope.session);
    final release = Completer<void>();
    late Future<Object?> late;
    await _launch(first, null, (_) {
      late = fixture.observe(() async {
        await release.future;
        return second.serviceAsync<fixture.AccountResource>();
      });
    });
    await first.dispose();
    release.complete();
    expect((await late as fixture.AccountResource).account, 'independent');
  });
}
