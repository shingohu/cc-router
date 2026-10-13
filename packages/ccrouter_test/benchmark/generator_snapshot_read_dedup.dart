import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ccrouter_generator/src/package_workspace.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import '../../ccrouter_generator/bin/ccrouter_generator.dart';
import '../../ccrouter_generator/bin/src/generation_file_reader.dart';
import '../../ccrouter_generator/bin/src/pub_hook_watch_coordination.dart';

/// Inventories duplicate reads within one input capture and measures a prototype.
///
/// This is benchmark-only research. The experimental production path was
/// rejected after actual CLI A/B showed no repeatable gain. Captures keep all
/// logical aliases, use four read workers and discard evidence at their end.
/// It neither benchmarks Analyzer/Builder nor changes generation decisions.
Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty)
    throw ArgumentError('This benchmark has no CLI prototype mode.');
  await _verifyCaptureBoundaries();
  final root = Directory.current;
  final workspace = await CCPackageWorkspace.load(
    buildRoot: root,
    hostRoot: Directory(path.join(root.path, 'demo')),
    workspace: true,
  );
  final lock =
      loadYaml(File(path.join(root.path, 'pubspec.lock')).readAsStringSync())
          as YamlMap;
  final lockPackages = lock['packages'] as YamlMap;
  final steps = <Map<String, File>>[];
  void add(String scope, String relative, Directory base) {
    final file = File(path.join(base.path, relative));
    if (file.existsSync()) steps.add({'$scope/$relative': file});
  }

  for (final relative in _parsedPubFiles) {
    add('parsed-resolution', relative, root);
  }
  final authoredNames = <String>{};
  void addAuthored(String name, Directory packageRoot) {
    if (!authoredNames.add(name)) return;
    final inputs = <String, File>{};
    final lib = Directory(path.join(packageRoot.path, 'lib'));
    if (lib.existsSync()) {
      final files =
          lib
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))
              .where(
                (file) => !path.split(file.path).contains('ccrouter_generated'),
              )
              .toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      for (final file in files) {
        inputs['authored/$name/${path.relative(file.path, from: packageRoot.path)}'] =
            file;
      }
    }
    steps.add(inputs);
    for (final relative in ['pubspec.yaml', 'build.yaml']) {
      add('authored/$name', relative, packageRoot);
    }
  }

  for (final package in workspace.packages.values) {
    if (!package.writable &&
        !package.requiresPackageIndex &&
        lockPackages[package.name]?['source'] != 'path')
      continue;
    addAuthored(package.name, package.root);
  }
  // Match the portable context's additional resolved Path packages, including
  // the isolated Demo plugin bootstrap outside the runtime closure.
  final configFile = File(
    path.join(root.path, '.dart_tool', 'package_config.json'),
  );
  final config = jsonDecode(configFile.readAsStringSync()) as Map;
  final graph =
      jsonDecode(
            File(
              path.join(root.path, '.dart_tool', 'package_graph.json'),
            ).readAsStringSync(),
          )
          as Map;
  final graphNames = (graph['packages'] as List)
      .cast<Map>()
      .map((entry) => entry['name'])
      .toSet();
  for (final entry in (config['packages'] as List).cast<Map>()) {
    final name = entry['name'] as String;
    if (lockPackages[name]?['source'] != 'path' || !graphNames.contains(name))
      continue;
    final uri = configFile.uri.resolve(entry['rootUri'] as String);
    if (uri.scheme == 'file')
      addAuthored(name, Directory.fromUri(uri).absolute);
  }
  final generator = Directory(
    path.join(root.path, 'packages', 'ccrouter_generator'),
  );
  steps.add({
    for (final file in await CCGeneratorExecutionKernel.files(generator))
      'generator/${path.relative(file.path, from: generator.path)}': file,
  });
  for (final relative in ['pubspec.yaml', 'build.yaml']) {
    add('generator', relative, generator);
  }
  for (final package in workspace.packages.values.where((p) => !p.writable)) {
    final outputs = await CCPackageWatchFingerprint.captureManagedOutputFiles(
      package.root,
    );
    steps.add({
      for (final relative in outputs.keys)
        'external/${package.name}/$relative': File(
          path.join(package.root.path, relative),
        ),
    });
    for (final file in [
      package.indexFile,
      package.bundleFile,
      File(
        path.join(
          package.catalogDirectory.path,
          'ccrouter_generation_state.json',
        ),
      ),
    ]) {
      if (file.existsSync()) {
        steps.add({
          'external-alias/${package.name}/${path.basename(file.path)}': file,
        });
      }
    }
  }
  for (final relative in ['pubspec.yaml', ..._parsedPubFiles]) {
    add('build', relative, root);
  }

  final counts = <String, int>{};
  var logicalBytes = 0;
  for (final step in steps) {
    for (final file in step.values) {
      final identity = file.absolute.path;
      counts[identity] = (counts[identity] ?? 0) + 1;
      logicalBytes += file.lengthSync();
    }
  }
  final uniqueBytes = counts.keys.fold<int>(
    0,
    (sum, name) => sum + File(name).lengthSync(),
  );
  stdout.writeln(
    jsonEncode({
      'scenario': 'demo-single-input-capture-read-inventory',
      'packages': workspace.packages.length,
      'logicalReads': counts.values.fold<int>(0, (sum, count) => sum + count),
      'uniqueFiles': counts.length,
      'logicalBytes': logicalBytes,
      'duplicateBytes': logicalBytes - uniqueBytes,
      'duplicates': [
        for (final entry in counts.entries.where((entry) => entry.value > 1))
          {
            'path': path.relative(entry.key, from: root.path),
            'reads': entry.value,
            'bytes': File(entry.key).lengthSync(),
          },
      ],
      'scope': 'production-shaped-inventory-not-complete-command',
    }),
  );
  final duplicatePaths = counts.entries
      .where((entry) => entry.value > 1)
      .map((entry) => entry.key)
      .toSet();
  final samples = <bool, List<int>>{false: [], true: []};
  String? previousFingerprint;
  for (var sample = -2; sample < 12; sample++) {
    for (final dedup in sample.isEven ? [false, true] : [true, false]) {
      final watch = Stopwatch()..start();
      final captured = await _capture(
        steps,
        dedup: dedup,
        duplicatePaths: duplicatePaths,
      );
      final fingerprint = CCPackageWatchFingerprint.digestEntries(captured);
      watch.stop();
      if (previousFingerprint != null && previousFingerprint != fingerprint) {
        throw StateError(
          'Input changed between captures; discard this timing run.',
        );
      }
      previousFingerprint = fingerprint;
      for (final step in steps) {
        for (final entry in step.entries) {
          _sameBytes(
            entry.value.readAsBytesSync(),
            captured[entry.key]!,
            entry.key,
          );
        }
      }
      if (sample < 0) continue;
      samples[dedup]!.add(watch.elapsedMicroseconds);
    }
  }
  stdout.writeln(
    jsonEncode({
      'scenario': 'demo-single-input-capture-prototype',
      'scope': 'read-and-hash-only-no-directory-scan-or-parsing',
      'readWorkers': 4,
      'samples': 12,
      'reference': _distribution(samples[false]!),
      'prototype': _distribution(samples[true]!),
      'fingerprint': previousFingerprint,
      'differential': [
        'independent-byte-oracle',
        'add',
        'edit-same-size-and-mtime',
        'delete',
        'rename',
        'missing-read-failure',
        'new-capture-after-failure',
      ],
    }),
  );
}

/// Resolution files parsed and later hashed by the same input capture.
const _parsedPubFiles = [
  '.dart_tool/package_graph.json',
  '.dart_tool/package_config.json',
  'pubspec.lock',
];

/// Shared read budget, with no file evidence retained between captures.
final _reader = CCGenerationFileReader(maxConcurrentReads: 4);

/// Derives aliases only from evidence collected in this one benchmark capture.
Future<Map<String, List<int>>> _capture(
  List<Map<String, File>> steps, {
  required bool dedup,
  Set<String> duplicatePaths = const {},
}) async {
  final captured = <String, List<int>>{};
  final cached = <String, List<int>>{};
  for (final step in steps) {
    if (!dedup) {
      captured.addAll(await _reader.readAll(step));
      continue;
    }
    final missing = <String, File>{
      for (final file in step.values)
        if (!cached.containsKey(file.absolute.path)) file.absolute.path: file,
    };
    final current = await _reader.readAll(missing);
    for (final entry in step.entries) {
      final identity = entry.value.absolute.path;
      final bytes = cached[identity] ?? current[identity]!;
      captured[entry.key] = bytes;
      if (duplicatePaths.contains(identity)) cached[identity] = bytes;
    }
  }
  return captured;
}

/// Exercises lifecycle mutations and failures against independent fresh reads.
Future<void> _verifyCaptureBoundaries() async {
  final fixture = await Directory.systemTemp.createTemp(
    'ccrouter_snapshot_read_dedup_',
  );
  try {
    final source = File(path.join(fixture.path, 'source.dart'))
      ..writeAsBytesSync([0, 255, 1]);
    final stamp = source.lastModifiedSync();
    List<Map<String, File>> steps(File file) => [
      {'source': file},
      {'alias': file},
    ];
    Future<String> compare(File file) async {
      final input = steps(file);
      final reference = await _capture(input, dedup: false);
      final candidate = await _capture(
        input,
        dedup: true,
        duplicatePaths: {file.absolute.path},
      );
      if (reference.keys.toSet().difference(candidate.keys.toSet()).isNotEmpty)
        throw StateError('Alias disappeared.');
      for (final entry in reference.entries) {
        _sameBytes(entry.value, candidate[entry.key]!, entry.key);
      }
      return CCPackageWatchFingerprint.digestEntries(candidate);
    }

    final before = await compare(source);
    source.writeAsBytesSync([0, 255, 2]);
    source.setLastModifiedSync(stamp);
    if (await compare(source) == before)
      throw StateError('Same-size/mtime edit was ignored.');
    final renamed = source.renameSync(path.join(fixture.path, 'renamed.dart'));
    for (final dedup in [false, true]) {
      try {
        await _capture(
          steps(source),
          dedup: dedup,
          duplicatePaths: {source.absolute.path},
        );
        throw StateError('Missing old name must fail.');
      } on FileSystemException {
        // Both variants reject a stale path, then a fresh capture must recover.
      }
    }
    await compare(renamed);
    renamed.deleteSync();
    source.writeAsBytesSync([0, 255, 1]);
    if (await compare(source) != before)
      throw StateError('Add after deletion retained stale bytes.');
  } finally {
    await fixture.delete(recursive: true);
  }
}

/// Checks the independent byte oracle, including binary and empty files.
void _sameBytes(List<int> expected, List<int> actual, String name) {
  if (expected.length != actual.length)
    throw StateError('Different bytes: $name');
  for (var index = 0; index < expected.length; index++) {
    if (expected[index] != actual[index])
      throw StateError('Different bytes: $name');
  }
}

/// Reports the observed sample distribution without a performance threshold.
Map<String, int> _distribution(List<int> samples) {
  final ordered = samples.toList()..sort();
  return {
    'p50Us': ordered[max(0, (ordered.length * .5).ceil() - 1)],
    'p95Us': ordered[max(0, (ordered.length * .95).ceil() - 1)],
  };
}
