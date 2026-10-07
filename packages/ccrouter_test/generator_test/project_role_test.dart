@TestOn('vm')
library;

// Project role resolution is generator-internal tooling behavior.
// ignore_for_file: implementation_imports

import 'dart:io';
import 'dart:convert';

import 'package:ccrouter_generator/src/project_context.dart';
import 'package:ccrouter_generator/src/project_role.dart';
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
      final fixture = _RoleFixture.create(
        dependencies: (item['dependencies']! as List).cast<String>(),
        projectType: item['projectType'] as String?,
        hostEnabled: item['hostEnabled'] as bool?,
      );
      addTearDown(fixture.dispose);
      if (item['invalid'] == true) {
        expect(
          fixture.resolve,
          throwsA(isA<CCProjectRoleException>()),
          reason: item['name'] as String,
        );
        continue;
      }
      final resolved = fixture.resolve();
      expect(resolved.role.name, item['role'], reason: item['name'] as String);
      expect(
        resolved.participation.name,
        item['participation'],
        reason: item['name'] as String,
      );
    }
  });

  test('Flutter app defaults to Host', () {
    final fixture = _RoleFixture.create(
      dependencies: const ['ccrouter'],
      projectType: 'app',
    );
    addTearDown(fixture.dispose);

    final resolved = fixture.resolve();

    expect(resolved.role, CCProjectRole.host);
    expect(resolved.participation, CCProjectParticipation.runtime);
    expect(resolved.explicitHostEnabled, isNull);
  });

  test('non-app Flutter project defaults to package-local', () {
    for (final projectType in const [
      'module',
      'package',
      'package_ffi',
      'plugin',
      'plugin_ffi',
      'unknown',
    ]) {
      final fixture = _RoleFixture.create(
        dependencies: const ['ccrouter'],
        projectType: projectType,
      );
      addTearDown(fixture.dispose);
      expect(
        fixture.resolve().role,
        CCProjectRole.package,
        reason: 'project_type=$projectType',
      );
    }
  });

  test('host.enabled overrides Flutter project type in both directions', () {
    final enabled = _RoleFixture.create(
      dependencies: const ['ccrouter'],
      projectType: 'module',
      hostEnabled: true,
    );
    final disabled = _RoleFixture.create(
      dependencies: const ['ccrouter'],
      projectType: 'app',
      hostEnabled: false,
    );
    addTearDown(enabled.dispose);
    addTearDown(disabled.dispose);

    expect(enabled.resolve().role, CCProjectRole.host);
    expect(disabled.resolve().role, CCProjectRole.package);
  });

  test('Pure Dart contracts Package is package-local', () {
    final fixture = _RoleFixture.create(
      dependencies: const ['ccrouter_contracts'],
    );
    addTearDown(fixture.dispose);

    final resolved = fixture.resolve();

    expect(resolved.role, CCProjectRole.package);
    expect(resolved.participation, CCProjectParticipation.contracts);
  });

  test('Workspace aggregator and unrelated Package are skipped', () {
    final fixture = _RoleFixture.create(dependencies: const []);
    addTearDown(fixture.dispose);

    expect(fixture.resolve().role, CCProjectRole.skip);
  });

  test('Host override requires a direct runtime dependency', () {
    final contracts = _RoleFixture.create(
      dependencies: const ['ccrouter_contracts'],
      hostEnabled: true,
    );
    final unrelated = _RoleFixture.create(
      dependencies: const [],
      hostEnabled: true,
    );
    addTearDown(contracts.dispose);
    addTearDown(unrelated.dispose);

    expect(contracts.resolve, throwsA(isA<CCProjectRoleException>()));
    expect(unrelated.resolve, throwsA(isA<CCProjectRoleException>()));
  });

  test('invalid host.enabled is rejected', () {
    final fixture = _RoleFixture.create(
      dependencies: const ['ccrouter'],
      rawConfiguration: 'host:\n  enabled: yes\n',
    );
    addTearDown(fixture.dispose);

    expect(fixture.resolve, throwsA(isA<CCProjectRoleException>()));
  });
}

Directory _workspaceRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (File(path.join(current.path, 'pubspec.yaml')).existsSync() &&
        Directory(
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

final class _RoleFixture {
  _RoleFixture(this.root);

  factory _RoleFixture.create({
    required List<String> dependencies,
    String? projectType,
    bool? hostEnabled,
    String? rawConfiguration,
  }) {
    final root = Directory.systemTemp.createTempSync('ccrouter_role_').absolute;
    File(path.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: role_fixture
environment:
  sdk: ^3.10.0
dependencies:
${dependencies.map((name) => '  $name: any').join('\n')}
''');
    if (projectType != null) {
      File(path.join(root.path, '.metadata')).writeAsStringSync('''
project_type: $projectType
''');
    }
    if (rawConfiguration != null) {
      File(
        path.join(root.path, 'ccrouter.yaml'),
      ).writeAsStringSync(rawConfiguration);
    } else if (hostEnabled != null) {
      File(path.join(root.path, 'ccrouter.yaml')).writeAsStringSync('''
host:
  enabled: $hostEnabled
''');
    }
    return _RoleFixture(root);
  }

  final Directory root;

  CCProjectRoleResolution resolve() =>
      CCProjectRoleResolver.resolve(CCProjectContext.resolve(root));

  void dispose() => root.deleteSync(recursive: true);
}
