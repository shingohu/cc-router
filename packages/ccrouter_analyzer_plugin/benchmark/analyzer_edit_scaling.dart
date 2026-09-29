import 'dart:io';

import 'package:ccrouter_analyzer_plugin/src/package_context_cache.dart';
import 'package:ccrouter_analyzer_plugin/src/source_analyzer.dart';
import 'package:path/path.dart' as path;

/// Runs a repeatable edit-path benchmark without enforcing machine timings.
void main() {
  final root = Directory.systemTemp.createTempSync('ccrouter-analyzer-bench-');
  try {
    File(
      path.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: analyzer_benchmark\n');
    final sourceFile = File(path.join(root.path, 'lib', 'src', 'routes.dart'))
      ..createSync(recursive: true);
    final cache = CCRouterPackageContextCache();

    final cases = <int, String>{
      for (final count in const [100, 1000, 3000]) count: _source(count),
    };
    for (final source in cases.values) {
      final context = cache.resolve(sourceFile.path)!;
      CCRouterSourceAnalyzer.analyzeWithLineInfo(
        source: source,
        filePath: sourceFile.path,
        packageRoot: context.root,
        packageName: context.name,
      );
    }
    for (final MapEntry(key: declarationCount, value: source)
        in cases.entries) {
      sourceFile.writeAsStringSync(source);
      final watch = Stopwatch()..start();
      for (var edit = 0; edit < 50; edit += 1) {
        final context = cache.resolve(sourceFile.path)!;
        CCRouterSourceAnalyzer.analyzeWithLineInfo(
          source: source,
          filePath: sourceFile.path,
          packageRoot: context.root,
          packageName: context.name,
        );
      }
      watch.stop();
      stdout.writeln(
        'CCRouter analyzer declarations=$declarationCount edits=50 '
        'total=${watch.elapsedMilliseconds}ms '
        'average=${(watch.elapsedMicroseconds / 50).round()}us',
      );
    }
  } finally {
    root.deleteSync(recursive: true);
  }
}

/// Builds a large but valid source buffer with one generated capability.
String _source(int declarationCount) {
  final out = StringBuffer()
    ..writeln("import 'package:ccrouter/ccrouter.dart';")
    ..writeln(
      "@CCRoute<void>(id: 'bench.route', pattern: CCPathPattern('/bench'))",
    )
    ..writeln('class BenchPage {}');
  for (var index = 0; index < declarationCount; index += 1) {
    out.writeln('class PassiveType$index { const PassiveType$index(); }');
  }
  return out.toString();
}
