@TestOn('vm')
@Timeout(Duration(minutes: 20))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'support/real_workspace_test_lock.dart';

void main() {
  serializeRealWorkspaceTests();

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
      expect(events.last.containsKey('profile'), isFalse);

      final profiled = await _run(
        ['generate', 'demo', '--watch=auto', '--machine', '--profile'],
        environment: {
          ...Platform.environment,
          'CCROUTER_DISABLE_BUILD_WATCH': '1',
        },
      );
      expect(profiled.exitCode, 0, reason: '${profiled.stderr}');
      final profiledEvents = const LineSplitter()
          .convert('${profiled.stdout}')
          .where((line) => line.trim().isNotEmpty)
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      expect(profiledEvents.last['profile'], isA<Map>());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'watch publishes active and stopped local status',
    () async {
      ProcessResult? activeStatus;
      Map<String, dynamic>? activeDocument;

      final watch = await _runWatchUntilReady(
        onReady: () async {
          activeStatus = await _run(['watch', 'status', 'demo']);
          activeDocument =
              jsonDecode(
                    File(
                      path.join(
                        Directory.current.path,
                        'demo',
                        '.dart_tool',
                        'ccrouter',
                        'v1',
                        'watch',
                        'status.json',
                      ),
                    ).readAsStringSync(),
                  )
                  as Map<String, dynamic>;
        },
      );

      expect(activeStatus, isNotNull);
      expect(activeStatus!.exitCode, 0, reason: '${activeStatus!.stderr}');
      expect('${activeStatus!.stdout}', contains('watch status: active'));
      expect(activeDocument!['state'], 'ready');
      expect(activeDocument!['active'], isTrue);
      expect(activeDocument!['lastEvent'], 'ready');
      expect(activeDocument!['lastBuildElapsedMs'], isA<int>());
      expect(activeDocument!['lastBuildRunnerMs'], isNull);
      expect(activeDocument!['lastAggregationElapsedMs'], isA<int>());
      expect(activeDocument!['lastCycleMode'], 'inProcess');
      expect(watch.aggregation.containsKey('profile'), isFalse);

      final stopped = await _run(['watch', 'status', 'demo']);
      expect(stopped.exitCode, 0, reason: '${stopped.stderr}');
      expect('${stopped.stdout}', contains('watch status: inactive'));
      expect('${stopped.stdout}', contains('state: stopped'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'optimized and reference watch cycles publish identical artifacts',
    () async {
      final before = await _managedArtifacts();
      final optimized = await _runWatchUntilReady(profile: true);
      final optimizedArtifacts = await _managedArtifacts();
      final optimizedPlanningState = await _localPlanningState();
      final outputEvidenceReference = await _runWatchUntilReady(
        profile: true,
        environment: {
          ...Platform.environment,
          'CCROUTER_DISABLE_WATCH_OUTPUT_EVIDENCE_REUSE': '1',
        },
      );
      final outputEvidenceReferenceArtifacts = await _managedArtifacts();
      final outputEvidenceReferencePlanningState = await _localPlanningState();
      final evidenceReference = await _runWatchUntilReady(
        profile: true,
        environment: {
          ...Platform.environment,
          'CCROUTER_DISABLE_WATCH_EVIDENCE_REUSE': '1',
        },
      );
      final evidenceReferenceArtifacts = await _managedArtifacts();
      final evidenceReferencePlanningState = await _localPlanningState();
      final reference = await _runWatchUntilReady(
        profile: true,
        environment: {
          ...Platform.environment,
          'CCROUTER_DISABLE_WATCH_CYCLE_OPTIMIZATION': '1',
          'CCROUTER_DISABLE_WATCH_IN_PROCESS_CYCLE': '1',
        },
      );
      final referenceArtifacts = await _managedArtifacts();
      final referencePlanningState = await _localPlanningState();

      expect(optimized.ready['schemaVersion'], 1);
      final buildRunner = (optimized.build['buildRunner'] as Map)
          .cast<String, dynamic>();
      expect(buildRunner['formatVersion'], 1);
      expect(buildRunner['durationMs'], isA<int>());
      expect(buildRunner['writtenOutputs'], isA<int>());
      expect((buildRunner['phases'] as List), isNotEmpty);
      expect(
        (buildRunner['totals'] as Map)['inputs'],
        greaterThanOrEqualTo((buildRunner['totals'] as Map)['skipped'] as int),
      );
      expect(buildRunner['unparsedFinalLines'], isNull);
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
      expect(
        (_profileSpan(
              optimized.aggregation,
              'planning-snapshot-capture',
            )['attributes']
            as Map)['evidenceMode'],
        'input-and-current-output',
      );
      expect(
        (_profileSpan(
              outputEvidenceReference.aggregation,
              'planning-snapshot-capture',
            )['attributes']
            as Map)['evidenceMode'],
        isIn(const ['input', 'input-and-aggregation-output']),
      );
      expect(
        (_profileSpan(
              evidenceReference.aggregation,
              'planning-snapshot-capture',
            )['attributes']
            as Map)['evidenceMode'],
        'recaptured',
      );
      expect(optimizedArtifacts, before);
      expect(outputEvidenceReferenceArtifacts, optimizedArtifacts);
      expect(evidenceReferenceArtifacts, optimizedArtifacts);
      expect(referenceArtifacts, optimizedArtifacts);
      expect(outputEvidenceReferencePlanningState, optimizedPlanningState);
      expect(evidenceReferencePlanningState, optimizedPlanningState);
      expect(referencePlanningState, optimizedPlanningState);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'watch restarts only when the resolved Host closure needs a new session',
    () async {
      final pubspec = File(
        path.join(Directory.current.path, 'demo', 'pubspec.yaml'),
      );
      final originalPubspec = pubspec.readAsStringSync();
      final originalArtifacts = await _managedArtifacts();
      var restoredResolution = false;
      try {
        final watch = await _runWatchUntilReady(
          onReady: () async {
            final initial = await _readWatchStatus();
            final initialSession = initial['sessionId'] as String;

            final added = _replaceOnce(
              originalPubspec,
              '  demo_order: ^0.1.0\n',
              '  demo_order: ^0.1.0\n'
                  '  demo_analytics_firebase: ^0.1.0\n',
            );
            pubspec.writeAsStringSync(added, flush: true);
            final addPub = await _runDemoPubGet();
            expect(addPub.exitCode, 0, reason: '${addPub.stderr}');
            final restarted = await _waitForWatchStatus(
              (status) =>
                  status['sessionId'] != initialSession &&
                  status['lastEvent'] == 'ready',
            );
            final restartedSession = restarted['sessionId'] as String;
            expect(restarted['sessionReady'], isTrue);

            pubspec.writeAsStringSync(originalPubspec, flush: true);
            final removePub = await _runDemoPubGet();
            expect(removePub.exitCode, 0, reason: '${removePub.stderr}');
            restoredResolution = true;
            await _waitForWatchStatus(
              (status) =>
                  (status['sessionId'] == restartedSession &&
                      status['cycle'] is int &&
                      (status['cycle'] as int) > 1 &&
                      status['lastEvent'] == 'aggregationSucceeded') ||
                  (status['sessionId'] != restartedSession &&
                      status['lastEvent'] == 'ready'),
            );
          },
        );

        expect(
          watch.eventTypes.where((type) => type == 'sessionRestarting'),
          isNotEmpty,
        );
        expect(await _managedArtifacts(), originalArtifacts);
      } finally {
        pubspec.writeAsStringSync(originalPubspec, flush: true);
        if (!restoredResolution) {
          final restorePub = await _runDemoPubGet();
          expect(restorePub.exitCode, 0, reason: '${restorePub.stderr}');
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  test(
    'watch handles Dart file add rename and delete without session restart',
    () async {
      final source = _watchProbeSource();
      final renamed = _watchProbeSource(renamed: true);
      final sourceOutputs = _watchProbeOutputs();
      final renamedOutputs = _watchProbeOutputs(renamed: true);
      final originalArtifacts = await _managedArtifacts();
      try {
        final added = await _runWatchUntilReady(
          onReady: () async {
            final initial = await _readWatchStatus();
            final session = initial['sessionId'];
            final cycle = initial['cycle'] as int;
            source.writeAsStringSync(_watchProbeContents, flush: true);
            await _waitForWatchStatus(
              (status) =>
                  status['sessionId'] == session &&
                  status['cycle'] is int &&
                  (status['cycle'] as int) > cycle &&
                  status['lastEvent'] == 'aggregationSucceeded' &&
                  sourceOutputs.every((file) => file.existsSync()),
            );
          },
        );
        expect(added.eventTypes, isNot(contains('sessionRestarting')));

        final moved = await _runWatchUntilReady(
          onReady: () async {
            final initial = await _readWatchStatus();
            final session = initial['sessionId'];
            final cycle = initial['cycle'] as int;
            source.renameSync(renamed.path);
            await _waitForWatchStatus(
              (status) =>
                  status['sessionId'] == session &&
                  status['cycle'] is int &&
                  (status['cycle'] as int) > cycle &&
                  status['lastEvent'] == 'aggregationSucceeded' &&
                  sourceOutputs.every((file) => !file.existsSync()) &&
                  renamedOutputs.every((file) => file.existsSync()),
            );
          },
        );
        expect(moved.eventTypes, isNot(contains('sessionRestarting')));

        final deleted = await _runWatchUntilReady(
          onReady: () async {
            final initial = await _readWatchStatus();
            final session = initial['sessionId'];
            final cycle = initial['cycle'] as int;
            renamed.deleteSync();
            await _waitForWatchStatus(
              (status) =>
                  status['sessionId'] == session &&
                  status['cycle'] is int &&
                  (status['cycle'] as int) > cycle &&
                  status['lastEvent'] == 'aggregationSucceeded' &&
                  renamedOutputs.every((file) => !file.existsSync()),
            );
          },
        );
        expect(deleted.eventTypes, isNot(contains('sessionRestarting')));
        expect(await _managedArtifacts(), originalArtifacts);
      } finally {
        if (source.existsSync()) source.deleteSync();
        if (renamed.existsSync()) renamed.deleteSync();
        final restored = await _run(['generate', 'demo', '--no-cache']);
        expect(restored.exitCode, 0, reason: '${restored.stderr}');
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
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
    'watch evidence reuse keeps current Builder-only output bytes',
    () async {
      final source = File(
        path.join(
          Directory.current.path,
          'demo',
          'modules',
          'navigation_lab',
          'lib',
          'src',
          'stack_page.dart',
        ),
      );
      final original = source.readAsStringSync();
      final originalArtifacts = await _managedArtifacts();
      final seededSource = _replaceOnce(
        _replaceOnce(
          original,
          "import 'ccrouter_generated/demo_navigation_lab_component.api.g.dart';\n",
          "import 'ccrouter_generated/demo_navigation_lab_component.api.g.dart';\n\n"
              'const ccrouterWatchDefaultReturnsResult = false;\n',
        ),
        'this.returnsResult = false',
        'this.returnsResult = ccrouterWatchDefaultReturnsResult',
      );
      final changedSource = _replaceOnce(
        seededSource,
        'ccrouterWatchDefaultReturnsResult = false',
        'ccrouterWatchDefaultReturnsResult = true',
      );
      try {
        source.writeAsStringSync(seededSource, flush: true);
        final seed = await _run(['generate', 'demo']);
        expect(seed.exitCode, 0, reason: '${seed.stderr}');
        final seededArtifacts = await _managedArtifacts();

        final optimized = await _runWatchUntilReady(
          profile: true,
          onReady: () async {
            source.writeAsStringSync(changedSource, flush: true);
          },
          additionalAggregationCycles: 1,
        );
        expect(
          (_profileSpan(
                optimized.aggregation,
                'aggregation-reuse-inspection',
              )['attributes']
              as Map)['result'],
          'hit',
        );
        expect(
          (_profileSpan(
                optimized.aggregation,
                'planning-snapshot-capture',
              )['attributes']
              as Map)['evidenceMode'],
          'input-and-current-output',
        );
        final optimizedArtifacts = await _managedArtifacts();
        final optimizedPlanningState = await _localPlanningState();
        expect(
          _changedArtifactPaths(seededArtifacts, optimizedArtifacts),
          contains(
            path.join(
              'demo',
              'modules',
              'navigation_lab',
              'lib',
              'src',
              'ccrouter_generated',
              'route',
              'stack_page.route.g.dart',
            ),
          ),
        );

        source.writeAsStringSync(seededSource, flush: true);
        final referenceSeed = await _run(['generate', 'demo']);
        expect(referenceSeed.exitCode, 0, reason: '${referenceSeed.stderr}');
        final evidenceReference = await _runWatchUntilReady(
          profile: true,
          environment: {
            ...Platform.environment,
            'CCROUTER_DISABLE_WATCH_EVIDENCE_REUSE': '1',
          },
          onReady: () async {
            source.writeAsStringSync(changedSource, flush: true);
          },
          additionalAggregationCycles: 1,
        );
        expect(
          (_profileSpan(
                evidenceReference.aggregation,
                'aggregation-reuse-inspection',
              )['attributes']
              as Map)['result'],
          'hit',
        );
        expect(
          (_profileSpan(
                evidenceReference.aggregation,
                'planning-snapshot-capture',
              )['attributes']
              as Map)['evidenceMode'],
          'recaptured',
        );
        expect(await _managedArtifacts(), optimizedArtifacts);
        expect(await _localPlanningState(), optimizedPlanningState);
      } finally {
        source.writeAsStringSync(original, flush: true);
        final restored = await _run(['generate', 'demo']);
        expect(restored.exitCode, 0, reason: '${restored.stderr}');
        expect(await _managedArtifacts(), originalArtifacts);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
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

File _watchProbeSource({bool renamed = false}) => File(
  path.join(
    Directory.current.path,
    'demo',
    'modules',
    'navigation_lab',
    'lib',
    'src',
    renamed
        ? 'ccrouter_watch_file_probe_renamed.dart'
        : 'ccrouter_watch_file_probe.dart',
  ),
);

List<File> _watchProbeOutputs({bool renamed = false}) {
  final stem = renamed
      ? 'ccrouter_watch_file_probe_renamed'
      : 'ccrouter_watch_file_probe';
  final generated = path.join(
    Directory.current.path,
    'demo',
    'modules',
    'navigation_lab',
    'lib',
    'src',
    'ccrouter_generated',
  );
  return [
    File(path.join(generated, 'route', '$stem.route.g.dart')),
    File(path.join(generated, 'binding', '$stem.route_binding.g.dart')),
  ];
}

const _watchProbeContents = '''
import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/widgets.dart';

@CCRoute<void>(
  id: 'demo_navigation_lab.watch_probe',
  pattern: CCPathPattern('/lab/watch-probe'),
)
final class CCRouterWatchProbePage extends StatelessWidget {
  const CCRouterWatchProbePage({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

Future<ProcessResult> _runDemoPubGet() => Process.run(
  'fvm',
  const ['flutter', 'pub', 'get'],
  workingDirectory: path.join(Directory.current.path, 'demo'),
  environment: {...Platform.environment, 'CCROUTER_PUB_HOOK_DISABLE': '1'},
);

Future<Map<String, dynamic>> _readWatchStatus() async =>
    jsonDecode(
          await File(
            path.join(
              Directory.current.path,
              'demo',
              '.dart_tool',
              'ccrouter',
              'v1',
              'watch',
              'status.json',
            ),
          ).readAsString(),
        )
        as Map<String, dynamic>;

Future<Map<String, dynamic>> _waitForWatchStatus(
  bool Function(Map<String, dynamic> status) predicate,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  Map<String, dynamic>? latest;
  while (DateTime.now().isBefore(deadline)) {
    try {
      latest = await _readWatchStatus();
      if (predicate(latest)) return latest;
    } on FileSystemException {
      // Atomic publication may briefly replace the status file.
    } on FormatException {
      // Retry if a non-atomic filesystem exposes an intermediate write.
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('watch status did not match: ${jsonEncode(latest)}');
}

File _lockFile(String relative) => File(
  path.join(Directory.current.path, '.dart_tool', 'ccrouter', 'v1', relative),
);

Future<_WatchRun> _runWatchUntilReady({
  Map<String, String>? environment,
  Future<void> Function()? onReady,
  int additionalAggregationCycles = 0,
  bool profile = false,
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
      if (profile) '--profile',
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
  Map<String, dynamic>? build;
  var aggregationCount = 0;
  int? targetAggregationCount;
  final additionalAggregationsCompleted = Completer<void>();
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
        if (event['type'] == 'buildSucceeded') {
          build = event;
        }
        if (event['type'] == 'aggregationSucceeded') {
          aggregation = event;
          aggregationCount += 1;
          final target = targetAggregationCount;
          if (target != null &&
              aggregationCount >= target &&
              !additionalAggregationsCompleted.isCompleted) {
            additionalAggregationsCompleted.complete();
          }
        }
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
    targetAggregationCount = aggregationCount + additionalAggregationCycles;
    await onReady?.call();
    if (additionalAggregationCycles > 0) {
      await additionalAggregationsCompleted.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw TimeoutException(
          'watch did not complete $additionalAggregationCycles additional '
          'aggregation cycle(s)\nstdout:\n${outputLines.join('\n')}\n'
          'stderr:\n${errorLines.join('\n')}',
        ),
      );
    }
    await lease.delete();
    await stopped.future.timeout(const Duration(seconds: 10));
    expect(await process.exitCode, 0);
    return _WatchRun(
      ready: readyEvent,
      build: build!,
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

Future<Map<String, List<int>>> _localPlanningState() async {
  final state = <String, List<int>>{};
  for (final directoryName in const ['manifests', 'build_plans']) {
    final directory = Directory(
      path.join(
        Directory.current.path,
        '.dart_tool',
        'ccrouter',
        'v1',
        directoryName,
      ),
    );
    if (!directory.existsSync()) continue;
    for (final file in directory.listSync().whereType<File>()) {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map || decoded['hostPackage'] != 'ccrouter_demo')
        continue;
      state['$directoryName/${path.basename(file.path)}'] = await file
          .readAsBytes();
    }
  }
  return state;
}

List<String> _changedArtifactPaths(
  Map<String, List<int>> before,
  Map<String, List<int>> after,
) {
  bool bytesEqual(List<int>? left, List<int>? right) {
    if (left == null || right == null || left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  return <String>{
    ...before.keys,
    ...after.keys,
  }.where((name) => !bytesEqual(before[name], after[name])).toList()..sort();
}

String _replaceOnce(String source, String from, String to) {
  final first = source.indexOf(from);
  if (first < 0 || source.indexOf(from, first + from.length) >= 0) {
    throw StateError('Expected exactly one source marker: $from');
  }
  return source.replaceRange(first, first + from.length, to);
}

final class _WatchRun {
  const _WatchRun({
    required this.ready,
    required this.build,
    required this.aggregation,
    required this.eventTypes,
  });

  final Map<String, dynamic> ready;
  final Map<String, dynamic> build;
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
