import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';

// fvm dart run packages/ccrouter_test/benchmark/diagnostic_delivery.dart <label>
// Same end-to-end workload before/after the implementation. Event-loop yields
// are outside command timing but inside delivery timing; this is not frame data.
// ignore_for_file: invalid_use_of_visible_for_testing_member
Future<void> main(List<String> args) async {
  const commands = 10000;
  final samples = <Map<String, Object>>[];
  final cpu = _ThreadCpuClock.open();
  try {
    for (var round = 0; round < 9; round++) {
      for (final mode
          in round.isEven
              ? ['off', 'sync', 'future']
              : ['future', 'sync', 'off']) {
        final sink = mode == 'off' ? null : _Sink(mode == 'future');
        final runtime = CCRouterRuntime.forTesting(
          traceCapacity: 0,
          diagnostics: CCDiagnosticsConfig(
            sink: sink,
            defaultEnabled: false,
            policies: const [
              CCDiagnosticCategoryPolicy(
                category: CCDiagnosticCategory.command,
              ),
            ],
          ),
        );
        runtime.registerCommand<_Command, void>((_, _) {});
        runtime.initialize();
        final totalCpuStart = cpu?.microseconds;
        var commandCpu = 0.0;
        final total = Stopwatch()..start();
        final command = Stopwatch();
        for (var index = 0; index < commands; index += 64) {
          final commandCpuStart = cpu?.microseconds;
          command.start();
          for (var j = index; j < index + 64 && j < commands; j++) {
            await runtime.command(const _Command());
          }
          command.stop();
          if (commandCpuStart != null)
            commandCpu += cpu!.microseconds - commandCpuStart;
          await Future<void>.delayed(Duration.zero);
        }
        total.stop();
        final totalCpu = totalCpuStart == null
            ? null
            : cpu!.microseconds - totalCpuStart;
        if (sink != null && sink.count != commands)
          throw StateError('Lost events: ${sink.count}');
        if (round > 1) {
          samples.add({
            'round': round,
            'mode': mode,
            'commandUsPerEvent': command.elapsedMicroseconds / commands,
            'deliveryUsPerEvent': total.elapsedMicroseconds / commands,
            if (totalCpu != null) 'commandCpuUsPerEvent': commandCpu / commands,
            if (totalCpu != null) 'deliveryCpuUsPerEvent': totalCpu / commands,
          });
        }
        await runtime.dispose();
      }
    }
  } finally {
    cpu?.dispose();
  }
  print(
    jsonEncode({
      'label': args.isEmpty ? 'unlabelled' : args.first,
      'commands': commands,
      'samples': samples,
    }),
  );
}

final class _Command implements CCCommand<void> {
  const _Command();
}

final class _Sink implements CCDiagnosticSink {
  _Sink(this.asyncCompletion);
  final bool asyncCompletion;
  var count = 0;
  @override
  FutureOr<void> record(CCDiagnosticEvent event) {
    count++;
    if (asyncCompletion) return Future<void>.value();
  }
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
