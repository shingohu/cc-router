import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as path;

import '../../ccrouter_generator/bin/src/generation_file_reader.dart';
import '../../ccrouter_generator/bin/src/pub_hook_watch_coordination.dart';

/// Compares exact-byte reads at 1/4/8 workers with isolated RSS measurements.
///
/// Copies Demo authored and generated Dart/metadata files into an isolated
/// 1x/3x/5x/10x fixture. Package captures remain sequential, like production;
/// only reads within each capture overlap. Every sample verifies full bytes
/// and fingerprints against an independent sequential oracle. This measures
/// read/hash cost, not build_runner, directory discovery, or complete generation.
Future<void> main(List<String> arguments) async {
  if (arguments.firstOrNull == '--demo') {
    await _demo();
    return;
  }
  if (arguments.firstOrNull == '--worker') {
    stdout.writeln(
      jsonEncode(
        await _worker(Directory(arguments[1]), int.parse(arguments[2])),
      ),
    );
    return;
  }
  final workspace = Directory.current;
  final demo = Directory(path.join(workspace.path, 'demo'));
  final seed = <String, List<int>>{};
  final entities = demo
      .listSync(recursive: true, followLinks: false)
      .whereType<File>();
  for (final file in entities) {
    final relative = path.relative(file.path, from: demo.path);
    final segments = path.split(relative);
    if (segments.any(
      (segment) =>
          segment.startsWith('.') || segment == 'build' || segment == 'tools',
    ))
      continue;
    final configuration = const [
      'pubspec.yaml',
      'build.yaml',
    ].contains(path.basename(file.path));
    final library =
        segments.contains('lib') &&
        (file.path.endsWith('.dart') ||
            (segments.contains('ccrouter_generated') &&
                file.path.endsWith('.json')));
    if (!configuration && !library) continue;
    seed[relative] = file.readAsBytesSync();
  }
  if (seed.isEmpty) throw StateError('Run from the CCRouter workspace root.');
  final scales = arguments.isEmpty
      ? [1, 3, 5, 10]
      : arguments.map(int.parse).toList();
  for (final scale in scales) {
    if (scale <= 0) throw ArgumentError.value(scale, 'scale');
    final fixture = await Directory.systemTemp.createTemp(
      'ccrouter-read-${scale}x-',
    );
    try {
      for (var copy = 0; copy < scale; copy++) {
        for (final entry in seed.entries) {
          final file = File(path.join(fixture.path, 'copy_$copy', entry.key));
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(entry.value);
        }
      }
      final results = <int, List<Map<String, dynamic>>>{1: [], 4: [], 8: []};
      // Rotate process order so later variants do not always inherit warmer I/O.
      for (var round = 0; round < 3; round++) {
        final order = [1, 4, 8];
        for (var index = 0; index < order.length; index++) {
          final concurrency = order[(index + round) % order.length];
          final child = await Process.run(Platform.resolvedExecutable, [
            Platform.script.toFilePath(),
            '--worker',
            fixture.path,
            '$concurrency',
          ]);
          if (child.exitCode != 0)
            throw StateError('${child.stdout}\n${child.stderr}');
          results[concurrency]!.add(
            jsonDecode('${child.stdout}') as Map<String, dynamic>,
          );
        }
      }
      stdout.writeln(
        jsonEncode({
          'scenario': 'generator-exact-file-read-scaling',
          'scale': scale,
          'files': seed.length * scale,
          'bytes':
              seed.values.fold<int>(0, (sum, bytes) => sum + bytes.length) *
              scale,
          'scope': 'package-sequential-read-and-hash-only',
          'variants': {
            for (final entry in results.entries)
              '${entry.key}': _summarize(entry.value),
          },
        }),
      );
    } finally {
      await fixture.delete(recursive: true);
    }
  }
}

/// Alternates actual Demo commands while isolating authored test mutations.
Future<void> _demo() async {
  final testLock = File(
    path.join(
      Directory.current.path,
      '.dart_tool',
      'ccrouter',
      'test-locks',
      'real-workspace.lock',
    ),
  );
  await testLock.parent.create(recursive: true);
  final lock = await testLock.open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.blockingExclusive);
    final demo = Directory(path.join(Directory.current.path, 'demo'));
    final before = await _demoArtifacts(demo);
    final samples = <Map<String, Object?>>[];
    for (final referencePath in [false, true]) {
      for (var round = -1; round < 6; round++) {
        for (final sequential in round.isEven ? [false, true] : [true, false]) {
          final wall = Stopwatch()..start();
          final result = await Process.run(
            Platform.resolvedExecutable,
            [
              'run',
              '--verbosity=error',
              'ccrouter_generator:ccrouter',
              'generate',
              'demo',
              '--check',
              '--profile',
              if (referencePath) '--no-cache',
            ],
            environment: {
              ...Platform.environment,
              CCGenerationFileReader.killSwitch: sequential ? '1' : '0',
            },
          );
          wall.stop();
          if (result.exitCode != 0)
            throw StateError('${result.stdout}\n${result.stderr}');
          final traceLine = const LineSplitter()
              .convert('${result.stdout}')
              .singleWhere(
                (line) => line.startsWith('CCRouter profile trace='),
              );
          final trace =
              jsonDecode(traceLine.substring('CCRouter profile trace='.length))
                  as Map<String, dynamic>;
          final after = await _demoArtifacts(demo);
          _expectBytes(before, after);
          if (round < 0) continue;
          final sample = <String, Object?>{
            'scenario': referencePath
                ? 'demo-no-cache-check'
                : 'demo-unchanged-check',
            'sequential': sequential,
            'sample': round,
            'wallMs': wall.elapsedMilliseconds,
            'totalMs': (trace['totalUs'] as int) / 1000,
            'spansMs': {
              for (final span
                  in (trace['spans'] as List).cast<Map<String, dynamic>>())
                span['name']: (span['durationUs'] as int) / 1000,
            },
          };
          samples.add(sample);
          stdout.writeln(jsonEncode(sample));
        }
      }
    }
    stdout.writeln(
      jsonEncode({
        'scenario': 'demo-read-ab-summary',
        'variants': {
          for (final scenario in [
            'demo-unchanged-check',
            'demo-no-cache-check',
          ])
            scenario: {
              for (final sequential in [true, false])
                sequential ? '1' : '4': _summarizeDemo(
                  samples
                      .where(
                        (sample) =>
                            sample['scenario'] == scenario &&
                            sample['sequential'] == sequential,
                      )
                      .toList(),
                ),
            },
        },
        'managedFiles': before.length,
        'differential': 'exact-managed-output-bytes',
      }),
    );
  } finally {
    await lock.close();
  }
}

/// Independently guards outputs of every Demo Package, including nested Hosts.
Future<Map<String, List<int>>> _demoArtifacts(Directory root) async {
  final files = <String, List<int>>{};
  final pending = [root];
  while (pending.isNotEmpty) {
    await for (final entity in pending.removeLast().list(followLinks: false)) {
      if (entity is Directory) {
        if (![
          '.dart_tool',
          'build',
          '.git',
        ].contains(path.basename(entity.path)))
          pending.add(entity);
        continue;
      }
      if (entity is! File) continue;
      final relative = path
          .relative(entity.path, from: root.path)
          .replaceAll(path.separator, '/');
      final name = path.basename(entity.path);
      final generated = relative.split('/').contains('ccrouter_generated');
      if (name.endsWith('_ccrouter.g.dart') ||
          (generated &&
              (name.endsWith('.g.dart') ||
                  name.endsWith('.json') ||
                  name.endsWith('.md'))))
        files[relative] = await entity.readAsBytes();
    }
  }
  return files;
}

/// Summarizes total and phase distributions without adding overlapping spans.
Map<String, Object?> _summarizeDemo(List<Map<String, Object?>> samples) {
  num percentile(Iterable<num> values, double fraction) {
    final sorted = values.toList()..sort();
    return sorted[(sorted.length * fraction).ceil() - 1];
  }

  final spanNames = (samples.first['spansMs'] as Map).keys.cast<String>();
  return {
    'samples': samples.length,
    'wallP50Ms': percentile(
      samples.map((sample) => sample['wallMs'] as num),
      .5,
    ),
    'wallP95Ms': percentile(
      samples.map((sample) => sample['wallMs'] as num),
      .95,
    ),
    'totalP50Ms': percentile(
      samples.map((sample) => sample['totalMs'] as num),
      .5,
    ),
    'totalP95Ms': percentile(
      samples.map((sample) => sample['totalMs'] as num),
      .95,
    ),
    'spanP50Ms': {
      for (final name in spanNames)
        name: percentile(
          samples.map((sample) => (sample['spansMs'] as Map)[name] as num),
          .5,
        ),
    },
  };
}

/// Checks full bytes independently of the candidate's fingerprint algorithm.
void _expectBytes(
  Map<String, List<int>> expected,
  Map<String, List<int>> actual,
) {
  if (expected.length != actual.length)
    throw StateError('Artifact set differs.');
  for (final entry in expected.entries) {
    final bytes = actual[entry.key];
    if (bytes == null || bytes.length != entry.value.length)
      throw StateError('Artifact length differs: ${entry.key}');
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != entry.value[i])
        throw StateError('Artifact bytes differ: ${entry.key}');
    }
  }
}

/// Measures one budget in a fresh process, with no cross-variant heap retention.
Future<Map<String, Object?>> _worker(Directory root, int concurrency) async {
  final packageFiles = <String, Map<String, File>>{};
  final entities =
      root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  for (final file in entities) {
    final relative = path
        .relative(file.path, from: root.path)
        .replaceAll(path.separator, '/');
    final owner = file.parent;
    var package = owner;
    while (package.path != root.path &&
        !File(path.join(package.path, 'pubspec.yaml')).existsSync()) {
      package = package.parent;
    }
    (packageFiles[package.path] ??= {})[relative] = file;
  }
  final expected = <String, Map<String, List<int>>>{};
  final fingerprints = <String, String>{};
  for (final entry in packageFiles.entries) {
    final bytes = <String, List<int>>{};
    for (final file in entry.value.entries) {
      bytes[file.key] = await file.value.readAsBytes();
    }
    expected[entry.key] = bytes;
    fingerprints[entry.key] = CCPackageWatchFingerprint.digestEntries(bytes);
  }
  final reader = CCGenerationFileReader(maxConcurrentReads: concurrency);
  final samples = <int>[];
  for (var sample = -2; sample < 12; sample++) {
    final watch = Stopwatch()..start();
    final actual = <String, Map<String, List<int>>>{};
    final actualFingerprints = <String, String>{};
    for (final entry in packageFiles.entries) {
      final bytes = await reader.readAll(entry.value);
      actual[entry.key] = bytes;
      actualFingerprints[entry.key] = CCPackageWatchFingerprint.digestEntries(
        bytes,
      );
    }
    watch.stop();
    for (final entry in actual.entries) {
      if (actualFingerprints[entry.key] != fingerprints[entry.key])
        throw StateError('Fingerprint differs.');
      for (final file in entry.value.entries) {
        final reference = expected[entry.key]![file.key]!;
        if (file.value.length != reference.length)
          throw StateError('Byte length differs.');
        for (var index = 0; index < reference.length; index++) {
          if (file.value[index] != reference[index])
            throw StateError('Bytes differ.');
        }
      }
    }
    if (sample >= 0) samples.add(watch.elapsedMicroseconds);
  }
  return {
    'samplesUs': samples,
    'peakRssBytes': ProcessInfo.maxRss,
    'packages': packageFiles.length,
    'differential': 'exact-bytes-and-digests',
  };
}

/// Aggregates interleaved process samples without mixing their memory peaks.
Map<String, Object?> _summarize(List<Map<String, dynamic>> runs) {
  final samples = [
    for (final run in runs) ...(run['samplesUs'] as List).cast<int>(),
  ]..sort();
  return {
    'samples': samples.length,
    'p50Us': samples[(samples.length * .5).ceil() - 1],
    'p95Us': samples[(samples.length * .95).ceil() - 1],
    'peakRssBytes': runs.map((run) => run['peakRssBytes'] as int).reduce(max),
    'packages': runs.first['packages'],
    'differential': runs.first['differential'],
  };
}
