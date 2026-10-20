@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ccrouter_generator/src/package_workspace.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test(
    'find ignores legacy framework indexes without changing files',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'ccrouter_find_framework_',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final framework = Directory(path.join(root.path, 'framework'))
        ..createSync();
      final packages = {'find_host': root, 'ccrouter_ui': framework};
      for (final entry in packages.entries) {
        File(
          path.join(entry.value.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: ${entry.key}\n');
      }
      final tool = Directory(path.join(root.path, '.dart_tool'))..createSync();
      File(path.join(tool.path, 'package_graph.json')).writeAsStringSync(
        jsonEncode({
          'packages': [
            for (final name in packages.keys)
              {
                'name': name,
                'version': '1.0.0',
                'dependencies': name == 'find_host' ? ['ccrouter_ui'] : [],
                'devDependencies': [],
              },
          ],
        }),
      );
      File(path.join(tool.path, 'package_config.json')).writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            for (final entry in packages.entries)
              {
                'name': entry.key,
                'rootUri': entry.value.uri.toString(),
                'packageUri': 'lib/',
                'languageVersion': '3.8',
              },
          ],
        }),
      );
      final hostIndex = _writeIndex(root, 'find_host');
      _writeIndex(framework, 'ccrouter_ui');
      final legacy = File(
        path.join(
          framework.path,
          'lib/src/ccrouter_generated/metadata/ccrouter_package.json',
        ),
      );
      for (final contents in [legacy.readAsStringSync(), '{obsolete index']) {
        legacy.writeAsStringSync(contents);
        final result = await _find(['anything', root.path]);
        expect(result.exitCode, 1);
        expect('${result.stderr}', contains('No capability matched'));
        expect(legacy.readAsStringSync(), contents);
        expect(
          File(
            path.join(
              root.path,
              'lib/src/ccrouter_generated/metadata/ccrouter_package.json',
            ),
          ).readAsStringSync(),
          hostIndex.toJson(),
        );
      }
    },
  );

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
        'package:demo_order_contracts/src/order_detail_route_contract.dart:16:16',
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

  test('find locates a generated InitTask by stable capability ID', () async {
    final result = await _find(['demo.startup.foundation', 'demo']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      '${result.stdout}',
      contains(
        'InitTask demo.startup.foundation '
        '(component: demo_navigation_lab_component)',
      ),
    );
    expect(
      '${result.stdout}',
      contains(
        'package:demo_navigation_lab/src/navigation_lab_component_registrar.dart:',
      ),
    );
    expect('${result.stdout}', contains('Generated initTaskRegistration:'));
  });

  test('find usage reports satisfied and missing typed dependencies', () async {
    final service = await _find([
      'demo_order.summary',
      'demo',
      '--usage',
      'demo_payment_component',
    ]);
    expect(service.exitCode, 0, reason: '${service.stderr}');
    expect(
      '${service.stdout}',
      contains('Usage recipe for component demo_payment_component'),
    );
    expect(
      '${service.stdout}',
      contains(
        'Public import: package:demo_order_contracts/demo_order_contracts.dart',
      ),
    );
    expect('${service.stdout}', contains('Pub dependency: satisfied'));
    expect('${service.stdout}', contains('Owner dependency: satisfied'));
    expect('${service.stdout}', contains('Service dependency: satisfied'));
    expect(
      '${service.stdout}',
      contains('Generated Client: DemoPaymentServices.orderSummary'),
    );

    final command = await _find([
      'demo_order.reserve',
      'demo',
      '--usage=demo_payment_component',
    ]);
    expect(command.exitCode, 0, reason: '${command.stderr}');
    expect('${command.stdout}', contains('Command dependency: missing'));
    expect(
      '${command.stdout}',
      contains(
        'Add to commandDependencies: '
        'CCCommandDependency<ReserveOrderCommand>()',
      ),
    );
    expect(
      '${command.stdout}',
      contains('Generated Client: DemoPaymentCommands.reserve'),
    );
  });

  test(
    'find usage does not invent a dependency for the capability owner',
    () async {
      final result = await _find([
        'demo_order.summary',
        'demo',
        '--usage',
        'demo_order_component',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        '${result.stdout}',
        contains(
          'Owner dependency: not applicable '
          '(consumer owns the capability)',
        ),
      );
      expect(
        '${result.stdout}',
        contains('Use local lookup: CCRouter.service<OrderSummaryService>()'),
      );
      expect('${result.stdout}', isNot(contains('Add to serviceDependencies')));
    },
  );

  test('find usage respects Route and internal Contract boundaries', () async {
    final route = await _find([
      'order.detail',
      'demo',
      '--usage',
      'demo_payment_component',
    ]);
    expect(route.exitCode, 0, reason: '${route.stderr}');
    expect(
      '${route.stdout}',
      contains(
        'Public import: package:demo_order_contracts/demo_order_contracts.dart',
      ),
    );
    expect('${route.stdout}', isNot(contains('demo_order_contracts_owner')));
    expect(
      '${route.stdout}',
      contains('Owner dependency: not required for a Route Contract'),
    );
    expect(
      '${route.stdout}',
      contains(
        'Typed call: CCRouter.navigator.push<String>('
        'OrderDetailRoute.intent(...))',
      ),
    );

    final event = await _find([
      'demo_navigation_lab.order_completed',
      'demo',
      '--usage',
      'demo_payment_component',
    ]);
    expect(event.exitCode, 0, reason: '${event.stderr}');
    expect('${event.stdout}', contains('Public import: unavailable'));
    expect('${event.stdout}', contains('Cross-component usage: unavailable'));
    expect('${event.stdout}', isNot(contains('Owner dependency: missing')));
  });

  test(
    'find usage rejects an unknown consumer without writing indexes',
    () async {
      final indexes = <File, List<int>>{};
      await for (final entity in Directory(
        'demo',
      ).list(recursive: true, followLinks: false)) {
        if (entity is File && entity.path.endsWith('ccrouter_package.json')) {
          indexes[entity] = entity.readAsBytesSync();
        }
      }
      final result = await _find([
        'demo_order.summary',
        'demo',
        '--usage',
        'missing_component',
      ]);
      expect(result.exitCode, 1);
      expect('${result.stderr}', contains('was not found'));
      for (final entry in indexes.entries) {
        expect(entry.key.readAsBytesSync(), entry.value);
      }
    },
  );

  test('find is scoped to the selected Host dependency closure', () async {
    final missing = await _find(['web.public', 'demo/modules/order']);
    expect(missing.exitCode, 1);
    expect('${missing.stderr}', contains('No capability matched'));

    final exact = await _find(['order.detail', 'demo/modules/order']);
    expect(exact.exitCode, 0, reason: '${exact.stderr}');
  });

  test('find rejects missing queries and generation flags', () async {
    final missing = await _find([]);
    expect(missing.exitCode, 2);
    expect('${missing.stderr}', contains('requires a capability ID'));

    final invalid = await _find(['order.detail', 'demo', '--check']);
    expect(invalid.exitCode, 2);
    expect('${invalid.stderr}', contains('find accepts only'));

    final missingUsage = await _find(['order.detail', '--usage']);
    expect(missingUsage.exitCode, 2);
    expect('${missingUsage.stderr}', contains('Missing value for --usage'));

    final wrongCommand = await _run([
      'clean',
      'demo',
      '--usage',
      'demo_payment_component',
    ]);
    expect(wrongCommand.exitCode, 2);
    expect(
      '${wrongCommand.stderr}',
      contains('--usage is only available with the find command'),
    );
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

Future<ProcessResult> _find(List<String> arguments) =>
    _run(['find', ...arguments]);

Future<ProcessResult> _run(List<String> arguments) => Process.run(
  Platform.resolvedExecutable,
  ['run', 'ccrouter_generator:ccrouter', ...arguments],
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
