import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

class CallerPayload {}

class SharedResource {}

final callerPayloadKey = Object();

@pragma('vm:never-inline')
bool alive(WeakReference<Object> reference) => reference.target != null;

Future<Object?> observe(Future<Object?> future) => future.then<Object?>(
  (value) => value,
  onError: (Object error, StackTrace _) => error,
);

// This is a second caller only: the shared initializer was already started in
// the Host Zone, so it cannot inherit this caller's payload or its Zone.
Future<WeakReference<CallerPayload>> finishWaiter(
  CCRouterRuntime runtime,
  String terminal,
  bool pending,
) async {
  final payload = CallerPayload();
  final weak = WeakReference(payload);
  final cancellation = CCCancellationToken();
  final result = Zone.current
      .fork(zoneValues: {callerPayloadKey: payload})
      .run(
        () => observe(
          runtime.serviceAsync<SharedResource>(
            cancellation: cancellation,
            timeout: terminal == 'timeout'
                ? const Duration(milliseconds: 50)
                : null,
          ),
        ),
      );
  if (terminal == 'cancel' && pending) cancellation.cancel();
  final outcome = await result;
  expect(
    outcome,
    pending
        ? terminal == 'timeout'
              ? isA<CCInvocationTimeoutError>()
              : isA<CCInvocationCancelledError>()
        : isA<SharedResource>(),
  );
  return weak;
}

void main() {
  for (final terminal in ['cancel', 'timeout']) {
    for (final pending in [false, true]) {
      test(
        'shared pending=$pending releases second caller after $terminal',
        () async {
          final runtime = CCRouterRuntime.forTesting();
          addTearDown(runtime.dispose);
          final started = Completer<void>();
          final release = Completer<void>();
          var starts = 0;
          runtime.registerService(
            CCServiceProvider<SharedResource>(
              factory: (_) => SharedResource(),
              initializer: (_, _) {
                starts++;
                started.complete();
                return release.future;
              },
            ),
          );
          runtime.initialize();
          final first = runtime.serviceAsync<SharedResource>();
          await started.future;
          if (!pending) {
            release.complete();
            await first;
          }
          final references = <WeakReference<CallerPayload>>[];
          for (var index = 0; index < 3; index++) {
            references.add(await finishWaiter(runtime, terminal, pending));
          }
          await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
          final retained = references.where(alive).length;
          if (pending) release.complete();
          await first;
          await Future<void>.delayed(Duration.zero);
          await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
          expect(starts, 1);
          expect(references.where(alive), isEmpty);
          expect(
            retained,
            0,
            reason:
                'ended callers must not accumulate behind a live shared initializer',
          );
        },
      );
    }
  }
}
