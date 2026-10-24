import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Codec implements CCRouteCodec<int> {
  const _Codec();
  @override
  int decode(CCRouteCodecValues input) => int.parse(input.path['id']!);
  @override
  CCRouteCodecValues encode(int value) =>
      CCRouteCodecValues(path: {'id': '$value'});
}

final class _Intent implements CCRouteIntent<int> {
  const _Intent(this.arguments);
  @override
  final int arguments;
  @override
  String get routeId => 'benchmark.detail';
}

final class _Registrar implements CCComponentRegistrar {
  @override
  void register(CCRegistry registry) => registry.registerRoute(
    CCRouteDefinition<int, int>(
      routeId: 'benchmark.detail',
      patterns: [const CCPathPattern('/detail/:id', primary: true)],
      codec: const _Codec(),
    ),
  );
}

// Measures the shared Runtime diagnostics path, not rendering or a legacy Adapter.
// Run separately: fvm flutter test --no-pub packages/ccrouter_test/benchmark/navigation_history.dart
void main() {
  test('reports backend-neutral Runtime history costs', () async {
    final cpu = _ThreadCpuClock.open();
    if (cpu != null) addTearDown(cpu.dispose);
    final results = <Map<String, Object?>>[];
    for (final capacity in [0, 2, 1000, 10000]) {
      final adapter = CCMemoryNavigationAdapter();
      // Benchmarks deliberately exercise the explicit test-only Runtime path.
      // ignore: invalid_use_of_visible_for_testing_member
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        navigationDiagnosticCapacity: capacity,
        traceCapacity: 0,
        components: [
          CCComponentManifest(
            id: 'benchmark',
            version: '1.0.0',
            registrar: _Registrar(),
          ),
        ],
      )..initialize();
      for (var index = 0; index < 6000; index++) {
        final result = runtime.pushRoute<int>(_Intent(index));
        runtime.popRoute(result: index);
        await result;
      }
      const iterations = 1000;
      final cpuStart = cpu?.microseconds;
      final watch = Stopwatch()..start();
      for (var index = 0; index < iterations; index++) {
        final result = runtime.pushRoute<int>(_Intent(index));
        runtime.popRoute(result: index);
        expect(await result, index);
      }
      watch.stop();
      final writeTime = watch.elapsedMicroseconds;
      final cpuTime = cpu == null ? null : cpu.microseconds - cpuStart!;
      final count = runtime.recentNavigationEvents.length;
      expect(count, capacity);
      const reads = 500;
      watch.reset();
      watch.start();
      var readCount = 0;
      for (var index = 0; index < reads; index++) {
        readCount += runtime.recentNavigationEvents.length;
      }
      watch.stop();
      expect(readCount, capacity * reads);
      results.add({
        'capacity': capacity,
        'wallMicrosecondsPerPushPop': writeTime / iterations,
        'cpuMicrosecondsPerPushPop': cpuTime == null
            ? null
            : cpuTime / iterations,
        'wallMicrosecondsPerSnapshot': watch.elapsedMicroseconds / reads,
      });
      await runtime.dispose();
    }
    print(
      jsonEncode({
        'benchmark': 'runtime-navigation-lifecycle-history',
        'scope':
            'memory-backend plus Runtime; excludes Flutter frames and allocation/heap',
        'sdk': Platform.version,
        'results': results,
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
