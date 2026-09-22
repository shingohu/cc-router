@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ccrouter_generator/src/package_workspace.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('find merges contract and page sources across Package indexes', () async {
    final result = await _find(['order.detail', 'demo']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      '${result.stdout}',
      contains('Route order.detail (component: demo_order_component)'),
    );
    expect(
      '${result.stdout}',
      contains(
        'package:demo_order_contracts/src/order_detail_route_contract.dart:19:16',
      ),
    );
    expect(
      '${result.stdout}',
      contains('package:demo_order/src/order_detail_page.dart:'),
    );
    expect('${result.stdout}', contains('Pattern: /orders/:orderId (primary)'));
    expect(
      RegExp(r'Route order\.detail \(').allMatches('${result.stdout}'),
      hasLength(1),
    );
    expect('${result.stdout}', isNot(contains('Generating Package artifacts')));
  });

  test('find accepts exact alias and absolute-URI declarations', () async {
    final alias = await _find(['/order/:orderId', 'demo']);
    expect(alias.exitCode, 0, reason: '${alias.stderr}');
    expect('${alias.stdout}', contains('Route order.detail'));

    final uri = await _find([
      'https://ccrouter.example/lab/detail/:id',
      'demo',
    ]);
    expect(uri.exitCode, 0, reason: '${uri.stderr}');
    expect('${uri.stdout}', contains('Route demo_navigation_lab.detail'));
  });

  test('find is scoped to the selected Host dependency closure', () async {
    final missing = await _find(['web.public', 'demo/modules/order']);
    expect(missing.exitCode, 1);
    expect('${missing.stderr}', contains('No route matched'));

    final exact = await _find(['order.detail', 'demo/modules/order']);
    expect(exact.exitCode, 0, reason: '${exact.stderr}');
  });

  test('find rejects missing queries and generation flags', () async {
    final missing = await _find([]);
    expect(missing.exitCode, 2);
    expect('${missing.stderr}', contains('requires a Route ID'));

    final invalid = await _find(['order.detail', 'demo', '--check']);
    expect(invalid.exitCode, 2);
    expect('${invalid.stderr}', contains('find accepts only'));
  });

  test('find rejects missing and corrupted Package indexes', () async {
    final root = Directory.systemTemp.createTempSync('ccrouter_find_index_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(
      path.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: find_fixture\n');
    final tool = Directory(path.join(root.path, '.dart_tool'))
      ..createSync(recursive: true);
    File(path.join(tool.path, 'package_graph.json')).writeAsStringSync(
      jsonEncode({
        'packages': [
          {
            'name': 'find_fixture',
            'version': '1.0.0',
            'dependencies': <String>[],
            'devDependencies': <String>[],
          },
        ],
      }),
    );
    File(path.join(tool.path, 'package_config.json')).writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'find_fixture',
            'rootUri': '../',
            'packageUri': 'lib/',
            'languageVersion': '3.8',
          },
        ],
      }),
    );

    final missing = await _find(['fixture.page', root.path]);
    expect(missing.exitCode, 1);
    expect('${missing.stderr}', contains('Package index is missing'));

    final index = File(
      path.join(
        root.path,
        'lib',
        'src',
        'ccrouter_generated',
        'metadata',
        'ccrouter_package.json',
      ),
    )..createSync(recursive: true);
    index.writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'package': {'name': 'find_fixture', 'version': '1.0.0'},
        'contentFingerprint': 'invalid',
        'bundle': null,
        'dependencies': <Object>[],
        'metadata': <Object>[],
      }),
    );
    final corrupted = await _find(['fixture.page', root.path]);
    expect(corrupted.exitCode, 1);
    expect('${corrupted.stderr}', contains('fingerprint mismatch'));
  });

  test(
    'find rejects mixed dependency Index revisions without writing',
    () async {
      final root = Directory.systemTemp.createTempSync('ccrouter_find_mixed_');
      addTearDown(() => root.deleteSync(recursive: true));
      final child = Directory(path.join(root.path, 'child'))..createSync();
      File(
        path.join(root.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: find_host\n');
      File(
        path.join(child.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: find_child\n');
      final tool = Directory(path.join(root.path, '.dart_tool'))
        ..createSync(recursive: true);
      File(path.join(tool.path, 'package_graph.json')).writeAsStringSync(
        jsonEncode({
          'packages': [
            {
              'name': 'find_host',
              'version': '1.0.0',
              'dependencies': ['find_child'],
              'devDependencies': <String>[],
            },
            {
              'name': 'find_child',
              'version': '1.0.0',
              'dependencies': <String>[],
              'devDependencies': <String>[],
            },
          ],
        }),
      );
      File(path.join(tool.path, 'package_config.json')).writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'find_host',
              'rootUri': '../',
              'packageUri': 'lib/',
              'languageVersion': '3.8',
            },
            {
              'name': 'find_child',
              'rootUri': '../child/',
              'packageUri': 'lib/',
              'languageVersion': '3.8',
            },
          ],
        }),
      );
      final childIndex = _writeIndex(child, 'find_child');
      final hostIndex = _writeIndex(
        root,
        'find_host',
        dependencies: [
          CCPackageIndexDependency(
            name: 'find_child',
            version: childIndex.packageVersion,
            contentFingerprint: 'previous-generated-revision',
          ),
        ],
      );
      final before = hostIndex.toJson();
      final result = await _find(['anything', root.path]);
      expect(result.exitCode, 1);
      expect(
        '${result.stderr}',
        contains('references a different "find_child"'),
      );
      expect(
        File(
          path.join(
            root.path,
            'lib',
            'src',
            'ccrouter_generated',
            'metadata',
            'ccrouter_package.json',
          ),
        ).readAsStringSync(),
        before,
      );
      expect(
        File(
          path.join(
            root.path,
            '.dart_tool',
            'ccrouter',
            'v1',
            'generation.lock',
          ),
        ).existsSync(),
        isFalse,
      );
    },
  );
}

CCPackageIndex _writeIndex(
  Directory root,
  String name, {
  List<CCPackageIndexDependency> dependencies = const [],
}) {
  final index = CCPackageIndex(
    packageName: name,
    packageVersion: '1.0.0',
    contentFingerprint: computeCCPackageFingerprint(
      packageName: name,
      packageVersion: '1.0.0',
      bundleLibrary: null,
      bundleSymbol: null,
      dependencies: dependencies,
      metadata: const [],
    ),
    dependencies: dependencies,
    metadata: const [],
  );
  File(
      path.join(
        root.path,
        'lib',
        'src',
        'ccrouter_generated',
        'metadata',
        'ccrouter_package.json',
      ),
    )
    ..createSync(recursive: true)
    ..writeAsStringSync(index.toJson());
  return index;
}

Future<ProcessResult> _find(List<String> arguments) => Process.run(
  Platform.resolvedExecutable,
  ['run', 'ccrouter_generator:ccrouter', 'find', ...arguments],
  workingDirectory: _repositoryRoot().path,
);

Directory _repositoryRoot() {
  var directory = Directory.current.absolute;
  while (!File(
        path.join(directory.path, 'demo', 'pubspec.yaml'),
      ).existsSync() ||
      !Directory(
        path.join(directory.path, 'packages', 'ccrouter_generator'),
      ).existsSync()) {
    if (directory.parent.path == directory.path) {
      throw StateError('CCRouter repository root not found.');
    }
    directory = directory.parent;
  }
  return directory;
}
