import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reentrant_lifecycle_regression_test.dart'
    show ProbeAdapter, Intent, Registrar, Resource;

typedef _Failure = ({Object error, StackTrace stack});

// Consume errors in the caller's error Zone before returning them as data.
Future<_Failure?> _settleIn(Zone zone, Future<void> Function() work) {
  final completion = Completer<_Failure?>();
  zone.run(() {
    unawaited(
      Future<void>.sync(work).then<void>(
        (_) => completion.complete(null),
        onError: (Object error, StackTrace stack) {
          completion.complete((error: error, stack: stack));
        },
      ),
    );
  });
  return completion.future;
}

Zone _errorZone(List<Object> uncaught) {
  late Zone zone;
  runZonedGuarded(() => zone = Zone.current, (error, _) => uncaught.add(error));
  return zone;
}

final class _ExitAdapter extends ProbeAdapter
    implements CCNavigationRouteExitBinding {
  _ExitAdapter() : super('primary');

  final exits = <String, void Function()>{};
  void Function()? onRemove;
  int removals = 0;

  @override
  void Function()? addRouteExitListener({
    required String navigationId,
    required String hostId,
    required void Function() onExited,
  }) {
    exits[navigationId] = onExited;
    return () {
      exits.remove(navigationId);
      removals++;
      onRemove?.call();
    };
  }
}

final class _HeldResource extends Resource {
  final released = Completer<void>();

  @override
  Future<void> dispose() {
    super.dispose();
    return released.future;
  }
}

void main() {
  for (final crossZone in [false, true]) {
    test(
      'exit failure keeps precedence over later Scope failure crossZone=$crossZone',
      () async {
        final uncaught = <Object>[];
        final owner = _errorZone(uncaught);
        final closer = crossZone ? _errorZone(uncaught) : owner;
        final adapter = _ExitAdapter();
        final resource = owner.run(_HeldResource.new);
        final runtime = owner.run(
          () => CCRouterRuntime.forTesting(
            navigationAdapter: adapter,
            components: [
              CCComponentManifest(
                id: 'probe',
                version: '1.0.0',
                registrar: Registrar(
                  extra: (registry) {
                    registry.registerService<Resource>(
                      CCServiceProvider(
                        scope: CCServiceScope.route,
                        factory: (_) => resource,
                      ),
                    );
                  },
                ),
              ),
            ],
          )..initialize(),
        );
        expect(
          await _settleIn(owner, () => runtime.goRoute(const Intent())),
          isNull,
        );
        final id = runtime.activeRouteEntries.single.navigationId;
        owner.run(() => runtime.serviceForRoute<Resource>(navigationId: id));
        expect(
          await _settleIn(owner, () => runtime.goRoute(const Intent())),
          isNull,
        );
        final first = StateError('first exit failure');
        final stack = StackTrace.fromString('original exit failure stack');
        adapter.onRemove = () => Error.throwWithStackTrace(first, stack);
        owner.run(adapter.exits[id]!);
        await Future<void>.delayed(Duration.zero);
        expect(resource.disposeCalls, 1);
        final stopping = _settleIn(closer, runtime.dispose);
        resource.released.completeError(StateError('later Scope failure'));
        final outcome = await stopping.timeout(const Duration(seconds: 2));
        expect(outcome?.error, same(first));
        expect(outcome?.stack.toString(), stack.toString());
        expect(adapter.disposeCalls, 1);
        expect(adapter.removals, 1);
        expect(runtime.activeRouteEntries, isEmpty);
        expect(uncaught, isEmpty);
      },
    );
  }

  for (final crossZone in [false, true]) {
    for (final fails in [false, true]) {
      test('Route close joins crossZone=$crossZone fails=$fails', () async {
        final uncaught = <Object>[];
        final owner = _errorZone(uncaught);
        final closer = crossZone ? _errorZone(uncaught) : owner;
        final adapter = _ExitAdapter();
        final resource = Resource();
        final failure = StateError('exit unsubscribe failed');
        final stack = StackTrace.fromString(
          'original Route exit cleanup stack',
        );
        final runtime = owner.run(
          () => CCRouterRuntime.forTesting(
            navigationAdapter: adapter,
            components: [
              CCComponentManifest(
                id: 'probe',
                version: '1.0.0',
                registrar: Registrar(
                  extra: (registry) {
                    registry.registerService<Resource>(
                      CCServiceProvider(
                        scope: CCServiceScope.route,
                        factory: (_) => resource,
                      ),
                    );
                  },
                ),
              ),
            ],
          )..initialize(),
        );
        expect(
          await _settleIn(owner, () => runtime.goRoute(const Intent())),
          isNull,
        );
        final navigationId = runtime.activeRouteEntries.single.navigationId;
        owner.run(
          () => runtime.serviceForRoute<Resource>(navigationId: navigationId),
        );
        expect(
          await _settleIn(owner, () => runtime.goRoute(const Intent())),
          isNull,
        );
        expect(resource.disposeCalls, 0);

        final shutdown = Completer<_Failure?>();
        adapter.onRemove = () {
          shutdown.complete(_settleIn(closer, runtime.dispose));
          if (fails) Error.throwWithStackTrace(failure, stack);
        };
        owner.run(adapter.exits[navigationId]!);
        // Keep the test bounded when the internal close barrier loses an error.
        final result = await shutdown.future.timeout(
          const Duration(seconds: 2),
        );
        if (fails) {
          expect(result?.error, same(failure));
          expect(result?.stack.toString(), stack.toString());
        } else {
          expect(result, isNull);
        }
        expect(uncaught, isEmpty);
        expect(resource.disposeCalls, 1);
        expect(adapter.disposeCalls, 1);
        expect(adapter.removals, 1);
        expect(adapter.exits, isEmpty);
        expect(runtime.activeRouteEntries, isEmpty);
        expect(runtime.runtimeHealth.exitingRouteEntryCount, 0);

        // A later Runtime caller in its disposal Zone sees the same receipt.
        final lateResult = await _settleIn(closer, runtime.dispose);
        expect(lateResult?.error, fails ? same(failure) : isNull);
        expect(resource.disposeCalls, 1);
        expect(adapter.disposeCalls, 1);
      });
    }
  }

  test(
    'Route close joins all Scopes and preserves first completed failure',
    () async {
      final uncaught = <Object>[];
      final owner = _errorZone(uncaught);
      final closer = _errorZone(uncaught);
      final adapter = _ExitAdapter();
      final resources = [_HeldResource(), _HeldResource()];
      final failures = [StateError('first Route'), StateError('second Route')];
      final stacks = [
        StackTrace.fromString('first stack'),
        StackTrace.fromString('second stack'),
      ];
      var created = 0;
      final runtime = owner.run(
        () => CCRouterRuntime.forTesting(
          navigationAdapter: adapter,
          components: [
            CCComponentManifest(
              id: 'probe',
              version: '1.0.0',
              registrar: Registrar(
                extra: (registry) {
                  registry.registerService<Resource>(
                    CCServiceProvider(
                      scope: CCServiceScope.route,
                      factory: (_) => resources[created++],
                    ),
                  );
                },
              ),
            ),
          ],
        )..initialize(),
      );
      for (var i = 0; i < 3; i++) {
        expect(
          await _settleIn(owner, () => runtime.goRoute(const Intent())),
          isNull,
        );
        if (i < 2) {
          owner.run(
            () => runtime.serviceForRoute<Resource>(
              navigationId: runtime.activeRouteEntries.single.navigationId,
            ),
          );
        }
      }
      var removed = 0;
      adapter.onRemove = () {
        final index = removed++;
        Error.throwWithStackTrace(failures[index], stacks[index]);
      };
      owner.run(() {
        for (final exit in adapter.exits.values.toList()) {
          exit();
        }
      });
      await Future<void>.delayed(Duration.zero);
      expect(resources.map((resource) => resource.disposeCalls), [1, 1]);
      final shutdown = _settleIn(closer, runtime.dispose);
      var finished = false;
      unawaited(shutdown.then((_) => finished = true));
      try {
        // Complete the second registered close first, then retain the first.
        resources[1].released.complete();
        await Future<void>.delayed(Duration.zero);
        expect(finished, isFalse);
        expect(adapter.disposeCalls, 0);
      } finally {
        for (final resource in resources) {
          if (!resource.released.isCompleted) resource.released.complete();
        }
      }
      final result = await shutdown.timeout(const Duration(seconds: 2));
      expect(result?.error, same(failures[1]));
      expect(result?.stack.toString(), stacks[1].toString());
      expect(adapter.disposeCalls, 1);
      expect(adapter.removals, 2);
      expect(adapter.exits, isEmpty);
      expect(resources.map((resource) => resource.disposeCalls), [1, 1]);
      expect(uncaught, isEmpty);
    },
  );

  for (final fails in [false, true]) {
    test(
      'Host joins outgoing cleanup across error Zones fails=$fails',
      () async {
        final uncaught = <Object>[];
        final owner = _errorZone(uncaught);
        final closer = _errorZone(uncaught);
        final joiner = _errorZone(uncaught);
        final adapter = _ExitAdapter();
        final appResource = Resource();
        final failure = StateError('Host exit unsubscribe failed');
        final stack = StackTrace.fromString('original Host exit cleanup stack');
        final backendStarted = Completer<void>();
        final releaseBackend = Completer<void>();
        var backendDisposals = 0;
        owner.run(() {
          CCRouterHost.initialize(
            hostAssembly: CCHostAssembly.fromComponents(
              components: [
                CCComponentManifest(
                  id: 'probe',
                  version: '1.0.0',
                  registrar: Registrar(
                    extra: (registry) {
                      registry.registerService<Resource>(
                        CCServiceProvider(
                          scope: CCServiceScope.app,
                          factory: (_) => appResource,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
          CCRouterHostBinding.attachNavigationAdapter(
            adapter,
            disposeBackend: () async {
              expect(adapter.disposeCalls, 1);
              expect(appResource.disposeCalls, 1);
              backendDisposals++;
              backendStarted.complete();
              await releaseBackend.future;
            },
          );
          expect(CCRouter.service<Resource>(), same(appResource));
        });
        expect(
          await _settleIn(owner, () => CCRouter.navigator.go(const Intent())),
          isNull,
        );
        final navigationId = CCRouter.activeRouteEntries.single.navigationId;
        expect(
          await _settleIn(owner, () => CCRouter.navigator.go(const Intent())),
          isNull,
        );
        final shutdowns = <Future<_Failure?>>[];
        adapter.onRemove = () {
          for (final caller in [closer, owner, joiner]) {
            shutdowns.add(_settleIn(caller, CCRouterHost.shutdown));
          }
          if (fails) Error.throwWithStackTrace(failure, stack);
        };
        owner.run(adapter.exits[navigationId]!);
        try {
          await backendStarted.future.timeout(const Duration(seconds: 2));
          expect(shutdowns, hasLength(3));
          var finished = 0;
          for (final shutdown in shutdowns) {
            unawaited(shutdown.then((_) => finished++));
          }
          await Future<void>.delayed(Duration.zero);
          expect(finished, 0, reason: 'shutdown must join Backend disposal');
          // A caller arriving after Runtime cleanup still joins the Backend.
          shutdowns.add(_settleIn(joiner, CCRouterHost.shutdown));
        } finally {
          releaseBackend.complete();
        }
        final results = await Future.wait(
          shutdowns,
        ).timeout(const Duration(seconds: 2));
        for (final result in results) {
          expect(result?.error, fails ? same(failure) : isNull);
          if (fails) expect(result?.stack.toString(), stack.toString());
        }
        expect(uncaught, isEmpty);
        expect(adapter.removals, 1);
        expect(adapter.exits, isEmpty);
        expect(adapter.disposeCalls, 1);
        expect(appResource.disposeCalls, 1);
        expect(backendDisposals, 1);
        expect(CCRouter.isInitialized, isFalse);
        // A completed Host generation is retired; later shutdown is a no-op.
        expect(await _settleIn(owner, CCRouterHost.shutdown), isNull);
        joiner.run(() {
          CCRouterHost.initialize(
            hostAssembly: CCHostAssembly.fromComponents(components: const []),
          );
        });
        expect(await _settleIn(joiner, CCRouterHost.shutdown), isNull);
        expect(adapter.disposeCalls, 1);
        expect(backendDisposals, 1);
      },
    );
  }
}
