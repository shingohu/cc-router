import 'dart:io';
import 'dart:convert';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';

import 'package:ccrouter_analyzer_plugin/src/package_context_cache.dart';
import 'package:ccrouter_analyzer_plugin/src/source_analyzer.dart';
import 'package:path/path.dart' as path;

/// Runs a repeatable edit-path benchmark without enforcing machine timings.
Future<void> main() async {
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
    await _semanticEdits(root, sourceFile);
  } finally {
    root.deleteSync(recursive: true);
  }
}

/// Separates SDK/session resolution cost from CCRouter's per-edit rule cost.
/// Uses the real Pure Dart contracts and never retains an AST between edits.
Future<void> _semanticEdits(Directory root, File sourceFile) async {
  final contracts = Directory('../ccrouter_contracts').absolute;
  final config = File(path.join(root.path, '.dart_tool/package_config.json'))
    ..createSync(recursive: true);
  config.writeAsStringSync(
    jsonEncode({
      'configVersion': 2,
      'packages': [
        {
          'name': 'analyzer_benchmark',
          'rootUri': '../',
          'packageUri': 'lib/',
          'languageVersion': '3.10',
        },
        {
          'name': 'ccrouter_contracts',
          'rootUri': contracts.uri.toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.10',
        },
      ],
    }),
  );
  final collection = AnalysisContextCollection(includedPaths: [root.path]);
  try {
    for (final count in [100, 1000, 3000]) {
      final source = StringBuffer()
        ..writeln(
          "import 'package:ccrouter_contracts/ccrouter_contracts.dart';",
        )
        ..writeln(
          "@CCService(id: 'bench') class Service { void dispose() {} }",
        );
      for (var i = 0; i < count; i++) {
        source.writeln('class Passive$i {}');
      }
      final resolution = <int>[];
      final rules = <int>[];
      for (var edit = 0; edit < 21; edit++) {
        final buffer = '$source\n// edit $edit';
        sourceFile.writeAsStringSync(buffer);
        final context = collection.contextFor(sourceFile.path);
        final watch = Stopwatch()..start();
        context.changeFile(sourceFile.path);
        await context.applyPendingFileChanges();
        final result =
            await context.currentSession.getResolvedUnit(sourceFile.path)
                as ResolvedUnitResult;
        final resolveUs = watch.elapsedMicroseconds;
        watch.reset();
        final analysis = CCRouterSourceAnalyzer.analyzeWithLineInfo(
          source: buffer,
          filePath: sourceFile.path,
          packageRoot: root.path,
          packageName: 'analyzer_benchmark',
          resolvedUnit: result.unit,
        );
        final rulesUs = watch.elapsedMicroseconds;
        if (analysis.diagnostics
                .where((d) => d.code == 'ccrouter_service_disposable_missing')
                .length !=
            1) {
          throw StateError('Semantic benchmark lost its expected diagnostic.');
        }
        if (edit == 0) {
          stdout.writeln(
            'CCRouter semantic declarations=$count firstResolve=${resolveUs}us firstRules=${rulesUs}us',
          );
        } else {
          resolution.add(resolveUs);
          rules.add(rulesUs);
        }
      }
      resolution.sort();
      rules.sort();
      stdout.writeln(
        'CCRouter semantic declarations=$count edits=20 resolveP50=${resolution[9]}us resolveP95=${resolution[18]}us rulesP50=${rules[9]}us rulesP95=${rules[18]}us',
      );
    }
  } finally {
    await collection.dispose();
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
