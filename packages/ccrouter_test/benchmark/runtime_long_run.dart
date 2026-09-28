import 'dart:convert';
import 'dart:io';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';

// Benchmark support intentionally consumes Core's visible-for-testing boundary.
// ignore_for_file: invalid_use_of_visible_for_testing_member

/// Runs a bounded long-lived Runtime navigation and reclamation benchmark.
///
/// The benchmark is deliberately a standalone process so RSS samples describe
/// the Dart VM hosting the Runtime rather than a test runner with unrelated
/// retained state. Use `--cycles=10000` for a longer local observation. RSS is
/// reported as a trend only; garbage collection and platform allocators make a
/// fixed byte threshold unsuitable for a cross-platform test assertion.
Future<void> main(List<String> arguments) async {
  final cycles = _option(arguments, 'cycles', 1000);
  final recreateEvery = _option(arguments, 'recreate-every', 100);
  if (cycles <= 0 || recreateEvery <= 0) {
    throw ArgumentError('cycles and recreate-every must be positive.');
  }

  final rssSamples = <int>[];
  final cycleMicros = <int>[];
  var peakEntries = 0;
  var peakPending = 0;
  var completedCycles = 0;
  final initialRss = ProcessInfo.currentRss;

  CCRouterRuntime? runtime;
  try {
    for (var cycle = 0; cycle < cycles; cycle++) {
      if (runtime == null || cycle % recreateEvery == 0) {
        if (runtime != null) {
          await runtime.dispose();
          _verifyDisposed(runtime);
        }
        runtime = _createRuntime()..initialize();
      }

      final watch = Stopwatch()..start();
      final result = runtime.pushRoute<void>(
        _StressIntent<void>('long-run-$cycle'),
      );
      await Future<void>.delayed(Duration.zero);
      peakEntries = _max(peakEntries, runtime.activeRouteEntries.length);
      peakPending = _max(peakPending, runtime.pendingNavigations.length);
      runtime.popRoute<void>();
      await result;
      watch.stop();
      cycleMicros.add(watch.elapsedMicroseconds);
      completedCycles++;

      if (runtime.activeRouteEntries.isNotEmpty ||
          runtime.pendingNavigations.isNotEmpty ||
          runtime.activeBackendEntries.isNotEmpty) {
        throw StateError('Runtime retained navigation state at cycle $cycle.');
      }
      if (cycle % 100 == 0 || cycle == cycles - 1) {
        rssSamples.add(ProcessInfo.currentRss);
      }
    }
  } finally {
    if (runtime != null) {
      await runtime.dispose();
      _verifyDisposed(runtime);
    }
  }

  final finalRss = ProcessInfo.currentRss;
  print(
    jsonEncode({
      'scenario': 'runtime-long-run-rss',
      'cycles': cycles,
      'recreateEvery': recreateEvery,
      'completedCycles': completedCycles,
      'cycleUsP50': _percentile(cycleMicros, 0.50),
      'cycleUsP95': _percentile(cycleMicros, 0.95),
      'peakActiveEntries': peakEntries,
      'peakPendingNavigations': peakPending,
      'initialRssBytes': initialRss,
      'finalRssBytes': finalRss,
      'rssDeltaBytes': finalRss - initialRss,
      'rssSamplesBytes': rssSamples,
      'rssObservation':
          'trend-only; compare same SDK, platform, and process conditions',
    }),
  );
}

int _option(List<String> arguments, String name, int fallback) {
  final prefix = '--$name=';
  final value = arguments
      .where((argument) => argument.startsWith(prefix))
      .map((argument) => int.parse(argument.substring(prefix.length)))
      .firstOrNull;
  return value ?? fallback;
}

CCRouterRuntime _createRuntime() => CCRouterRuntime.forTesting(
  traceCapacity: 32,
  navigationDiagnosticCapacity: 32,
  navigationAdapter: CCMemoryNavigationAdapter(),
  components: const [
    CCComponentManifest(
      id: 'long-run',
      version: '1.0.0',
      registrar: _StressRegistrar(),
    ),
  ],
);

final class _StressIntent<R> implements CCRouteIntent<R> {
  const _StressIntent(this.value);

  final String value;

  @override
  String get routeId => 'long-run.detail';

  @override
  Object get arguments => value;
}

final class _StressRegistrar implements CCComponentRegistrar {
  const _StressRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerRoute<String, void>(
      CCRouteDefinition<String, void>(
        routeId: 'long-run.detail',
        patterns: const [CCPathPattern('/long-run/:id', primary: true)],
        codec: const _StressCodec(),
      ),
    );
  }
}

final class _StressCodec implements CCRouteCodec<String> {
  const _StressCodec();

  @override
  String decode(CCEncodedRouteArguments input) => input.path['id']!;

  @override
  CCEncodedRouteArguments encode(String arguments) =>
      CCEncodedRouteArguments(path: {'id': arguments});
}

void _verifyDisposed(CCRouterRuntime runtime) {
  if (runtime.activeRouteEntries.isNotEmpty ||
      runtime.activeBackendEntries.isNotEmpty ||
      runtime.pendingNavigations.isNotEmpty) {
    throw StateError('Runtime retained state after dispose.');
  }
}

int _max(int first, int second) => first > second ? first : second;

int _percentile(List<int> values, double percentile) {
  if (values.isEmpty) {
    return 0;
  }
  final sorted = [...values]..sort();
  final index = (sorted.length * percentile).ceil() - 1;
  return sorted[index.clamp(0, sorted.length - 1)];
}
