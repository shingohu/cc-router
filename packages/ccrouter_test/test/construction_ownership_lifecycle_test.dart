import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

import 'review_repros/runtime_round_trip/construction_retention.dart'
    as fixture;

class _Dependency extends fixture.Resource {}

class _CapturingPolicy implements CCNavigationInterceptor {
  _CapturingPolicy(this.zones);
  final List<Zone> zones;

  @override
  CCNavigationInterceptorDecision intercept(
    CCNavigationInterceptorContext context,
  ) {
    zones.add(Zone.current);
    return const CCNavigationProceed();
  }
}

Future<WeakReference<CCRouterRuntime>> _navigateAndDispose(
  List<Zone> zones, {
  required bool decision,
}) async {
  final runtime = CCRouterRuntime.forTesting(
    navigationAdapter: CCMemoryNavigationAdapter(),
    components: [
      CCComponentManifest(
        id: 'probe',
        version: '1.0.0',
        registrar: fixture.Registrar('none', (_) {}),
      ),
    ],
    globalInterceptors: decision
        ? [
            CCGlobalNavigationInterceptor(
              id: 'capture',
              interceptor: _CapturingPolicy(zones),
            ),
          ]
        : const [],
  )..initialize();
  if (!decision) {
    runtime.addNavigationListener((_) => zones.add(Zone.current));
  }
  await runtime.goRoute(fixture.Intent(fixture.Payload()));
  await Future<void>.delayed(Duration.zero);
  await runtime.dispose();
  return WeakReference(runtime);
}

Future<fixture.Resource> _resolveOwner(
  CCRouterRuntime runtime,
  CCServiceScope scope,
) async {
  if (scope == CCServiceScope.session) {
    runtime.openSession(accountId: 'old');
  }
  if (scope == CCServiceScope.route) {
    await runtime.goRoute(fixture.Intent(fixture.Payload()));
    return runtime.serviceForRouteAsync<fixture.Resource>(
      navigationId: runtime.activeRouteEntries.single.navigationId,
    );
  }
  return runtime.serviceAsync<fixture.Resource>();
}

Future<WeakReference<CCRouterRuntime>> _constructAndDispose(
  String phase,
  CCServiceScope scope,
  List<Zone> zones,
) async {
  final runtime = CCRouterRuntime.forTesting(
    navigationAdapter: CCMemoryNavigationAdapter(),
    components: [
      CCComponentManifest(
        id: 'probe',
        version: '1.0.0',
        registrar: fixture.Registrar(phase, zones.add, scope: scope),
      ),
    ],
  )..initialize();
  final resource = await _resolveOwner(runtime, scope);
  await runtime.dispose();
  expect(resource.disposals, 1);
  return WeakReference(runtime);
}

class _RouteAppRegistrar implements CCComponentRegistrar {
  _RouteAppRegistrar(this.phase, this.runtime, this.capture);
  final String phase;
  final CCRouterRuntime Function() runtime;
  final void Function(Zone) capture;

  @override
  void register(CCRegistry registry) {
    registry.registerRoute(
      CCRouteDefinition<fixture.Payload, void>(
        routeId: 'probe.payload',
        patterns: [const CCPathPattern('/payload', primary: true)],
        codec: const fixture.Codec(),
      ),
    );
    registry.registerService(
      CCServiceProvider<_Dependency>(
        factory: (_) {
          if (phase == 'factory') capture(Zone.current);
          return _Dependency();
        },
        initializer: phase == 'initializer'
            ? (_, _) => capture(Zone.current)
            : null,
      ),
    );
    registry.registerService(
      CCServiceProvider<fixture.Resource>(
        scope: CCServiceScope.route,
        factory: (_) {
          if (phase == 'factory') runtime().service<_Dependency>();
          return fixture.Resource();
        },
        initializer: phase == 'initializer'
            ? (_, _) async {
                await runtime().serviceAsync<_Dependency>();
              }
            : null,
      ),
    );
  }
}

void main() {
  for (final decision in [false, true]) {
    test(
      'retained navigation callback Zone releases Runtime decision=$decision',
      () async {
        final zones = <Zone>[];
        final runtime = await _navigateAndDispose(zones, decision: decision);
        expect(zones, isNotEmpty);
        await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
        expect(runtime.target, isNull);
        expect(zones, isNotEmpty);
      },
    );
  }
  for (final phase in ['factory', 'initializer']) {
    for (final scope in CCServiceScope.values) {
      test('retained $scope $phase Zone releases ended Runtime', () async {
        final zones = <Zone>[];
        final runtime = await _constructAndDispose(phase, scope, zones);
        expect(zones, hasLength(1));
        await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
        expect(runtime.target, isNull);
        expect(zones, hasLength(1));
      });

      test(
        'live $scope $phase owner survives GC and fences its later callback',
        () async {
          final zones = <Zone>[];
          final runtime = CCRouterRuntime.forTesting(
            navigationAdapter: CCMemoryNavigationAdapter(),
            components: [
              CCComponentManifest(
                id: 'probe',
                version: '1.0.0',
                registrar: fixture.Registrar(phase, zones.add, scope: scope),
              ),
            ],
          );
          addTearDown(runtime.dispose);
          runtime.registerService(
            CCServiceProvider<_Dependency>(
              creationPolicy: CCServiceCreationPolicy.newInstance,
              factory: (_) => _Dependency(),
            ),
          );
          runtime.initialize();
          final resource = await _resolveOwner(runtime, scope);
          await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
          final dependency = zones.single.run(runtime.service<_Dependency>);
          expect(dependency.disposals, 0);
          switch (scope) {
            case CCServiceScope.app:
              await runtime.dispose();
            case CCServiceScope.session:
              await runtime.closeSession();
              runtime.openSession(accountId: 'new');
            case CCServiceScope.route:
              await runtime.closeRoute(
                runtime.activeRouteEntries.single.handle!,
              );
              await Future<void>.delayed(Duration.zero);
              await runtime.goRoute(fixture.Intent(fixture.Payload()));
          }
          expect(resource.disposals, 1);
          expect(dependency.disposals, 1);
          await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
          expect(
            () => zones.single.run(runtime.service<_Dependency>),
            throwsA(
              anyOf(
                isA<CCInvocationCancelledError>(),
                isA<CCScopeClosedError>(),
                isA<CCRouterNotInitializedError>(),
              ),
            ),
          );
          if (scope != CCServiceScope.app) {
            final independent = runtime.service<_Dependency>();
            expect(independent.disposals, 0);
            await runtime.dispose();
            expect(independent.disposals, 1);
          }
        },
      );
    }

    test(
      'shared App $phase retains no first Route payload or short-lived owner',
      () async {
        late CCRouterRuntime runtime;
        final zones = <Zone>[];
        runtime = CCRouterRuntime.forTesting(
          navigationAdapter: CCMemoryNavigationAdapter(),
          components: [
            CCComponentManifest(
              id: 'probe',
              version: '1.0.0',
              registrar: _RouteAppRegistrar(phase, () => runtime, zones.add),
            ),
          ],
        )..initialize();
        addTearDown(runtime.dispose);
        final retained = await fixture.openAndClose(runtime, phase);
        expect(retained.$2.disposals, 1);
        final app = runtime.service<_Dependency>();
        expect(zones, hasLength(1));
        await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
        expect(retained.$1.target, isNull);
        expect(zones.single.run(runtime.service<_Dependency>), same(app));
        expect(app.disposals, 0);
        await runtime.dispose();
        expect(app.disposals, 1);
      },
    );
  }
}
