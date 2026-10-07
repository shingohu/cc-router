import 'dart:io';

import 'package:ccrouter_analyzer_plugin/src/filesystem_identity_index.dart';
import 'package:ccrouter_analyzer_plugin/src/generator_diagnostics_bridge.dart';
import 'package:ccrouter_analyzer_plugin/src/project_context.dart';
import 'package:path/path.dart' as path;

/// Measures steady Analyzer watch polling across increasing Workspace sizes.
void main() {
  _benchmarkExactPathPolling();
  for (final packageCount in const <int>[10, 30, 50, 100]) {
    final workspace = Directory.systemTemp.createTempSync(
      'ccrouter-analyzer-watch-bench-',
    );
    try {
      final members = <String>[];
      for (var index = 0; index < packageCount; index++) {
        final relative = 'packages/package_$index';
        members.add(relative);
        final root = Directory(path.join(workspace.path, relative))
          ..createSync(recursive: true);
        File(path.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: package_$index
resolution: workspace
dependencies:
  ccrouter: any
''');
        File(
          path.join(root.path, '.metadata'),
        ).writeAsStringSync('project_type: package\n');
      }
      File(path.join(workspace.path, 'pubspec.yaml')).writeAsStringSync(
        'name: watch_benchmark\nworkspace:\n'
        '${members.map((member) => '  - $member').join('\n')}\n',
      );
      final dartTool = Directory(path.join(workspace.path, '.dart_tool'))
        ..createSync(recursive: true);
      File(
        path.join(dartTool.path, 'package_graph.json'),
      ).writeAsStringSync('{}\n');
      File(
        path.join(dartTool.path, 'package_config.json'),
      ).writeAsStringSync('{}\n');
      final manifests = <String>[
        for (final member in members)
          path.join(workspace.path, member, 'pubspec.yaml'),
      ];
      final cache = CCRouterAnalyzerProjectContextCache();
      final bridge = CCRouterGeneratorDiagnosticsBridge();

      for (final manifest in manifests) {
        cache.observe(manifest);
      }
      bridge.pollResolutionGraphChanged(workspace);
      final cachedWatch = Stopwatch()..start();
      for (var poll = 0; poll < 100; poll++) {
        for (final manifest in manifests) {
          cache.observe(manifest);
        }
        bridge.pollResolutionGraphChanged(workspace);
      }
      cachedWatch.stop();

      final referenceWatch = Stopwatch()..start();
      for (var poll = 0; poll < 100; poll++) {
        for (final manifest in manifests) {
          CCRouterAnalyzerProjectContext.resolve(manifest);
          CCRouterAnalyzerProjectContext.resolve(manifest);
        }
      }
      referenceWatch.stop();

      final cachedAverage = (cachedWatch.elapsedMicroseconds / 100).round();
      final referenceAverage = (referenceWatch.elapsedMicroseconds / 100)
          .round();

      stdout.writeln(
        'CCRouter analyzer watch packages=$packageCount polls=100 '
        'cachedAverage=${cachedAverage}us '
        'doubleResolveAverage=${referenceAverage}us '
        'speedup=${(referenceAverage / cachedAverage).toStringAsFixed(1)}x',
      );
    } finally {
      workspace.deleteSync(recursive: true);
    }
  }
}

/// Measures the exact-path fallback used when Analysis Server drops events.
///
/// This intentionally keeps a full-scan reference. Future incremental polling
/// implementations must run against the same fixture and return the same
/// affected source set before their timing can be compared with this baseline.
void _benchmarkExactPathPolling() {
  for (final pathCount in const <int>[100, 1000, 5000, 10000]) {
    final fixture = _ExactPathFixture.create(pathCount);
    try {
      final reference = _FullScanReference(fixture.sourcesByPath)..poll();
      final candidate = CCRouterFilesystemIdentityIndex();
      for (final entry in fixture.pathsBySource.entries) {
        candidate.replace(
          entry.key,
          watchedPaths: entry.value,
          affectedPaths: [entry.key],
        );
      }
      candidate.pollAll();
      final referenceSamples = <int>[];
      final candidateSamples = <int>[];
      for (var poll = 0; poll < 50; poll++) {
        final referenceWatch = Stopwatch()..start();
        final referenceAffected = reference.poll();
        referenceWatch.stop();
        final candidateWatch = Stopwatch()..start();
        final candidateAffected = candidate.pollAll().affectedPaths;
        candidateWatch.stop();
        if (referenceAffected.isNotEmpty || candidateAffected.isNotEmpty) {
          throw StateError('Stable exact-path poll reported a false change.');
        }
        referenceSamples.add(referenceWatch.elapsedMicroseconds);
        candidateSamples.add(candidateWatch.elapsedMicroseconds);
      }

      final changedPath = fixture.paths[pathCount ~/ 2];
      final expectedSources = fixture.sourcesByPath[changedPath]!;
      File(
        changedPath,
      ).writeAsStringSync('// changed\n', mode: FileMode.append);
      final referenceChangedWatch = Stopwatch()..start();
      final referenceChanged = reference.poll();
      referenceChangedWatch.stop();
      final eventChangedWatch = Stopwatch()..start();
      final eventChanged = candidate.pollPaths([changedPath]).affectedPaths;
      eventChangedWatch.stop();
      if (!_sameSet(referenceChanged, expectedSources) ||
          !_sameSet(eventChanged, expectedSources)) {
        throw StateError('Changed exact path returned the wrong sources.');
      }

      final removedPath = fixture.paths.last;
      final expectedRemovedSources = fixture.sourcesByPath[removedPath]!;
      File(removedPath).deleteSync();
      final referenceRemoved = reference.poll();
      final candidateRemoved = candidate.pollAll().affectedPaths;
      if (!_sameSet(referenceRemoved, expectedRemovedSources) ||
          !_sameSet(candidateRemoved, expectedRemovedSources)) {
        throw StateError('Deleted exact path returned the wrong sources.');
      }
      File(removedPath).writeAsStringSync('// recreated\n');
      final referenceRecreated = reference.poll();
      final candidateRecreated = candidate.pollAll().affectedPaths;
      if (!_sameSet(referenceRecreated, expectedRemovedSources) ||
          !_sameSet(candidateRecreated, expectedRemovedSources)) {
        throw StateError('Recreated exact path returned the wrong sources.');
      }

      referenceSamples.sort();
      candidateSamples.sort();
      stdout.writeln(
        'CCRouter analyzer exactPaths=$pathCount polls=50 '
        'referenceP50=${_percentile(referenceSamples, 0.50)}us '
        'referenceP95=${_percentile(referenceSamples, 0.95)}us '
        'candidateP50=${_percentile(candidateSamples, 0.50)}us '
        'candidateP95=${_percentile(candidateSamples, 0.95)}us '
        'referenceChange=${referenceChangedWatch.elapsedMicroseconds}us '
        'eventChange=${eventChangedWatch.elapsedMicroseconds}us',
      );
    } finally {
      fixture.dispose();
    }
  }
}

/// Current exact identity scan retained as the correctness reference.
final class _FullScanReference {
  /// Captures the initial identity of every exact path.
  _FullScanReference(this.sourcesByPath)
    : _identities = {
        for (final watchedPath in sourcesByPath.keys)
          watchedPath: _fileIdentity(watchedPath),
      };

  /// Authored sources affected by each generated or metadata input.
  final Map<String, Set<String>> sourcesByPath;

  /// Identity last observed for each exact input.
  final Map<String, String> _identities;

  /// Scans all exact inputs and returns sources affected by identity changes.
  Set<String> poll() {
    final affected = <String>{};
    for (final watchedPath in sourcesByPath.keys) {
      final current = _fileIdentity(watchedPath);
      if (current == _identities[watchedPath]) continue;
      _identities[watchedPath] = current;
      affected.addAll(sourcesByPath[watchedPath]!);
    }
    return affected;
  }
}

/// Temporary exact-path graph with five watched outputs per authored source.
final class _ExactPathFixture {
  /// Creates a fixture containing exactly [pathCount] watched files.
  factory _ExactPathFixture.create(int pathCount) {
    final root = Directory.systemTemp.createTempSync(
      'ccrouter-analyzer-exact-poll-',
    );
    final paths = <String>[];
    final sourcesByPath = <String, Set<String>>{};
    for (var index = 0; index < pathCount; index++) {
      final watched = File(path.join(root.path, 'generated', '$index.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{"index":$index}\n');
      final source = path.join(root.path, 'lib', 'src', '${index ~/ 5}.dart');
      paths.add(watched.path);
      sourcesByPath[watched.path] = {source};
    }
    return _ExactPathFixture._(root, paths, sourcesByPath);
  }

  const _ExactPathFixture._(this.root, this.paths, this.sourcesByPath);

  /// Root deleted after each scale sample.
  final Directory root;

  /// Stable path order used to select deterministic mutations.
  final List<String> paths;

  /// Reverse dependency evidence used by both reference and candidates.
  final Map<String, Set<String>> sourcesByPath;

  /// Exact watched paths grouped by their authored source registration.
  Map<String, Set<String>> get pathsBySource {
    final result = <String, Set<String>>{};
    for (final entry in sourcesByPath.entries) {
      for (final source in entry.value) {
        result.putIfAbsent(source, () => <String>{}).add(entry.key);
      }
    }
    return result;
  }

  /// Removes the complete temporary graph.
  void dispose() => root.deleteSync(recursive: true);
}

/// Returns a cheap identity matching the production polling representation.
String _fileIdentity(String filePath) {
  try {
    final stat = File(filePath).statSync();
    return '${stat.type}:${stat.size}:${stat.modified.microsecondsSinceEpoch}:'
        '${stat.changed.microsecondsSinceEpoch}';
  } on Object {
    return 'missing';
  }
}

/// Selects one nearest-rank percentile from already sorted microseconds.
int _percentile(List<int> sorted, double percentile) {
  final index = ((sorted.length - 1) * percentile).ceil();
  return sorted[index];
}

/// Compares unordered source identities without allocating sorted lists.
bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
