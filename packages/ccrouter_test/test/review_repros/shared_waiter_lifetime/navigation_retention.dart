import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

import '../runtime_round_trip/construction_retention.dart' as routes;
import 'repro.dart' show alive, observe;

class Gate
    implements
        CCNavigationInterceptor,
        CCNavigationFailurePolicy,
        CCRouteRevalidationPolicy,
        CCDiagnosticSink {
  bool enabled = false;
  final started = Completer<void>();
  final release = Completer<Object>();

  Future<T> wait<T>() {
    if (!started.isCompleted) started.complete();
    return release.future.then((value) => value as T);
  }

  @override
  FutureOr<CCNavigationInterceptorDecision> intercept(
    CCNavigationInterceptorContext context,
  ) => enabled
      ? wait<CCNavigationInterceptorDecision>()
      : const CCNavigationProceed();
  @override
  Future<CCNavigationFailureDecision> onFailure(
    CCNavigationFailureContext context,
  ) => wait();
  @override
  Future<CCRouteRevalidationDecision> evaluate(
    CCRouteRevalidationContext context,
  ) => wait();
  @override
  FutureOr<void> record(CCDiagnosticEvent event) {
    if (!enabled) return Future<void>.value();
    return wait<Object>().then<void>((_) {});
  }
}

class MissingIntent implements CCRouteIntent<void> {
  @override
  String get routeId => 'probe.missing';
  @override
  Object get arguments => 'missing';
}

Object decision(String mode) => switch (mode) {
  'interceptor' => const CCNavigationProceed(),
  'failurePolicy' => const CCNavigationFailurePropagate(),
  'revalidation' => const CCRouteRevalidationKeep(),
  _ => Object(),
};

Future<
  ({
    WeakReference<CCRouterRuntime> runtime,
    WeakReference<routes.Payload> payload,
  })
>
startAndDispose(String mode, Gate gate, bool pending, bool lateError) async {
  final runtime = CCRouterRuntime.forTesting(
    navigationAdapter: CCMemoryNavigationAdapter(),
    globalInterceptors: mode == 'interceptor'
        ? [CCGlobalNavigationInterceptor(id: 'probe.policy', interceptor: gate)]
        : const [],
    navigationFailurePolicy: mode == 'failurePolicy' ? gate : null,
    routeRevalidationPolicies: mode == 'revalidation'
        ? [
            CCGlobalRouteRevalidationPolicy(
              id: 'probe.revalidate',
              policy: gate,
            ),
          ]
        : const [],
    diagnostics: CCDiagnosticsConfig(
      sink: mode == 'diagnostics' ? gate : null,
      defaultMinimumLevel: CCDiagnosticLevel.debug,
    ),
    components: [
      CCComponentManifest(
        id: 'probe',
        version: '1.0.0',
        registrar: routes.Registrar('none', (_) {}),
      ),
    ],
  );
  runtime.initialize();
  final payload = routes.Payload();
  await runtime.goRoute(routes.Intent(payload));
  gate.enabled = true;
  final work = observe(switch (mode) {
    'interceptor' => runtime.goRoute(routes.Intent(payload)),
    'failurePolicy' => runtime.goRoute(MissingIntent()),
    'revalidation' => runtime.revalidateActiveRoutes(reason: 'probe.changed'),
    _ => runtime.goRoute(routes.Intent(payload)),
  });
  await gate.started.future;
  if (!pending) {
    if (lateError)
      gate.release.completeError(StateError('business failure'));
    else
      gate.release.complete(decision(mode));
    await work;
  }
  await runtime.dispose();
  if (pending && mode != 'diagnostics') {
    expect(await work, isA<CCRouteCancelledError>());
  } else {
    await work;
  }
  return (runtime: WeakReference(runtime), payload: WeakReference(payload));
}

void main() {
  for (final mode in [
    'interceptor',
    'failurePolicy',
    'revalidation',
    'diagnostics',
  ]) {
    for (final pending in [false, true]) {
      for (final lateError in [false, true]) {
        test(
          '$mode pending=$pending lateError=$lateError releases Runtime and payload',
          () async {
            final gate = Gate();
            final references = await startAndDispose(
              mode,
              gate,
              pending,
              lateError,
            );
            await forceGC(
              fullGcCycles: 3,
              timeout: const Duration(seconds: 20),
            );
            final runtimeRetained = alive(references.runtime);
            final payloadRetained = alive(references.payload);
            if (pending) {
              if (lateError)
                gate.release.completeError(StateError('late business failure'));
              else
                gate.release.complete(decision(mode));
            }
            await Future<void>.delayed(Duration.zero);
            await forceGC(
              fullGcCycles: 3,
              timeout: const Duration(seconds: 20),
            );
            expect(alive(references.runtime), isFalse);
            expect(alive(references.payload), isFalse);
            expect((runtimeRetained, payloadRetained), (false, false));
          },
        );
      }
    }
  }
}
