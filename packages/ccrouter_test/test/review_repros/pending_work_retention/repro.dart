import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

import '../runtime_round_trip/construction_retention.dart' as fixture;

class Resource implements CCDisposable {
  int disposals = 0;
  @override
  void dispose() => disposals++;
}

// Keep WeakReference dereferences out of the async test's suspended stack.
// In particular, a nullable-chain temporary must not itself retain the payload
// across the following await/GC cycle.
@pragma('vm:never-inline')
bool targetIsAlive(WeakReference<Object>? reference) =>
    reference?.target != null;

class Registrar implements CCComponentRegistrar {
  Registrar(this.scope, this.resource, this.started, this.release, this.policy);
  final CCServiceScope scope;
  final Resource resource;
  final Completer<void> started;
  final Completer<void> release;
  final CCServiceCreationPolicy policy;

  @override
  void register(CCRegistry registry) {
    fixture.Registrar('none', (_) {}).register(registry);
    registry.registerService(
      CCServiceProvider<Resource>(
        scope: scope,
        creationPolicy: policy,
        factory: (_) => resource,
        initializer: (_, _) {
          started.complete();
          return release.future;
        },
      ),
    );
  }
}

Future<
  ({
    WeakReference<CCRouterRuntime> runtime,
    WeakReference<fixture.Payload>? payload,
    Resource resource,
  })
>
startAndDispose(
  CCServiceScope scope,
  Completer<void> release,
  bool pending,
  CCServiceCreationPolicy policy,
) async {
  final started = Completer<void>();
  final resource = Resource();
  final runtime = CCRouterRuntime.forTesting(
    navigationAdapter: CCMemoryNavigationAdapter(),
    components: [
      CCComponentManifest(
        id: 'probe',
        version: '1.0.0',
        registrar: Registrar(scope, resource, started, release, policy),
      ),
    ],
  );
  runtime.initialize();
  WeakReference<fixture.Payload>? payload;
  if (scope == CCServiceScope.session) runtime.openSession(accountId: 'old');
  if (scope == CCServiceScope.route) {
    final arguments = fixture.Payload();
    payload = WeakReference(arguments);
    await runtime.goRoute(fixture.Intent(arguments));
  }
  final work = scope == CCServiceScope.route
      ? runtime.serviceForRouteAsync<Resource>(
          navigationId: runtime.activeRouteEntries.single.navigationId,
        )
      : runtime.serviceAsync<Resource>();
  final observed = work.then<Object?>(
    (_) => null,
    onError: (Object error, StackTrace _) => error,
  );
  await started.future;
  if (!pending) {
    release.complete();
    expect(await observed, isNull);
  }
  await runtime.dispose();
  if (pending) expect(await observed, isA<CCInvocationCancelledError>());
  expect(resource.disposals, 1);
  return (
    runtime: WeakReference(runtime),
    payload: payload,
    resource: resource,
  );
}

void main() {
  for (final scope in CCServiceScope.values) {
    for (final policy in CCServiceCreationPolicy.values) {
      for (final pending in [false, true]) {
        test(
          'pending initializer=$pending scope=$scope policy=$policy releases ended owner',
          () async {
            final release = Completer<void>();
            final retained = await startAndDispose(
              scope,
              release,
              pending,
              policy,
            );
            await forceGC(
              fullGcCycles: 3,
              timeout: const Duration(seconds: 20),
            );
            final runtimeRetained = targetIsAlive(retained.runtime);
            final payloadRetained = targetIsAlive(retained.payload);
            if (pending) release.complete();
            await Future<void>.delayed(Duration.zero);
            await forceGC(
              fullGcCycles: 3,
              timeout: const Duration(seconds: 20),
            );
            expect(
              (
                runtimeBefore: runtimeRetained,
                payloadBefore: payloadRetained,
                runtimeAfter: targetIsAlive(retained.runtime),
                payloadAfter: targetIsAlive(retained.payload),
              ),
              (
                runtimeBefore: false,
                payloadBefore: false,
                runtimeAfter: false,
                payloadAfter: false,
              ),
              reason:
                  'initializer holds only the external Future; fields describe retention before/after release',
            );
          },
        );
      }
    }
  }
}
