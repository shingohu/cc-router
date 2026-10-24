import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:demo_analytics/demo_analytics.dart';

/// Measures analytics enqueue latency, bounded queue pressure, and RSS trend.
///
/// This is a standalone process so RSS samples are not polluted by a test
/// runner. It does not assert an absolute memory limit: compare the JSON output
/// on the same Dart SDK, platform, and process conditions. Use `--events=10000`
/// for a larger local run.
Future<void> main(List<String> arguments) async {
  final eventCount = _option(arguments, 'events', 1000);
  final capacity = _option(arguments, 'capacity', 64);
  if (eventCount <= 0 || capacity <= 0) {
    throw ArgumentError('events and capacity must be positive.');
  }

  final sink = _BlockingSink();
  final dispatcher = AppAnalyticsEventDispatcher(
    sinks: [sink],
    capacity: capacity,
    policy: AppAnalyticsPolicy(consentGranted: true),
  );
  final initialRss = ProcessInfo.currentRss;
  final timings = <int>[];
  for (var index = 0; index < eventCount; index++) {
    final watch = Stopwatch()..start();
    if (!dispatcher.dispatch(_event(index))) {
      throw StateError('Analytics event $index was unexpectedly rejected.');
    }
    watch.stop();
    timings.add(watch.elapsedMicroseconds);
  }

  sink.ready.complete();
  await dispatcher.close();
  final finalRss = ProcessInfo.currentRss;
  stdout.writeln(
    jsonEncode({
      'scenario': 'analytics-dispatcher-pressure',
      'events': eventCount,
      'capacity': capacity,
      'enqueueUsP50': _percentile(timings, .5),
      'enqueueUsP95': _percentile(timings, .95),
      'acceptedEvents': dispatcher.acceptedEventCount,
      'droppedEvents': dispatcher.droppedEventCount,
      'peakQueueDepth': dispatcher.peakQueueDepth,
      'pendingEventsAfterClose': dispatcher.pendingEventCount,
      'initialRssBytes': initialRss,
      'finalRssBytes': finalRss,
      'rssDeltaBytes': finalRss - initialRss,
      'rssObservation':
          'trend-only; compare the same SDK, platform, and process conditions',
    }),
  );
}

final class _BlockingSink implements AppAnalyticsSink {
  final ready = Completer<void>();

  @override
  Future<void> write(AppAnalyticsEvent event) async {
    await ready.future;
  }
}

AppAnalyticsEvent _event(int index) => AppAnalyticsEvent(
  eventId: 'benchmark.event.$index',
  type: AppAnalyticsEventType.custom,
  occurredAt: DateTime.now(),
);

int _option(List<String> arguments, String name, int fallback) {
  final prefix = '--$name=';
  for (final argument in arguments) {
    if (argument.startsWith(prefix)) {
      return int.parse(argument.substring(prefix.length));
    }
  }
  return fallback;
}

int _percentile(List<int> values, double percentile) {
  final sorted = [...values]..sort();
  final index = (sorted.length * percentile).ceil() - 1;
  return sorted[index.clamp(0, sorted.length - 1)];
}
