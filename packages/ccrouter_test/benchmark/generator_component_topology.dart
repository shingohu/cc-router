import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

part 'generator_invalidation_scenarios.dart';

/// Benchmarks multi-Package component additions and removals.
///
/// Each synthetic component owns five Routes plus one Service, Command, Event,
/// and InitTask. The default `3 5 10` factors scale the current Demo baseline
/// of six business components to 18, 30, and 60 component Packages.
///
/// Run from the CCRouter workspace with the project FVM Dart SDK:
///
/// ```bash
/// fvm dart run packages/ccrouter_test/benchmark/
///   generator_component_topology.dart 3 5 10
/// ```
Future<void> main(List<String> arguments) async {
  final workspaceRoot = _findWorkspaceRoot(Directory.current);
  final invalidation = arguments.contains('--invalidation');
  final scaleArguments = arguments
      .where((value) => value != '--invalidation')
      .toList();
  final scales = scaleArguments.isEmpty
      ? const <int>[3, 5, 10]
      : scaleArguments.map(int.parse).toList(growable: false);
  for (final scale in scales) {
    if (scale <= 0) {
      throw ArgumentError.value(scale, 'scale', 'must be positive');
    }
    final report = invalidation
        ? await _runInvalidationScale(workspaceRoot, scale)
        : await _runScale(workspaceRoot, scale);
    stdout.writeln(jsonEncode(report));
  }
}

/// Runs personal and team workflows for one component-count multiplier.
Future<Map<String, Object?>> _runScale(
  Directory workspaceRoot,
  int scale,
) async {
  const baselineComponents = 6;
  final componentCount = baselineComponents * scale;
  final author = Directory.systemTemp.createTempSync(
    'ccrouter-component-author-${scale}x-',
  );
  final teammate = Directory.systemTemp.createTempSync(
    'ccrouter-component-team-${scale}x-',
  );
  var succeeded = false;
  try {
    _writeWorkspace(
      workspaceRoot: workspaceRoot,
      fixture: author,
      componentCount: componentCount,
      hostDependencyCount: componentCount,
    );
    final authorPubGet = await _pubGet(author);
    final authorCold = await _runGeneration(author, noCache: true);
    _expectCatalog(
      authorCold,
      components: componentCount,
      routes: componentCount * _routesPerComponent,
      packages: componentCount + 1,
    );
    final allComponentsSnapshot = await _ArtifactSnapshot.capture(author);

    final authorWarm = await _runGeneration(author, check: true);
    _expectPlan(authorWarm, 'unchanged');

    _writeHostPubspec(author, componentCount - 1);
    final personalDeletePubGet = await _pubGet(author);
    final personalDelete = await _runGeneration(author);
    _expectPlan(personalDelete, 'aggregateOnly');
    _expectCatalog(
      personalDelete,
      components: componentCount - 1,
      routes: (componentCount - 1) * _routesPerComponent,
      packages: componentCount,
    );
    final personalDeleteAccuracy = await _verifyReference(author);

    final addedPackageName = _packageName(componentCount - 1);
    final authorGenerated = _generatedPackageDirectory(
      author,
      addedPackageName,
    );
    final authorBuilderMetadata = _builderMetadataDirectory(
      author,
      addedPackageName,
    );
    if (authorGenerated.existsSync()) {
      authorGenerated.deleteSync(recursive: true);
    }
    if (authorBuilderMetadata.existsSync()) {
      authorBuilderMetadata.deleteSync(recursive: true);
    }
    _writeHostPubspec(author, componentCount);
    final personalAddPubGet = await _pubGet(author);
    final personalAdd = await _runGeneration(author);
    _expectPlan(personalAdd, 'runBuilder');
    _expectCatalog(
      personalAdd,
      components: componentCount,
      routes: componentCount * _routesPerComponent,
      packages: componentCount + 1,
    );
    if (personalAdd.buildMs == 0) {
      throw StateError('A new ungenerated component skipped build_runner.');
    }
    final personalAddSnapshot = await _ArtifactSnapshot.capture(author);
    _expectExact(
      allComponentsSnapshot,
      personalAddSnapshot,
      'personal add did not reproduce the seeded full graph',
    );
    final personalAddAccuracy = await _verifyReference(author);

    _writeWorkspace(
      workspaceRoot: workspaceRoot,
      fixture: teammate,
      componentCount: componentCount,
      hostDependencyCount: componentCount - 1,
    );
    final teamBasePubGet = await _pubGet(teammate);
    final teamFreshBase = await _runGeneration(teammate, noCache: true);
    _expectCatalog(
      teamFreshBase,
      components: componentCount - 1,
      routes: (componentCount - 1) * _routesPerComponent,
      packages: componentCount,
    );

    final teammateGenerated = _generatedPackageDirectory(
      teammate,
      addedPackageName,
    );
    if (!authorGenerated.existsSync()) {
      throw StateError('Author output is missing for $addedPackageName.');
    }
    await _copyDirectory(authorGenerated, teammateGenerated);
    final teamBaseWithPrebuilt = await _ArtifactSnapshot.capture(teammate);
    final addedBuilderMetadata = _builderMetadataDirectory(
      teammate,
      addedPackageName,
    );
    if (addedBuilderMetadata.existsSync()) {
      throw StateError(
        'Team fixture unexpectedly has Builder metadata for $addedPackageName.',
      );
    }

    _writeHostPubspec(teammate, componentCount);
    final teamAddPubGet = await _pubGet(teammate);
    final teamAdd = await _runGeneration(teammate);
    _expectPlan(teamAdd, 'aggregateOnly');
    _expectCatalog(
      teamAdd,
      components: componentCount,
      routes: componentCount * _routesPerComponent,
      packages: componentCount + 1,
    );
    final teamAddSnapshot = await _ArtifactSnapshot.capture(teammate);
    _expectExact(
      allComponentsSnapshot,
      teamAddSnapshot,
      'team add differs from the author-generated full graph',
    );
    final teamAddAccuracy = await _verifyReference(teammate);

    _writeHostPubspec(teammate, componentCount - 1);
    final teamDeletePubGet = await _pubGet(teammate);
    final teamDelete = await _runGeneration(teammate);
    _expectPlan(teamDelete, 'aggregateOnly');
    _expectCatalog(
      teamDelete,
      components: componentCount - 1,
      routes: (componentCount - 1) * _routesPerComponent,
      packages: componentCount,
    );
    final teamDeleteSnapshot = await _ArtifactSnapshot.capture(teammate);
    _expectExact(
      teamBaseWithPrebuilt,
      teamDeleteSnapshot,
      'team delete did not reproduce the pre-pull base graph',
    );
    final teamDeleteAccuracy = await _verifyReference(teammate);

    succeeded = true;
    return <String, Object?>{
      'scenario': 'component-package-topology',
      'scale': scale,
      'baselineComponents': baselineComponents,
      'componentPackages': componentCount,
      'capabilitiesPerComponent': const <String, int>{
        'routes': _routesPerComponent,
        'services': 1,
        'commands': 1,
        'events': 1,
        'initTasks': 1,
      },
      'personal': <String, Object?>{
        'initialPubGetMs': authorPubGet,
        'coldSeed': authorCold.toJson(),
        'stableCheck': authorWarm.toJson(),
        'delete': <String, Object?>{
          'pubGetMs': personalDeletePubGet,
          'generation': personalDelete.toJson(),
          'accuracy': personalDeleteAccuracy.toJson(),
        },
        'addNewUngeneratedPackage': <String, Object?>{
          'pubGetMs': personalAddPubGet,
          'generation': personalAdd.toJson(),
          'accuracy': personalAddAccuracy.toJson(),
          'matchesColdSeed': true,
          'builderMetadataPresentBeforeAdd': false,
        },
      },
      'team': <String, Object?>{
        'freshClonePubGetMs': teamBasePubGet,
        'freshCloneBase': teamFreshBase.toJson(),
        'addPrebuiltPackage': <String, Object?>{
          'pubGetMs': teamAddPubGet,
          'generation': teamAdd.toJson(),
          'accuracy': teamAddAccuracy.toJson(),
          'authorBytesEqual': true,
          'builderMetadataPresentBeforeAdd': false,
        },
        'deletePackage': <String, Object?>{
          'pubGetMs': teamDeletePubGet,
          'generation': teamDelete.toJson(),
          'accuracy': teamDeleteAccuracy.toJson(),
          'baseBytesRestored': true,
        },
      },
    };
  } finally {
    if (succeeded) {
      if (author.existsSync()) author.deleteSync(recursive: true);
      if (teammate.existsSync()) teammate.deleteSync(recursive: true);
    } else {
      stderr.writeln(
        'Benchmark fixtures retained for diagnosis:\n'
        '  author: ${author.path}\n'
        '  teammate: ${teammate.path}',
      );
    }
  }
}

/// Resolves one Package's source-controlled generated directory.
Directory _generatedPackageDirectory(Directory fixture, String packageName) =>
    Directory(
      path.join(
        fixture.path,
        'components',
        packageName,
        'lib',
        'src',
        'ccrouter_generated',
      ),
    );

/// Resolves one Package's disposable local Builder metadata directory.
Directory _builderMetadataDirectory(Directory fixture, String packageName) =>
    Directory(
      path.join(fixture.path, '.dart_tool', 'build', 'generated', packageName),
    );

/// Number of realistic typed Route pages generated by each component.
const int _routesPerComponent = 5;

/// Writes an isolated Dart Workspace and all authored component sources.
void _writeWorkspace({
  required Directory workspaceRoot,
  required Directory fixture,
  required int componentCount,
  required int hostDependencyCount,
}) {
  final members = <String>['host'];
  for (var index = 0; index < componentCount; index += 1) {
    members.add('components/${_packageName(index)}');
  }
  final ccrouter = path.join(workspaceRoot.path, 'packages', 'ccrouter');
  final contracts = path.join(
    workspaceRoot.path,
    'packages',
    'ccrouter_contracts',
  );
  final core = path.join(workspaceRoot.path, 'packages', 'ccrouter_core');
  final generator = path.join(
    workspaceRoot.path,
    'packages',
    'ccrouter_generator',
  );
  File(path.join(fixture.path, 'pubspec.yaml')).writeAsStringSync('''
name: ccrouter_component_topology_benchmark
publish_to: none
environment:
  sdk: ^3.10.0
dev_dependencies:
  build_runner: ^2.10.0
  ccrouter_generator:
    path: ${jsonEncode(generator)}
dependency_overrides:
  ccrouter:
    path: ${jsonEncode(ccrouter)}
  ccrouter_contracts:
    path: ${jsonEncode(contracts)}
  ccrouter_core:
    path: ${jsonEncode(core)}
workspace:
${members.map((member) => '  - $member').join('\n')}
''');
  Directory(path.join(fixture.path, 'host', 'lib')).createSync(recursive: true);
  File(
    path.join(fixture.path, 'host', 'lib', 'benchmark_host.dart'),
  ).writeAsStringSync('library;\n');
  for (var index = 0; index < componentCount; index += 1) {
    _writeComponent(fixture, index, generator: generator);
  }
  _writeHostPubspec(fixture, hostDependencyCount);
}

/// Rewrites the generated fixture Host dependency closure deterministically.
void _writeHostPubspec(Directory fixture, int dependencyCount) {
  final dependencies = <String>[
    '  ccrouter: ^0.1.0',
    for (var index = 0; index < dependencyCount; index += 1)
      '  ${_packageName(index)}: ^1.0.0',
  ];
  File(path.join(fixture.path, 'host', 'pubspec.yaml')).writeAsStringSync('''
name: benchmark_host
version: 1.0.0
publish_to: none
resolution: workspace
environment:
  sdk: ^3.10.0
dependencies:
${dependencies.join('\n')}
''');
}

/// Writes one component Package with all five generated capability families.
void _writeComponent(
  Directory fixture,
  int index, {
  required String generator,
}) {
  final packageName = _packageName(index);
  final packageRoot = Directory(
    path.join(fixture.path, 'components', packageName),
  );
  final source = Directory(path.join(packageRoot.path, 'lib', 'src'))
    ..createSync(recursive: true);
  File(path.join(packageRoot.path, 'pubspec.yaml')).writeAsStringSync('''
name: $packageName
version: 1.0.0
publish_to: none
resolution: workspace
environment:
  sdk: ^3.10.0
dependencies:
  ccrouter: ^0.1.0
  flutter:
    sdk: flutter
dev_dependencies:
  ccrouter_generator:
    path: ${jsonEncode(generator)}
''');
  File(
    path.join(packageRoot.path, 'lib', '$packageName.dart'),
  ).writeAsStringSync(
    "export 'src/${packageName}_component.dart' show ${_componentName(index)};\n",
  );
  File(
    path.join(source.path, '${packageName}_component.dart'),
  ).writeAsStringSync(_componentSource(index));
  File(
    path.join(source.path, '${packageName}_routes.dart'),
  ).writeAsStringSync(_routesSource(index));
  File(
    path.join(source.path, '${packageName}_service.dart'),
  ).writeAsStringSync(_serviceSource(index));
  File(
    path.join(source.path, '${packageName}_command.dart'),
  ).writeAsStringSync(_commandSource(index));
  File(
    path.join(source.path, '${packageName}_event.dart'),
  ).writeAsStringSync(_eventSource(index));
  File(
    path.join(source.path, '${packageName}_init_task.dart'),
  ).writeAsStringSync(_initTaskSource(index));
}

/// Returns the stable synthetic Package name for [index].
String _packageName(int index) =>
    'benchmark_component_${index.toString().padLeft(3, '0')}';

/// Returns the public component constant name for [index].
String _componentName(int index) =>
    'benchmarkComponent${index.toString().padLeft(3, '0')}';

/// Declares one top-level component identity.
String _componentSource(int index) {
  final suffix = index.toString().padLeft(3, '0');
  return '''
import 'package:ccrouter/ccrouter.dart';

const benchmarkComponent${suffix}Id = CCComponentId('benchmark_component_$suffix');
const benchmarkComponent$suffix = CCComponent(
  id: benchmarkComponent${suffix}Id,
  version: '1.0.0',
);
''';
}

/// Declares five unique typed Routes for one component.
String _routesSource(int componentIndex) {
  final component = componentIndex.toString().padLeft(3, '0');
  return '''
import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/widgets.dart';

${[for (var route = 0; route < _routesPerComponent; route += 1) '''
@CCRoute<void>(
  id: 'benchmark.component.$component.route.$route',
  pattern: CCPathPattern('/benchmark/$component/$route/:id'),
  description: 'Synthetic component $component route $route.',
)
final class Benchmark${component}Route${route}Page extends StatelessWidget {
  const Benchmark${component}Route${route}Page({required this.id, super.key});

  final int id;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
'''].join('\n')}
''';
}

/// Declares one component-internal generated Service.
String _serviceSource(int index) {
  final suffix = index.toString().padLeft(3, '0');
  return '''
import 'package:ccrouter/ccrouter.dart';

@CCService(id: 'benchmark.component.$suffix.service')
final class Benchmark${suffix}Service {
  Benchmark${suffix}Service();

  int read(int value) => value + $index;
}
''';
}

/// Declares one typed Command and Handler.
String _commandSource(int index) {
  final suffix = index.toString().padLeft(3, '0');
  return '''
import 'package:ccrouter/ccrouter.dart';

@CCCommandContract(
  id: 'benchmark.component.$suffix.command',
  description: 'Synthetic component $suffix command.',
)
final class Benchmark${suffix}Command implements CCCommand<int> {
  const Benchmark${suffix}Command(this.value);

  final int value;
}

@CCCommandHandler()
int handleBenchmark${suffix}Command(Benchmark${suffix}Command command) =>
    command.value + $index;
''';
}

/// Declares one typed Event and Subscriber.
String _eventSource(int index) {
  final suffix = index.toString().padLeft(3, '0');
  return '''
import 'package:ccrouter/ccrouter.dart';

@CCEventContract(
  id: 'benchmark.component.$suffix.event',
  description: 'Synthetic component $suffix event.',
)
final class Benchmark${suffix}Event implements CCEvent {
  const Benchmark${suffix}Event(this.value);

  final int value;
}

@CCEventSubscription()
void observeBenchmark${suffix}Event(Benchmark${suffix}Event event) {}
''';
}

/// Declares one typed InitTask Contract and Handler.
String _initTaskSource(int index) {
  final suffix = index.toString().padLeft(3, '0');
  return '''
import 'package:ccrouter/ccrouter.dart';

const benchmark${suffix}InitTask = CCInitTaskContract(
  id: 'benchmark.component.$suffix.init_task',
  description: 'Synthetic component $suffix initialization task.',
);

@CCInitTask(
  contract: benchmark${suffix}InitTask,
  gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.optional,
)
void initializeBenchmark${suffix}Component() {}
''';
}

/// Resolves fixture dependencies without allowing an installed Pub Hook to run.
Future<int> _pubGet(Directory fixture) async {
  final watch = Stopwatch()..start();
  final result = await Process.run(
    _flutterExecutable(),
    const <String>['pub', 'get'],
    workingDirectory: fixture.path,
    environment: <String, String>{
      ...Platform.environment,
      'CCROUTER_PUB_HOOK_DISABLE': '1',
    },
  );
  watch.stop();
  if (result.exitCode != 0) {
    throw StateError(
      'Fixture pub get failed (${result.exitCode}).\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
  return watch.elapsedMilliseconds;
}

/// Runs one profiled generation or authoritative check.
Future<_GenerationRun> _runGeneration(
  Directory fixture, {
  bool noCache = false,
  bool check = false,
}) async {
  final watch = Stopwatch()..start();
  final result = await Process.run(Platform.resolvedExecutable, <String>[
    'run',
    '--verbosity=error',
    'ccrouter_generator:ccrouter',
    'generate',
    'host',
    if (check) '--check',
    if (noCache) '--no-cache',
    '--profile',
  ], workingDirectory: fixture.path);
  watch.stop();
  if (result.exitCode != 0) {
    throw StateError(
      'Fixture generation failed (${result.exitCode}).\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
  return _GenerationRun.parse(
    '${result.stdout}',
    wallMs: watch.elapsedMilliseconds,
  );
}

/// Runs the full Builder reference path and proves it made no byte changes.
Future<_AccuracyResult> _verifyReference(
  Directory fixture, {
  String? expectedAggregationInputFingerprint,
}) async {
  final before = await _ArtifactSnapshot.capture(fixture);
  final reference = await _runGeneration(fixture, noCache: true, check: true);
  _expectPlan(reference, 'runBuilder');
  if (expectedAggregationInputFingerprint != null &&
      reference.aggregationInputFingerprint !=
          expectedAggregationInputFingerprint) {
    throw StateError(
      'Optimized/reference aggregation inputs differ: '
      '$expectedAggregationInputFingerprint != '
      '${reference.aggregationInputFingerprint}',
    );
  }
  final after = await _ArtifactSnapshot.capture(fixture);
  _expectExact(before, after, 'optimized output differs from reference output');
  return _AccuracyResult(
    reference: reference,
    artifactCount: before.files.length,
    fingerprint: before.fingerprint,
  );
}

/// Requires the expected Build Plan from a benchmark run.
void _expectPlan(_GenerationRun run, String actual) {
  if (run.actualPlan != actual) {
    throw StateError(
      'Expected Build Plan $actual, got ${run.actualPlan}: ${run.reasons}',
    );
  }
}

/// Requires the expected validated Host closure shape.
void _expectCatalog(
  _GenerationRun run, {
  required int components,
  required int routes,
  required int packages,
}) {
  if (run.components != components ||
      run.routes != routes ||
      run.packages != packages) {
    throw StateError(
      'Unexpected validated graph: '
      '${run.components}/${run.routes}/${run.packages}, expected '
      '$components/$routes/$packages.',
    );
  }
}

/// Requires exact file names and bytes across two generated trees.
void _expectExact(
  _ArtifactSnapshot expected,
  _ArtifactSnapshot actual,
  String message,
) {
  if (!expected.equals(actual)) {
    throw StateError(
      '$message: ${expected.fingerprint} != ${actual.fingerprint}',
    );
  }
}

/// Copies one generated directory without retaining source filesystem paths.
Future<void> _copyDirectory(Directory source, Directory target) async {
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = path.relative(entity.path, from: source.path);
    final destination = path.join(target.path, relative);
    if (entity is Directory) {
      Directory(destination).createSync(recursive: true);
    } else if (entity is File) {
      final file = File(destination);
      file.parent.createSync(recursive: true);
      await entity.copy(file.path);
    }
  }
}

/// Finds the repository root from any nested benchmark invocation path.
Directory _findWorkspaceRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    if (File(
      path.join(current.path, 'packages', 'ccrouter', 'pubspec.yaml'),
    ).existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Run the benchmark from the CCRouter workspace.');
    }
    current = parent;
  }
}

/// Resolves the Flutter executable paired with the current FVM Dart process.
String _flutterExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var level = 0; level < 3; level += 1) {
    directory = directory.parent;
  }
  final executable = File(
    path.join(directory.path, Platform.isWindows ? 'flutter.bat' : 'flutter'),
  );
  if (!executable.existsSync()) {
    throw StateError(
      'Cannot locate Flutter beside ${Platform.resolvedExecutable}; run with '
      'the project FVM Dart SDK.',
    );
  }
  return executable.path;
}

/// Exact generated artifact bytes relative to one fixture root.
final class _ArtifactSnapshot {
  /// Creates one deterministic generated tree snapshot.
  const _ArtifactSnapshot(this.files, this.fingerprint);

  /// Generated file bytes keyed by normalized fixture-relative paths.
  final Map<String, List<int>> files;

  /// Stable FNV-1a summary used only to identify report samples.
  final String fingerprint;

  /// Captures every source-controlled CCRouter generated artifact.
  static Future<_ArtifactSnapshot> capture(Directory fixture) async {
    final files = <String, List<int>>{};
    await for (final entity in fixture.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final relative = path
          .relative(entity.path, from: fixture.path)
          .replaceAll(path.separator, '/');
      final segments = relative.split('/');
      if (segments.contains('.dart_tool') ||
          !segments.contains('lib') ||
          !segments.contains('src') ||
          !segments.contains('ccrouter_generated')) {
        continue;
      }
      files[relative] = await entity.readAsBytes();
    }
    final sorted = files.keys.toList()..sort();
    final mask = (BigInt.one << 64) - BigInt.one;
    final prime = BigInt.parse('100000001b3', radix: 16);
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    for (final relative in sorted) {
      for (final byte in utf8.encode(relative)) {
        hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
      }
      hash = (hash * prime) & mask;
      for (final byte in files[relative]!) {
        hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
      }
    }
    return _ArtifactSnapshot(
      Map.unmodifiable(files),
      hash.toRadixString(16).padLeft(16, '0'),
    );
  }

  /// Whether file names and every byte equal [other].
  bool equals(_ArtifactSnapshot other) {
    if (files.length != other.files.length) return false;
    for (final entry in files.entries) {
      final candidate = other.files[entry.key];
      if (candidate == null || !_bytesEqual(entry.value, candidate)) {
        return false;
      }
    }
    return true;
  }
}

/// Returns whether two byte lists are exactly equal.
bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// Parsed timings, plan, and validated graph for one CLI invocation.
final class _GenerationRun {
  /// Creates one immutable benchmark run.
  const _GenerationRun({
    required this.wallMs,
    required this.profileTotalMs,
    required this.buildMs,
    required this.discoveryMs,
    required this.parseMs,
    required this.validateMs,
    required this.aggregateMs,
    required this.suggestedPlan,
    required this.actualPlan,
    required this.reasons,
    required this.components,
    required this.routes,
    required this.packages,
    required this.buildTargets,
    required this.aggregationInputFingerprint,
    this.attribution = const {},
  });

  /// Parent-process elapsed time including Dart process startup.
  final int wallMs;

  /// CLI-internal total time.
  final int profileTotalMs;

  /// build_runner phase time, or zero when skipped.
  final int buildMs;

  /// Package discovery phase time.
  final int discoveryMs;

  /// Metadata parsing phase time.
  final int parseMs;

  /// Workspace validation phase time.
  final int validateMs;

  /// Aggregate, format, and write phase time.
  final int aggregateMs;

  /// Candidate plan before the safety gate.
  final String suggestedPlan;

  /// Plan actually executed.
  final String actualPlan;

  /// Bounded machine-safe Build Plan reasons.
  final String reasons;

  /// Validated component count.
  final int components;

  /// Validated Route count.
  final int routes;

  /// Participating generated Package count.
  final int packages;

  /// Number of writable Package targets passed to build_runner.
  final int buildTargets;

  /// Exact post-Builder aggregation input identity, absent on a fast-path hit.
  final String? aggregationInputFingerprint;

  /// Observational input/output deltas; never used as an equivalence proof.
  final Map<String, Object?> attribution;

  /// Parses stable profile and validation lines from CLI [output].
  factory _GenerationRun.parse(String output, {required int wallMs}) {
    final plan = RegExp(
      r'build-plan suggested=(\w+) actual=(\w+) reasons=([^\n]+)',
    ).firstMatch(output);
    final total = RegExp(r'CCRouter profile total=(\d+)ms').firstMatch(output);
    final validated = RegExp(
      r'Validated (\d+) components and (\d+) routes across (\d+) generated Packages\.',
    ).firstMatch(output);
    if (plan == null || total == null) {
      throw FormatException('Missing Build Plan or total profile:\n$output');
    }
    final phase = RegExp(
      r'CCRouter profile build=(\d+)ms discovery=(\d+)ms parse=(\d+)ms '
      r'validate=(\d+)ms aggregate/format/write=(\d+)ms',
    ).firstMatch(output);
    final fastPath = output.contains('CCRouter profile fast-path=hit');
    if (!fastPath && (phase == null || validated == null)) {
      throw FormatException(
        'Missing generation phase or graph profile:\n$output',
      );
    }
    final targets = RegExp(
      r'CCRouter profile build-targets=(\d+)',
    ).firstMatch(output);
    final aggregationInput = RegExp(
      r'CCRouter profile aggregation-input=([0-9a-f]{64})',
    ).firstMatch(output);
    if (!fastPath && aggregationInput == null) {
      throw FormatException('Missing aggregation input fingerprint:\n$output');
    }
    return _GenerationRun(
      wallMs: wallMs,
      profileTotalMs: int.parse(total.group(1)!),
      buildMs: phase == null ? 0 : int.parse(phase.group(1)!),
      discoveryMs: phase == null ? 0 : int.parse(phase.group(2)!),
      parseMs: phase == null ? 0 : int.parse(phase.group(3)!),
      validateMs: phase == null ? 0 : int.parse(phase.group(4)!),
      aggregateMs: phase == null ? 0 : int.parse(phase.group(5)!),
      suggestedPlan: plan.group(1)!,
      actualPlan: plan.group(2)!,
      reasons: plan.group(3)!,
      components: validated == null ? -1 : int.parse(validated.group(1)!),
      routes: validated == null ? -1 : int.parse(validated.group(2)!),
      packages: validated == null ? -1 : int.parse(validated.group(3)!),
      buildTargets: targets == null ? 0 : int.parse(targets.group(1)!),
      aggregationInputFingerprint: aggregationInput?.group(1),
      attribution: {
        for (final key in ['input-delta', 'output-delta', 'output-delta-scan'])
          if (RegExp('CCRouter profile $key=([^\\n]+)').firstMatch(output)
              case final match?)
            key: match.group(1)!.startsWith('{')
                ? jsonDecode(match.group(1)!)
                : match.group(1),
      },
    );
  }

  /// Encodes stable timings and graph counts for JSON-line reports.
  Map<String, Object> toJson() => <String, Object>{
    'wallMs': wallMs,
    'profileTotalMs': profileTotalMs,
    'buildMs': buildMs,
    'discoveryMs': discoveryMs,
    'parseMs': parseMs,
    'validateMs': validateMs,
    'aggregateMs': aggregateMs,
    'suggestedPlan': suggestedPlan,
    'actualPlan': actualPlan,
    'reasons': reasons,
    'components': components,
    'routes': routes,
    'packages': packages,
    'buildTargets': buildTargets,
    if (aggregationInputFingerprint case final fingerprint?)
      'aggregationInputFingerprint': fingerprint,
    if (attribution.isNotEmpty) 'attribution': attribution,
  };
}

/// Result of comparing an optimized path with the full Builder reference.
final class _AccuracyResult {
  /// Creates one successful byte-exact reference comparison.
  const _AccuracyResult({
    required this.reference,
    required this.artifactCount,
    required this.fingerprint,
  });

  /// Authoritative no-cache check used for comparison.
  final _GenerationRun reference;

  /// Number of source-controlled generated artifacts compared.
  final int artifactCount;

  /// Stable fingerprint of all compared paths and bytes.
  final String fingerprint;

  /// Encodes proof fields for the benchmark report.
  Map<String, Object> toJson() => <String, Object>{
    'byteExact': true,
    'artifactCount': artifactCount,
    'fingerprint': fingerprint,
    'reference': reference.toJson(),
  };
}
