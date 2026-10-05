@TestOn('vm')
@Timeout(Duration(minutes: 20))
library;

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'support/real_workspace_test_lock.dart';

void main() {
  serializeRealWorkspaceTests();

  test(
    'failed generation restores the previous managed source outputs',
    () async {
      final root = _workspaceRoot();
      final serviceSource = File(
        path.join(
          root.path,
          'demo',
          'modules',
          'order',
          'lib',
          'src',
          'order_summary_service.dart',
        ),
      );
      final originalSource = serviceSource.readAsBytesSync();
      final originalGenerated = _generatedSourceSnapshot(root);
      addTearDown(() {
        serviceSource.writeAsBytesSync(originalSource, flush: true);
      });

      final source = String.fromCharCodes(originalSource);
      const constructor = '  DemoOrderSummaryService();';
      expect(source, contains(constructor));
      serviceSource.writeAsStringSync(
        source.replaceFirst(
          constructor,
          '  DemoOrderSummaryService(this.requiredSeed);\n\n'
          '  final int requiredSeed;',
        ),
        flush: true,
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        '--packages=${path.join(root.path, '.dart_tool', 'package_config.json')}',
        path.join(
          root.path,
          'packages',
          'ccrouter_generator',
          'bin',
          'ccrouter.dart',
        ),
        'generate',
        'demo',
      ], workingDirectory: root.path);

      expect(result.exitCode, 1);
      expect('${result.stdout}\n${result.stderr}', contains('zero-argument'));
      final restoredGenerated = _generatedSourceSnapshot(root);
      expect(restoredGenerated.keys, unorderedEquals(originalGenerated.keys));
      for (final entry in originalGenerated.entries) {
        expect(
          restoredGenerated[entry.key],
          entry.value,
          reason: '${entry.key} changed after failed generation',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Map<String, List<int>> _generatedSourceSnapshot(Directory root) {
  final snapshot = <String, List<int>>{};
  void visit(Directory directory) {
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = path.basename(entity.path);
      if (name == '.git' ||
          name == '.dart_tool' ||
          name == 'build' ||
          name == 'Pods') {
        continue;
      }
      if (name == 'ccrouter_generated') {
        for (final generated in entity.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (generated is! File) continue;
          snapshot[path.relative(generated.path, from: root.path)] = generated
              .readAsBytesSync();
        }
        continue;
      }
      visit(entity);
    }
  }

  visit(root);
  return snapshot;
}

Directory _workspaceRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (Directory(path.join(current.path, '.git')).existsSync()) return current;
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('CCRouter workspace root was not found.');
    }
    current = parent;
  }
}
