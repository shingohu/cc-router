import 'dart:io';

import 'package:ccrouter_analyzer_plugin/src/generator_diagnostics_bridge.dart';
import 'package:ccrouter_analyzer_plugin/src/project_context.dart';
import 'package:path/path.dart' as path;

/// Measures steady Analyzer watch polling across increasing Workspace sizes.
void main() {
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
