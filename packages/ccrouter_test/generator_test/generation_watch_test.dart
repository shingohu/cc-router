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
          .where((line) => line.trim().isNotEmpty)
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
    'optimized and reference watch cycles publish identical artifacts',
    () async {
      final before = await _managedArtifacts();
      final optimized = await _runWatchUntilReady();
      final optimizedArtifacts = await _managedArtifacts();
      final reference = await _runWatchUntilReady(
        environment: {
          ...Platform.environment,
          'CCROUTER_DISABLE_WATCH_CYCLE_OPTIMIZATION': '1',
          'CCROUTER_DISABLE_WATCH_IN_PROCESS_CYCLE': '1',
        },
      );
      final referenceArtifacts = await _managedArtifacts();

      expect(optimized.ready['schemaVersion'], 1);
      expect(
        optimized.eventTypes,
        containsAllInOrder(['buildSucceeded', 'aggregationSucceeded', 'ready']),
      );
      expect(optimized.aggregation['cycleMode'], 'inProcess');
      expect(reference.aggregation['cycleMode'], 'subprocessReference');
      print(
        'watch aggregation timing: '
        'inProcess=${optimized.aggregation['elapsedMs']}ms '
        'subprocessReference=${reference.aggregation['elapsedMs']}ms',
      );
      expect(
        _profileSpan(optimized.aggregation, 'fast-path-inspection')['status'],
        'skipped',
      );
      expect(
        _profileSpan(optimized.aggregation, 'build-plan-inspection')['status'],
        'skipped',
      );
      expect(
        _profileSpan(reference.aggregation, 'fast-path-inspection')['status'],
        isNot('skipped'),
      );
      expect(optimizedArtifacts, before);
      expect(referenceArtifacts, optimizedArtifacts);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'one-shot generation fails fast while the root watch is active',
    () async {
      ProcessResult? result;

      await _runWatchUntilReady(
        onReady: () async {
          result = await _run([
            'generate',
            'demo',
            '--check',
          ]).timeout(const Duration(seconds: 30));
        },
      );

      expect(result, isNotNull);
      expect(result!.exitCode, 1);
      expect('${result!.stderr}', contains('active CCRouter generation watch'));
      expect('${result!.stderr}', contains('aggregationSucceeded'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'watch fails fast while one-shot generation is waiting for the root lock',
    () async {
      final generationFile = await _lockFile(
        'generation.lock',
      ).open(mode: FileMode.append);
      await generationFile.lock(FileLock.exclusive);
      final oneShot = await Process.start(Platform.resolvedExecutable, [
        _generatorEntrypoint,
        'generate',
        'demo',
        '--check',
      ], workingDirectory: Directory.current.path);
      final oneShotOutput = utf8.decodeStream(oneShot.stdout);
      final oneShotError = utf8.decodeStream(oneShot.stderr);
      ProcessResult? watch;
      try {
        await _waitForOneShotWatchGuard();
        watch = await _run([
          'generate',
          'demo',
          '--watch=auto',
          '--machine',
        ]).timeout(const Duration(seconds: 30));
      } finally {
        await generationFile.unlock();
        await generationFile.close();
      }

      final oneShotCode = await oneShot.exitCode.timeout(
        const Duration(minutes: 2),
      );
      expect(
        oneShotCode,
        0,
        reason: '${await oneShotError}\n${await oneShotOutput}',
      );
      expect(watch, isNotNull);
      expect(watch.exitCode, 1);
      expect('${watch.stdout}', contains('"stage":"watch-lock"'));
      expect(
        '${watch.stdout}',
        contains('Another CCRouter generation command or watch owns'),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _waitForOneShotWatchGuard() async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final probe = await _lockFile(
      path.join('watch', 'owner.lock'),
    ).open(mode: FileMode.append);
    try {
      await probe.lock(FileLock.exclusive);
      await probe.unlock();
    } on FileSystemException {
      return;
    } finally {
      await probe.close();
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TimeoutException('one-shot command did not acquire its watch guard');
}

File _lockFile(String relative) => File(
  path.join(Directory.current.path, '.dart_tool', 'ccrouter', 'v1', relative),
);

Future<_WatchRun> _runWatchUntilReady({
  Map<String, String>? environment,
  Future<void> Function()? onReady,
}) async {
  final leaseDirectory = Directory(
    path.join(
      Directory.current.path,
      '.dart_tool',
      'ccrouter',
      'test-watch-leases',
    ),
  );
  await leaseDirectory.create(recursive: true);
  final lease = File(
    path.join(
      leaseDirectory.path,
      'flutter-run-${DateTime.now().microsecondsSinceEpoch}.lease',
    ),
  )..writeAsStringSync('test');
  final process = await Process.start(
    Platform.resolvedExecutable,
    [
      _generatorEntrypoint,
      'generate',
      'demo',
      '--watch=auto',
      '--machine',
      '--watch-lease',
      lease.path,
    ],
    workingDirectory: Directory.current.path,
    environment: environment,
  );
  final ready = Completer<Map<String, dynamic>>();
  final stopped = Completer<Map<String, dynamic>>();
  final eventTypes = <String>[];
  final outputLines = <String>[];
  final errorLines = <String>[];
  Map<String, dynamic>? aggregation;
  final outputSubscription = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        outputLines.add(line);
        if (line.trim().isEmpty) return;
        late final Map<String, dynamic> event;
        try {
          event = jsonDecode(line) as Map<String, dynamic>;
        } on Object catch (error) {
          if (!ready.isCompleted) {
            ready.completeError(
              StateError('watch emitted non-machine stdout: $line ($error)'),
            );
          }
          return;
        }
        eventTypes.add(event['type'] as String);
        if (event['type'] == 'aggregationSucceeded') aggregation = event;
        if (event['type'] == 'ready' && !ready.isCompleted) {
          ready.complete(event);
        }
        if (event['type'] == 'failed' && !ready.isCompleted) {
          ready.completeError(
            StateError('watch failed before ready: ${jsonEncode(event)}'),
          );
        }
        if (event['type'] == 'stopped' && !stopped.isCompleted) {
          stopped.complete(event);
        }
      });
  final errorSubscription = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(errorLines.add);
  try {
    final readyEvent = await ready.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => throw TimeoutException(
        'watch did not reach ready\nstdout:\n${outputLines.join('\n')}\n'
        'stderr:\n${errorLines.join('\n')}',
      ),
    );
    await onReady?.call();
    await lease.delete();
    await stopped.future.timeout(const Duration(seconds: 10));
    expect(await process.exitCode, 0);
    return _WatchRun(
      ready: readyEvent,
      aggregation: aggregation!,
      eventTypes: eventTypes,
    );
  } finally {
    process.kill(ProcessSignal.sigterm);
    if (lease.existsSync()) await lease.delete();
    await outputSubscription.cancel();
    await errorSubscription.cancel();
    if (leaseDirectory.existsSync() && leaseDirectory.listSync().isEmpty) {
      await leaseDirectory.delete(recursive: true);
    }
  }
}

Map<String, dynamic> _profileSpan(Map<String, dynamic> event, String name) =>
    ((event['profile'] as Map)['spans'] as List)
        .cast<Map>()
        .map((span) => span.cast<String, dynamic>())
        .singleWhere((span) => span['name'] == name);

Future<Map<String, List<int>>> _managedArtifacts() async {
  final artifacts = <String, List<int>>{};
  for (final rootName in const ['demo', 'packages']) {
    await for (final entity in Directory(
      rootName,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = path.relative(entity.path, from: Directory.current.path);
      final segments = path.split(relative);
      if (segments.contains('.dart_tool') || segments.contains('build')) {
        continue;
      }
      if (!segments.contains('ccrouter_generated')) continue;
      if (!relative.endsWith('.g.dart') &&
          !relative.endsWith('.json') &&
          !relative.endsWith('.md')) {
        continue;
      }
      artifacts[relative] = await entity.readAsBytes();
    }
  }
  return artifacts;
}

final class _WatchRun {
  const _WatchRun({
    required this.ready,
    required this.aggregation,
    required this.eventTypes,
  });

  final Map<String, dynamic> ready;
  final Map<String, dynamic> aggregation;
  final List<String> eventTypes;
}

Future<ProcessResult> _run(
  List<String> arguments, {
  Map<String, String>? environment,
}) => Process.run(
  Platform.resolvedExecutable,
  [_generatorEntrypoint, ...arguments],
  workingDirectory: Directory.current.path,
  environment: environment,
);

String get _generatorEntrypoint => path.join(
  Directory.current.path,
  'packages',
  'ccrouter_generator',
  'bin',
  'ccrouter.dart',
);
