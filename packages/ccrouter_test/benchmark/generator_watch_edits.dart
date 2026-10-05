import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

/// Measures repeated authored edits in one long-lived generation watch.
///
/// The benchmark edits one real Demo source with exact-content guards, waits
/// for both Builder and CCRouter aggregation, restores the source after every
/// sample, and finishes with a byte comparison plus `--no-cache --check`.
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

  _WatchSession? session;
  var expectedSource = original;
  Object? failure;
  StackTrace? failureStack;
  final scenarioReports = <Map<String, Object?>>[];
  Map<String, Object?>? warmup;
  String? baselineAggregationInputFingerprint;
  try {
    session = await _WatchSession.start(root);
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

    for (final scenario in _scenarios) {
      final samples = <_CycleSample>[];
      for (var index = 0; index < sampleCount; index++) {
        final changed = scenario.edit(original, index);
        final applied = await session.runCycle(() {
          _writeExpected(source, expectedSource, changed);
          expectedSource = changed;
        });
        samples.add(applied);
        final restored = await session.runCycle(() {
          _writeExpected(source, expectedSource, original);
          expectedSource = original;
        });
        if (restored.aggregationInputFingerprint !=
            baselineAggregationInputFingerprint) {
          throw StateError(
            '${scenario.name} restore did not recover aggregation inputs.',
          );
        }
      }
      final unexpectedOutput = samples.where(
        (sample) => scenario.changesGeneratedOutput
            ? sample.outputFiles <= 0
            : sample.outputFiles != 0,
      );
      if (unexpectedOutput.isNotEmpty) {
        throw StateError(
          '${scenario.name} reported unexpected output deltas: '
          '${unexpectedOutput.map((sample) => sample.outputFiles).join(', ')}',
        );
      }
      if (samples.any((sample) => sample.cycleMode != 'inProcess')) {
        throw StateError('${scenario.name} did not use in-process cycles.');
      }
      final reuseDisabled =
          Platform.environment['CCROUTER_DISABLE_AGGREGATION_REUSE'] == '1';
      final expectedReuseHits = reuseDisabled
          ? 0
          : scenario.changesGeneratedOutput
          ? 0
          : samples.length;
      final reuseHits = samples
          .where((sample) => sample.aggregationReuseResult == 'hit')
          .length;
      if (reuseHits != expectedReuseHits) {
        throw StateError(
          '${scenario.name} aggregation reuse hits '
          '$reuseHits/${samples.length}; expected '
          '$expectedReuseHits/${samples.length}.',
        );
      }
      if (reuseDisabled &&
          samples.any(
            (sample) => sample.aggregationReuseReason != 'disabled',
          )) {
        throw StateError('${scenario.name} did not honor the kill switch.');
      }
      final matchingAggregationInputs = samples
          .where(
            (sample) =>
                sample.aggregationInputFingerprint ==
                baselineAggregationInputFingerprint,
          )
          .length;
      final expectedMatches = scenario.changesGeneratedOutput
          ? 0
          : samples.length;
      if (matchingAggregationInputs != expectedMatches) {
        throw StateError(
          '${scenario.name} aggregation-input matches '
          '$matchingAggregationInputs/${samples.length}; expected '
          '$expectedMatches/${samples.length}.',
        );
      }
      scenarioReports.add({
        'scenario': scenario.name,
        'changesGeneratedOutput': scenario.changesGeneratedOutput,
        'aggregationInput': {
          'baselineMatches': matchingAggregationInputs,
          'distinctFingerprints': samples
              .map((sample) => sample.aggregationInputFingerprint)
              .toSet()
              .length,
        },
        'aggregationReuse': {'hits': reuseHits, 'disabled': reuseDisabled},
        'summary': _summarize(samples),
        if (options.includeRawSamples)
          'samples': [for (final sample in samples) sample.toJson()],
      });
      stderr.writeln(
        'Watch benchmark ${scenario.name}: '
        '${samples.length} samples completed.',
      );
    }
  } on Object catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
  } finally {
    final activeSession = session;
    final current = source.readAsStringSync();
    if (current == expectedSource && current != original) {
      if (activeSession != null) {
        try {
          await activeSession.runCycle(() {
            _writeExpected(source, expectedSource, original);
            expectedSource = original;
          });
        } on Object catch (error, stackTrace) {
          failure ??= error;
          failureStack ??= stackTrace;
        }
      } else {
        source.writeAsBytesSync(originalBytes, flush: true);
        expectedSource = original;
      }
    } else if (current != original) {
      failure ??= StateError(
        'Benchmark source changed concurrently; preserving current bytes: '
        '${source.path}',
      );
    }
    await activeSession?.stop();
  }
  if (failure != null) Error.throwWithStackTrace(failure, failureStack!);

  final finalBytes = source.readAsBytesSync();
  if (!_bytesEqual(originalBytes, finalBytes)) {
    throw StateError('Benchmark did not restore ${source.path}.');
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

Map<String, Object?> _summarize(List<_CycleSample> samples) {
  final spanSamples = <String, List<int>>{};
  for (final sample in samples) {
    for (final entry in sample.spanDurationsUs.entries) {
      spanSamples.putIfAbsent(entry.key, () => []).add(entry.value);
    }
  }
  return {
    'wallMs': _distribution(samples.map((sample) => sample.wallMs).toList()),
    'buildMs': _distribution(samples.map((sample) => sample.buildMs).toList()),
    'aggregationMs': _distribution(
      samples.map((sample) => sample.aggregationMs).toList(),
    ),
    'outputFiles': _distribution(
      samples.map((sample) => sample.outputFiles).toList(),
    ),
    'profileSpansUs': {
      for (final entry in spanSamples.entries)
        entry.key: _distribution(entry.value),
    },
  };
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
    await session._ready.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => throw TimeoutException(
        'Generation watch did not reach ready.\n${session._diagnostics}',
      ),
    );
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
          if (type == 'buildSucceeded') {
            _lastBuild = event;
          } else if (type == 'aggregationSucceeded') {
            final sample = _cycleSample(event);
            final pending = _pending;
            if (!_ready.isCompleted) {
              initial = sample;
            } else if (pending != null && !pending.completer.isCompleted) {
              pending.stopwatch.stop();
              pending.completer.complete(
                sample.withWallMs(pending.stopwatch.elapsedMilliseconds),
              );
              _pending = null;
            }
          } else if (type == 'ready') {
            _startupWatch.stop();
            initial = initial.withWallMs(_startupWatch.elapsedMilliseconds);
            if (!_ready.isCompleted) _ready.complete();
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
    }
    if (aggregationInputFingerprint == null) {
      throw StateError('Aggregation input fingerprint is missing.');
    }
    if (aggregationReuseResult == null || aggregationReuseReason == null) {
      throw StateError('Aggregation reuse inspection is missing.');
    }
    final outputDelta = (aggregation['outputDelta'] as Map?)
        ?.cast<String, dynamic>();
    return _CycleSample(
      wallMs: 0,
      buildMs: build['elapsedMs'] as int,
      aggregationMs: aggregation['elapsedMs'] as int,
      outputFiles: outputDelta?['files'] as int? ?? -1,
      cycleMode: aggregation['cycleMode'] as String,
      aggregationInputFingerprint: aggregationInputFingerprint,
      aggregationReuseResult: aggregationReuseResult,
      aggregationReuseReason: aggregationReuseReason,
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

  void _fail(Object error) {
    final pending = _pending;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.completeError(error);
      _pending = null;
    }
    if (!_ready.isCompleted) _ready.completeError(error);
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
}

final class _CycleSample {
  const _CycleSample({
    required this.wallMs,
    required this.buildMs,
    required this.aggregationMs,
    required this.outputFiles,
    required this.cycleMode,
    required this.aggregationInputFingerprint,
    required this.aggregationReuseResult,
    required this.aggregationReuseReason,
    required this.spanDurationsUs,
    required this.spanStatuses,
  });

  final int wallMs;
  final int buildMs;
  final int aggregationMs;
  final int outputFiles;
  final String cycleMode;
  final String aggregationInputFingerprint;
  final String aggregationReuseResult;
  final String aggregationReuseReason;
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
    spanDurationsUs: spanDurationsUs,
    spanStatuses: spanStatuses,
  );

  Map<String, Object?> toJson() => {
    'wallMs': wallMs,
    'buildMs': buildMs,
    'aggregationMs': aggregationMs,
    'outputFiles': outputFiles,
    'cycleMode': cycleMode,
    'aggregationInputFingerprint': aggregationInputFingerprint,
    'aggregationReuseResult': aggregationReuseResult,
    'aggregationReuseReason': aggregationReuseReason,
    'profileSpansUs': spanDurationsUs,
    'profileSpanStatuses': spanStatuses,
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
