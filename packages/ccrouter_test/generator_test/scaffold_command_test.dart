@TestOn('vm')
library;

import 'dart:io';

import 'package:ccrouter_generator/src/project_context.dart';
import 'package:ccrouter_generator/src/project_role.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../ccrouter_generator/bin/src/scaffold.dart';

void main() {
  test(
    'create component and page emits a minimal non-overwriting template',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'ccrouter-scaffold-',
      );
      addTearDown(() => parent.delete(recursive: true));

      final component = await _run([
        'create',
        'component',
        'demo_inventory',
        parent.path,
      ]);
      expect(component.exitCode, 0, reason: '${component.stderr}');
      expect('${component.stdout}', contains('Next steps:'));
      expect(
        '${component.stdout}',
        contains('Add the new Package to the intended Host'),
      );
      expect('${component.stdout}', contains('flutter pub get'));

      final packageRoot = Directory(path.join(parent.path, 'demo_inventory'));
      expect(
        File(path.join(packageRoot.path, '.metadata')).readAsStringSync(),
        contains('project_type: package'),
      );
      expect(
        Directory(path.join(packageRoot.path, 'example')).existsSync(),
        isFalse,
      );
      final page = await _run([
        'create',
        'page',
        'InventoryPage',
        packageRoot.path,
      ]);
      expect(page.exitCode, 0, reason: '${page.stderr}');
      expect('${page.stdout}', contains('ccrouter generate <host-root>'));
      expect(
        '${page.stdout}',
        contains('stable generated Component API only after generation'),
      );

      final componentSource = File(
        path.join(
          packageRoot.path,
          'lib',
          'src',
          'demo_inventory_component.dart',
        ),
      );
      final pageSource = File(
        path.join(packageRoot.path, 'lib', 'src', 'inventory_page.dart'),
      );
      expect(componentSource.existsSync(), isTrue);
      expect(pageSource.existsSync(), isTrue);
      expect(
        componentSource.readAsStringSync(),
        contains("CCComponentId('demo_inventory')"),
      );
      expect(
        pageSource.readAsStringSync(),
        allOf(
          contains("id: 'demo_inventory.inventory'"),
          contains("CCPathPattern('/inventory')"),
          contains('class InventoryPage'),
        ),
      );

      final duplicate = await _run([
        'create',
        'page',
        'InventoryPage',
        packageRoot.path,
      ]);
      expect(duplicate.exitCode, isNot(0));
      expect('${duplicate.stderr}', contains('Refusing to overwrite'));
    },
  );

  test('create rejects invalid names before writing files', () async {
    final parent = await Directory.systemTemp.createTemp('ccrouter-scaffold-');
    addTearDown(() => parent.delete(recursive: true));

    final result = await _run([
      'create',
      'component',
      'Not-A-Dart-Package',
      parent.path,
    ]);
    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('Dart Package name'));
    expect(
      Directory(path.join(parent.path, 'not-a-dart-package')).existsSync(),
      isFalse,
    );
  });

  test('create component can atomically add a runnable example Host', () async {
    final parent = await Directory.systemTemp.createTemp('ccrouter-scaffold-');
    addTearDown(() => parent.delete(recursive: true));
    final framework = Directory(path.join(parent.path, 'framework'))
      ..createSync();
    final runtime = Directory(path.join(framework.path, 'ccrouter'))
      ..createSync();
    final generator = Directory(path.join(framework.path, 'generator'))
      ..createSync();
    File(path.join(runtime.path, 'pubspec.yaml')).writeAsStringSync('''
name: ccrouter
version: 0.1.0
environment:
  sdk: ^3.10.0
dependencies:
  flutter:
    sdk: flutter
''');
    File(path.join(runtime.path, 'lib', 'ccrouter.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('library;\n');
    File(path.join(generator.path, 'pubspec.yaml')).writeAsStringSync('''
name: ccrouter_generator
version: 0.1.0
environment:
  sdk: ^3.10.0
''');
    File(path.join(parent.path, 'pubspec.yaml')).writeAsStringSync('''
name: scaffold_owner
environment:
  sdk: ^3.10.0
dependencies:
  ccrouter:
    path: framework/ccrouter
dev_dependencies:
  ccrouter_generator:
    path: framework/generator
''');

    final result = await _run([
      'create',
      'component',
      'demo_inventory',
      parent.path,
      '--with-example',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final packageRoot = Directory(path.join(parent.path, 'demo_inventory'));
    final example = Directory(path.join(packageRoot.path, 'example'));
    expect(
      File(path.join(packageRoot.path, '.metadata')).readAsStringSync(),
      contains('project_type: package'),
    );
    expect(
      File(path.join(example.path, '.metadata')).readAsStringSync(),
      contains('project_type: app'),
    );
    expect(
      File(path.join(example.path, 'lib', 'main.dart')).existsSync(),
      isTrue,
    );
    final manifest = File(
      path.join(example.path, 'pubspec.yaml'),
    ).readAsStringSync();
    expect(manifest, contains('name: demo_inventory_example'));
    expect(manifest, contains('ccrouter:'));
    expect(manifest, contains('demo_inventory:'));
    expect(manifest, contains('path: ..'));
    expect(manifest, contains('ccrouter_generator:'));
    expect(
      '${result.stdout}',
      contains('generated example is a CCRouter Host'),
    );
    final pub = await Process.run(
      _flutterExecutable(),
      ['pub', 'get'],
      workingDirectory: example.path,
      environment: {...Platform.environment, 'CCROUTER_PUB_HOOK_DISABLE': '1'},
    );
    expect(pub.exitCode, 0, reason: '${pub.stdout}\n${pub.stderr}');
    expect(
      CCProjectRoleResolver.resolve(CCProjectContext.resolve(packageRoot)).role,
      CCProjectRole.package,
    );
    expect(
      CCProjectRoleResolver.resolve(CCProjectContext.resolve(example)).role,
      CCProjectRole.host,
    );
  });

  test('failed example creation publishes no partial component', () async {
    final parent = await Directory.systemTemp.createTemp('ccrouter-scaffold-');
    addTearDown(() => parent.delete(recursive: true));

    await expectLater(
      createScaffold(
        kind: CCScaffoldKind.component,
        name: 'demo_inventory',
        root: parent,
        withExample: true,
        processRunner:
            (executable, arguments, {workingDirectory, environment}) async =>
                ProcessResult(1, 1, '', 'injected flutter failure'),
      ),
      throwsA(
        isA<CCScaffoldException>().having(
          (error) => error.message,
          'message',
          contains('injected flutter failure'),
        ),
      ),
    );

    expect(
      Directory(path.join(parent.path, 'demo_inventory')).existsSync(),
      isFalse,
    );
    expect(
      parent.listSync().whereType<Directory>().where(
        (directory) => path.basename(directory.path).startsWith('.ccrouter-'),
      ),
      isEmpty,
    );
  });

  test('create component reports its exact workspace entry', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'ccrouter-scaffold-workspace-',
    );
    addTearDown(() => workspace.delete(recursive: true));
    File(path.join(workspace.path, 'pubspec.yaml')).writeAsStringSync('''
name: scaffold_workspace
environment:
  sdk: ^3.10.0
workspace:
  - existing
''');
    final modules = Directory(path.join(workspace.path, 'modules'))
      ..createSync();

    final result = await _run([
      'create',
      'component',
      'demo_inventory',
      modules.path,
      '--with-example',
    ]);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      '${result.stdout}',
      contains(
        'Add `modules/demo_inventory` to `${workspace.path}/pubspec.yaml`',
      ),
    );
    expect(
      '${result.stdout}',
      contains(
        'Add `modules/demo_inventory/example` to `${workspace.path}/pubspec.yaml`',
      ),
    );
    final exampleManifest = File(
      path.join(modules.path, 'demo_inventory', 'example', 'pubspec.yaml'),
    ).readAsStringSync();
    expect(exampleManifest, contains('resolution: workspace'));
    expect(exampleManifest, contains('demo_inventory: ^0.1.0'));
  });

  test('create component inherits resolved dependency sources', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'ccrouter-scaffold-sources-',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final modules = Directory(path.join(workspace.path, 'modules'))
      ..createSync();
    Directory(
      path.join(workspace.path, 'framework', 'ccrouter'),
    ).createSync(recursive: true);
    File(path.join(workspace.path, 'pubspec.yaml')).writeAsStringSync('''
name: scaffold_workspace
environment:
  sdk: ">=3.12.0 <4.0.0"
dependencies:
  ccrouter:
    path: framework/ccrouter
dev_dependencies:
  ccrouter_generator:
    git:
      url: https://example.com/cc-router.git
      ref: abcdef1234567890
      path: packages/ccrouter_generator
workspace:
  - existing
''');

    final result = await _run([
      'create',
      'component',
      'demo_inventory',
      modules.path,
    ]);
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    final manifest = File(
      path.join(modules.path, 'demo_inventory', 'pubspec.yaml'),
    ).readAsStringSync();

    expect(manifest, contains('sdk: >=3.12.0 <4.0.0'));
    expect(manifest, contains('path: ../../framework/ccrouter'));
    expect(manifest, contains('url: "https://example.com/cc-router.git"'));
    expect(manifest, contains('ref: abcdef1234567890'));
    expect(manifest, contains('path: packages/ccrouter_generator'));
  });

  test(
    'create capability templates emit valid annotation starting points',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'ccrouter-scaffold-',
      );
      addTearDown(() => parent.delete(recursive: true));

      final component = await _run([
        'create',
        'component',
        'demo_inventory',
        parent.path,
      ]);
      expect(component.exitCode, 0, reason: '${component.stderr}');
      final packageRoot = Directory(path.join(parent.path, 'demo_inventory'));

      for (final kind in ['service', 'command', 'event', 'init-task']) {
        final result = await _run([
          'create',
          kind,
          'Inventory',
          packageRoot.path,
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
      }

      final source = packageRoot
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => file.readAsStringSync())
          .join('\n');
      expect(source, isNot(contains('@CCServiceContract(')));
      expect(source, contains("@CCService(id: 'demo_inventory.inventory')"));
      expect(source, contains('@CCCommandContract('));
      expect(source, contains('@CCCommandHandler()'));
      expect(source, contains('@CCEventContract('));
      expect(source, isNot(contains('@CCEventSubscription()')));
      expect(source, contains('@CCInitTask('));
      expect(source, contains("id: 'demo_inventory.inventory',"));
      expect(source, isNot(contains('CCInitTaskContract(')));
      expect(source, contains('gate: CCInitTaskGate.appStarted'));
      expect(
        source,
        contains('failurePolicy: CCInitTaskFailurePolicy.optional'),
      );

      final duplicate = await _run([
        'create',
        'command',
        'Inventory',
        packageRoot.path,
      ]);
      expect(duplicate.exitCode, isNot(0));
      expect('${duplicate.stderr}', contains('Refusing to overwrite'));
    },
  );

  test(
    'create capability options add only explicitly requested glue',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'ccrouter-scaffold-',
      );
      addTearDown(() => parent.delete(recursive: true));

      final component = await _run([
        'create',
        'component',
        'demo_inventory',
        parent.path,
      ]);
      expect(component.exitCode, 0, reason: '${component.stderr}');
      final packageRoot = Directory(path.join(parent.path, 'demo_inventory'));

      final event = await _run([
        'create',
        'event',
        'Inventory',
        packageRoot.path,
        '--with-subscriber',
      ]);
      expect(event.exitCode, 0, reason: '${event.stderr}');
      expect(
        File(
          path.join(packageRoot.path, 'lib', 'src', 'inventory_event.dart'),
        ).readAsStringSync(),
        contains('@CCEventSubscription()'),
      );

      final task = await _run([
        'create',
        'init-task',
        'WarmCache',
        '--with-contract',
        packageRoot.path,
      ]);
      expect(task.exitCode, 0, reason: '${task.stderr}');
      final taskSource = File(
        path.join(packageRoot.path, 'lib', 'src', 'warm_cache_init_task.dart'),
      ).readAsStringSync();
      expect(taskSource, contains('CCInitTaskContract('));
      expect(taskSource, contains('contract: warmCacheInitTaskContract,'));

      final invalid = await _run([
        'create',
        'service',
        'Invalid',
        '--with-contract',
        packageRoot.path,
      ]);
      expect(invalid.exitCode, 2);
      expect('${invalid.stderr}', contains('only once for `create init-task`'));

      final invalidExample = await _run([
        'create',
        'page',
        'InvalidExample',
        packageRoot.path,
        '--with-example',
      ]);
      expect(invalidExample.exitCode, 2);
      expect(
        '${invalidExample.stderr}',
        contains('only once for `create component`'),
      );
    },
  );

  test('create reports an incomplete template command', () async {
    final result = await _run(['create', 'component']);
    expect(result.exitCode, 2);
    expect('${result.stderr}', contains('create requires'));
  });
}

Future<ProcessResult> _run(List<String> arguments) => Process.run(
  Platform.resolvedExecutable,
  ['run', 'ccrouter_generator:ccrouter', ...arguments],
  workingDirectory: Directory.current.path,
);

String _flutterExecutable() {
  final name = Platform.isWindows ? 'flutter.bat' : 'flutter';
  var sdkBin = File(Platform.resolvedExecutable).absolute.parent;
  for (var index = 0; index < 3; index++) {
    sdkBin = sdkBin.parent;
  }
  final paired = File(path.join(sdkBin.path, name));
  return paired.existsSync() ? paired.path : name;
}
