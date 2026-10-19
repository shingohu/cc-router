import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:test/test.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

final class _Command implements CCCommand<String> {
  const _Command();
}

final class _NestedCommand implements CCCommand<String> {
  const _NestedCommand();
}

final _hostZoneKey = Object();
final _callerRuntimeKey = Object();

final class _RootHeldSink implements CCDiagnosticSink {
  // Create the Future outside invocation Zones so only framework callbacks can
  // retain the Runtime under test, rather than the Sink's own Future origin.
  final release = Completer<void>();
  final observedZones = <Object?>[];

  @override
  Future<void> record(CCDiagnosticEvent event) {
    observedZones.add(Zone.current[_hostZoneKey]);
    return release.future;
  }
}

final class _HeldSink implements CCDiagnosticSink {
  final events = <CCDiagnosticEvent>[];
  final writes = <Completer<void>>[];

  @override
  Future<void> record(CCDiagnosticEvent event) {
    events.add(event);
    final write = Completer<void>();
    writes.add(write);
    return write.future;
  }

  void releaseAll() {
    for (final write in writes) {
      if (!write.isCompleted) write.complete();
    }
  }
}

CCRouterRuntime _runtime(
  CCDiagnosticSink sink, {
  int capacity = 64,
  int? queueCapacity,
  bool nested = false,
}) {
  final runtime = CCRouterRuntime.forTesting(
    traceCapacity: 0,
    navigationDiagnosticCapacity: capacity,
    diagnostics: CCDiagnosticsConfig(
      sink: sink,
      queueCapacity: queueCapacity,
      defaultEnabled: false,
      policies: const [
        CCDiagnosticCategoryPolicy(category: CCDiagnosticCategory.command),
      ],
    ),
  );
  runtime.registerCommand<_Command, String>(
    (_, context) => context.invocationId,
  );
  if (nested) {
    runtime.registerCommand<_NestedCommand, String>(
      (_, _) => runtime.command(const _Command()),
    );
  }
  runtime.initialize();
  return runtime;
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);

void main() {
  for (final closeBeforeTurn in [false, true]) {
    test(
      'nested delivery retains Host Zone, not Runtime; idle close=$closeBeforeTurn',
      () async {
        final sink = _RootHeldSink();
        final reference = await _closedNestedRuntime(sink, closeBeforeTurn);
        try {
          await forceGC(fullGcCycles: 3);
          expect(reference.target, isNull);
          expect(sink.release.isCompleted, isFalse);
          expect(sink.observedZones, ['host']);
        } finally {
          sink.release.complete();
          await _turn();
        }
      },
    );
  }

  for (final mode in [
    'sync',
    'throw',
    'synchronousFuture',
    'future',
    'error',
  ]) {
    for (final seeds in [1, 3]) {
      test('reentrant $mode yields after $seeds initial writes', () async {
        const total = 128;
        var calls = 0;
        final received = <String?>[];
        final observedZones = <Object?>[];
        final timerCalls = Completer<int>();
        late CCRouterRuntime runtime;
        void emit(int index) => runtime.recordHostToolLifecycleFailure(
          integrationId: 'fairness-$index',
          operation: 'probe',
          errorType: 'Probe',
        );

        runtime = runZoned(
          () => CCRouterRuntime.forTesting(
            traceCapacity: 0,
            diagnostics: CCDiagnosticsConfig(
              sink: _CallbackSink((event) {
                calls++;
                received.add(event.target);
                observedZones.add(Zone.current[_hostZoneKey]);
                if (calls == 1) Timer.run(() => timerCalls.complete(calls));
                if (calls <= total - seeds) emit(calls + seeds - 1);
                switch (mode) {
                  case 'throw':
                    throw StateError('sync failure');
                  case 'synchronousFuture':
                    return SynchronousFuture<void>(null);
                  case 'future':
                    return Future<void>.value();
                  case 'error':
                    return Future<void>.error(StateError('async failure'));
                }
              }),
              defaultEnabled: false,
              policies: const [
                CCDiagnosticCategoryPolicy(
                  category: CCDiagnosticCategory.initialization,
                  minimumLevel: CCDiagnosticLevel.error,
                ),
              ],
            ),
          ),
          zoneValues: {_hostZoneKey: 'host'},
        );
        runtime.initialize();
        try {
          runZoned(() {
            for (var index = 0; index < seeds; index++) {
              emit(index);
            }
          }, zoneValues: {_hostZoneKey: 'caller'});
          // Exact first-batch size also prevents a Timer-per-event regression.
          expect(await timerCalls.future, seeds);
          for (var turn = 0; turn < total + 2 && calls < total; turn++) {
            await _turn();
          }
          await _turn();
          expect(calls, total);
          expect(received, [for (var i = 0; i < total; i++) 'fairness-$i']);
          expect(observedZones, everyElement('host'));
          final snapshot = runtime.diagnosticDeliverySnapshot;
          final fails = mode == 'throw' || mode == 'error';
          expect(snapshot.failedEventCount, fails ? total : 0);
          expect(snapshot.deliveredEventCount, fails ? 0 : total);
          expect(snapshot.droppedEventCount, 0);
          expect(snapshot.inFlightWriteCount, 0);
          expect(snapshot.queuedEventCount, 0);
        } finally {
          await runtime.dispose();
        }
      });
    }
  }

  for (final capacity in [0, 64, 128, 1000]) {
    test(
      'slow Sink keeps only one unfinished write at capacity $capacity',
      () async {
        final sink = _HeldSink();
        final runtime = _runtime(sink, capacity: capacity);
        try {
          for (var index = 0; index < 2000; index++) {
            await runtime.command(const _Command());
            if (index % 10 == 9) await _turn();
          }
          expect(sink.events, hasLength(1));
          final snapshot = runtime.diagnosticDeliverySnapshot;
          final limit = capacity < 64 ? 64 : capacity;
          expect(snapshot.queuedEventCount, limit);
          expect(snapshot.inFlightWriteCount, 1);
          expect(snapshot.droppedEventCount, 1999 - limit);
          expect(snapshot.peakQueueDepth, limit);
          // Shutdown must not wait for an application Future that never finishes.
          await runtime.dispose().timeout(const Duration(seconds: 1));
          expect(runtime.diagnosticDeliverySnapshot.queuedEventCount, 0);
          expect(runtime.diagnosticDeliverySnapshot.droppedEventCount, 1999);
          expect(runtime.diagnosticDeliverySnapshot.isClosed, isTrue);
          sink.releaseAll();
          await _turn();
          expect(runtime.diagnosticDeliverySnapshot.inFlightWriteCount, 0);
          expect(sink.events, hasLength(1));
        } finally {
          await runtime.dispose();
          sink.releaseAll();
        }
      },
    );
  }

  test(
    'async failure releases the slot and preserves surviving FIFO order',
    () async {
      final sink = _HeldSink();
      final runtime = _runtime(sink);
      try {
        final first = await runtime.command(const _Command());
        await _turn();
        final waiting = <String>[];
        for (var index = 0; index < 70; index++) {
          waiting.add(await runtime.command(const _Command()));
        }
        expect(runtime.recentTraces, isEmpty);
        expect(sink.events, hasLength(1));
        sink.writes.single.completeError(StateError('private Sink error'));
        // The first batch had one write. Its completion schedules the next
        // batch on a Timer rather than extending the exhausted batch inline.
        await _turn();
        await _turn();
        expect(sink.events, hasLength(2));
        for (var index = 1; index <= 64; index++) {
          sink.writes[index].complete();
          await _turn();
        }
        expect(sink.events, hasLength(65));
        expect(sink.events.map((event) => event.invocationId), [
          first,
          ...waiting.skip(6),
        ]);
        final snapshot = runtime.diagnosticDeliverySnapshot;
        expect(snapshot.deliveredEventCount, 64);
        expect(snapshot.failedEventCount, 1);
        expect(snapshot.droppedEventCount, 6);
        expect(snapshot.inFlightWriteCount, 0);
        expect(snapshot.queuedEventCount, 0);
      } finally {
        await runtime.dispose();
        sink.releaseAll();
      }
    },
  );

  test(
    'explicit capacity is independent and drops oldest before first turn',
    () async {
      final received = <String?>[];
      final runtime = _runtime(
        _CallbackSink((event) {
          received.add(event.invocationId);
        }),
        capacity: 1000,
        queueCapacity: 2,
      );
      try {
        final ids = <String>[];
        for (var index = 0; index < 5; index++) {
          ids.add(await runtime.command(const _Command()));
        }
        expect(received, isEmpty);
        final before = runtime.diagnosticDeliverySnapshot;
        expect(before.queuedEventCount, 2);
        expect(before.droppedEventCount, 3);
        await _turn();
        expect(received, ids.skip(3));
        expect(before.queuedEventCount, 2); // Independent immutable snapshot.
        expect(runtime.diagnosticDeliverySnapshot.deliveredEventCount, 2);
      } finally {
        await runtime.dispose();
      }
    },
  );

  test(
    'synchronous throw and synchronously completing Future keep progressing',
    () async {
      var calls = 0;
      final runtime = _runtime(
        _CallbackSink((_) {
          calls++;
          if (calls == 1) throw StateError('private synchronous error');
          return SynchronousFuture<void>(null);
        }),
      );
      try {
        for (var index = 0; index < 5; index++) {
          await runtime.command(const _Command());
        }
        for (var index = 0; index < 5; index++) {
          await _turn();
        }
        expect(calls, 5);
        final snapshot = runtime.diagnosticDeliverySnapshot;
        expect(snapshot.failedEventCount, 1);
        expect(snapshot.deliveredEventCount, 4);
        expect(snapshot.inFlightWriteCount, 0);
      } finally {
        await runtime.dispose();
      }
    },
  );

  test(
    'reentrant Sink can emit diagnostics and close without deadlock',
    () async {
      late CCRouterRuntime runtime;
      var calls = 0;
      Future<String>? reentrant;
      runtime = _runtime(
        _CallbackSink((_) {
          calls++;
          if (calls == 1) {
            reentrant = runtime.command(const _Command());
          } else {
            return runtime.dispose();
          }
        }),
      );
      await runtime.command(const _Command());
      for (var index = 0; index < 5; index++) {
        await _turn();
      }
      await reentrant;
      await runtime.dispose().timeout(const Duration(seconds: 1));
      expect(calls, 2);
      expect(runtime.diagnosticDeliverySnapshot.isClosed, isTrue);
      expect(runtime.diagnosticDeliverySnapshot.inFlightWriteCount, 0);
    },
  );

  test(
    'late failed write after close is handled without starting waiting data',
    () async {
      final sink = _HeldSink();
      final runtime = _runtime(sink);
      await runtime.command(const _Command());
      await _turn();
      await runtime.command(const _Command());
      await runtime.dispose();
      await runtime.dispose();
      sink.writes.single.completeError(StateError('late failure'));
      await _turn();
      expect(sink.events, hasLength(1));
      expect(runtime.diagnosticDeliverySnapshot.failedEventCount, 1);
      expect(runtime.diagnosticDeliverySnapshot.droppedEventCount, 1);
    },
  );

  test(
    'idle close preserves synchronous final delivery and cancels the timer',
    () async {
      var calls = 0;
      final runtime = _runtime(
        _CallbackSink((_) {
          calls++;
        }),
      );
      await runtime.command(const _Command());
      await runtime.dispose();
      await _turn();
      expect(calls, 1);
      expect(runtime.diagnosticDeliverySnapshot.deliveredEventCount, 1);
      expect(runtime.diagnosticDeliverySnapshot.queuedEventCount, 0);
      expect(runtime.diagnosticDeliverySnapshot.droppedEventCount, 0);
    },
  );

  test(
    'idle close starts at most one async write and discards the rest',
    () async {
      final sink = _HeldSink();
      final runtime = _runtime(sink);
      for (var index = 0; index < 5; index++) {
        await runtime.command(const _Command());
      }
      expect(sink.events, isEmpty);
      await runtime.dispose().timeout(const Duration(seconds: 1));
      expect(sink.events, hasLength(1));
      expect(runtime.diagnosticDeliverySnapshot.droppedEventCount, 4);
      sink.releaseAll();
      await _turn();
      expect(sink.events, hasLength(1));
    },
  );

  test(
    'unfinished application Future does not retain a disposed Runtime',
    () async {
      final sink = _HeldSink();
      final reference = await _closedRuntime(sink);
      try {
        await forceGC(fullGcCycles: 3);
        expect(reference.target, isNull);
        expect(sink.writes.single.isCompleted, isFalse);
      } finally {
        sink.releaseAll();
        await _turn();
      }
    },
  );

  test('invalid independent capacities fail before component installation', () {
    for (final capacity in [0, -1]) {
      expect(
        () => _runtime(_HeldSink(), queueCapacity: capacity),
        throwsArgumentError,
      );
    }
  });
}

final class _CallbackSink implements CCDiagnosticSink {
  _CallbackSink(this.callback);
  final FutureOr<void> Function(CCDiagnosticEvent) callback;
  @override
  FutureOr<void> record(CCDiagnosticEvent event) => callback(event);
}

Future<WeakReference<CCRouterRuntime>> _closedRuntime(_HeldSink sink) async {
  final runtime = _runtime(sink);
  await runtime.command(const _Command());
  await _turn();
  await runtime.command(const _Command());
  await runtime.dispose();
  return WeakReference(runtime);
}

Future<WeakReference<CCRouterRuntime>> _closedNestedRuntime(
  _RootHeldSink sink,
  bool closeBeforeTurn,
) async {
  final runtime = runZoned(
    () => _runtime(sink, nested: true),
    zoneValues: {_hostZoneKey: 'host'},
  );
  await runtime.command(const _NestedCommand());
  if (!closeBeforeTurn) await _turn();
  await runZoned(
    () => runtime.dispose(),
    zoneValues: {_hostZoneKey: 'caller', _callerRuntimeKey: runtime},
  );
  return WeakReference(runtime);
}
