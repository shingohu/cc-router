import 'dart:async';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'reentrant_lifecycle_regression_test.dart'
    show ProbeAdapter, Intent, Registrar, Resource;

class ReleaseProbe extends ProbeAdapter
    implements CCNavigationManagedEntryReleaseSink {
  ReleaseProbe() : super('primary');
  bool armed = false;
  String? failingId;
  final released = <String>[];
  final failureStack = StackTrace.fromString('release-original-stack');
  final failure = StateError('release sink failed');
  @override
  void releaseManagedNavigation(String id) {
    released.add(id);
    if (armed && (failingId == null || id == failingId)) {
      Error.throwWithStackTrace(failure, failureStack);
    }
  }
}

CCRouterRuntime runtimeFor(
  CCNavigationAdapter adapter,
  List<Resource> resources,
) {
  var created = 0;
  return CCRouterRuntime.forTesting(
    navigationAdapter: adapter,
    components: [
      CCComponentManifest(
        id: 'probe',
        version: '1.0.0',
        registrar: Registrar(
          extra: (r) {
            r.registerService<Resource>(
              CCServiceProvider(
                scope: CCServiceScope.route,
                factory: (_) => resources[created++],
              ),
            );
          },
        ),
      ),
    ],
  )..initialize();
}

void main() {
  for (final fails in [false, true]) {
    test('batch shutdown closes every Route fails=$fails', () async {
      final adapter = ReleaseProbe();
      final resources = [Resource(), Resource()];
      final runtime = runtimeFor(adapter, resources);
      await runtime.goRoute(const Intent());
      runtime.serviceForRoute<Resource>(
        navigationId: runtime.activeRouteEntries.last.navigationId,
      );
      final pushed = runtime
          .pushRoute(const Intent())
          .then<Object?>((_) => null, onError: (Object e) => e);
      await Future<void>.delayed(Duration.zero);
      expect(runtime.activeRouteEntries, hasLength(2));
      runtime.serviceForRoute<Resource>(
        navigationId: runtime.activeRouteEntries.last.navigationId,
      );
      adapter.armed = fails;
      Object? failure;
      try {
        await runtime.dispose();
      } catch (e) {
        failure = e;
      }
      await pushed;
      expect(failure, fails ? same(adapter.failure) : isNull);
      expect(resources.map((r) => r.disposeCalls), [1, 1]);
      expect(runtime.activeRouteEntries, isEmpty);
    });
  }
  for (final boundary in ['shutdown', 'go', 'reset', 'detach']) {
    for (final failureIndex in [0, 1, 2]) {
      for (final crossZone in [false, true]) {
        test(
          '$boundary drains all Entries failure=$failureIndex crossZone=$crossZone',
          () async {
            final adapter = ReleaseProbe();
            final resources = List.generate(3, (_) => Resource());
            final runtime = runtimeFor(adapter, resources);
            addTearDown(() async {
              if (!runtime.isInitialized) return;
              try {
                await runtime.dispose();
              } catch (error) {
                expect(error, same(adapter.failure));
              }
            });
            final disposed = <String>{};
            runtime.addRouteEntryListener((event) {
              if (event.entry.lifecycleState ==
                  CCRouteEntryLifecycleState.disposed) {
                disposed.add(event.entry.navigationId);
              }
            });
            final pushes = <Future<Object?>>[];
            await runtime.goRoute(const Intent());
            for (var i = 0; i < 3; i++) {
              if (i != 0) {
                pushes.add(
                  runtime
                      .pushRoute(const Intent())
                      .then<Object?>(
                        (_) => null,
                        onError: (Object error) => error,
                      ),
                );
                await Future<void>.delayed(Duration.zero);
              }
              runtime.serviceForRoute<Resource>(
                navigationId: runtime.activeRouteEntries.last.navigationId,
              );
            }
            final ids = runtime.activeRouteEntries
                .map((entry) => entry.navigationId)
                .toList();
            adapter
              ..released.clear()
              ..failingId = ids.reversed.elementAt(failureIndex)
              ..armed = true;
            for (final listener in adapter.listeners.toList()) {
              listener(
                CCNavigationBackendEvent(
                  kind: CCNavigationBackendEventKind.push,
                  timestamp: DateTime.now(),
                  hostId: 'primary',
                  backendEntryId: 'foreign',
                  owner: CCBackendEntryOwner.foreign,
                  sequence: 1,
                ),
              );
            }
            Future<(Object?, StackTrace?)> invoke() async {
              try {
                switch (boundary) {
                  case 'shutdown':
                    await runtime.dispose();
                  case 'go':
                    await runtime.goRoute(const Intent());
                  case 'reset':
                    await runtime.resetRoute(const Intent());
                  case 'detach':
                    for (final listener in adapter.listeners.toList()) {
                      listener(
                        CCNavigationBackendEvent(
                          kind: CCNavigationBackendEventKind.hostDetached,
                          timestamp: DateTime.now(),
                          hostId: 'primary',
                          sequence: 2,
                        ),
                      );
                    }
                }
                return (null, null);
              } catch (error, stack) {
                return (error, stack);
              }
            }

            final uncaught = <Object>[];
            final outcome = await (crossZone
                ? runZonedGuarded(invoke, (error, _) => uncaught.add(error))!
                : invoke());
            if (boundary == 'go' || boundary == 'reset') {
              // Business navigation keeps its existing sanitized Adapter error.
              expect(outcome.$1, isA<CCNavigationAdapterError>());
            } else {
              expect(outcome.$1, same(adapter.failure));
              expect(outcome.$2.toString(), adapter.failureStack.toString());
            }
            await Future<void>.delayed(Duration.zero);
            expect(uncaught, isEmpty);
            expect(resources.map((resource) => resource.disposeCalls), [
              1,
              1,
              1,
            ]);
            expect(runtime.activeRouteEntries, isEmpty);
            expect(adapter.released.where(ids.contains), ids.reversed);
            expect(disposed, containsAll(ids));
            if (boundary == 'detach') {
              expect(runtime.activeBackendEntries, isEmpty);
              expect(runtime.desynchronizedBackendHosts, isEmpty);
              // A fresh incarnation may restart its sequence baseline.
              for (final listener in adapter.listeners.toList()) {
                listener(
                  CCNavigationBackendEvent(
                    kind: CCNavigationBackendEventKind.push,
                    timestamp: DateTime.now(),
                    hostId: 'primary',
                    backendEntryId: 'replacement',
                    owner: CCBackendEntryOwner.foreign,
                    sequence: 1,
                  ),
                );
              }
              expect(
                runtime.activeBackendEntries.single.backendEntryId,
                'replacement',
              );
            }
            if (boundary != 'shutdown') await runtime.dispose();
            await Future.wait(pushes);
            expect(resources.map((resource) => resource.disposeCalls), [
              1,
              1,
              1,
            ]);
          },
        );
      }
    }
  }
}
