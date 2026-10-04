@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('machine requires watch mode', () async {
    final result = await _run(['generate', 'demo', '--machine']);

    expect(result.exitCode, 2);
    expect('${result.stderr}', contains('--machine requires --watch=auto'));
  });

  test(
    'watch kill switch performs one machine-readable fallback',
    () async {
      final result = await _run(
        ['generate', 'demo', '--watch=auto', '--machine'],
        environment: {
          ...Platform.environment,
          'CCROUTER_DISABLE_BUILD_WATCH': '1',
        },
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final events = const LineSplitter()
          .convert('${result.stdout}')
          .where((line) => line.trimLeft().startsWith('{'))
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      expect(events.map((event) => event['type']), [
        'starting',
        'fallback',
        'succeeded',
      ]);
      expect(events.last['profile'], isA<Map>());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'watch reaches ready and stops when its lease is removed',
    () async {
      final leaseDirectory = await Directory.systemTemp.createTemp(
        'ccrouter_watch_lease_',
      );
      addTearDown(() async {
        if (leaseDirectory.existsSync()) {
          await leaseDirectory.delete(recursive: true);
        }
      });
      final lease = File(path.join(leaseDirectory.path, 'flutter-run.lease'))
        ..writeAsStringSync('test');
      final process = await Process.start(Platform.resolvedExecutable, [
        'run',
        '--verbosity=error',
        'ccrouter_generator:ccrouter',
        'generate',
        'demo',
        '--watch=auto',
        '--machine',
        '--watch-lease',
        lease.path,
      ], workingDirectory: Directory.current.path);
      addTearDown(() => process.kill(ProcessSignal.sigterm));
      final ready = Completer<Map<String, dynamic>>();
      final stopped = Completer<Map<String, dynamic>>();
      final eventTypes = <String>[];
      final outputSubscription = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (!line.trimLeft().startsWith('{')) return;
            final event = jsonDecode(line) as Map<String, dynamic>;
            eventTypes.add(event['type'] as String);
            if (event['type'] == 'ready' && !ready.isCompleted) {
              ready.complete(event);
            }
            if (event['type'] == 'stopped' && !stopped.isCompleted) {
              stopped.complete(event);
            }
          });
      final errorSubscription = process.stderr.listen((_) {});
      addTearDown(outputSubscription.cancel);
      addTearDown(errorSubscription.cancel);
      final readyEvent = await ready.future.timeout(const Duration(minutes: 2));
      expect(readyEvent['schemaVersion'], 1);
      expect(
        eventTypes,
        containsAllInOrder([
          'buildSucceeded',
          'aggregationSucceeded',
          'ready',
        ]),
      );

      await lease.delete();
      final stoppedEvent = await stopped.future.timeout(
        const Duration(seconds: 10),
      );
      expect(stoppedEvent['type'], 'stopped');
      expect(await process.exitCode, 0);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<ProcessResult> _run(
  List<String> arguments, {
  Map<String, String>? environment,
}) => Process.run(
  Platform.resolvedExecutable,
  ['run', '--verbosity=error', 'ccrouter_generator:ccrouter', ...arguments],
  workingDirectory: Directory.current.path,
  environment: environment,
);
