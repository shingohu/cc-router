import 'dart:io';
import 'dart:convert';

import 'package:ccrouter_analyzer_plugin/src/project_context.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('matches the shared Generator and Analyzer role matrix', () {
    final cases =
        jsonDecode(
              File(
                path.join(
                  _workspaceRoot().path,
                  'tool',
                  'test_fixtures',
                  'project_role_cases.json',
                ),
              ).readAsStringSync(),
            )
            as List;
    for (final raw in cases.cast<Map>()) {
      final item = raw.cast<String, Object?>();
      final root = _writeRoleFixture(item);
      addTearDown(() => root.deleteSync(recursive: true));
      final resolved = CCRouterAnalyzerProjectContext.resolve(root.path);
      if (item['invalid'] == true) {
        expect(resolved, isNull, reason: item['name'] as String);
        continue;
      }
      expect(resolved?.role.name, item['role'], reason: item['name'] as String);
      expect(
        resolved?.participation.name,
        item['participation'],
        reason: item['name'] as String,
      );
    }
  });

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

  test('reports malformed and contradictory ccrouter configuration', () {
    final root = Directory.systemTemp.createTempSync(
      'ccrouter-project-context-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    File(path.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: configuration_fixture
dependencies:
  ccrouter_contracts: any
''');
    final configuration = File(path.join(root.path, 'ccrouter.yaml'));

    configuration.writeAsStringSync('host: [\n');
    expect(
      CCRouterAnalyzerProjectContext.configurationIssue(root.path)?.message,
      contains('Invalid ccrouter.yaml'),
    );

    configuration.writeAsStringSync('host:\n  enabled: yes\n');
    expect(
      CCRouterAnalyzerProjectContext.configurationIssue(root.path)?.message,
      contains('must be true or false'),
    );

    configuration.writeAsStringSync('host:\n  enabled: true\n');
    expect(
      CCRouterAnalyzerProjectContext.configurationIssue(root.path)?.message,
      contains('requires a direct `ccrouter` dependency'),
    );
  });
}

Directory _writeRoleFixture(Map<String, Object?> item) {
  final root = Directory.systemTemp.createTempSync('ccrouter-role-matrix-');
  final dependencies = (item['dependencies']! as List).cast<String>();
  File(path.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: analyzer_role_fixture
dependencies:
${dependencies.map((name) => '  $name: any').join('\n')}
''');
  if (item['projectType'] case final String projectType) {
    File(
      path.join(root.path, '.metadata'),
    ).writeAsStringSync('project_type: $projectType\n');
  }
  if (item['hostEnabled'] case final bool enabled) {
    File(
      path.join(root.path, 'ccrouter.yaml'),
    ).writeAsStringSync('host:\n  enabled: $enabled\n');
  }
  return root;
}

Directory _workspaceRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (Directory(
      path.join(current.path, 'tool', 'test_fixtures'),
    ).existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (path.equals(parent.path, current.path)) {
      throw StateError('Workspace test fixtures were not found.');
    }
    current = parent;
  }
}
