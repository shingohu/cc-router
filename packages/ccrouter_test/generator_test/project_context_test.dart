@TestOn('vm')
library;

// Project context resolution is generator-internal tooling behavior.
// ignore_for_file: implementation_imports

import 'dart:io';

import 'package:ccrouter_generator/src/project_context.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('separates a Workspace member request from its resolution root', () {
    final fixture = _ProjectContextFixture.workspace();
    addTearDown(fixture.dispose);

    final context = CCProjectContext.resolve(
      Directory(path.join(fixture.member.path, 'lib', 'src')),
    );

    expect(context.requestedRoot.path, fixture.member.path);
    expect(context.resolutionRoot.path, fixture.root.path);
    expect(context.isWorkspace, isTrue);
  });

  test('uses a valid Pub workspace reference before ancestor discovery', () {
    final fixture = _ProjectContextFixture.workspace();
    addTearDown(fixture.dispose);
    final unrelated = Directory(path.join(fixture.root.path, 'nested'))
      ..createSync();
    File(path.join(unrelated.path, 'pubspec.yaml')).writeAsStringSync('''
name: unrelated_parent
workspace:
  - ../member
''');
    final ref = File(
      path.join(fixture.member.path, '.dart_tool', 'pub', 'workspace_ref.json'),
    )..createSync(recursive: true);
    ref.writeAsStringSync('{"workspaceRoot":"../../.."}');

    final context = CCProjectContext.resolve(fixture.member);

    expect(context.resolutionRoot.path, fixture.root.path);
  });

  test('keeps a standalone Package independent below a Workspace', () {
    final fixture = _ProjectContextFixture.workspace();
    addTearDown(fixture.dispose);
    final standalone = Directory(path.join(fixture.root.path, 'standalone'))
      ..createSync();
    File(path.join(standalone.path, 'pubspec.yaml')).writeAsStringSync('''
name: standalone
environment:
  sdk: ^3.10.0
''');

    final context = CCProjectContext.resolve(standalone);

    expect(context.requestedRoot.path, standalone.path);
    expect(context.resolutionRoot.path, standalone.path);
    expect(context.isWorkspace, isFalse);
  });

  test('rejects a stale workspace reference instead of using another root', () {
    final fixture = _ProjectContextFixture.workspace();
    addTearDown(fixture.dispose);
    final ref = File(
      path.join(fixture.member.path, '.dart_tool', 'pub', 'workspace_ref.json'),
    )..createSync(recursive: true);
    ref.writeAsStringSync('{"workspaceRoot":"../../missing"}');

    expect(
      () => CCProjectContext.resolve(fixture.member),
      throwsA(isA<CCProjectContextException>()),
    );
  });
}

final class _ProjectContextFixture {
  _ProjectContextFixture(this.root, this.member);

  factory _ProjectContextFixture.workspace() {
    final root = Directory.systemTemp.createTempSync(
      'ccrouter_project_context_',
    );
    final member = Directory(path.join(root.path, 'member'))
      ..createSync(recursive: true);
    Directory(path.join(member.path, 'lib', 'src')).createSync(recursive: true);
    File(path.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: workspace_root
environment:
  sdk: ^3.10.0
workspace:
  - member
''');
    File(path.join(member.path, 'pubspec.yaml')).writeAsStringSync('''
name: member
resolution: workspace
environment:
  sdk: ^3.10.0
''');
    return _ProjectContextFixture(root.absolute, member.absolute);
  }

  final Directory root;
  final Directory member;

  void dispose() => root.deleteSync(recursive: true);
}
