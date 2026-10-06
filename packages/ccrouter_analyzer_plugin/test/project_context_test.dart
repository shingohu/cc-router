import 'dart:io';

import 'package:ccrouter_analyzer_plugin/src/project_context.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('project context cache reparses only after role inputs change', () {
    final root = Directory.systemTemp.createTempSync(
      'ccrouter-project-context-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final pubspec = File(path.join(root.path, 'pubspec.yaml'))
      ..writeAsStringSync('''
name: project_context_fixture
dependencies:
  ccrouter: any
''');
    final metadata = File(path.join(root.path, '.metadata'))
      ..writeAsStringSync('project_type: package\n');
    final cache = CCRouterAnalyzerProjectContextCache();

    final first = cache.observe(pubspec.path);
    final unchanged = cache.observe(pubspec.path);

    expect(first.inputChanged, isFalse);
    expect(first.context?.role, CCRouterAnalyzerProjectRole.package);
    expect(identical(first.context, unchanged.context), isTrue);
    expect(unchanged.inputChanged, isFalse);
    expect(cache.entryCount, 1);

    metadata.writeAsStringSync('project_type: app\n# changed\n');
    final changed = cache.observe(pubspec.path);

    expect(changed.inputChanged, isTrue);
    expect(changed.context?.role, CCRouterAnalyzerProjectRole.host);
    expect(identical(first.context, changed.context), isFalse);
  });

  test(
    'project context cache retains malformed configuration until change',
    () {
      final root = Directory.systemTemp.createTempSync(
        'ccrouter-project-context-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final pubspec = File(path.join(root.path, 'pubspec.yaml'))
        ..writeAsStringSync('name: invalid_fixture\ndependencies: [\n');
      final cache = CCRouterAnalyzerProjectContextCache();

      final first = cache.observe(pubspec.path);
      final unchanged = cache.observe(pubspec.path);

      expect(first.context, isNull);
      expect(unchanged.context, isNull);
      expect(unchanged.inputChanged, isFalse);
      expect(cache.entryCount, 1);

      pubspec.writeAsStringSync('name: valid_fixture\n# repaired\n');
      final repaired = cache.observe(pubspec.path);
      expect(repaired.inputChanged, isTrue);
      expect(repaired.context, isNotNull);
    },
  );
}
