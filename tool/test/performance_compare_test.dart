import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync(
      'ccrouter-performance-compare-',
    );
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  Future<ProcessResult> compare(
    Map<String, Object?> baseline,
    Map<String, Object?> current,
  ) async {
    final baselineFile = File('${temporary.path}/baseline.json')
      ..writeAsStringSync(jsonEncode(baseline));
    final currentFile = File('${temporary.path}/current.json')
      ..writeAsStringSync(jsonEncode(current));
    return Process.run(Platform.resolvedExecutable, [
      'tool/performance_compare.dart',
      baselineFile.path,
      currentFile.path,
      '--max-regression=0.30',
    ]);
  }

  test('reports relative regressions as non-blocking advisories', () async {
    final result = await compare(_report(100), _report(131));

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}', contains('+31.0%'));
    expect('${result.stdout}', contains('1 benchmark(s) exceeded'));
    expect('${result.stdout}', contains('does not block the build'));
  });

  test('accepts a result at the relative budget boundary', () async {
    final result = await compare(_report(100), _report(130));

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}', contains('within budget'));
    expect('${result.stdout}', contains('No relative wall-time regression'));
  });

  test('rejects reports from different execution environments', () async {
    final current = _report(100)..['platform'] = 'macos';
    final result = await compare(_report(100), current);

    expect(result.exitCode, 2);
    expect('${result.stderr}', contains('same platform, SDK, and suite mode'));
  });

  test('rejects duplicate benchmark identities', () async {
    final baseline = _report(100);
    final benchmarks = baseline['benchmarks']! as List<Object?>;
    benchmarks.add({'benchmark': 'runtime.dart', 'wallMs': 200});
    final result = await compare(baseline, _report(100));

    expect(result.exitCode, 2);
    expect('${result.stderr}', contains('duplicate benchmark'));
  });
}

Map<String, Object?> _report(int wallMs) => {
  'schemaVersion': 1,
  'suite': 'ccrouter-performance-regression',
  'full': false,
  'sdk': '3.11.5',
  'platform': 'linux',
  'revision': '0123456789abcdef',
  'benchmarks': [
    {'benchmark': 'runtime.dart', 'wallMs': wallMs, 'results': <Object?>[]},
  ],
};
