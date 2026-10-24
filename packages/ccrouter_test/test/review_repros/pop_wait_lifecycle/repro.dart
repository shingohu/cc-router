import 'dart:async';

import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

import '../../reentrant_lifecycle_regression_test.dart' as fixture;
import '../runtime_round_trip/construction_retention.dart' as routes;
import '../shared_waiter_lifetime/repro.dart' show alive, observe;

class Gate {
  final completion = Completer<CCPopOutcome>();
  int calls = 0;

  Future<CCPopOutcome> wait() {
    calls++;
    return completion.future;
  }

  void finish(bool error) {
    if (error) {
      completion.completeError(StateError('late backend failure'));
    } else {
      completion.complete(const CCPopOutcome(handled: false));
    }
  }
}

class LegacyAdapter extends fixture.ProbeAdapter {
  LegacyAdapter(super.hostId, this.gate);
  final Gate gate;
  @override
  Future<bool> maybePop({Object? result}) =>
      gate.wait().then((outcome) => outcome.handled);
}

class Coordinator extends LegacyAdapter
    implements CCNavigationPopCoordinator, CCNavigationTargetedCloseAdapter {
  Coordinator(super.hostId, super.gate);
  @override
  Future<CCPopOutcome> maybePopOutcome({Object? result}) => gate.wait();
  @override
  CCPopOutcome popOutcome({Object? result}) =>
      const CCPopOutcome(handled: false);
  @override
  Future<CCRouteCloseOutcome> closeNavigation({
    required String navigationId,
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) => gate.wait().then(
    (_) => const CCRouteCloseOutcome(CCRouteCloseStatus.notFound),
  );
}

class ScopedCoordinator extends Coordinator
    implements CCNavigationScopedPopCoordinator {
  ScopedCoordinator(super.hostId, super.gate);
  @override
  Future<CCPopOutcome> maybePopOutcomeAt({
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) => gate.wait();
  @override
  CCPopOutcome popOutcomeAt({
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) => const CCPopOutcome(handled: false);
  @override
  bool canPopAt({required String hostId, required String navigatorOutlet}) =>
      true;
}

class Completion {
  bool settled = false;
  Object? outcome;
  final done = Completer<void>();
}

Future<void> track(Future<Object?> future, Completion state) async {
  state.outcome = await observe(future);
  state.settled = true;
  state.done.complete();
}

final payloadKey = Object();

Future<
  ({
    WeakReference<CCRouterRuntime> runtime,
    WeakReference<routes.Payload> routePayload,
    WeakReference<Object> callerPayload,
    bool settledAtBoundary,
  })
>
startAndEnd(
  String mode,
  String terminal,
  Gate gate,
  Completion state,
  bool pending,
  bool error,
) async {
  final LegacyAdapter adapter = switch (mode) {
    'legacy' => LegacyAdapter('right', gate),
    'scoped' => ScopedCoordinator('right', gate),
    _ => Coordinator('right', gate),
  };
  final aggregate = terminal == 'detach'
      ? CCMultiHostNavigationAdapter(
          defaultHostId: 'right',
          adapters: {'left': fixture.ProbeAdapter('left'), 'right': adapter},
        )
      : null;
  final runtime = CCRouterRuntime.forTesting(
    navigationAdapter: aggregate ?? adapter,
    components: [
      CCComponentManifest(
        id: 'probe',
        version: '1.0.0',
        registrar: routes.Registrar('none', (_) {}),
      ),
    ],
  );
  runtime.initialize();
  final routePayload = routes.Payload();
  await runtime.goRoute(routes.Intent(routePayload));
  final callerPayload = Object();
  final future = Zone.current
      .fork(zoneValues: {payloadKey: callerPayload})
      .run(
        () => track(
          mode == 'close'
              ? runtime.closeRoute(runtime.activeRouteEntries.single.handle!)
              : runtime.maybePopOutcomeRoute<void>(
                  placementOverride: mode == 'scoped'
                      ? const CCRoutePlacement(hostId: 'right')
                      : null,
                ),
          state,
        ),
      );
  expect(gate.calls, 1);
  if (!pending) {
    gate.finish(error);
    await future;
  }
  if (terminal == 'replace') {
    await runtime.goRoute(routes.Intent(routes.Payload()));
    expect(runtime.activeRouteEntries, hasLength(1));
  } else if (terminal == 'detach') {
    aggregate!.unregisterHost('right', replacementActiveHostId: 'left');
  } else {
    await runtime.dispose();
  }
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  final settled = state.settled;
  // End the remaining live Host before measuring Runtime GC. The independent
  // settlement assertion above was captured at the original detach boundary.
  await runtime.dispose();
  expect(adapter.disposeCalls, 1);
  expect(adapter.listeners, isEmpty);
  expect(runtime.activeRouteEntries, isEmpty);
  return (
    runtime: WeakReference(runtime),
    routePayload: WeakReference(routePayload),
    callerPayload: WeakReference(callerPayload),
    settledAtBoundary: settled,
  );
}

void main() {
  for (final mode in ['legacy', 'coordinator', 'scoped', 'close']) {
    for (final terminal in [
      'dispose',
      'detach',
      if (mode == 'close') 'replace',
    ]) {
      for (final pending in [false, true]) {
        for (final error in [false, true]) {
          test('$mode $terminal pending=$pending error=$error', () async {
            final gate = Gate();
            final state = Completion();
            final references = await startAndEnd(
              mode,
              terminal,
              gate,
              state,
              pending,
              error,
            );
            await forceGC(
              fullGcCycles: 3,
              timeout: const Duration(seconds: 20),
            );
            final before = (
              runtime: alive(references.runtime),
              routePayload: alive(references.routePayload),
              callerPayload: alive(references.callerPayload),
            );
            if (pending) gate.finish(error);
            await state.done.future;
            await forceGC(
              fullGcCycles: 3,
              timeout: const Duration(seconds: 20),
            );
            expect(alive(references.runtime), isFalse);
            expect(alive(references.routePayload), isFalse);
            expect(alive(references.callerPayload), isFalse);
            expect(
              (settled: references.settledAtBoundary, retained: before),
              (
                settled: true,
                retained: (
                  runtime: false,
                  routePayload: false,
                  callerPayload: false,
                ),
              ),
              reason:
                  'Owner teardown must end framework waits before backend completion.',
            );
          });
        }
      }
    }
  }
}
