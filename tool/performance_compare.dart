import 'dart:convert';
import 'dart:io';

const _defaultBudget = 0.30;

void main(List<String> arguments) {
  try {
    final options = _Options.parse(arguments);
    final baseline = _Report.read(options.baselinePath);
    final current = _Report.read(options.currentPath);
    final comparison = _compare(baseline, current, budget: options.budget);
    stdout.write(comparison.render());
  } on FormatException catch (error) {
    stderr.writeln('Performance comparison input error: ${error.message}');
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln('Performance comparison file error: ${error.message}');
    exitCode = 2;
  }
}

final class _Options {
  const _Options({
    required this.baselinePath,
    required this.currentPath,
    required this.budget,
  });

  final String baselinePath;
  final String currentPath;
  final double budget;

  static _Options parse(List<String> arguments) {
    if (arguments.length < 2) {
      throw const FormatException(
        'Usage: dart tool/performance_compare.dart '
        '<baseline.json> <current.json> [--max-regression=0.30]',
      );
    }
    var budget = _defaultBudget;
    for (final argument in arguments.skip(2)) {
      if (!argument.startsWith('--max-regression=')) {
        throw FormatException('Unknown option: $argument');
      }
      final raw = argument.substring('--max-regression='.length);
      final parsed = double.tryParse(raw);
      if (parsed == null || !parsed.isFinite || parsed < 0) {
        throw FormatException('Invalid relative regression budget: $raw');
      }
      budget = parsed;
    }
    return _Options(
      baselinePath: arguments[0],
      currentPath: arguments[1],
      budget: budget,
    );
  }
}

final class _Report {
  const _Report({
    required this.source,
    required this.full,
    required this.sdk,
    required this.platform,
    required this.revision,
    required this.wallMilliseconds,
  });

  final String source;
  final bool full;
  final String sdk;
  final String platform;
  final String revision;
  final Map<String, int> wallMilliseconds;

  static _Report read(String path) {
    final source = File(path).readAsStringSync();
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('$path is not valid JSON: ${error.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw FormatException('$path must contain a JSON object.');
    }
    if (decoded['schemaVersion'] != 1 ||
        decoded['suite'] != 'ccrouter-performance-regression') {
      throw FormatException('$path has an unsupported report schema.');
    }
    final full = decoded['full'];
    final sdk = decoded['sdk'];
    final platform = decoded['platform'];
    final revision = decoded['revision'];
    final benchmarks = decoded['benchmarks'];
    if (full is! bool ||
        sdk is! String ||
        platform is! String ||
        revision is! String ||
        benchmarks is! List<Object?>) {
      throw FormatException('$path is missing required report fields.');
    }
    final wallMilliseconds = <String, int>{};
    for (var index = 0; index < benchmarks.length; index++) {
      final benchmark = benchmarks[index];
      if (benchmark is! Map<String, Object?>) {
        throw FormatException('$path benchmark $index must be an object.');
      }
      final name = benchmark['benchmark'];
      final wallMs = benchmark['wallMs'];
      if (name is! String || name.isEmpty || wallMs is! int || wallMs <= 0) {
        throw FormatException(
          '$path benchmark $index requires a name and positive wallMs.',
        );
      }
      if (wallMilliseconds.containsKey(name)) {
        throw FormatException('$path contains duplicate benchmark $name.');
      }
      wallMilliseconds[name] = wallMs;
    }
    if (wallMilliseconds.isEmpty) {
      throw FormatException('$path contains no benchmarks.');
    }
    return _Report(
      source: path,
      full: full,
      sdk: sdk,
      platform: platform,
      revision: revision,
      wallMilliseconds: Map.unmodifiable(wallMilliseconds),
    );
  }
}

final class _Comparison {
  const _Comparison({
    required this.baseline,
    required this.current,
    required this.budget,
    required this.rows,
  });

  final _Report baseline;
  final _Report current;
  final double budget;
  final List<_ComparisonRow> rows;

  String render() {
    final buffer = StringBuffer()
      ..writeln('## Performance advisory')
      ..writeln()
      ..writeln(
        'Same-runner comparison on `${current.platform}` with a '
        '${(budget * 100).toStringAsFixed(0)}% relative wall-time budget.',
      )
      ..writeln()
      ..writeln('| Benchmark | Baseline | Current | Change | Result |')
      ..writeln('| --- | ---: | ---: | ---: | --- |');
    for (final row in rows) {
      buffer.writeln(
        '| `${row.name}` | ${row.baselineMs} ms | ${row.currentMs} ms | '
        '${_signedPercent(row.relativeChange)} | '
        '${row.regressed ? 'advisory' : 'within budget'} |',
      );
    }
    final regressions = rows.where((row) => row.regressed).length;
    buffer
      ..writeln()
      ..writeln(
        regressions == 0
            ? 'No relative wall-time regression exceeded the advisory budget.'
            : '$regressions benchmark(s) exceeded the advisory budget; '
                  'this phase does not block the build.',
      )
      ..writeln()
      ..writeln(
        'Baseline `${_shortRevision(baseline.revision)}`; '
        'current `${_shortRevision(current.revision)}`.',
      );
    return buffer.toString();
  }
}

final class _ComparisonRow {
  const _ComparisonRow({
    required this.name,
    required this.baselineMs,
    required this.currentMs,
    required this.relativeChange,
    required this.regressed,
  });

  final String name;
  final int baselineMs;
  final int currentMs;
  final double relativeChange;
  final bool regressed;
}

_Comparison _compare(
  _Report baseline,
  _Report current, {
  required double budget,
}) {
  if (baseline.platform != current.platform ||
      baseline.sdk != current.sdk ||
      baseline.full != current.full) {
    throw FormatException(
      'Reports must use the same platform, SDK, and suite mode. '
      'Baseline=${baseline.platform}/${baseline.sdk}/full=${baseline.full}; '
      'current=${current.platform}/${current.sdk}/full=${current.full}.',
    );
  }
  final baselineNames = baseline.wallMilliseconds.keys.toSet();
  final currentNames = current.wallMilliseconds.keys.toSet();
  if (baselineNames.length != currentNames.length ||
      !baselineNames.containsAll(currentNames)) {
    throw FormatException(
      'Reports contain different benchmark sets. '
      'Baseline=${baselineNames.toList()..sort()}; '
      'current=${currentNames.toList()..sort()}.',
    );
  }
  final names = baselineNames.toList()..sort();
  final rows = <_ComparisonRow>[];
  for (final name in names) {
    final baselineMs = baseline.wallMilliseconds[name]!;
    final currentMs = current.wallMilliseconds[name]!;
    final relativeChange = (currentMs - baselineMs) / baselineMs;
    rows.add(
      _ComparisonRow(
        name: name,
        baselineMs: baselineMs,
        currentMs: currentMs,
        relativeChange: relativeChange,
        regressed: relativeChange > budget,
      ),
    );
  }
  return _Comparison(
    baseline: baseline,
    current: current,
    budget: budget,
    rows: List.unmodifiable(rows),
  );
}

String _signedPercent(double value) {
  final prefix = value >= 0 ? '+' : '';
  return '$prefix${(value * 100).toStringAsFixed(1)}%';
}

String _shortRevision(String revision) =>
    revision.length <= 12 ? revision : revision.substring(0, 12);
