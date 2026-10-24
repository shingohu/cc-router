import 'dart:convert';
import 'dart:io';

/// Runs the repeatable Pure Dart performance and lifecycle regression suite.
///
/// The default suite covers Runtime scaling, concurrent navigation, Service
/// lookup/lifecycle and a bounded long run. Application analytics benchmarks
/// live under demo/modules/analytics/benchmark and are not framework gates. Add
/// `--full` to include the end-to-end generator fixture at 1x/10x/20x/30x.
/// Each child process owns its state so RSS samples are not mixed with the
/// orchestrator or a test runner. This is a trend/reporting tool, not a fixed
/// cross-platform performance assertion. Pass `--output=<path>` to persist the
/// final machine-readable report after every benchmark succeeds.
Future<void> main(List<String> arguments) async {
  final full = arguments.contains('--full');
  final outputPath = _outputPath(arguments);
  final root = _findWorkspaceRoot(Directory.current);
  final benchmarks = <_BenchmarkSpec>[
    const _BenchmarkSpec('runtime_scaling.dart'),
    const _BenchmarkSpec('runtime_concurrency.dart'),
    const _BenchmarkSpec('service_scaling.dart'),
    const _BenchmarkSpec(
      'runtime_long_run.dart',
      arguments: ['--cycles=1000', '--recreate-every=100'],
    ),
    if (full)
      const _BenchmarkSpec(
        'generator_full_scaling.dart',
        arguments: ['1', '10', '20', '30', '--convergence'],
      ),
  ];

  final report = <String, Object?>{
    'schemaVersion': 1,
    'suite': 'ccrouter-performance-regression',
    'full': full,
    'sdk': Platform.version,
    'platform': Platform.operatingSystem,
    'revision': _revision(root),
    'benchmarks': <Object?>[],
  };
  final results = report['benchmarks']! as List<Object?>;
  for (final benchmark in benchmarks) {
    final result = await _runBenchmark(root, benchmark);
    results.add(result);
    stdout.writeln(jsonEncode(result));
  }
  final encoded = jsonEncode(report);
  if (outputPath != null) {
    final output = File(outputPath);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
  }
  stdout.writeln(encoded);
}

String? _outputPath(List<String> arguments) {
  String? result;
  for (final argument in arguments) {
    if (argument == '--full') continue;
    if (!argument.startsWith('--output=')) {
      throw ArgumentError.value(argument, 'arguments', 'Unknown option.');
    }
    final value = argument.substring('--output='.length).trim();
    if (value.isEmpty || result != null) {
      throw ArgumentError.value(
        argument,
        'arguments',
        'Provide exactly one non-empty --output path.',
      );
    }
    result = value;
  }
  return result;
}

String _revision(Directory root) {
  final result = Process.runSync('git', [
    'rev-parse',
    'HEAD',
  ], workingDirectory: root.path);
  return result.exitCode == 0 ? '${result.stdout}'.trim() : 'unknown';
}

Future<Map<String, Object?>> _runBenchmark(
  Directory root,
  _BenchmarkSpec benchmark,
) async {
  final file = File(
    '${root.path}${Platform.pathSeparator}packages${Platform.pathSeparator}ccrouter_test${Platform.pathSeparator}benchmark${Platform.pathSeparator}${benchmark.fileName}',
  );
  final watch = Stopwatch()..start();
  final process = await Process.run(Platform.resolvedExecutable, [
    'run',
    file.path,
    ...benchmark.arguments,
  ], workingDirectory: root.path);
  watch.stop();
  if (process.exitCode != 0) {
    throw ProcessException(
      Platform.resolvedExecutable,
      ['run', file.path, ...benchmark.arguments],
      '${process.stdout}\n${process.stderr}',
      process.exitCode,
    );
  }
  final lines = '${process.stdout}'
      .trim()
      .split('\n')
      .where((line) => line.trim().startsWith('{'))
      .toList(growable: false);
  return <String, Object?>{
    'benchmark': benchmark.fileName,
    'wallMs': watch.elapsedMilliseconds,
    'results': [for (final line in lines) jsonDecode(line)],
  };
}

final class _BenchmarkSpec {
  const _BenchmarkSpec(this.fileName, {this.arguments = const []});

  final String fileName;
  final List<String> arguments;
}

Directory _findWorkspaceRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    final pubspec = File(
      '${current.path}${Platform.pathSeparator}pubspec.yaml',
    );
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
