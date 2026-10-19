import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ccrouter_go_router/ccrouter_go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Interleave the actual Adapter with a test-only legacy raw-event reference:
// fvm flutter test --no-pub packages/ccrouter_test/benchmark/navigation_history.dart
// This measures the complete synchronous Observer -> Adapter event path, not
// frame rendering. Timings are reports, never machine-dependent CI thresholds.
void main() {
  test('reports bounded navigation history write and read costs', () {
    const capacities = [0, 2, 1000, 10000];
    const rounds = 7;
    const iterations = 10000;
    const reads = 500;
    final writes = <String, List<double>>{};
    final snapshots = <String, List<double>>{};
    final cpuWrites = <String, List<double>>{};
    final cpuReads = <String, List<double>>{};
    final cpuClock = _ThreadCpuClock.open();
    if (cpuClock != null) addTearDown(cpuClock.dispose);
    for (var round = 0; round < rounds; round++) {
      // Rotate ordering to avoid assigning all startup/thermal effects to one
      // capacity. Each sample gets an independent Adapter and a full buffer.
      for (var offset = 0; offset < capacities.length; offset++) {
        final capacity = capacities[(round + offset) % capacities.length];
        // Alternate pair ordering, so the reference does not always run first.
        for (final legacy in round.isEven ? [true, false] : [false, true]) {
          final key = '$capacity/${legacy ? 'legacy' : 'snapshot'}';
          final rawHistory = <CCGoRouterNavigationEvent>[];
          final observer = CCGoRouterNavigationObserver(
            outlet: 'root',
            onEvent: (event) {
              // Benchmark fixture only. This intentionally reproduces the old
              // retention bug; the two test Routes stay alive in both samples.
              if (!legacy || capacity == 0) return;
              if (rawHistory.length == capacity) rawHistory.removeAt(0);
              rawHistory.add(event);
            },
          );
          final router = GoRouter(
            routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
          );
          final adapter = CCGoRouterAdapter(
            router: router,
            observers: [observer],
            lifecycleEventCapacity: legacy ? 0 : capacity,
          );
          adapter.initialize(const []);
          List<Object> readHistory() => legacy
              ? List<CCGoRouterNavigationEvent>.unmodifiable(rawHistory)
              : adapter.lifecycleEvents;
          final home = MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/'),
            builder: (_) => const SizedBox(),
          );
          final detail = MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/detail'),
            builder: (_) => const SizedBox(),
          );
          var delivered = 0;
          final unsubscribe = adapter.addBackendEventListener(
            (_) => delivered++,
          );
          void visit() {
            observer.didPush(detail, home);
            observer.didPop(detail, home);
          }

          for (var index = 0; index < 12000; index++) {
            visit();
          }
          final cpuWriteStart = cpuClock?.microseconds;
          final watch = Stopwatch()..start();
          for (var index = 0; index < iterations; index++) {
            visit();
          }
          watch.stop();
          if (cpuClock != null) {
            cpuWrites
                .putIfAbsent(key, () => [])
                .add(
                  (cpuClock.microseconds - cpuWriteStart!) / (iterations * 2),
                );
          }
          writes
              .putIfAbsent(key, () => [])
              .add(watch.elapsedMicroseconds / (iterations * 2));
          expect(delivered, (12000 + iterations) * 2);
          // Avoid benchmarking only the aligned head==0 fast path: default
          // capacity divides the event counts above. Exercise wrapped reads.
          observer.didPush(detail, home);
          expect(readHistory(), hasLength(capacity));

          var readCount = 0;
          watch.reset();
          final cpuReadStart = cpuClock?.microseconds;
          watch.start();
          for (var index = 0; index < reads; index++) {
            readCount += readHistory().length;
          }
          watch.stop();
          if (cpuClock != null) {
            cpuReads
                .putIfAbsent(key, () => [])
                .add((cpuClock.microseconds - cpuReadStart!) / reads);
          }
          snapshots
              .putIfAbsent(key, () => [])
              .add(watch.elapsedMicroseconds / reads);
          expect(readCount, capacity * reads);
          unsubscribe();
          adapter.dispose();
          router.dispose();
          home.dispose();
          detail.dispose();
        }
      }
    }

    double median(List<double> values) =>
        (values.toList()..sort())[rounds ~/ 2];
    // JSON is easy to retain alongside a commit or compare across processes.
    // RSS is intentionally excluded: the two fixed test Routes do not model
    // retained application trees; lifecycle regression tests check actual GC.
    print(
      jsonEncode({
        'benchmark': 'navigation-history',
        'sdk': Platform.version,
        'rounds': rounds,
        'eventsPerRound': iterations * 2,
        'cpuClock': cpuClock == null ? 'unavailable' : 'mutator-thread',
        'results': [
          for (final capacity in capacities)
            for (final implementation in ['legacy', 'snapshot'])
              {
                'capacity': capacity,
                'implementation': implementation,
                'writeMicrosecondsPerEvent': median(
                  writes['$capacity/$implementation']!,
                ),
                'readMicrosecondsPerSnapshot': median(
                  snapshots['$capacity/$implementation']!,
                ),
                'writeSamples': writes['$capacity/$implementation'],
                'readSamples': snapshots['$capacity/$implementation'],
                if (cpuClock != null) ...{
                  'writeCpuMicrosecondsPerEvent': median(
                    cpuWrites['$capacity/$implementation']!,
                  ),
                  'readCpuMicrosecondsPerSnapshot': median(
                    cpuReads['$capacity/$implementation']!,
                  ),
                  'writeCpuSamples': cpuWrites['$capacity/$implementation'],
                  'readCpuSamples': cpuReads['$capacity/$implementation'],
                },
              },
        ],
      }),
    );
  });
}

// Optional test-only POSIX clock. Wall time is still reported above, but busy
// developer machines can deschedule Flutter for unrelated builds. Thread CPU
// time isolates synchronous mutator work; it excludes GC pauses/other threads
// and must not be presented as end-to-end frame latency or allocation cost.
final class _ClockTimespec extends Struct {
  @Int64()
  external int seconds;

  @Int64()
  external int nanoseconds;
}

final class _ThreadCpuClock {
  _ThreadCpuClock(this._read, this._free, this._value, this._clockId);

  static _ThreadCpuClock? open() {
    if ((!Platform.isMacOS && !Platform.isLinux) || sizeOf<IntPtr>() != 8) {
      return null;
    }
    final library = DynamicLibrary.process();
    final allocate = library
        .lookupFunction<
          Pointer<Void> Function(IntPtr),
          Pointer<Void> Function(int)
        >('malloc');
    final free = library
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('free');
    final read = library
        .lookupFunction<
          Int32 Function(Int32, Pointer<_ClockTimespec>),
          int Function(int, Pointer<_ClockTimespec>)
        >('clock_gettime');
    final pointer = allocate(sizeOf<_ClockTimespec>()).cast<_ClockTimespec>();
    if (pointer == nullptr) throw StateError('Could not allocate CPU clock.');
    // Darwin and Linux define different clockid_t values for thread CPU time.
    final clock = _ThreadCpuClock(
      read,
      free,
      pointer,
      Platform.isMacOS ? 16 : 3,
    );
    if (read(clock._clockId, pointer) != 0) {
      clock.dispose();
      return null;
    }
    return clock;
  }

  final int Function(int, Pointer<_ClockTimespec>) _read;
  final void Function(Pointer<Void>) _free;
  final Pointer<_ClockTimespec> _value;
  final int _clockId;

  double get microseconds {
    if (_read(_clockId, _value) != 0)
      throw StateError('CPU clock read failed.');
    return _value.ref.seconds * 1000000 + _value.ref.nanoseconds / 1000;
  }

  void dispose() => _free(_value.cast<Void>());
}
