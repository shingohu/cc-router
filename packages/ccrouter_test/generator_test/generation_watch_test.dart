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
      expect(activeDocument!['inputRevision'], 0);
      expect(activeDocument!['completedInputRevision'], 0);
      expect(activeDocument!['hotRestartRequired'], isFalse);
      expect(watch.aggregation.containsKey('profile'), isFalse);

      final stopped = await _run(['watch', 'status', 'demo']);
      expect(stopped.exitCode, 0, reason: '${stopped.stderr}');
      expect('${stopped.stdout}', contains('watch status: inactive'));
      expect('${stopped.stdout}', contains('state: stopped'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'shared Builder status publication is fail-open',
    () async {
      final status = _lockFile(path.join('watch', 'builder-status.json'));
      final original = status.existsSync() ? status.readAsBytesSync() : null;
      if (status.existsSync()) status.deleteSync();
      Directory(status.path).createSync(recursive: true);
      try {
        final watch = await _runWatchUntilReady();

        expect(
          watch.eventTypes,
          containsAll(['aggregationSucceeded', 'ready']),
        );
        expect(
          watch.errors.where(
            (line) => line.contains(
              'CCRouter shared Builder status updates are disabled',
            ),
          ),
          hasLength(1),
        );
      } finally {
        if (Directory(status.path).existsSync()) {
          Directory(status.path).deleteSync(recursive: true);
        }
        if (original != null) {
          status
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(original);
        }
      }
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
      expect(
        outputEvidenceReferencePlanningState,
        optimizedPlanningState,
        reason: _planningStateDifferenceReason(
          optimizedPlanningState,
          outputEvidenceReferencePlanningState,
        ),
      );
      expect(
        evidenceReferencePlanningState,
        optimizedPlanningState,
        reason: _planningStateDifferenceReason(
          optimizedPlanningState,
          evidenceReferencePlanningState,
        ),
      );
      expect(
        referencePlanningState,
        optimizedPlanningState,
        reason: _planningStateDifferenceReason(
          optimizedPlanningState,
          referencePlanningState,
        ),
      );
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
            expect(restarted['hotRestartRequired'], isTrue);

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
    'watch does not attribute a mid-cycle save to the older cycle',
    () async {
      final source = _watchProbeSource();
      final originalArtifacts = await _managedArtifacts();
      Map<String, dynamic>? firstCompletion;
      var secondSaveWritten = false;
      try {
        await _runWatchUntilReady(
          onReady: () async {
            source.writeAsStringSync(_watchProbeContents, flush: true);
          },
          onEvent: (event) {
            if (event['type'] == 'buildStarted' &&
                event['initial'] == false &&
                !secondSaveWritten) {
              secondSaveWritten = true;
              source.writeAsStringSync(
                '$_watchProbeContents\n// Mid-cycle authored save.\n',
                flush: true,
              );
              return;
            }
            if (event['type'] == 'aggregationSucceeded' &&
                secondSaveWritten &&
                firstCompletion == null) {
              firstCompletion = _readWatchStatusSync();
            }
          },
          additionalAggregationCycles: 2,
        );

        expect(secondSaveWritten, isTrue);
        expect(firstCompletion, isNotNull);
        expect(
          firstCompletion!['completedInputRevision'],
          lessThan(firstCompletion!['inputRevision'] as int),
        );
        final completed = await _readWatchStatus();
        expect(completed['lastEvent'], 'stopped');
        expect(completed['completedInputRevision'], completed['inputRevision']);
      } finally {
        if (source.existsSync()) source.deleteSync();
        final restored = await _run(['generate', 'demo', '--no-cache']);
        expect(restored.exitCode, 0, reason: '${restored.stderr}');
        expect(await _managedArtifacts(), originalArtifacts);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
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
            final inputRevision = initial['inputRevision'] as int;
            source.writeAsStringSync(_watchProbeContents, flush: true);
            final completed = await _waitForWatchStatus(
              (status) =>
                  status['sessionId'] == session &&
                  status['cycle'] is int &&
                  (status['cycle'] as int) > cycle &&
                  status['lastEvent'] == 'aggregationSucceeded' &&
                  sourceOutputs.every((file) => file.existsSync()),
            );
            expect(completed['inputRevision'], greaterThan(inputRevision));
            expect(
              completed['completedInputRevision'],
              completed['inputRevision'],
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
    'Hosts sharing one build root reuse one Builder owner in either start order',
    () async {
      final demoRoot = Directory(path.join(Directory.current.path, 'demo'));
      final exampleRoot = Directory(
        path.join(demoRoot.path, 'modules', 'order', 'example'),
      );
      final source = File(
        path.join(
          demoRoot.path,
          'modules',
          'navigation_lab',
          'lib',
          'src',
          'stack_page.dart',
        ),
      );
      final original = source.readAsStringSync();

      Future<void> verifyOrder(Directory first, Directory second) async {
        final owner = await _ConcurrentWatch.start(first);
        _ConcurrentWatch? subscriber;
        try {
          final ownerReady = await owner.waitUntilReady();
          subscriber = await _ConcurrentWatch.start(second);
          final subscriberReady = await subscriber.waitUntilReady();
          expect(ownerReady['builderOwnerPid'], isA<int>());
          expect(
            subscriberReady['builderOwnerPid'],
            ownerReady['builderOwnerPid'],
          );

          final ownerCycle = ownerReady['cycle'] as int;
          final subscriberCycle = subscriberReady['cycle'] as int;
          source.writeAsStringSync(
            '$original\n// Shared build-root watch probe.\n',
            flush: true,
          );
          final ownerAfter = await owner.waitForCycleAfter(ownerCycle);
          final subscriberAfter = await subscriber.waitForCycleAfter(
            subscriberCycle,
          );
          final ownerIsDemo = path.equals(first.path, demoRoot.path);
          final demoBefore = ownerIsDemo ? ownerReady : subscriberReady;
          final demoAfter = ownerIsDemo ? ownerAfter : subscriberAfter;
          final exampleBefore = ownerIsDemo ? subscriberReady : ownerReady;
          final exampleAfter = ownerIsDemo ? subscriberAfter : ownerAfter;
          expect(
            demoAfter['inputRevision'] as int,
            greaterThan(demoBefore['inputRevision'] as int),
          );
          expect(exampleAfter['inputRevision'], exampleBefore['inputRevision']);
          source.writeAsStringSync(original, flush: true);
          await owner.waitForCycleAfter(ownerCycle + 1);
          await subscriber.waitForCycleAfter(subscriberCycle + 1);
        } finally {
          source.writeAsStringSync(original, flush: true);
          await subscriber?.stop();
          await owner.stop();
        }
      }

      await verifyOrder(demoRoot, exampleRoot);
      await verifyOrder(exampleRoot, demoRoot);
      final reference = await _run([
        'generate',
        'demo',
        '--no-cache',
        '--check',
      ]);
      expect(reference.exitCode, 0, reason: '${reference.stderr}');
      final exampleReference = await _run([
        'generate',
        'demo/modules/order/example',
        '--no-cache',
        '--check',
      ]);
      expect(
        exampleReference.exitCode,
        0,
        reason: '${exampleReference.stderr}',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  test(
    'subscriber takes over the shared Builder when its owner exits',
    () async {
      final demoRoot = Directory(path.join(Directory.current.path, 'demo'));
      final exampleRoot = Directory(
        path.join(demoRoot.path, 'modules', 'order', 'example'),
      );
      final owner = await _ConcurrentWatch.start(demoRoot);
      _ConcurrentWatch? subscriber;
      try {
        final ownerReady = await owner.waitUntilReady();
        subscriber = await _ConcurrentWatch.start(exampleRoot);
        final subscriberReady = await subscriber.waitUntilReady();
        final originalOwnerPid = ownerReady['builderOwnerPid'] as int;
        expect(subscriberReady['builderOwnerPid'], originalOwnerPid);

        await owner.stop();
        final promoted = await subscriber.waitForBuilderOwnerAfter(
          originalOwnerPid,
        );
        expect(promoted['builderOwnerPid'], subscriber.process.pid);
        expect(promoted['pid'], subscriber.process.pid);
        expect(promoted['sessionReady'], isTrue);
      } finally {
        await subscriber?.stop();
        await owner.stop();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'subscriber rotates its Host session when its topology adds a target',
    () async {
      final demoRoot = Directory(path.join(Directory.current.path, 'demo'));
      final exampleRoot = Directory(
        path.join(demoRoot.path, 'modules', 'order', 'example'),
      );
      final pubspec = File(path.join(demoRoot.path, 'pubspec.yaml'));
      final originalPubspec = pubspec.readAsStringSync();
      final owner = await _ConcurrentWatch.start(exampleRoot);
      _ConcurrentWatch? subscriber;
      var resolutionChanged = false;
      try {
        final ownerReady = await owner.waitUntilReady();
        subscriber = await _ConcurrentWatch.start(demoRoot);
        final subscriberReady = await subscriber.waitUntilReady();
        final initialSession = subscriberReady['sessionId'] as String;
        final builderOwnerPid = ownerReady['builderOwnerPid'];

        pubspec.writeAsStringSync(
          _replaceOnce(
            originalPubspec,
            '  demo_order: ^0.1.0\n',
            '  demo_order: ^0.1.0\n'
                '  demo_analytics_firebase: ^0.1.0\n',
          ),
          flush: true,
        );
        final pub = await _runDemoPubGet();
        expect(pub.exitCode, 0, reason: '${pub.stderr}');
        resolutionChanged = true;

        final restarted = await subscriber.waitForSessionAfter(initialSession);
        expect(restarted['builderOwnerPid'], builderOwnerPid);
        expect(restarted['hotRestartRequired'], isTrue);
      } finally {
        pubspec.writeAsStringSync(originalPubspec, flush: true);
        if (resolutionChanged) {
          final restorePub = await _runDemoPubGet();
          expect(restorePub.exitCode, 0, reason: '${restorePub.stderr}');
        }
        await subscriber?.stop();
        await owner.stop();
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  test(
    'multi-Host watch kill switch preserves fail-fast ownership',
    () async {
      final demoRoot = Directory(path.join(Directory.current.path, 'demo'));
      final exampleRoot = Directory(
        path.join(demoRoot.path, 'modules', 'order', 'example'),
      );
      final environment = <String, String>{
        ...Platform.environment,
        'CCROUTER_DISABLE_MULTI_HOST_WATCH': '1',
      };
      final owner = await _ConcurrentWatch.start(
        demoRoot,
        environment: environment,
      );
      _ConcurrentWatch? conflicting;
      try {
        await owner.waitUntilReady();
        conflicting = await _ConcurrentWatch.start(
          exampleRoot,
          environment: environment,
        );
        final code = await conflicting.process.exitCode.timeout(
          const Duration(seconds: 30),
        );
        expect(code, 1);
        expect(
          conflicting.output.join('\n'),
          contains('Another CCRouter generation command or watch owns'),
        );
      } finally {
        await conflicting?.stop();
        await owner.stop();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'duplicate watch for one Host fails before sharing its status file',
    () async {
      final demoRoot = Directory(path.join(Directory.current.path, 'demo'));
      final owner = await _ConcurrentWatch.start(demoRoot);
      _ConcurrentWatch? duplicate;
      try {
        await owner.waitUntilReady();
        duplicate = await _ConcurrentWatch.start(demoRoot);
        final code = await duplicate.process.exitCode.timeout(
          const Duration(seconds: 30),
        );
        expect(code, 1);
        expect(
          duplicate.output.join('\n'),
          contains('already has an active CCRouter generation watch'),
        );
      } finally {
        await duplicate?.stop();
        await owner.stop();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'stopped Host watch retains a stable registration lock for restart',
    () async {
      final demoRoot = Directory(path.join(Directory.current.path, 'demo'));
      final first = await _ConcurrentWatch.start(demoRoot);
      _ConcurrentWatch? replacement;
      late final ({File document, File lock}) registration;
      try {
        await first.waitUntilReady();
        registration = _watchRegistrationForHost(demoRoot);
        expect(registration.document.existsSync(), isTrue);
        expect(registration.lock.existsSync(), isTrue);

        await first.stop();
        expect(registration.document.existsSync(), isFalse);
        expect(registration.lock.existsSync(), isTrue);

        replacement = await _ConcurrentWatch.start(demoRoot);
        await replacement.waitUntilReady();
        final restarted = _watchRegistrationForHost(demoRoot);
        expect(restarted.document.path, registration.document.path);
        expect(restarted.lock.path, registration.lock.path);
      } finally {
        await replacement?.stop();
        await first.stop();
      }
      expect(registration.document.existsSync(), isFalse);
      expect(registration.lock.existsSync(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 4)),
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
        final evidenceReferencePlanningState = await _localPlanningState();
        expect(
          evidenceReferencePlanningState,
          optimizedPlanningState,
          reason: _planningStateDifferenceReason(
            optimizedPlanningState,
            evidenceReferencePlanningState,
          ),
        );
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

Map<String, dynamic> _readWatchStatusSync() =>
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

({File document, File lock}) _watchRegistrationForHost(Directory hostRoot) {
  final directory = Directory(
    path.join(
      Directory.current.path,
      '.dart_tool',
      'ccrouter',
      'v1',
      'watch',
      'registrations',
    ),
  );
  for (final document in directory.listSync().whereType<File>()) {
    if (!document.path.endsWith('.json')) continue;
    final decoded = jsonDecode(document.readAsStringSync()) as Map;
    if (decoded['hostRoot'] is String &&
        path.equals(decoded['hostRoot'] as String, hostRoot.absolute.path)) {
      final stem = path.basenameWithoutExtension(document.path);
      return (
        document: document,
        lock: File(path.join(directory.path, '$stem.lock')),
      );
    }
  }
  throw StateError('No active watch registration for ${hostRoot.path}.');
}

final class _ConcurrentWatch {
  _ConcurrentWatch._({
    required this.hostRoot,
    required this.process,
    required this.lease,
    required this.stdoutSubscription,
    required this.stderrSubscription,
    required this.output,
  });

  final Directory hostRoot;
  final Process process;
  final File lease;
  final StreamSubscription<String> stdoutSubscription;
  final StreamSubscription<String> stderrSubscription;
  final List<String> output;
  bool _stopped = false;

  static Future<_ConcurrentWatch> start(
    Directory hostRoot, {
    Map<String, String>? environment,
  }) async {
    final watchDirectory = Directory(
      path.join(hostRoot.path, '.dart_tool', 'ccrouter', 'v1', 'watch'),
    );
    await watchDirectory.create(recursive: true);
    final lease = File(
      path.join(
        watchDirectory.path,
        'test-${DateTime.now().microsecondsSinceEpoch}-$pid.lease',
      ),
    )..writeAsStringSync('test');
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        _generatorEntrypoint,
        'generate',
        hostRoot.path,
        '--watch=auto',
        '--machine',
        '--watch-lease',
        lease.path,
      ],
      workingDirectory: Directory.current.path,
      environment: environment,
    );
    final output = <String>[];
    final stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => output.add('stdout: $line'));
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => output.add('stderr: $line'));
    return _ConcurrentWatch._(
      hostRoot: hostRoot,
      process: process,
      lease: lease,
      stdoutSubscription: stdoutSubscription,
      stderrSubscription: stderrSubscription,
      output: output,
    );
  }

  Future<Map<String, dynamic>> waitUntilReady() => _waitForStatus(
    (status) =>
        status['active'] == true &&
        status['sessionReady'] == true &&
        status['lastEvent'] == 'ready',
  );

  Future<Map<String, dynamic>> waitForCycleAfter(int cycle) => _waitForStatus(
    (status) =>
        status['active'] == true &&
        (status['cycle'] as int) > cycle &&
        status['lastEvent'] == 'aggregationSucceeded',
  );

  Future<Map<String, dynamic>> waitForBuilderOwnerAfter(int ownerPid) =>
      _waitForStatus(
        (status) =>
            status['active'] == true &&
            status['sessionReady'] == true &&
            status['lastEvent'] == 'ready' &&
            status['builderOwnerPid'] != ownerPid,
      );

  Future<Map<String, dynamic>> waitForSessionAfter(String sessionId) =>
      _waitForStatus(
        (status) =>
            status['active'] == true &&
            status['sessionReady'] == true &&
            status['lastEvent'] == 'ready' &&
            status['sessionId'] != sessionId,
      );

  Future<Map<String, dynamic>> _waitForStatus(
    bool Function(Map<String, dynamic>) predicate,
  ) async {
    final statusFile = File(
      path.join(
        hostRoot.path,
        '.dart_tool',
        'ccrouter',
        'v1',
        'watch',
        'status.json',
      ),
    );
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    var exited = false;
    int? processExitCode;
    unawaited(
      process.exitCode.then((value) {
        exited = true;
        processExitCode = value;
      }),
    );
    Map<String, dynamic>? latest;
    while (DateTime.now().isBefore(deadline)) {
      if (exited) {
        throw StateError(
          'watch exited with $processExitCode before expected status\n'
          '${output.join('\n')}',
        );
      }
      try {
        latest =
            jsonDecode(await statusFile.readAsString()) as Map<String, dynamic>;
        if (predicate(latest)) return latest;
      } on FileSystemException {
        // Atomic status publication may briefly replace the file.
      } on FormatException {
        // Retry an incomplete read on non-atomic filesystems.
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException(
      'watch status did not match for ${hostRoot.path}: '
      '${jsonEncode(latest)}\n${output.join('\n')}',
    );
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    if (lease.existsSync()) await lease.delete();
    try {
      await process.exitCode.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      await process.exitCode;
    } finally {
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
    }
  }
}

Future<_WatchRun> _runWatchUntilReady({
  Map<String, String>? environment,
  Future<void> Function()? onReady,
  void Function(Map<String, dynamic> event)? onEvent,
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
        onEvent?.call(event);
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
      errors: errorLines,
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

String _planningStateDifferenceReason(
  Map<String, List<int>> expected,
  Map<String, List<int>> actual,
) {
  final differences = <String>[];
  final files = <String>{...expected.keys, ...actual.keys}.toList()..sort();
  for (final file in files) {
    final expectedBytes = expected[file];
    final actualBytes = actual[file];
    if (expectedBytes == null || actualBytes == null) {
      differences.add(
        '$file: ${expectedBytes == null ? 'missing expected' : 'missing actual'}',
      );
      continue;
    }
    final expectedJson = jsonDecode(utf8.decode(expectedBytes));
    final actualJson = jsonDecode(utf8.decode(actualBytes));
    _collectJsonDifferences(file, expectedJson, actualJson, differences);
  }
  return differences.isEmpty
      ? 'Planning-state JSON is equal but serialized bytes differ.'
      : differences.take(20).join('\n');
}

void _collectJsonDifferences(
  String location,
  Object? expected,
  Object? actual,
  List<String> differences,
) {
  if (expected is Map && actual is Map) {
    final keys = <Object?>{...expected.keys, ...actual.keys}.toList()
      ..sort((left, right) => '$left'.compareTo('$right'));
    for (final key in keys) {
      _collectJsonDifferences(
        '$location.$key',
        expected[key],
        actual[key],
        differences,
      );
    }
    return;
  }
  if (expected is List && actual is List) {
    if (jsonEncode(expected) != jsonEncode(actual)) {
      differences.add('$location: $expected != $actual');
    }
    return;
  }
  if (expected != actual) differences.add('$location: $expected != $actual');
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
    required this.errors,
  });

  final Map<String, dynamic> ready;
  final Map<String, dynamic> build;
  final Map<String, dynamic> aggregation;
  final List<String> eventTypes;
  final List<String> errors;
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
