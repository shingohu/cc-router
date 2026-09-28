import 'dart:convert';
import 'dart:io';

/// Runs the repeatable Pure Dart performance and lifecycle regression suite.
///
/// The default suite covers Runtime scaling, concurrent navigation, Service
/// lookup/lifecycle, a bounded long run, and Analytics queue pressure. Add
/// `--full` to include the end-to-end generator fixture at 1x/10x/20x/30x.
/// Each child process owns its state so RSS samples are not mixed with the
/// orchestrator or a test runner. This is a trend/reporting tool, not a fixed
/// cross-platform performance assertion.
Future<void> main(List<String> arguments) async {
  final full = arguments.contains('--full');
  final root = _findWorkspaceRoot(Directory.current);
  final benchmarks = <_BenchmarkSpec>[
    const _BenchmarkSpec('runtime_scaling.dart'),
    const _BenchmarkSpec('runtime_concurrency.dart'),
    const _BenchmarkSpec('service_scaling.dart'),
    const _BenchmarkSpec(
      'runtime_long_run.dart',
      arguments: ['--cycles=1000', '--recreate-every=100'],
    ),
    const _BenchmarkSpec(
      'analytics_dispatcher.dart',
      arguments: ['--events=5000', '--capacity=64'],
    ),
    if (full)
      const _BenchmarkSpec(
        'generator_full_scaling.dart',
        arguments: ['1', '10', '20', '30', '--convergence'],
      ),
  ];

  final report = <String, Object?>{
    'suite': 'ccrouter-performance-regression',
    'full': full,
    'sdk': Platform.version,
    'platform': Platform.operatingSystem,
    'benchmarks': <Object?>[],
  };
  final results = report['benchmarks']! as List<Object?>;
  for (final benchmark in benchmarks) {
    final result = await _runBenchmark(root, benchmark);
    results.add(result);
    stdout.writeln(jsonEncode(result));
  }
  stdout.writeln(jsonEncode(report));
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
