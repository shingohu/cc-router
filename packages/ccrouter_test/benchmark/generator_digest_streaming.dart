import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../../ccrouter_generator/bin/src/generation_file_reader.dart';
import '../../ccrouter_generator/bin/src/pub_hook_watch_coordination.dart';

/// Evaluates chunked SHA-256 without changing production fingerprint behavior.
///
/// Names, sorting, UTF-8, NUL delimiters and complete file bytes are unchanged.
/// Each hash creates a new sink; there is no cross-capture byte or digest cache.
/// Timings exclude discovery, reads, Builder, Analyzer and process startup.
/// Fresh interleaved processes report RSS, including VM/JIT and fixture costs.
/// Actual Demo CLI A/B did not establish a consistent benefit, so the temporary
/// production prototype and its switch were removed. This is research only;
/// it does not provide a CLI/watch optimization or a production experiment mode.
Future<void> main(List<String> arguments) async {
  if (arguments.firstOrNull == '--worker') {
    final workload = await _loadWorkload(
      scale: int.parse(arguments[2]),
      largeMiB: int.parse(arguments[3]),
    );
    final result = switch (arguments[1]) {
      'streaming' => _measure(workload, true, arguments[4], arguments[5]),
      'concatenated' => _measure(workload, false, arguments[4], arguments[5]),
      'paired' => _measurePaired(workload, arguments[4], arguments[5]),
      _ => throw ArgumentError('Unknown digest variant.'),
    };
    stdout.writeln(jsonEncode(result));
    return;
  }
  if (arguments.isNotEmpty &&
      !['--verify-only', '--timing-only'].contains(arguments.single)) {
    throw ArgumentError('Supported arguments: --verify-only or --timing-only.');
  }
  _verifyEncoding();
  await _verifyNewCaptures();
  stdout.writeln(
    jsonEncode({
      'scenario': 'streaming-digest-differential',
      'verified': [
        'independent-encoding-oracle',
        'empty-map-and-empty-file',
        'unicode-and-NUL',
        'SHA-256-block-boundaries',
        'insertion-order',
        'input-bytes-preserved',
        'add',
        'edit-same-size-and-mtime',
        'delete',
        'rename',
        'missing-read-failure',
        'new-capture-after-failure',
      ],
    }),
  );
  if (arguments.firstOrNull == '--verify-only') return;
  final timingOnly = arguments.firstOrNull == '--timing-only';

  for (final specification in [
    for (final scale in [1, 3, 5, 10]) (scale, 0),
    for (final largeMiB in [1, 8, 32]) (1, largeMiB),
  ]) {
    final workload = await _loadWorkload(
      scale: specification.$1,
      largeMiB: specification.$2,
    );
    final global = _oracle(workload.entries);
    final packageProof = _packageProof(workload.packages, _oracle);
    final runs = <bool, List<Map<String, dynamic>>>{false: [], true: []};
    final pairedRuns = <bool, List<Map<String, dynamic>>>{false: [], true: []};
    for (var round = 0; round < 3; round++) {
      final order = round.isEven ? [false, true] : [true, false];
      for (final variant in [
        if (!timingOnly)
          for (final streaming in order)
            streaming ? 'streaming' : 'concatenated',
        'paired',
      ]) {
        final result = await Process.run(Platform.resolvedExecutable, [
          Platform.script.toFilePath(),
          '--worker',
          variant,
          '${specification.$1}',
          '${specification.$2}',
          global,
          packageProof,
        ]);
        if (result.exitCode != 0) {
          throw StateError('${result.stdout}\n${result.stderr}');
        }
        final decoded = jsonDecode('${result.stdout}') as Map<String, dynamic>;
        if (variant == 'paired') {
          pairedRuns[false]!.add(
            decoded['concatenated'] as Map<String, dynamic>,
          );
          pairedRuns[true]!.add(decoded['streaming'] as Map<String, dynamic>);
        } else {
          runs[variant == 'streaming']!.add(decoded);
        }
      }
    }
    stdout.writeln(
      jsonEncode({
        'scenario': specification.$2 == 0
            ? 'demo-digest-scaling'
            : 'synthetic-large-file-digest',
        'scale': specification.$1,
        'largeFileMiB': specification.$2,
        'files': workload.entries.length,
        'packages': workload.packages.length,
        'payloadBytes': workload.entries.values.fold<int>(
          0,
          (sum, bytes) => sum + bytes.length,
        ),
        'concatenatedBufferBytes': _encodedLength(workload.entries),
        'scope': 'hash-only-preloaded-bytes',
        'processesPerVariant': 3,
        'warmupSamplesPerProcess': _warmups,
        'hashesPerSample': _hashesPerSample,
        'globalFingerprint': global,
        'packageFingerprintProof': packageProof,
        if (!timingOnly) 'concatenated': _summarize(runs[false]!),
        if (!timingOnly) 'streaming': _summarize(runs[true]!),
        'pairedTiming': {
          'concatenated': _summarize(pairedRuns[false]!, includeRss: false),
          'streaming': _summarize(pairedRuns[true]!, includeRss: false),
        },
      }),
    );
  }
}

const _warmups = 3;
const _samples = 12;
const _hashesPerSample = 2;
final _separator = Uint8List(1);

/// Fixed research reference, independent of the selected production path.
String _concatenated(Map<String, List<int>> entries) {
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

/// Candidate: hashes the existing encoding without joining the complete input.
String _streaming(Map<String, List<int>> entries) {
  final names = entries.keys.toList()..sort();
  final result = _DigestResult();
  final sink = sha256.startChunkedConversion(result);
  for (final name in names) {
    sink
      ..add(utf8.encode(name))
      ..add(_separator)
      ..add(entries[name]!)
      ..add(_separator);
  }
  sink.close();
  return result.value!.toString();
}

/// Owns exactly one digest for one synchronous hash operation.
final class _DigestResult implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest digest) {
    if (value != null) throw StateError('More than one final digest.');
    value = digest;
  }

  @override
  void close() {}
}

/// Independent encoding oracle: fills explicit offsets instead of chunks.
String _oracle(Map<String, List<int>> entries) {
  final names = entries.keys.toList()..sort();
  final bytes = Uint8List(_encodedLength(entries));
  var offset = 0;
  for (final name in names) {
    final encodedName = utf8.encode(name);
    bytes.setRange(offset, offset + encodedName.length, encodedName);
    offset += encodedName.length;
    bytes[offset++] = 0;
    final content = entries[name]!;
    bytes.setRange(offset, offset + content.length, content);
    offset += content.length;
    bytes[offset++] = 0;
  }
  if (offset != bytes.length) throw StateError('Incomplete oracle encoding.');
  return sha256.convert(bytes).toString();
}

int _encodedLength(Map<String, List<int>> entries) => entries.entries.fold<int>(
  0,
  (sum, entry) => sum + utf8.encode(entry.key).length + 2 + entry.value.length,
);

void _expectDigest(Map<String, List<int>> entries) {
  final before = {
    for (final entry in entries.entries) entry.key: List<int>.of(entry.value),
  };
  final expected = _oracle(entries);
  if (_concatenated(entries) != expected ||
      CCPackageWatchFingerprint.digestEntries(entries) != expected ||
      _streaming(entries) != expected) {
    throw StateError('Digest differs from independent encoding oracle.');
  }
  for (final entry in before.entries) {
    final current = entries[entry.key]!;
    if (current.length != entry.value.length) {
      throw StateError('Hash mutated input length.');
    }
    for (var index = 0; index < current.length; index++) {
      if (current[index] != entry.value[index]) {
        throw StateError('Hash mutated input bytes.');
      }
    }
  }
}

void _verifyEncoding() {
  _expectDigest({});
  if (_streaming({}) !=
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') {
    throw StateError('SHA-256 empty-message vector differs.');
  }
  for (final length in [0, 1, 55, 56, 63, 64, 65, 127, 128, 129, 1024, 4096]) {
    final entries = <String, List<int>>{
      '组件/页面😀.dart': List.generate(length, (index) => index % 256),
      'a\u0000b': Uint8List.fromList([0, 255, 0, 128]),
      'empty.dart': [],
      '': [0],
    };
    _expectDigest(entries);
    final reversed = Map<String, List<int>>.fromEntries(
      entries.entries.toList().reversed,
    );
    _expectDigest(reversed);
    if (_streaming(entries) != _streaming(reversed)) {
      throw StateError('Insertion order affects digest.');
    }
  }
}

/// Fresh filesystem captures prove that the candidate retains no old evidence.
Future<void> _verifyNewCaptures() async {
  final fixture = await Directory.systemTemp.createTemp('ccrouter-digest-');
  try {
    final reader = CCGenerationFileReader(maxConcurrentReads: 4);
    final file = File(path.join(fixture.path, 'page.dart'));
    await file.writeAsBytes([1, 2, 3]);
    final files = <String, File>{'page.dart': file};
    String? previous;
    Future<void> changed() async {
      final capture = await reader.readAll(files);
      _expectDigest(capture);
      final digest = _streaming(capture);
      if (digest == previous) throw StateError('Mutation was not observed.');
      previous = digest;
    }

    await changed();
    final timestamp = await file.lastModified();
    await file.writeAsBytes([3, 2, 1]);
    await file.setLastModified(timestamp);
    await changed();
    final added = File(path.join(fixture.path, 'added.dart'));
    await added.writeAsBytes([4, 5, 6]);
    files['added.dart'] = added;
    await changed();
    await added.rename(path.join(fixture.path, 'renamed.dart'));
    files
      ..remove('added.dart')
      ..['renamed.dart'] = File(path.join(fixture.path, 'renamed.dart'));
    await changed();
    await files.remove('renamed.dart')!.delete();
    await changed();
    files['missing.dart'] = File(path.join(fixture.path, 'missing.dart'));
    var failed = false;
    try {
      await reader.readAll(files);
    } on FileSystemException {
      failed = true;
    }
    if (!failed) throw StateError('Missing read unexpectedly succeeded.');
    files.remove('missing.dart');
    await file.writeAsBytes([7, 8, 9]);
    await changed();
  } finally {
    await fixture.delete(recursive: true);
  }
}

/// Copies Demo file bytes into independent 1x/3x/5x/10x in-memory workloads.
Future<_Workload> _loadWorkload({
  required int scale,
  required int largeMiB,
}) async {
  if (scale < 1 || largeMiB < 0) throw ArgumentError('Invalid workload size.');
  if (largeMiB > 0) {
    final content = Uint8List(largeMiB * 1024 * 1024);
    for (var index = 0; index < content.length; index++) {
      content[index] = index % 251;
    }
    final entries = <String, List<int>>{
      'large/lib/source.dart': content,
      'large/pubspec.yaml': utf8.encode('name: large\n'),
    };
    return _Workload(entries, {'large': entries});
  }
  final demo = Directory(path.join(Directory.current.path, 'demo'));
  if (!demo.existsSync()) throw StateError('Run from the workspace root.');
  final entries = <String, List<int>>{};
  final packages = <String, Map<String, List<int>>>{};
  final pending = [demo];
  while (pending.isNotEmpty) {
    final directory = pending.removeLast();
    await for (final entity in directory.list(followLinks: false)) {
      final name = path.basename(entity.path);
      if (entity is Directory) {
        if (name.startsWith('.') || name == 'build' || name == 'tools')
          continue;
        pending.add(entity);
        continue;
      }
      if (entity is! File) continue;
      final relative = path.relative(entity.path, from: demo.path);
      final segments = path.split(relative);
      final configuration = const ['pubspec.yaml', 'build.yaml'].contains(name);
      final library =
          segments.contains('lib') &&
          (name.endsWith('.dart') ||
              (segments.contains('ccrouter_generated') &&
                  name.endsWith('.json')));
      if (!configuration && !library) continue;
      var owner = entity.parent;
      while (owner.path != demo.path &&
          !File(path.join(owner.path, 'pubspec.yaml')).existsSync()) {
        owner = owner.parent;
      }
      final ownerName = path.relative(owner.path, from: demo.path);
      final bytes = await entity.readAsBytes();
      for (var copy = 0; copy < scale; copy++) {
        final identity =
            'copy_$copy/${relative.replaceAll(path.separator, '/')}';
        final content = Uint8List.fromList(bytes);
        entries[identity] = content;
        (packages['copy_$copy/$ownerName'] ??= {})[identity] = content;
      }
    }
  }
  if (entries.isEmpty) throw StateError('Demo fixture is empty.');
  return _Workload(entries, packages);
}

final class _Workload {
  const _Workload(this.entries, this.packages);
  final Map<String, List<int>> entries;
  final Map<String, Map<String, List<int>>> packages;
}

String _packageProof(
  Map<String, Map<String, List<int>>> packages,
  String Function(Map<String, List<int>>) digest,
) {
  final names = packages.keys.toList()..sort();
  final results = {for (final name in names) name: digest(packages[name]!)};
  return sha256.convert(utf8.encode(jsonEncode(results))).toString();
}

Map<String, Object?> _measure(
  _Workload workload,
  bool streaming,
  String expectedGlobal,
  String expectedPackages,
) {
  final digest = streaming ? _streaming : _concatenated;
  final beforeRss = ProcessInfo.currentRss;
  final beforePeak = ProcessInfo.maxRss;
  final globalSamples = <double>[];
  final packageSamples = <double>[];
  for (var sample = -_warmups; sample < _samples; sample++) {
    for (final global in sample.isEven ? [true, false] : [false, true]) {
      final timer = Stopwatch()..start();
      for (var repetition = 0; repetition < _hashesPerSample; repetition++) {
        final actual = global
            ? digest(workload.entries)
            : _packageProof(workload.packages, digest);
        if (actual != (global ? expectedGlobal : expectedPackages)) {
          throw StateError(
            'Digest or Demo source changed; discard timing run.',
          );
        }
      }
      timer.stop();
      if (sample >= 0) {
        (global ? globalSamples : packageSamples).add(
          timer.elapsedMicroseconds / _hashesPerSample,
        );
      }
    }
  }
  return {
    'globalSamplesUs': globalSamples,
    'packageSamplesUs': packageSamples,
    'rssBeforeHashBytes': beforeRss,
    'peakRssBeforeHashBytes': beforePeak,
    'peakRssBytes': ProcessInfo.maxRss,
  };
}

/// Alternates both algorithms in one process to reduce process/load bias.
/// RSS is deliberately excluded because both variants share this heap.
Map<String, Object?> _measurePaired(
  _Workload workload,
  String expectedGlobal,
  String expectedPackages,
) {
  final samples = <bool, Map<String, List<double>>>{
    false: {'globalSamplesUs': [], 'packageSamplesUs': []},
    true: {'globalSamplesUs': [], 'packageSamplesUs': []},
  };
  for (var sample = -_warmups; sample < _samples; sample++) {
    for (final global in sample.isEven ? [true, false] : [false, true]) {
      for (final streaming in sample.isEven ? [false, true] : [true, false]) {
        final digest = streaming ? _streaming : _concatenated;
        final timer = Stopwatch()..start();
        for (var repetition = 0; repetition < _hashesPerSample; repetition++) {
          final actual = global
              ? digest(workload.entries)
              : _packageProof(workload.packages, digest);
          if (actual != (global ? expectedGlobal : expectedPackages)) {
            throw StateError('Digest changed; discard timing run.');
          }
        }
        timer.stop();
        if (sample >= 0) {
          samples[streaming]![global ? 'globalSamplesUs' : 'packageSamplesUs']!
              .add(timer.elapsedMicroseconds / _hashesPerSample);
        }
      }
    }
  }
  return {'concatenated': samples[false], 'streaming': samples[true]};
}

Map<String, Object?> _summarize(
  List<Map<String, dynamic>> runs, {
  bool includeRss = true,
}) {
  final result = <String, Object?>{};
  for (final scope in ['global', 'package']) {
    final samples = [
      for (final run in runs) ...(run['${scope}SamplesUs'] as List).cast<num>(),
    ]..sort();
    result[scope] = {
      'samples': samples.length,
      'p50Us': _percentile(samples, .5),
      'p95Us': _percentile(samples, .95),
      'processP50Us': [
        for (final run in runs)
          _percentile(
            (run['${scope}SamplesUs'] as List).cast<num>().toList()..sort(),
            .5,
          ),
      ],
    };
  }
  if (!includeRss) return result;
  result['rssRuns'] = [
    for (final run in runs)
      {
        for (final name in [
          'rssBeforeHashBytes',
          'peakRssBeforeHashBytes',
          'peakRssBytes',
        ])
          name: run[name],
      },
  ];
  result['maxPeakRssBytes'] = runs
      .map((run) => run['peakRssBytes'] as int)
      .reduce(max);
  return result;
}

num _percentile(List<num> sorted, double fraction) =>
    sorted[(sorted.length * fraction).ceil() - 1];
