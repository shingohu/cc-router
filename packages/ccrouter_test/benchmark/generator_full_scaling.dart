import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Runs cold, end-to-end generator benchmarks with a realistic capability mix.
///
/// Execute this script from the workspace root with FVM:
///
/// ```bash
/// fvm dart run packages/ccrouter_test/benchmark/generator_full_scaling.dart
/// ```
///
/// Optional integer arguments select scale factors; the default is
/// `1 10 20 30`. Pass `--convergence` to measure two warm follow-up runs or
/// `--incremental` to change one Service ID and measure a correct rebuild.
/// Dependency resolution is deliberately excluded from each reported
/// generation duration. Every fixture is removed in `finally`.
Future<void> main(List<String> arguments) async {
  final workspaceRoot = _findWorkspaceRoot(Directory.current);
  final convergence = arguments.contains('--convergence');
  final incremental = arguments.contains('--incremental');
  final scaleArguments = arguments
      .where(
        (argument) =>
            argument != '--convergence' && argument != '--incremental',
      )
      .toList(growable: false);
  final scales = scaleArguments.isEmpty
      ? const [1, 10, 20, 30]
      : scaleArguments.map(int.parse).toList(growable: false);
  for (final scale in scales) {
    if (scale <= 0) {
      throw ArgumentError.value(scale, 'scale', 'must be positive');
    }
    await _runScale(
      workspaceRoot,
      scale,
      convergence: convergence,
      incremental: incremental,
    );
  }
}

/// Creates, resolves, benchmarks, reports, and removes one isolated fixture.
Future<void> _runScale(
  Directory workspaceRoot,
  int scale, {
  required bool convergence,
  required bool incremental,
}) async {
  final fixture = Directory.systemTemp.createTempSync(
    'ccrouter-full-generator-${scale}x-',
  );
  try {
    final counts = _CapabilityCounts.forScale(scale);
    _writeFixture(
      workspaceRoot: workspaceRoot,
      fixture: fixture,
      counts: counts,
    );
    final flutter = _flutterExecutable();
    final pubGet = await Process.run(flutter, const [
      'pub',
      'get',
    ], workingDirectory: fixture.path);
    if (pubGet.exitCode != 0) {
      throw StateError(
        'Fixture pub get failed (${pubGet.exitCode}).\n'
        '${pubGet.stdout}\n${pubGet.stderr}',
      );
    }

    final firstRun = await _runGeneration(fixture, noCache: true);
    final followUpRuns = <Map<String, Object>>[];
    if (convergence) {
      followUpRuns.add(
        (await _runGeneration(fixture, noCache: false)).toJson(),
      );
      followUpRuns.add(
        (await _runGeneration(fixture, noCache: false)).toJson(),
      );
    }
    Map<String, Object>? incrementalRun;
    if (incremental) {
      final service = File(
        path.join(fixture.path, 'lib', 'src', 'service_0.dart'),
      );
      service.writeAsStringSync(
        service.readAsStringSync().replaceFirst(
          'benchmark.service.0',
          'benchmark.service.changed.0',
        ),
      );
      incrementalRun = (await _runGeneration(fixture, noCache: false)).toJson();
    }
    final generatedFiles = fixture
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.contains('ccrouter_generated'))
        .length;
    stdout.writeln(
      jsonEncode({
        'scenario': 'full-capability-cold-generation',
        'scale': scale,
        ...counts.toJson(),
        'sourceFiles': counts.sourceFiles,
        'generatedFiles': generatedFiles,
        ...firstRun.toJson(),
        if (convergence) 'followUpRuns': followUpRuns,
        if (incrementalRun != null) 'incrementalRun': incrementalRun,
      }),
    );
  } finally {
    if (fixture.existsSync()) fixture.deleteSync(recursive: true);
  }
}

/// Executes one profiled generation pass and preserves its build summary.
Future<_GenerationRun> _runGeneration(
  Directory fixture, {
  required bool noCache,
}) async {
  final watch = Stopwatch()..start();
  final generation = await Process.run(Platform.resolvedExecutable, [
    'run',
    'ccrouter_generator:ccrouter',
    'generate',
    '.',
    if (noCache) '--no-cache',
    '--profile',
  ], workingDirectory: fixture.path);
  watch.stop();
  if (generation.exitCode != 0) {
    throw StateError(
      'Fixture generation failed (${generation.exitCode}).\n'
      '${generation.stdout}\n${generation.stderr}',
    );
  }
  final stdoutText = '${generation.stdout}';
  final fastPathHit = stdoutText.contains('CCRouter profile fast-path=hit');
  return _GenerationRun(
    phase: fastPathHit
        ? const {
            'buildMs': 0,
            'discoveryMs': 0,
            'parseMs': 0,
            'validateMs': 0,
            'aggregateMs': 0,
          }
        : _parsePhaseProfile(stdoutText),
    profileTotalMs: _parseTotalProfile(stdoutText),
    wallMs: watch.elapsedMilliseconds,
    buildSummary: _buildSummary(stdoutText),
    fastPathHit: fastPathHit,
  );
}

/// Extracts the final build_runner result without retaining noisy progress.
String _buildSummary(String output) {
  final matches = RegExp(
    r'Built with build_runner[^\n]*',
  ).allMatches(output).toList(growable: false);
  return matches.isEmpty ? '' : matches.last.group(0)!;
}

/// Writes one standalone Flutter Package containing all supported capabilities.
void _writeFixture({
  required Directory workspaceRoot,
  required Directory fixture,
  required _CapabilityCounts counts,
}) {
  final source = Directory(path.join(fixture.path, 'lib', 'src'))
    ..createSync(recursive: true);
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
name: ccrouter_generator_benchmark
description: Ephemeral full-capability CCRouter generator benchmark.
version: 1.0.0
publish_to: none
environment:
  sdk: ^3.10.0
dependencies:
  ccrouter:
    path: ${jsonEncode(ccrouter)}
  flutter:
    sdk: flutter
dev_dependencies:
  build_runner: ^2.10.0
  ccrouter_generator:
    path: ${jsonEncode(generator)}
dependency_overrides:
  ccrouter_contracts:
    path: ${jsonEncode(contracts)}
  ccrouter_core:
    path: ${jsonEncode(core)}
''');
  File(path.join(fixture.path, 'lib', 'benchmark.dart')).writeAsStringSync(
    "export 'src/benchmark_component.dart' show benchmarkComponent;\n",
  );
  File(path.join(source.path, 'benchmark_component.dart')).writeAsStringSync('''
import 'package:ccrouter/ccrouter.dart';

const benchmarkComponentId = CCComponentId('benchmark_component');
const benchmarkComponent = CCComponent(
  id: benchmarkComponentId,
  version: '1.0.0',
);
''');
  for (var index = 0; index < counts.routes; index += 1) {
    File(
      path.join(source.path, 'route_$index.dart'),
    ).writeAsStringSync(_routeSource(index));
  }
  for (var index = 0; index < counts.services; index += 1) {
    File(
      path.join(source.path, 'service_$index.dart'),
    ).writeAsStringSync(_serviceSource(index));
  }
  for (var index = 0; index < counts.commands; index += 1) {
    File(
      path.join(source.path, 'command_$index.dart'),
    ).writeAsStringSync(_commandSource(index));
  }
  for (var index = 0; index < counts.events; index += 1) {
    File(
      path.join(source.path, 'event_$index.dart'),
    ).writeAsStringSync(_eventSource(index));
  }
  for (var index = 0; index < counts.initTasks; index += 1) {
    File(
      path.join(source.path, 'init_task_$index.dart'),
    ).writeAsStringSync(_initTaskSource(index));
  }
}

/// Creates one typed Flutter Route with a unique fixed segment and path value.
String _routeSource(int index) =>
    '''
import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/widgets.dart';

@CCRoute<void>(
  id: 'benchmark.route.$index',
  pattern: CCPathPattern('/benchmark/$index/:id'),
  description: 'Synthetic route $index used by the generator benchmark.',
)
final class BenchmarkRoute${index}Page extends StatelessWidget {
  const BenchmarkRoute${index}Page({required this.id, super.key});

  /// Stable synthetic entity identity.
  final int id;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

/// Creates one component-internal generated singleton Service.
String _serviceSource(int index) =>
    '''
import 'package:ccrouter/ccrouter.dart';

@CCService(id: 'benchmark.service.$index')
final class BenchmarkService$index {
  BenchmarkService$index();

  int read(int value) => value + $index;
}
''';

/// Creates one typed Command contract and its owning handler.
String _commandSource(int index) =>
    '''
import 'package:ccrouter/ccrouter.dart';

@CCCommandContract(
  id: 'benchmark.command.$index',
  description: 'Synthetic command $index used by the generator benchmark.',
)
final class BenchmarkCommand$index implements CCCommand<int> {
  const BenchmarkCommand$index(this.value);

  final int value;
}

@CCCommandHandler()
int handleBenchmarkCommand$index(BenchmarkCommand$index command) =>
    command.value + $index;
''';

/// Creates one typed Event contract and an independent subscription.
String _eventSource(int index) =>
    '''
import 'package:ccrouter/ccrouter.dart';

@CCEventContract(
  id: 'benchmark.event.$index',
  description: 'Synthetic event $index used by the generator benchmark.',
)
final class BenchmarkEvent$index implements CCEvent {
  const BenchmarkEvent$index(this.value);

  final int value;
}

@CCEventSubscription()
void observeBenchmarkEvent$index(BenchmarkEvent$index event) {}
''';

/// Creates one typed InitTask contract and its generated task bridge.
String _initTaskSource(int index) =>
    '''
import 'package:ccrouter/ccrouter.dart';

const benchmarkInitTask$index = CCInitTaskContract(
  id: 'benchmark.init_task.$index',
  description: 'Synthetic initialization task $index.',
);

@CCInitTask(
  contract: benchmarkInitTask$index,
  gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.optional,
)
void initializeBenchmarkTask$index() {}
''';

/// Parses the detailed profile line emitted by the generation command.
Map<String, int> _parsePhaseProfile(String output) {
  final match = RegExp(
    r'CCRouter profile build=(\d+)ms discovery=(\d+)ms parse=(\d+)ms '
    r'validate=(\d+)ms aggregate/format/write=(\d+)ms .*dirty=(\d+)/(\d+)',
  ).firstMatch(output);
  if (match == null) {
    throw FormatException('Missing CCRouter phase profile in:\n$output');
  }
  return {
    'buildMs': int.parse(match.group(1)!),
    'discoveryMs': int.parse(match.group(2)!),
    'parseMs': int.parse(match.group(3)!),
    'validateMs': int.parse(match.group(4)!),
    'aggregateMs': int.parse(match.group(5)!),
    'dirtyPackages': int.parse(match.group(6)!),
    'dirtyPackageTotal': int.parse(match.group(7)!),
  };
}

/// Parses the end-to-end CLI profile line emitted after lock cleanup.
int _parseTotalProfile(String output) {
  final match = RegExp(r'CCRouter profile total=(\d+)ms').firstMatch(output);
  if (match == null) {
    throw FormatException('Missing CCRouter total profile in:\n$output');
  }
  return int.parse(match.group(1)!);
}

/// Finds the repository root from any nested benchmark working directory.
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
      '`fvm dart`.',
    );
  }
  return executable.path;
}

/// Realistic base mix derived from the current multi-component Demo.
final class _CapabilityCounts {
  /// Creates one immutable benchmark capability distribution.
  const _CapabilityCounts({
    required this.routes,
    required this.services,
    required this.commands,
    required this.events,
    required this.initTasks,
  });

  /// Scales every capability category without changing its relative mix.
  factory _CapabilityCounts.forScale(int scale) => _CapabilityCounts(
    routes: 31 * scale,
    services: 8 * scale,
    commands: 5 * scale,
    events: 3 * scale,
    initTasks: 8 * scale,
  );

  /// Number of annotated Route pages.
  final int routes;

  /// Number of generated component-internal Service Providers.
  final int services;

  /// Number of generated Command contracts and handlers.
  final int commands;

  /// Number of generated Event contracts and subscriptions.
  final int events;

  /// Number of generated InitTask contracts and handlers.
  final int initTasks;

  /// Number of authored Dart files, including component and public barrel.
  int get sourceFiles => routes + services + commands + events + initTasks + 2;

  /// Encodes stable counters used by machine-readable benchmark reports.
  Map<String, int> toJson() => {
    'routes': routes,
    'services': services,
    'commands': commands,
    'events': events,
    'initTasks': initTasks,
  };
}

/// One complete CLI execution used for cold and convergence comparisons.
final class _GenerationRun {
  /// Creates an immutable run result from parsed CLI output.
  const _GenerationRun({
    required this.phase,
    required this.profileTotalMs,
    required this.wallMs,
    required this.buildSummary,
    required this.fastPathHit,
  });

  /// Detailed generator phase durations keyed by report field.
  final Map<String, int> phase;

  /// Time measured inside the CLI, including lock lifecycle.
  final int profileTotalMs;

  /// Parent-process wall time, including Dart process startup.
  final int wallMs;

  /// Concise build_runner output count and elapsed-time summary.
  final String buildSummary;

  /// Whether exact state verification skipped build_runner and aggregation.
  final bool fastPathHit;

  /// Encodes this run for stable JSON-line reporting.
  Map<String, Object> toJson() => {
    ...phase,
    'profileTotalMs': profileTotalMs,
    'wallMs': wallMs,
    'buildSummary': buildSummary,
    'fastPathHit': fastPathHit,
  };
}
