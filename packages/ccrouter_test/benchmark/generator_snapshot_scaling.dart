import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

/// Benchmarks repeated exact-content scans against one shared epoch snapshot.
///
/// The fixture models the current Demo at 1x and scales its Package and file
/// counts to 3x, 5x, and 10x. Every candidate result is checked byte-for-byte
/// against independently captured reference views before timing is reported.
///
/// Run from the CCRouter workspace root with:
///
/// ```bash
/// fvm dart run packages/ccrouter_test/benchmark/generator_snapshot_scaling.dart
/// ```
Future<void> main(List<String> arguments) async {
  final scales = arguments.isEmpty
      ? const <int>[1, 3, 5, 10]
      : arguments.map(int.parse).toList(growable: false);
  for (final scale in scales) {
    if (scale <= 0) {
      throw ArgumentError.value(scale, 'scale', 'must be positive');
    }
    stdout.writeln(jsonEncode(await _runScale(scale)));
  }
}

/// Creates, verifies, measures, and removes one isolated filesystem fixture.
Future<Map<String, Object?>> _runScale(int scale) async {
  final fixture = Directory.systemTemp.createTempSync(
    'ccrouter-snapshot-${scale}x-',
  );
  try {
    final packageCount = _baselinePackageCount * scale;
    final writablePackageCount = (packageCount * 0.8).ceil();
    _writeFixture(
      fixture,
      packageCount: packageCount,
      writablePackageCount: writablePackageCount,
    );

    final reference = await _ReferenceSnapshot.capture(
      fixture,
      writablePackageCount: writablePackageCount,
    );
    final candidate = await _EpochSnapshot.capture(
      fixture,
      writablePackageCount: writablePackageCount,
    );
    _expectEquivalent(reference, candidate, scenario: 'baseline');
    await _verifyFilesystemMutations(
      fixture,
      writablePackageCount: writablePackageCount,
    );

    // Warm both paths before collecting alternating-order samples.
    await _ReferenceSnapshot.capture(
      fixture,
      writablePackageCount: writablePackageCount,
    );
    await _EpochSnapshot.capture(
      fixture,
      writablePackageCount: writablePackageCount,
    );
    final referenceSamples = <int>[];
    final candidateSamples = <int>[];
    for (var sample = 0; sample < _sampleCount; sample++) {
      if (sample.isEven) {
        referenceSamples.add(
          await _measureReference(fixture, writablePackageCount),
        );
        candidateSamples.add(
          await _measureCandidate(fixture, writablePackageCount),
        );
      } else {
        candidateSamples.add(
          await _measureCandidate(fixture, writablePackageCount),
        );
        referenceSamples.add(
          await _measureReference(fixture, writablePackageCount),
        );
      }
    }
    referenceSamples.sort();
    candidateSamples.sort();
    final finalSnapshot = await _EpochSnapshot.capture(
      fixture,
      writablePackageCount: writablePackageCount,
    );
    return <String, Object?>{
      'scenario': 'generator-snapshot-scaling',
      'scale': scale,
      'packages': packageCount,
      'writablePackages': writablePackageCount,
      'files': finalSnapshot.allFiles.length,
      'bytes': _byteCount(finalSnapshot.allFiles),
      'inputFiles': finalSnapshot.inputs.length,
      'managedOutputFiles': finalSnapshot.managedOutputs.length,
      'writableOutputFiles': finalSnapshot.writableOutputs.length,
      'aggregationOutputFiles': finalSnapshot.aggregationOutputs.length,
      'samples': _sampleCount,
      'referenceIndependentScans': 4,
      'candidateSharedScans': 1,
      'referenceP50Us': _percentile(referenceSamples, 0.50),
      'referenceP95Us': _percentile(referenceSamples, 0.95),
      'candidateP50Us': _percentile(candidateSamples, 0.50),
      'candidateP95Us': _percentile(candidateSamples, 0.95),
      'p95Speedup': _ratio(
        _percentile(referenceSamples, 0.95),
        _percentile(candidateSamples, 0.95),
      ),
      'differential': const <String>[
        'baseline',
        'add',
        'change',
        'delete',
        'rename',
      ],
    };
  } finally {
    if (fixture.existsSync()) fixture.deleteSync(recursive: true);
  }
}

/// Measures the four independent reads performed by the reference path.
Future<int> _measureReference(Directory root, int writablePackages) async {
  final watch = Stopwatch()..start();
  await _ReferenceSnapshot.capture(
    root,
    writablePackageCount: writablePackages,
  );
  watch.stop();
  return watch.elapsedMicroseconds;
}

/// Measures the single read used to derive all candidate views.
Future<int> _measureCandidate(Directory root, int writablePackages) async {
  final watch = Stopwatch()..start();
  await _EpochSnapshot.capture(root, writablePackageCount: writablePackages);
  watch.stop();
  return watch.elapsedMicroseconds;
}

/// Proves that every mutation kind is visible to both implementations.
Future<void> _verifyFilesystemMutations(
  Directory root, {
  required int writablePackageCount,
}) async {
  var previous = await _captureAndCompare(
    root,
    writablePackageCount: writablePackageCount,
    scenario: 'mutation-baseline',
  );
  final packageRoot = Directory(path.join(root.path, _packageName(0)));
  final sourceDirectory = Directory(path.join(packageRoot.path, 'lib', 'src'));
  final outputDirectory = Directory(
    path.join(sourceDirectory.path, 'ccrouter_generated', 'route'),
  );

  final addedInput = File(path.join(sourceDirectory.path, 'added.dart'))
    ..writeAsBytesSync(_bytesFor('added-input', _sourceBytes));
  final addedOutput = File(
    path.join(outputDirectory.path, 'added.route.g.dart'),
  )..writeAsBytesSync(_bytesFor('added-output', _outputBytes));
  previous = await _expectChanged(
    root,
    writablePackageCount: writablePackageCount,
    scenario: 'add',
    previous: previous,
  );

  addedInput.writeAsBytesSync(_bytesFor('changed-input', _sourceBytes));
  addedOutput.writeAsBytesSync(_bytesFor('changed-output', _outputBytes));
  previous = await _expectChanged(
    root,
    writablePackageCount: writablePackageCount,
    scenario: 'change',
    previous: previous,
  );

  addedInput.deleteSync();
  addedOutput.deleteSync();
  previous = await _expectChanged(
    root,
    writablePackageCount: writablePackageCount,
    scenario: 'delete',
    previous: previous,
  );

  final renamedInput = File(path.join(sourceDirectory.path, 'source_0.dart'));
  final renamedOutput = File(
    path.join(outputDirectory.path, 'route_0.route.g.dart'),
  );
  renamedInput.renameSync(
    path.join(sourceDirectory.path, 'renamed_source.dart'),
  );
  renamedOutput.renameSync(
    path.join(outputDirectory.path, 'renamed_route.route.g.dart'),
  );
  await _expectChanged(
    root,
    writablePackageCount: writablePackageCount,
    scenario: 'rename',
    previous: previous,
  );
}

/// Captures both implementations and returns the combined state identity.
Future<String> _captureAndCompare(
  Directory root, {
  required int writablePackageCount,
  required String scenario,
}) async {
  final reference = await _ReferenceSnapshot.capture(
    root,
    writablePackageCount: writablePackageCount,
  );
  final candidate = await _EpochSnapshot.capture(
    root,
    writablePackageCount: writablePackageCount,
  );
  _expectEquivalent(reference, candidate, scenario: scenario);
  return candidate.combinedFingerprint;
}

/// Requires a mutation to change the exact combined input/output identity.
Future<String> _expectChanged(
  Directory root, {
  required int writablePackageCount,
  required String scenario,
  required String previous,
}) async {
  final current = await _captureAndCompare(
    root,
    writablePackageCount: writablePackageCount,
    scenario: scenario,
  );
  if (current == previous) {
    throw StateError('$scenario was not detected by the exact snapshot.');
  }
  return current;
}

/// Validates all logical views, including every exact byte, before timing.
void _expectEquivalent(
  _ReferenceSnapshot reference,
  _EpochSnapshot candidate, {
  required String scenario,
}) {
  final views = <String, (Map<String, List<int>>, Map<String, List<int>>)>{
    'inputs': (reference.inputs, candidate.inputs),
    'managedOutputs': (reference.managedOutputs, candidate.managedOutputs),
    'writableOutputs': (reference.writableOutputs, candidate.writableOutputs),
    'aggregationOutputs': (
      reference.aggregationOutputs,
      candidate.aggregationOutputs,
    ),
  };
  for (final entry in views.entries) {
    if (!_sameFiles(entry.value.$1, entry.value.$2)) {
      throw StateError('$scenario ${entry.key} differs from the reference.');
    }
    if (_digestEntries(entry.value.$1) != _digestEntries(entry.value.$2)) {
      throw StateError('$scenario ${entry.key} fingerprint differs.');
    }
  }
}

/// Independent phase reads representing the current repeated-scan strategy.
final class _ReferenceSnapshot {
  const _ReferenceSnapshot({
    required this.inputs,
    required this.managedOutputs,
    required this.writableOutputs,
    required this.aggregationOutputs,
  });

  final Map<String, List<int>> inputs;
  final Map<String, List<int>> managedOutputs;
  final Map<String, List<int>> writableOutputs;
  final Map<String, List<int>> aggregationOutputs;

  static Future<_ReferenceSnapshot> capture(
    Directory root, {
    required int writablePackageCount,
  }) async => _ReferenceSnapshot(
    inputs: await _readMatching(root, _isInput),
    managedOutputs: await _readMatching(root, _isManagedOutput),
    writableOutputs: await _readMatching(
      root,
      (relative) =>
          _isManagedOutput(relative) &&
          _isWritable(relative, writablePackageCount),
    ),
    aggregationOutputs: await _readMatching(
      root,
      (relative) =>
          _isManagedOutput(relative) &&
          _isWritable(relative, writablePackageCount) &&
          _isAggregationOutput(relative),
    ),
  );
}

/// One exact filesystem capture with derived immutable phase-specific views.
final class _EpochSnapshot {
  const _EpochSnapshot({
    required this.allFiles,
    required this.inputs,
    required this.managedOutputs,
    required this.writableOutputs,
    required this.aggregationOutputs,
  });

  final Map<String, List<int>> allFiles;
  final Map<String, List<int>> inputs;
  final Map<String, List<int>> managedOutputs;
  final Map<String, List<int>> writableOutputs;
  final Map<String, List<int>> aggregationOutputs;

  String get combinedFingerprint => _digestEntries(<String, List<int>>{
    for (final entry in inputs.entries) 'input/${entry.key}': entry.value,
    for (final entry in managedOutputs.entries)
      'output/${entry.key}': entry.value,
  });

  static Future<_EpochSnapshot> capture(
    Directory root, {
    required int writablePackageCount,
  }) async {
    final allFiles = await _readMatching(
      root,
      (relative) => _isInput(relative) || _isManagedOutput(relative),
    );
    Map<String, List<int>> select(bool Function(String relative) include) =>
        Map.unmodifiable(<String, List<int>>{
          for (final entry in allFiles.entries)
            if (include(entry.key)) entry.key: entry.value,
        });
    return _EpochSnapshot(
      allFiles: Map.unmodifiable(allFiles),
      inputs: select(_isInput),
      managedOutputs: select(_isManagedOutput),
      writableOutputs: select(
        (relative) =>
            _isManagedOutput(relative) &&
            _isWritable(relative, writablePackageCount),
      ),
      aggregationOutputs: select(
        (relative) =>
            _isManagedOutput(relative) &&
            _isWritable(relative, writablePackageCount) &&
            _isAggregationOutput(relative),
      ),
    );
  }
}

/// Reads exact bytes for every selected fixture file in deterministic order.
Future<Map<String, List<int>>> _readMatching(
  Directory root,
  bool Function(String relative) include,
) async {
  final files = <String, List<int>>{};
  final entities = await root.list(recursive: true, followLinks: false).toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  for (final entity in entities.whereType<File>()) {
    final relative = path
        .relative(entity.path, from: root.path)
        .replaceAll(path.separator, '/');
    if (include(relative)) files[relative] = await entity.readAsBytes();
  }
  return files;
}

/// Builds deterministic source and generated output trees for all Packages.
void _writeFixture(
  Directory root, {
  required int packageCount,
  required int writablePackageCount,
}) {
  for (var packageIndex = 0; packageIndex < packageCount; packageIndex++) {
    final packageRoot = Directory(
      path.join(root.path, _packageName(packageIndex)),
    )..createSync(recursive: true);
    File(
      path.join(packageRoot.path, 'pubspec.yaml'),
    ).writeAsBytesSync(_bytesFor('pubspec-$packageIndex', _pubspecBytes));
    final source = Directory(path.join(packageRoot.path, 'lib', 'src'))
      ..createSync(recursive: true);
    for (var fileIndex = 0; fileIndex < _sourceFilesPerPackage; fileIndex++) {
      File(path.join(source.path, 'source_$fileIndex.dart')).writeAsBytesSync(
        _bytesFor('source-$packageIndex-$fileIndex', _sourceBytes),
      );
    }
    for (var fileIndex = 0; fileIndex < _outputFilesPerPackage; fileIndex++) {
      final aggregation = fileIndex >= _builderOutputsPerPackage;
      final directory = Directory(
        path.join(
          source.path,
          'ccrouter_generated',
          aggregation ? 'metadata' : 'route',
        ),
      )..createSync(recursive: true);
      final name = aggregation
          ? 'catalog_$fileIndex.aggregate.json'
          : 'route_$fileIndex.route.g.dart';
      File(path.join(directory.path, name)).writeAsBytesSync(
        _bytesFor('output-$packageIndex-$fileIndex', _outputBytes),
      );
    }
    if (packageIndex >= writablePackageCount) {
      File(path.join(packageRoot.path, '.external')).writeAsStringSync('1');
    }
  }
}

/// Produces stable non-compressible-enough bytes with a unique prefix.
List<int> _bytesFor(String identity, int length) {
  final seed = utf8.encode('$identity\n');
  final bytes = List<int>.filled(length, 0);
  for (var index = 0; index < bytes.length; index++) {
    bytes[index] = seed[index % seed.length] ^ ((index * 31) & 0xff);
  }
  return bytes;
}

/// Whether a fixture path participates in exact authored input identity.
bool _isInput(String relative) =>
    relative.endsWith('/pubspec.yaml') ||
    (relative.endsWith('.dart') && !relative.contains('/ccrouter_generated/'));

/// Whether a fixture path is owned by CCRouter generation.
bool _isManagedOutput(String relative) =>
    relative.contains('/ccrouter_generated/');

/// Whether a managed file belongs to a Package writable in this invocation.
bool _isWritable(String relative, int writablePackageCount) {
  final packageName = relative.split('/').first;
  final packageIndex = int.parse(packageName.substring('package_'.length));
  return packageIndex < writablePackageCount;
}

/// Whether a generated file belongs to the post-Builder aggregation phase.
bool _isAggregationOutput(String relative) =>
    relative.contains('/ccrouter_generated/metadata/');

/// Hashes logical names and exact bytes with deterministic separators.
String _digestEntries(Map<String, List<int>> entries) {
  final names = entries.keys.toList()..sort();
  final bytes = BytesBuilder(copy: false);
  for (final name in names) {
    bytes
      ..add(utf8.encode(name))
      ..addByte(0)
      ..add(entries[name]!)
      ..addByte(0);
  }
  return sha256.convert(bytes.takeBytes()).toString();
}

/// Compares logical names and every byte without trusting metadata.
bool _sameFiles(Map<String, List<int>> left, Map<String, List<int>> right) {
  if (left.length != right.length || !left.keys.every(right.containsKey)) {
    return false;
  }
  for (final entry in left.entries) {
    final other = right[entry.key]!;
    if (entry.value.length != other.length) return false;
    for (var index = 0; index < entry.value.length; index++) {
      if (entry.value[index] != other[index]) return false;
    }
  }
  return true;
}

/// Counts the exact payload bytes retained by one snapshot.
int _byteCount(Map<String, List<int>> files) =>
    files.values.fold<int>(0, (total, bytes) => total + bytes.length);

/// Selects one nearest-rank percentile from sorted microseconds.
int _percentile(List<int> sorted, double percentile) =>
    sorted[((sorted.length - 1) * percentile).ceil()];

/// Reports one stable two-decimal speedup ratio.
double _ratio(int reference, int candidate) =>
    double.parse((reference / max(candidate, 1)).toStringAsFixed(2));

/// Returns the deterministic Package directory name used by the fixture.
String _packageName(int index) => 'package_${index.toString().padLeft(3, '0')}';

const int _baselinePackageCount = 11;
const int _sourceFilesPerPackage = 6;
const int _outputFilesPerPackage = 24;
const int _builderOutputsPerPackage = 16;
const int _sourceBytes = 2048;
const int _outputBytes = 4096;
const int _pubspecBytes = 512;
const int _sampleCount = 12;
