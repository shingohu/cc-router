import 'dart:async';
import 'dart:convert';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';

// Benchmark support intentionally consumes Core's visible-for-testing boundary.
// ignore_for_file: invalid_use_of_visible_for_testing_member

// Run with fvm dart run packages/ccrouter_test/benchmark/diagnostic_capacity.dart.
// This reports the distinction between retained history, a bounded delivery
// queue and unfinished asynchronous Sink work. It is not a memory byte budget.
Future<void> main() async {
  const commands = 2000;
  final results = <Map<String, Object>>[];
  for (final capacity in [0, 64, 128, 1000]) {
    final sink = _HeldSink();
    final runtime = CCRouterRuntime.forTesting(
      traceCapacity: capacity,
      navigationDiagnosticCapacity: capacity,
      diagnostics: CCDiagnosticsConfig(
        sink: sink,
        defaultEnabled: false,
        policies: const [
          CCDiagnosticCategoryPolicy(category: CCDiagnosticCategory.command),
        ],
      ),
    );
    runtime.registerCommand<_ProbeCommand, void>((_, _) {});
    runtime.initialize();
    try {
      for (var index = 0; index < commands; index++) {
        await runtime.command(const _ProbeCommand());
        // Allow the queue to drain without resolving any Sink Future. Each
        // burst stays below even the minimum operational queue capacity.
        if (index % 10 == 9) await Future<void>.delayed(Duration.zero);
      }
      final traces = runtime.recentTraces.length;
      if (traces != capacity || sink.inFlight != 1) {
        throw StateError('Unexpected capacity probe: $traces/${sink.inFlight}');
      }
      final delivery = runtime.diagnosticDeliverySnapshot;
      results.add({
        'configuredCapacity': capacity,
        'retainedTraces': traces,
        'commands': commands,
        'unfinishedSinkWrites': sink.inFlight,
        'peakUnfinishedSinkWrites': sink.peakInFlight,
        'queuedEvents': delivery.queuedEventCount,
        'queueCapacity': delivery.queueCapacity,
        'droppedEvents': delivery.droppedEventCount,
      });
    } finally {
      await runtime.dispose();
      sink.release.complete();
      await Future<void>.delayed(Duration.zero);
      if (sink.inFlight != 0) throw StateError('Probe Sink did not finish.');
    }
  }
  print(jsonEncode({'benchmark': 'diagnostic-capacity', 'results': results}));
}

final class _ProbeCommand implements CCCommand<void> {
  const _ProbeCommand();
}

final class _HeldSink implements CCDiagnosticSink {
  final release = Completer<void>();
  var inFlight = 0;
  var peakInFlight = 0;

  @override
  Future<void> record(CCDiagnosticEvent event) async {
    inFlight++;
    if (inFlight > peakInFlight) peakInFlight = inFlight;
    await release.future;
    inFlight--;
  }
}
