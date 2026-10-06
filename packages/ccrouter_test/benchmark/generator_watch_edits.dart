import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

/// Measures repeated authored edits in one long-lived generation watch.
///
/// The benchmark edits one real Demo source and performs real Dart file add,
/// delete, and rename mutations with exact-content guards. It waits for both
/// Builder and CCRouter aggregation, records the scheduling boundaries around
/// both phases, restores every mutation after each sample, and finishes with a
/// byte comparison plus `--no-cache --check`.
Future<void> main(List<String> arguments) async {
  final options = _BenchmarkOptions.parse(arguments);
  final sampleCount = options.sampleCount;
  final root = _findWorkspaceRoot(Directory.current);
  final source = File(
    path.join(
      root.path,
      'demo',
      'modules',
      'navigation_lab',
      'lib',
      'src',
      'stack_page.dart',
    ),
  );
  final originalBytes = source.readAsBytesSync();
  final original = utf8.decode(originalBytes);
  final baselineArtifacts = await _ManagedArtifacts.capture(root);
  await _referenceCheck(root);

  final fixturePrefix = 'ccrouter_watch_benchmark_$pid';
  final addedFile = File(
    path.join(source.parent.path, '${fixturePrefix}_added.dart'),
  );
  final deletedFile = File(
    path.join(source.parent.path, '${fixturePrefix}_deleted.dart'),
  );
  final renameSource = File(
    path.join(source.parent.path, '${fixturePrefix}_rename_source.dart'),
  );
  final renameDestination = File(
    path.join(source.parent.path, '${fixturePrefix}_rename_destination.dart'),
  );
  final fixtureFiles = [
    addedFile,
    deletedFile,
    renameSource,
    renameDestination,
  ];
  for (final fixture in fixtureFiles) {
    if (fixture.existsSync()) {
      throw StateError('Benchmark fixture already exists: ${fixture.path}');
    }
  }
  const deletedContents =
      '// CCRouter watch delete benchmark fixture.\n'
      'const int ccrouterWatchDeletedFixture = 1;\n';
  const renameContents =
      '// CCRouter watch rename benchmark fixture.\n'
      'const int ccrouterWatchRenamedFixture = 1;\n';
  _createExpectedAbsent(deletedFile, deletedContents);
  _createExpectedAbsent(renameSource, renameContents);

  _WatchSession? session;
  var expectedSource = original;
  String? addedContents;
  var deletedFilePresent = true;
  var renameLocation = _RenameLocation.source;
  Object? failure;
  StackTrace? failureStack;
  final scenarioReports = <Map<String, Object?>>[];
  Map<String, Object?>? warmup;
  String? baselineAggregationInputFingerprint;
  try {
    session = await _WatchSession.start(root);
    final activeSession = session;
    final warmupSource = _replaceOnce(
      original,
      'final entries = CCRouter.activeRouteEntries;',
      'final entries = CCRouter.activeRouteEntries;\n'
          '    // CCRouter watch benchmark warm-up.',
    );
    final warmupApply = await session.runCycle(() {
      _writeExpected(source, expectedSource, warmupSource);
      expectedSource = warmupSource;
    });
    final warmupRestore = await session.runCycle(() {
      _writeExpected(source, expectedSource, original);
      expectedSource = original;
    });
    warmup = {'apply': warmupApply.toJson(), 'restore': warmupRestore.toJson()};
    baselineAggregationInputFingerprint =
        warmupRestore.aggregationInputFingerprint;
    if (warmupApply.aggregationInputFingerprint !=
            baselineAggregationInputFingerprint ||
        session.initial.aggregationInputFingerprint !=
            baselineAggregationInputFingerprint) {
      throw StateError(
        'Comment warm-up changed aggregation inputs before sampling.',
      );
    }

    Future<void> runScenario({
      required String name,
      required String mutation,
      required FutureOr<void> Function(int index) apply,
      required FutureOr<void> Function(int index) restore,
      bool changesGeneratedOutput = false,
    }) async {
      final samples = <_CycleSample>[];
      for (var index = 0; index < sampleCount; index++) {
        final applied = await activeSession.runCycle(() => apply(index));
        samples.add(applied);
        final restored = await activeSession.runCycle(() => restore(index));
        if (restored.aggregationInputFingerprint !=
            baselineAggregationInputFingerprint) {
          throw StateError('$name restore did not recover aggregation inputs.');
        }
      }
      final unexpectedOutput = samples.where(
        (sample) => changesGeneratedOutput
            ? sample.outputFiles <= 0
            : sample.outputFiles != 0,
      );
      if (unexpectedOutput.isNotEmpty) {
        throw StateError(
          '$name reported unexpected output deltas: '
          '${unexpectedOutput.map((sample) => sample.outputFiles).join(', ')}',
        );
      }
      if (samples.any((sample) => sample.cycleMode != 'inProcess')) {
        throw StateError('$name did not use in-process cycles.');
      }
      final reuseDisabled =
          Platform.environment['CCROUTER_DISABLE_AGGREGATION_REUSE'] == '1';
      final expectedReuseHits = reuseDisabled
          ? 0
          : changesGeneratedOutput
          ? 0
          : samples.length;
      final reuseHits = samples
          .where((sample) => sample.aggregationReuseResult == 'hit')
          .length;
      if (reuseHits != expectedReuseHits) {
        throw StateError(
          '$name aggregation reuse hits '
          '$reuseHits/${samples.length}; expected '
          '$expectedReuseHits/${samples.length}.',
        );
      }
      if (reuseDisabled &&
          samples.any(
            (sample) => sample.aggregationReuseReason != 'disabled',
          )) {
        throw StateError('$name did not honor the kill switch.');
      }
      final evidenceReuseDisabled =
          Platform.environment['CCROUTER_DISABLE_WATCH_EVIDENCE_REUSE'] == '1';
      final outputEvidenceReuseDisabled =
          Platform
              .environment['CCROUTER_DISABLE_WATCH_OUTPUT_EVIDENCE_REUSE'] ==
          '1';
      final unexpectedEvidence = samples.where((sample) {
        final expected = evidenceReuseDisabled
            ? 'recaptured'
            : !outputEvidenceReuseDisabled
            ? 'input-and-current-output'
            : sample.aggregationReuseResult == 'hit'
            ? 'input-and-aggregation-output'
            : 'input';
        return sample.planningEvidenceMode != expected;
      });
      if (unexpectedEvidence.isNotEmpty) {
        throw StateError(
          '$name reported unexpected planning evidence modes: '
          '${unexpectedEvidence.map((sample) => sample.planningEvidenceMode).join(', ')}',
        );
      }
      final matchingAggregationInputs = samples
          .where(
            (sample) =>
                sample.aggregationInputFingerprint ==
                baselineAggregationInputFingerprint,
          )
          .length;
      final expectedMatches = changesGeneratedOutput ? 0 : samples.length;
      if (matchingAggregationInputs != expectedMatches) {
        throw StateError(
          '$name aggregation-input matches '
          '$matchingAggregationInputs/${samples.length}; expected '
          '$expectedMatches/${samples.length}.',
        );
      }
      scenarioReports.add({
        'scenario': name,
        'mutation': mutation,
        'changesGeneratedOutput': changesGeneratedOutput,
        'aggregationInput': {
          'baselineMatches': matchingAggregationInputs,
          'distinctFingerprints': samples
              .map((sample) => sample.aggregationInputFingerprint)
              .toSet()
              .length,
        },
        'aggregationReuse': {'hits': reuseHits, 'disabled': reuseDisabled},
        'planningEvidence': {
          'reused': !evidenceReuseDisabled,
          'currentOutputReused':
              !evidenceReuseDisabled && !outputEvidenceReuseDisabled,
          'modes':
              samples
                  .map((sample) => sample.planningEvidenceMode)
                  .toSet()
                  .toList()
                ..sort(),
        },
        'summary': _summarize(samples),
        if (options.includeRawSamples)
          'samples': [for (final sample in samples) sample.toJson()],
      });
      stderr.writeln(
        'Watch benchmark $name: ${samples.length} samples completed.',
      );
    }

    for (final scenario in _scenarios) {
      await runScenario(
        name: scenario.name,
        mutation: 'content-edit',
        changesGeneratedOutput: scenario.changesGeneratedOutput,
        apply: (index) {
          final changed = scenario.edit(original, index);
          _writeExpected(source, expectedSource, changed);
          expectedSource = changed;
        },
        restore: (_) {
          _writeExpected(source, expectedSource, original);
          expectedSource = original;
        },
      );
    }

    await runScenario(
      name: 'dart-file-add',
      mutation: 'file-add',
      apply: (index) {
        addedContents =
            '// CCRouter watch add benchmark sample ${index + 1}.\n'
            'const int ccrouterWatchAddedFixture = ${index + 1};\n';
        _createExpectedAbsent(addedFile, addedContents!);
      },
      restore: (_) {
        _deleteExpected(addedFile, addedContents!);
        addedContents = null;
      },
    );
    await runScenario(
      name: 'dart-file-delete',
      mutation: 'file-delete',
      apply: (_) {
        _deleteExpected(deletedFile, deletedContents);
        deletedFilePresent = false;
      },
      restore: (_) {
        _createExpectedAbsent(deletedFile, deletedContents);
        deletedFilePresent = true;
      },
    );
    await runScenario(
      name: 'dart-file-rename',
      mutation: 'file-rename',
      apply: (_) {
        _renameExpected(renameSource, renameDestination, renameContents);
        renameLocation = _RenameLocation.destination;
      },
      restore: (_) {
        _renameExpected(renameDestination, renameSource, renameContents);
        renameLocation = _RenameLocation.source;
      },
    );
  } on Object catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
  } finally {
    final activeSession = session;
    void restoreWorkspace() {
      if (expectedSource != original) {
        _writeExpected(source, expectedSource, original);
        expectedSource = original;
      }
      final currentAddedContents = addedContents;
      if (currentAddedContents != null) {
        _deleteExpected(addedFile, currentAddedContents);
        addedContents = null;
      }
      if (!deletedFilePresent) {
        _createExpectedAbsent(deletedFile, deletedContents);
        deletedFilePresent = true;
      }
      if (renameLocation == _RenameLocation.destination) {
        _renameExpected(renameDestination, renameSource, renameContents);
        renameLocation = _RenameLocation.source;
      }
      if (deletedFilePresent) {
        _deleteExpected(deletedFile, deletedContents);
        deletedFilePresent = false;
      }
      if (renameLocation == _RenameLocation.source) {
        _deleteExpected(renameSource, renameContents);
        renameLocation = _RenameLocation.absent;
      }
    }

    if (activeSession != null) {
      try {
        await activeSession.runCycle(restoreWorkspace);
      } on Object catch (error, stackTrace) {
        failure ??= error;
        failureStack ??= stackTrace;
        try {
          restoreWorkspace();
        } on Object catch (cleanupError, cleanupStack) {
          failure = StateError(
            'Watch cleanup failed after $error: $cleanupError',
          );
          failureStack = cleanupStack;
        }
      }
    } else {
      try {
        restoreWorkspace();
      } on Object catch (error, stackTrace) {
        failure ??= error;
        failureStack ??= stackTrace;
      }
    }
    try {
      await activeSession?.stop();
    } on Object catch (error, stackTrace) {
      failure ??= error;
      failureStack ??= stackTrace;
    }
  }
  if (failure != null) Error.throwWithStackTrace(failure, failureStack!);

  final finalBytes = source.readAsBytesSync();
  if (!_bytesEqual(originalBytes, finalBytes)) {
    throw StateError('Benchmark did not restore ${source.path}.');
  }
  final remainingFixtures = fixtureFiles
      .where((fixture) => fixture.existsSync())
      .map((fixture) => fixture.path)
      .toList();
  if (remainingFixtures.isNotEmpty) {
    throw StateError(
      'Benchmark did not remove fixtures: ${remainingFixtures.join(', ')}',
    );
  }
  final finalArtifacts = await _ManagedArtifacts.capture(root);
  baselineArtifacts.expectEqual(finalArtifacts);
  await _referenceCheck(root);

  stdout.writeln(
    jsonEncode({
      'schemaVersion': 1,
      'benchmark': 'ccrouter-generation-watch-edits',
      'sdk': Platform.version,
      'platform': Platform.operatingSystem,
      'samplesPerScenario': sampleCount,
      'planningStateMode':
          Platform.environment['CCROUTER_DISABLE_SHARED_PLANNING_SNAPSHOT'] ==
              '1'
          ? 'legacySeparateWrites'
          : 'sharedSnapshot',
      'baselineAggregationInputFingerprint':
          baselineAggregationInputFingerprint,
      'initial': session!.initial.toJson(),
      'warmup': warmup,
      'scenarios': scenarioReports,
      'equivalence': {
        'sourceRestored': true,
        'fileFixturesRemoved': true,
        'managedArtifactsByteExact': true,
        'artifactCount': finalArtifacts.files.length,
        'artifactFingerprint': finalArtifacts.fingerprint,
        'reference': 'generate demo --no-cache --check',
      },
    }),
  );
}

final _scenarios = <_EditScenario>[
  _EditScenario(
    'comment',
    (source, index) => '$source// CCRouter watch comment ${index + 1}.\n',
  ),
  _EditScenario(
    'widget-body',
    (source, index) => _replaceOnce(
      source,
      '    final entries = CCRouter.activeRouteEntries;',
      '    final entries = CCRouter.activeRouteEntries;\n'
          '    final watchBodyProbe = ${index + 1};\n'
          '    assert(watchBodyProbe > 0);',
    ),
  ),
  _EditScenario(
    'init-state',
    (source, index) => _replaceOnce(
      source,
      '    super.initState();',
      '    super.initState();\n'
          "    assert(widget.level >= 0, 'watch initState ${index + 1}');",
    ),
  ),
  _EditScenario(
    'added-function',
    (source, index) => _replaceOnce(
      source,
      'CCRouteIntent<String> demoStackIntent({',
      'int _watchBenchmarkHelper(int value) => value + ${index + 1};\n\n'
          'CCRouteIntent<String> demoStackIntent({',
    ),
  ),
  _EditScenario(
    'route-annotation',
    (source, index) => _replaceOnce(
      source,
      "  description: '交互验证 Push、Replace、Pop、Go 与 Reset。',",
      "  description: '交互验证 Push、Replace、Pop、Go 与 Reset。watch ${index + 1}',",
    ),
    changesGeneratedOutput: true,
  ),
];

String _replaceOnce(String source, String from, String to) {
  final first = source.indexOf(from);
  if (first < 0 || source.indexOf(from, first + from.length) >= 0) {
    throw StateError('Expected exactly one benchmark marker: $from');
  }
  return source.replaceRange(first, first + from.length, to);
}

void _writeExpected(File file, String expected, String replacement) {
  final current = file.readAsStringSync();
  if (current != expected) {
    throw StateError(
      'Benchmark source changed concurrently; refusing to overwrite '
      '${file.path}.',
    );
  }
  file.writeAsStringSync(replacement, flush: true);
}

void _createExpectedAbsent(File file, String contents) {
  if (file.existsSync()) {
    throw StateError(
      'Benchmark expected an absent file; refusing to overwrite ${file.path}.',
    );
  }
  file.writeAsStringSync(contents, flush: true);
}

void _deleteExpected(File file, String expected) {
  if (!file.existsSync() || file.readAsStringSync() != expected) {
    throw StateError(
      'Benchmark file changed concurrently; refusing to delete ${file.path}.',
    );
  }
  file.deleteSync();
}

void _renameExpected(File source, File destination, String expected) {
  if (!source.existsSync() || source.readAsStringSync() != expected) {
    throw StateError(
      'Benchmark file changed concurrently; refusing to rename ${source.path}.',
    );
  }
  if (destination.existsSync()) {
    throw StateError(
      'Benchmark rename destination already exists: ${destination.path}.',
    );
  }
  source.renameSync(destination.path);
}

Map<String, Object?> _summarize(List<_CycleSample> samples) {
  final spanSamples = <String, List<int>>{};
  final builderPhaseSamples = <String, List<_BuilderPhaseSample>>{};
  for (final sample in samples) {
    for (final entry in sample.spanDurationsUs.entries) {
      spanSamples.putIfAbsent(entry.key, () => []).add(entry.value);
    }
    for (final phase in sample.buildRunner.phases) {
      builderPhaseSamples.putIfAbsent(phase.name, () => []).add(phase);
    }
  }
  return {
    'wallMs': _distribution(samples.map((sample) => sample.wallMs).toList()),
    'changeToBuildStartMs': _distribution(
      samples.map((sample) => sample.changeToBuildStartMs!).toList(),
    ),
    'observedBuildWindowMs': _distribution(
      samples.map((sample) => sample.observedBuildWindowMs!).toList(),
    ),
    'buildToAggregationHandoffMs': _distribution(
      samples.map((sample) => sample.buildToAggregationHandoffMs!).toList(),
    ),
    'observedAggregationWindowMs': _distribution(
      samples.map((sample) => sample.observedAggregationWindowMs!).toList(),
    ),
    'buildMs': _distribution(samples.map((sample) => sample.buildMs).toList()),
    'aggregationMs': _distribution(
      samples.map((sample) => sample.aggregationMs).toList(),
    ),
    'outputFiles': _distribution(
      samples.map((sample) => sample.outputFiles).toList(),
    ),
    'buildRunner': {
      'durationMs': _distribution(
        samples.map((sample) => sample.buildRunner.durationMs).toList(),
      ),
      'writtenOutputs': _distribution(
        samples.map((sample) => sample.buildRunner.writtenOutputs).toList(),
      ),
      'invalidationTotals': _summarizeBuilderCounters(
        samples.map((sample) => sample.buildRunner).toList(),
      ),
      'phases': {
        for (final entry in builderPhaseSamples.entries)
          entry.key: _summarizeBuilderPhase(entry.value, samples.length),
      },
      'unparsedFinalLines': samples.fold<int>(
        0,
        (total, sample) => total + sample.buildRunner.unparsedFinalLines.length,
      ),
    },
    'profileSpansUs': {
      for (final entry in spanSamples.entries)
        entry.key: _distribution(entry.value),
    },
  };
}

Map<String, Object?> _summarizeBuilderPhase(
  List<_BuilderPhaseSample> phases,
  int cycleCount,
) {
  final activitySamples = <String, List<int>>{};
  for (final phase in phases) {
    for (final entry in phase.activitiesMs.entries) {
      activitySamples.putIfAbsent(entry.key, () => []).add(entry.value);
    }
  }
  return {
    'reportedCycles': phases.length,
    'missingCycles': cycleCount - phases.length,
    'durationMs': _distribution(
      phases.map((phase) => phase.durationMs).toList(),
    ),
    ..._summarizeBuilderCounters(phases),
    'activitiesMs': {
      for (final entry in activitySamples.entries)
        entry.key: {
          'reportedCycles': entry.value.length,
          'durationMs': _distribution(entry.value),
        },
    },
  };
}

Map<String, Object?> _summarizeBuilderCounters(
  Iterable<_BuilderCounters> values,
) => {
  for (final field in _builderCounterFields)
    field.name: _distribution(values.map(field.read).toList()),
};

const _builderCounterFields = <_BuilderCounterField>[
  _BuilderCounterField('inputs', _readBuilderInputs),
  _BuilderCounterField('skipped', _readBuilderSkipped),
  _BuilderCounterField('notTriggered', _readBuilderNotTriggered),
  _BuilderCounterField('invalidatedInputs', _readBuilderInvalidatedInputs),
  _BuilderCounterField('executedInputs', _readBuilderExecutedInputs),
  _BuilderCounterField('outputs', _readBuilderOutputs),
  _BuilderCounterField('sameOutputs', _readBuilderSameOutputs),
  _BuilderCounterField('noOp', _readBuilderNoOp),
];

int _readBuilderInputs(_BuilderCounters value) => value.inputs;

int _readBuilderSkipped(_BuilderCounters value) => value.skipped;

int _readBuilderNotTriggered(_BuilderCounters value) => value.notTriggered;

int _readBuilderInvalidatedInputs(_BuilderCounters value) =>
    value.invalidatedInputs;

int _readBuilderExecutedInputs(_BuilderCounters value) => value.executedInputs;

int _readBuilderOutputs(_BuilderCounters value) => value.outputs;

int _readBuilderSameOutputs(_BuilderCounters value) => value.sameOutputs;

int _readBuilderNoOp(_BuilderCounters value) => value.noOp;

final class _BuilderCounterField {
  const _BuilderCounterField(this.name, this.read);

  final String name;
  final int Function(_BuilderCounters value) read;
}

Map<String, int> _distribution(List<int> values) => {
  'min': values.reduce((left, right) => left < right ? left : right),
  'p50': _percentile(values, 0.50),
  'p95': _percentile(values, 0.95),
  'max': values.reduce((left, right) => left > right ? left : right),
};

int _percentile(List<int> values, double percentile) {
  final sorted = [...values]..sort();
  final index = (sorted.length * percentile).ceil() - 1;
  return sorted[index.clamp(0, sorted.length - 1)];
}

Future<void> _referenceCheck(Directory root) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    '--packages=${path.join(root.path, '.dart_tool', 'package_config.json')}',
    path.join(
      root.path,
      'packages',
      'ccrouter_generator',
      'bin',
      'ccrouter.dart',
    ),
    'generate',
    'demo',
    '--no-cache',
    '--check',
  ], workingDirectory: root.path);
  if (result.exitCode != 0) {
    throw ProcessException(
      Platform.resolvedExecutable,
      const ['generate', 'demo', '--no-cache', '--check'],
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}

Directory _findWorkspaceRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    final pubspec = File(path.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('\nworkspace:')) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Run the benchmark from the CCRouter workspace.');
    }
    current = parent;
  }
}

final class _EditScenario {
  const _EditScenario(
    this.name,
    this.edit, {
    this.changesGeneratedOutput = false,
  });

  final String name;
  final String Function(String source, int index) edit;
  final bool changesGeneratedOutput;
}

enum _RenameLocation { source, destination, absent }

final class _BenchmarkOptions {
  const _BenchmarkOptions({
    required this.sampleCount,
    required this.includeRawSamples,
  });

  final int sampleCount;
  final bool includeRawSamples;

  static _BenchmarkOptions parse(List<String> arguments) {
    var sampleCount = 10;
    var includeRawSamples = false;
    for (final argument in arguments) {
      if (argument.startsWith('--samples=')) {
        sampleCount = int.parse(argument.substring('--samples='.length));
      } else if (argument == '--raw-samples') {
        includeRawSamples = true;
      } else {
        throw ArgumentError.value(
          argument,
          'arguments',
          'unsupported argument',
        );
      }
    }
    if (sampleCount < 3) {
      throw ArgumentError.value(sampleCount, 'samples', 'must be at least 3');
    }
    return _BenchmarkOptions(
      sampleCount: sampleCount,
      includeRawSamples: includeRawSamples,
    );
  }
}

final class _WatchSession {
  _WatchSession._({
    required this.root,
    required this.lease,
    required this.process,
    required Stopwatch startupWatch,
  }) : _startupWatch = startupWatch;

  final Directory root;
  final File lease;
  final Process process;
  final Stopwatch _startupWatch;
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _stopped = Completer<void>();
  final List<String> _stderrTail = [];
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Map<String, dynamic>? _lastBuild;
  _PendingCycle? _pending;
  late _CycleSample initial;

  static Future<_WatchSession> start(Directory root) async {
    final leaseDirectory = Directory(
      path.join(root.path, '.dart_tool', 'ccrouter', 'benchmark-watch-leases'),
    )..createSync(recursive: true);
    final lease = File(
      path.join(
        leaseDirectory.path,
        'watch-$pid-${DateTime.now().microsecondsSinceEpoch}.lease',
      ),
    )..writeAsStringSync('benchmark');
    final startupWatch = Stopwatch()..start();
    final process = await Process.start(Platform.resolvedExecutable, [
      path.join(
        root.path,
        'packages',
        'ccrouter_generator',
        'bin',
        'ccrouter.dart',
      ),
      'generate',
      'demo',
      '--watch=auto',
      '--machine',
      '--profile',
      '--watch-lease',
      lease.path,
    ], workingDirectory: root.path);
    final session = _WatchSession._(
      root: root,
      lease: lease,
      process: process,
      startupWatch: startupWatch,
    );
    session._listen();
    try {
      await session._ready.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw TimeoutException(
          'Generation watch did not reach ready.\n${session._diagnostics}',
        ),
      );
    } on Object {
      await session.stop();
      rethrow;
    }
    return session;
  }

  void _listen() {
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.trim().isEmpty) return;
          Map<String, dynamic> event;
          try {
            event = (jsonDecode(line) as Map).cast<String, dynamic>();
          } on Object catch (error) {
            _fail(StateError('Non-machine watch output: $line ($error)'));
            return;
          }
          final type = event['type'];
          final pending = _pending;
          if (type == 'buildStarted') {
            pending?.recordBuildStarted();
          } else if (type == 'buildSucceeded') {
            pending?.recordBuildSucceeded();
            _lastBuild = event;
          } else if (type == 'aggregationStarted') {
            pending?.recordAggregationStarted();
          } else if (type == 'aggregationSucceeded') {
            _CycleSample sample;
            try {
              sample = _cycleSample(event);
            } on Object catch (error, stackTrace) {
              _fail(error, stackTrace);
              return;
            }
            if (!_ready.isCompleted) {
              initial = sample;
            } else if (pending != null && !pending.completer.isCompleted) {
              pending.stopwatch.stop();
              pending.completer.complete(sample.withObservedTiming(pending));
              _pending = null;
            }
          } else if (type == 'ready') {
            if (_ready.isCompleted) return;
            _startupWatch.stop();
            initial = initial.withWallMs(_startupWatch.elapsedMilliseconds);
            _ready.complete();
          } else if (type == 'failed') {
            _fail(StateError('Generation watch failed: ${jsonEncode(event)}'));
          } else if (type == 'stopped' && !_stopped.isCompleted) {
            _stopped.complete();
          }
        });
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          _stderrTail.add(line);
          if (_stderrTail.length > 80) _stderrTail.removeAt(0);
        });
  }

  _CycleSample _cycleSample(Map<String, dynamic> aggregation) {
    final build = _lastBuild;
    if (build == null) {
      throw StateError('Aggregation succeeded without a Builder result.');
    }
    _lastBuild = null;
    final profile = (aggregation['profile'] as Map).cast<String, dynamic>();
    final spans = <String, int>{};
    final statuses = <String, String>{};
    String? aggregationInputFingerprint;
    String? aggregationReuseResult;
    String? aggregationReuseReason;
    String? planningEvidenceMode;
    for (final raw in (profile['spans'] as List).cast<Map>()) {
      final span = raw.cast<String, dynamic>();
      spans[span['name'] as String] = span['durationUs'] as int;
      statuses[span['name'] as String] = span['status'] as String;
      if (span['name'] == 'aggregation-input-fingerprint') {
        final attributes = (span['attributes'] as Map?)
            ?.cast<String, dynamic>();
        aggregationInputFingerprint = attributes?['fingerprint'] as String?;
      }
      if (span['name'] == 'aggregation-reuse-inspection') {
        final attributes = (span['attributes'] as Map?)
            ?.cast<String, dynamic>();
        aggregationReuseResult = attributes?['result'] as String?;
        aggregationReuseReason = attributes?['reason'] as String?;
      }
      if (span['name'] == 'planning-snapshot-capture') {
        final attributes = (span['attributes'] as Map?)
            ?.cast<String, dynamic>();
        planningEvidenceMode = attributes?['evidenceMode'] as String?;
      }
    }
    if (aggregationInputFingerprint == null) {
      throw StateError('Aggregation input fingerprint is missing.');
    }
    if (aggregationReuseResult == null || aggregationReuseReason == null) {
      throw StateError('Aggregation reuse inspection is missing.');
    }
    if (planningEvidenceMode == null) {
      throw StateError('Planning evidence mode is missing.');
    }
    final outputDelta = (aggregation['outputDelta'] as Map?)
        ?.cast<String, dynamic>();
    final buildRunner = _BuilderCycleSample.fromJson(
      (build['buildRunner'] as Map?)?.cast<String, dynamic>(),
    );
    return _CycleSample(
      wallMs: 0,
      buildMs: build['elapsedMs'] as int,
      aggregationMs: aggregation['elapsedMs'] as int,
      outputFiles: outputDelta?['files'] as int? ?? -1,
      cycleMode: aggregation['cycleMode'] as String,
      aggregationInputFingerprint: aggregationInputFingerprint,
      aggregationReuseResult: aggregationReuseResult,
      aggregationReuseReason: aggregationReuseReason,
      planningEvidenceMode: planningEvidenceMode,
      buildRunner: buildRunner,
      spanDurationsUs: spans,
      spanStatuses: statuses,
    );
  }

  Future<_CycleSample> runCycle(FutureOr<void> Function() edit) async {
    if (_pending != null) throw StateError('A watch cycle is already pending.');
    final pending = _PendingCycle();
    _pending = pending;
    try {
      await edit();
      return await pending.completer.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw TimeoutException(
          'Generation watch did not complete an edit cycle.\n$_diagnostics',
        ),
      );
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  void _fail(Object error, [StackTrace? stackTrace]) {
    final pending = _pending;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.completeError(error, stackTrace);
      _pending = null;
    }
    if (!_ready.isCompleted) _ready.completeError(error, stackTrace);
  }

  String get _diagnostics => _stderrTail.join('\n');

  Future<void> stop() async {
    if (lease.existsSync()) lease.deleteSync();
    try {
      await _stopped.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
    }
    final processCode = await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return process.exitCode;
      },
    );
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    if (processCode != 0) {
      throw StateError('Generation watch exited $processCode.\n$_diagnostics');
    }
    final leaseDirectory = lease.parent;
    if (leaseDirectory.existsSync() && leaseDirectory.listSync().isEmpty) {
      leaseDirectory.deleteSync();
    }
  }
}

final class _PendingCycle {
  _PendingCycle() : stopwatch = (Stopwatch()..start());

  final Stopwatch stopwatch;
  final Completer<_CycleSample> completer = Completer<_CycleSample>();
  int? buildStartedMs;
  int? buildSucceededMs;
  int? aggregationStartedMs;

  void recordBuildStarted() {
    buildStartedMs ??= stopwatch.elapsedMilliseconds;
  }

  void recordBuildSucceeded() {
    buildSucceededMs ??= stopwatch.elapsedMilliseconds;
  }

  void recordAggregationStarted() {
    aggregationStartedMs ??= stopwatch.elapsedMilliseconds;
  }
}

final class _CycleSample {
  const _CycleSample({
    required this.wallMs,
    this.changeToBuildStartMs,
    this.observedBuildWindowMs,
    this.buildToAggregationHandoffMs,
    this.observedAggregationWindowMs,
    required this.buildMs,
    required this.aggregationMs,
    required this.outputFiles,
    required this.cycleMode,
    required this.aggregationInputFingerprint,
    required this.aggregationReuseResult,
    required this.aggregationReuseReason,
    required this.planningEvidenceMode,
    required this.buildRunner,
    required this.spanDurationsUs,
    required this.spanStatuses,
  });

  final int wallMs;
  final int? changeToBuildStartMs;
  final int? observedBuildWindowMs;
  final int? buildToAggregationHandoffMs;
  final int? observedAggregationWindowMs;
  final int buildMs;
  final int aggregationMs;
  final int outputFiles;
  final String cycleMode;
  final String aggregationInputFingerprint;
  final String aggregationReuseResult;
  final String aggregationReuseReason;
  final String planningEvidenceMode;
  final _BuilderCycleSample buildRunner;
  final Map<String, int> spanDurationsUs;
  final Map<String, String> spanStatuses;

  _CycleSample withWallMs(int value) => _CycleSample(
    wallMs: value,
    buildMs: buildMs,
    aggregationMs: aggregationMs,
    outputFiles: outputFiles,
    cycleMode: cycleMode,
    aggregationInputFingerprint: aggregationInputFingerprint,
    aggregationReuseResult: aggregationReuseResult,
    aggregationReuseReason: aggregationReuseReason,
    planningEvidenceMode: planningEvidenceMode,
    buildRunner: buildRunner,
    spanDurationsUs: spanDurationsUs,
    spanStatuses: spanStatuses,
  );

  _CycleSample withObservedTiming(_PendingCycle pending) {
    final buildStarted = pending.buildStartedMs;
    final buildSucceeded = pending.buildSucceededMs;
    final aggregationStarted = pending.aggregationStartedMs;
    if (buildStarted == null ||
        buildSucceeded == null ||
        aggregationStarted == null) {
      throw StateError(
        'Watch cycle is missing scheduling events: '
        'buildStarted=$buildStarted, buildSucceeded=$buildSucceeded, '
        'aggregationStarted=$aggregationStarted.',
      );
    }
    return _CycleSample(
      wallMs: pending.stopwatch.elapsedMilliseconds,
      changeToBuildStartMs: buildStarted,
      observedBuildWindowMs: buildSucceeded - buildStarted,
      buildToAggregationHandoffMs: aggregationStarted - buildSucceeded,
      observedAggregationWindowMs:
          pending.stopwatch.elapsedMilliseconds - aggregationStarted,
      buildMs: buildMs,
      aggregationMs: aggregationMs,
      outputFiles: outputFiles,
      cycleMode: cycleMode,
      aggregationInputFingerprint: aggregationInputFingerprint,
      aggregationReuseResult: aggregationReuseResult,
      aggregationReuseReason: aggregationReuseReason,
      planningEvidenceMode: planningEvidenceMode,
      buildRunner: buildRunner,
      spanDurationsUs: spanDurationsUs,
      spanStatuses: spanStatuses,
    );
  }

  Map<String, Object?> toJson() => {
    'wallMs': wallMs,
    if (changeToBuildStartMs != null)
      'changeToBuildStartMs': changeToBuildStartMs,
    if (observedBuildWindowMs != null)
      'observedBuildWindowMs': observedBuildWindowMs,
    if (buildToAggregationHandoffMs != null)
      'buildToAggregationHandoffMs': buildToAggregationHandoffMs,
    if (observedAggregationWindowMs != null)
      'observedAggregationWindowMs': observedAggregationWindowMs,
    'buildMs': buildMs,
    'aggregationMs': aggregationMs,
    'outputFiles': outputFiles,
    'cycleMode': cycleMode,
    'aggregationInputFingerprint': aggregationInputFingerprint,
    'aggregationReuseResult': aggregationReuseResult,
    'aggregationReuseReason': aggregationReuseReason,
    'planningEvidenceMode': planningEvidenceMode,
    'buildRunner': buildRunner.toJson(),
    'profileSpansUs': spanDurationsUs,
    'profileSpanStatuses': spanStatuses,
  };
}

abstract interface class _BuilderCounters {
  int get inputs;

  int get skipped;

  int get notTriggered;

  int get invalidatedInputs;

  int get executedInputs;

  int get outputs;

  int get sameOutputs;

  int get noOp;
}

final class _BuilderCycleSample implements _BuilderCounters {
  const _BuilderCycleSample({
    required this.durationMs,
    required this.writtenOutputs,
    required this.inputs,
    required this.skipped,
    required this.notTriggered,
    required this.invalidatedInputs,
    required this.executedInputs,
    required this.outputs,
    required this.sameOutputs,
    required this.noOp,
    required this.phases,
    required this.unparsedFinalLines,
  });

  final int durationMs;
  final int writtenOutputs;
  @override
  final int inputs;
  @override
  final int skipped;
  @override
  final int notTriggered;
  @override
  final int invalidatedInputs;
  @override
  final int executedInputs;
  @override
  final int outputs;
  @override
  final int sameOutputs;
  @override
  final int noOp;
  final List<_BuilderPhaseSample> phases;
  final List<String> unparsedFinalLines;

  factory _BuilderCycleSample.fromJson(Map<String, dynamic>? json) {
    if (json == null || json['formatVersion'] != 1) {
      throw StateError('Structured build_runner diagnostics are missing.');
    }
    final durationMs = json['durationMs'];
    final writtenOutputs = json['writtenOutputs'];
    final totals = (json['totals'] as Map?)?.cast<String, dynamic>();
    final rawPhases = json['phases'];
    if (durationMs is! int ||
        writtenOutputs is! int ||
        totals == null ||
        rawPhases is! List) {
      throw StateError('Structured build_runner diagnostics are incomplete.');
    }
    final phases = rawPhases
        .cast<Map>()
        .map((phase) => _BuilderPhaseSample.fromJson(phase.cast()))
        .toList(growable: false);
    if (phases.isEmpty) {
      throw StateError('Structured build_runner phase list is empty.');
    }
    int counter(String name) {
      final value = totals[name];
      if (value is! int) {
        throw StateError('build_runner total $name is missing.');
      }
      return value;
    }

    return _BuilderCycleSample(
      durationMs: durationMs,
      writtenOutputs: writtenOutputs,
      inputs: counter('inputs'),
      skipped: counter('skipped'),
      notTriggered: counter('notTriggered'),
      invalidatedInputs: counter('invalidatedInputs'),
      executedInputs: counter('executedInputs'),
      outputs: counter('outputs'),
      sameOutputs: counter('sameOutputs'),
      noOp: counter('noOp'),
      phases: phases,
      unparsedFinalLines:
          (json['unparsedFinalLines'] as List?)?.cast<String>() ?? const [],
    );
  }

  Map<String, Object?> toJson() => {
    'durationMs': durationMs,
    'writtenOutputs': writtenOutputs,
    'totals': {
      'inputs': inputs,
      'skipped': skipped,
      'notTriggered': notTriggered,
      'invalidatedInputs': invalidatedInputs,
      'executedInputs': executedInputs,
      'outputs': outputs,
      'sameOutputs': sameOutputs,
      'noOp': noOp,
    },
    'phases': [for (final phase in phases) phase.toJson()],
    if (unparsedFinalLines.isNotEmpty) 'unparsedFinalLines': unparsedFinalLines,
  };
}

final class _BuilderPhaseSample implements _BuilderCounters {
  const _BuilderPhaseSample({
    required this.name,
    required this.durationMs,
    required this.inputs,
    required this.skipped,
    required this.notTriggered,
    required this.invalidatedInputs,
    required this.executedInputs,
    required this.outputs,
    required this.sameOutputs,
    required this.noOp,
    required this.activitiesMs,
  });

  final String name;
  final int durationMs;
  @override
  final int inputs;
  @override
  final int skipped;
  @override
  final int notTriggered;
  @override
  final int invalidatedInputs;
  @override
  final int executedInputs;
  @override
  final int outputs;
  @override
  final int sameOutputs;
  @override
  final int noOp;
  final Map<String, int> activitiesMs;

  factory _BuilderPhaseSample.fromJson(Map<String, dynamic> json) {
    int counter(String name) {
      final value = json[name];
      if (value is! int) {
        throw StateError('build_runner phase counter $name is missing.');
      }
      return value;
    }

    final name = json['name'];
    final durationMs = json['durationMs'];
    if (name is! String || durationMs is! int) {
      throw StateError('build_runner phase identity is incomplete.');
    }
    return _BuilderPhaseSample(
      name: name,
      durationMs: durationMs,
      inputs: counter('inputs'),
      skipped: counter('skipped'),
      notTriggered: counter('notTriggered'),
      invalidatedInputs: counter('invalidatedInputs'),
      executedInputs: counter('executedInputs'),
      outputs: counter('outputs'),
      sameOutputs: counter('sameOutputs'),
      noOp: counter('noOp'),
      activitiesMs:
          (json['activitiesMs'] as Map?)?.cast<String, int>() ?? const {},
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'durationMs': durationMs,
    'inputs': inputs,
    'skipped': skipped,
    'notTriggered': notTriggered,
    'invalidatedInputs': invalidatedInputs,
    'executedInputs': executedInputs,
    'outputs': outputs,
    'sameOutputs': sameOutputs,
    'noOp': noOp,
    if (activitiesMs.isNotEmpty) 'activitiesMs': activitiesMs,
  };
}

final class _ManagedArtifacts {
  const _ManagedArtifacts(this.files, this.fingerprint);

  final Map<String, List<int>> files;
  final String fingerprint;

  static Future<_ManagedArtifacts> capture(Directory root) async {
    final files = <String, List<int>>{};
    for (final rootName in const ['demo', 'packages']) {
      await for (final entity in Directory(
        path.join(root.path, rootName),
      ).list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relative = path.relative(entity.path, from: root.path);
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
        files[relative] = await entity.readAsBytes();
      }
    }
    final names = files.keys.toList()..sort();
    final bytes = BytesBuilder(copy: false);
    for (final name in names) {
      bytes
        ..add(utf8.encode(name))
        ..add(const [0])
        ..add(files[name]!)
        ..add(const [0]);
    }
    return _ManagedArtifacts(
      files,
      sha256.convert(bytes.takeBytes()).toString(),
    );
  }

  void expectEqual(_ManagedArtifacts other) {
    final names = <String>{...files.keys, ...other.files.keys}.toList()..sort();
    final changed = [
      for (final name in names)
        if (files[name] == null ||
            other.files[name] == null ||
            !_bytesEqual(files[name]!, other.files[name]!))
          name,
    ];
    if (changed.isNotEmpty) {
      throw StateError(
        'Managed artifacts changed after benchmark: ${changed.join(', ')}',
      );
    }
  }
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
