import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_test/ccrouter_ui_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

final class _CleanupCount {
  int calls = 0;
}

final class _CleanupOwner {
  _CleanupOwner(this.count);
  final _CleanupCount count;

  Future<void> unmount() async => count.calls++;
}

// Keep the body and cleanup in separate objects. Closures sharing a captured
// application Context would retain the Owner independently of the test helper.
final class _BodyGate {
  final completion = Completer<void>();

  Future<void> wait() => completion.future;
}

typedef _Probe = ({
  WeakReference<_CleanupOwner> owner,
  _CleanupCount cleanup,
  CCUIFragmentTestHost host,
  _BodyGate gate,
  Future<void> running,
});

Future<_Probe> _prepare({required bool pendingBody}) async {
  final count = _CleanupCount();
  final owner = _CleanupOwner(count);
  final gate = _BodyGate();
  if (!pendingBody) gate.completion.complete();
  final host = CCUIFragmentTestHost(
    hostAssembly: CCHostAssembly.fromComponents(components: const []),
  );
  final running = host.run(gate.wait, unmount: owner.unmount);
  await host.dispose();
  if (!pendingBody) await running;
  expect(count.calls, 1);
  return (
    owner: WeakReference(owner),
    cleanup: count,
    host: host,
    gate: gate,
    running: running,
  );
}

void main() {
  tearDown(CCRouterHost.shutdown);

  for (final pendingBody in [false, true]) {
    test(
      'disposed UI Host releases unmount Owner: pending body=$pendingBody',
      () async {
        final probe = await _prepare(pendingBody: pendingBody);
        try {
          // Retain the Host, body producer and returned Future through GC. Only
          // the helper's reference to the already-executed cleanup should end.
          expect(probe.gate.completion.isCompleted, !pendingBody);
          expect(CCRouter.isInitialized, isFalse);
          await forceGC(fullGcCycles: 5, timeout: const Duration(seconds: 15));
          expect(
            probe.owner.target,
            isNull,
            reason:
                'Unmount ownership must end before an external body finishes',
          );
        } finally {
          if (!probe.gate.completion.isCompleted)
            probe.gate.completion.complete();
          await probe.running;
          await probe.host.dispose();
        }
        expect(probe.cleanup.calls, 1);
      },
    );
  }
}
