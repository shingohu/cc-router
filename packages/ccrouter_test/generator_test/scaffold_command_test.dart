@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ccrouter_generator/src/project_context.dart';
import 'package:ccrouter_generator/src/project_role.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

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

  test(
    'YAML scalar round trips preserve SDK ranges and Git ref strings',
    () async {
      for (final ref in ['000123', 'on', '*', 'true']) {
        final parent = await Directory.systemTemp.createTemp(
          'ccrouter-scaffold-scalar-',
        );
        addTearDown(() => parent.delete(recursive: true));
        File(path.join(parent.path, 'pubspec.yaml')).writeAsStringSync('''
name: scaffold_invoker
environment:
  sdk: ">=3.10.0 <4.0.0"
dependencies:
  ccrouter: ^0.1.0
dev_dependencies:
  ccrouter_generator:
    git:
      url: https://example.com/framework.git
      ref: ${jsonEncode(ref)}
      path: packages/ccrouter_generator
''');
        await createScaffold(
          kind: CCScaffoldKind.component,
          name: 'feature',
          root: parent,
        );
        final generated =
            loadYaml(
                  File(
                    path.join(parent.path, 'feature/pubspec.yaml'),
                  ).readAsStringSync(),
                )
                as YamlMap;
        expect(generated['environment']['sdk'], '>=3.10.0 <4.0.0');
        expect(
          generated['dev_dependencies']['ccrouter_generator']['git']['ref'],
          ref,
        );
      }
    },
  );

  test(
    'example inherits build_runner from the same staged component snapshot',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'ccrouter-scaffold-snapshot-',
      );
      addTearDown(() => parent.delete(recursive: true));
      final ownerManifest = File(path.join(parent.path, 'pubspec.yaml'));
      const original = '''
name: scaffold_invoker
environment:
  sdk: ^3.10.0
dependencies:
  ccrouter: ^0.1.0
dev_dependencies:
  ccrouter_generator: ^0.1.0
  build_runner: ^2.10.0
''';
      ownerManifest.writeAsStringSync(original);
      await createScaffold(
        kind: CCScaffoldKind.component,
        name: 'feature',
        root: parent,
        withExample: true,
        processRunner:
            (executable, arguments, {workingDirectory, environment}) async {
              final example = Directory(arguments.last)
                ..createSync(recursive: true);
              File(path.join(example.path, 'pubspec.yaml')).writeAsStringSync(
                '''
name: feature_example
environment:
  sdk: ^3.10.0
dependencies:
  flutter:
    sdk: flutter
''',
              );
              ownerManifest.writeAsStringSync(
                original.replaceFirst('^2.10.0', '^2.11.0'),
              );
              return ProcessResult(0, 0, '', '');
            },
      );
      for (final relative in ['feature', 'feature/example']) {
        final generated =
            loadYaml(
                  File(
                    path.join(parent.path, relative, 'pubspec.yaml'),
                  ).readAsStringSync(),
                )
                as YamlMap;
        expect(
          generated['dev_dependencies']['build_runner'],
          '^2.10.0',
          reason: relative,
        );
      }
    },
  );

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
    expect(manifest, contains('build_runner:'));
    expect(
      File(path.join(packageRoot.path, 'pubspec.yaml')).readAsStringSync(),
      contains('build_runner:'),
    );
    expect(
      File(path.join(packageRoot.path, 'ccrouter.yaml')).readAsStringSync(),
      contains('portable: true'),
    );
    expect('${result.stdout}', contains('ccrouter portable prepare'));
    final mainSource = File(
      path.join(example.path, 'lib/main.dart'),
    ).readAsStringSync();
    expect(mainSource, contains('CCRouterHost.initialize'));
    expect(mainSource, contains('CCManagedRouterApp('));
    expect(mainSource, contains('ccrouter_host.api.g.dart'));
    expect(
      File(
        path.join(example.path, 'lib/src/example_component.dart'),
      ).readAsStringSync(),
      contains("CCComponentId('demo_inventory_example')"),
    );
    expect(
      File(
        path.join(example.path, 'lib/src/example_home_page.dart'),
      ).readAsStringSync(),
      contains("CCPathPattern('/')"),
    );
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
    expect(
      File(
        path.join(modules.path, 'demo_inventory', 'ccrouter.yaml'),
      ).existsSync(),
      isFalse,
    );
  });

  test(
    'example fails before publishing when build tool source is unknown',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'ccrouter-scaffold-no-tool-',
      );
      addTearDown(() => parent.delete(recursive: true));
      File(path.join(parent.path, 'pubspec.yaml')).writeAsStringSync('''
name: scaffold_invoker
environment:
  sdk: ^3.10.0
dependencies:
  ccrouter: ^0.1.0
dev_dependencies:
  ccrouter_generator: ^0.1.0
''');
      final result = await Process.run(Platform.resolvedExecutable, [
        '--packages=${path.absolute('.dart_tool/package_config.json')}',
        path.absolute('packages/ccrouter_generator/bin/ccrouter.dart'),
        'create',
        'component',
        'feature',
        parent.path,
        '--with-example',
      ], workingDirectory: parent.path);
      expect(result.exitCode, isNot(0));
      expect(
        '${result.stderr}',
        contains('Cannot prove dependency source for build_runner'),
      );
      expect(parent.listSync().whereType<Directory>(), isEmpty);
    },
  );

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
  build_runner:
    path: framework/build_runner
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
      '--with-example',
    ]);
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    final manifest = File(
      path.join(modules.path, 'demo_inventory', 'pubspec.yaml'),
    ).readAsStringSync();

    expect(
      (loadYaml(manifest) as YamlMap)['environment']['sdk'],
      '>=3.12.0 <4.0.0',
    );
    expect(manifest, contains('path: ../../framework/ccrouter'));
    expect(manifest, contains('url: "https://example.com/cc-router.git"'));
    expect(manifest, contains('ref: abcdef1234567890'));
    expect(manifest, contains('path: packages/ccrouter_generator'));
    expect(manifest, contains('path: ../../framework/build_runner'));
    final exampleManifest = File(
      path.join(modules.path, 'demo_inventory/example/pubspec.yaml'),
    ).readAsStringSync();
    expect(exampleManifest, contains('path: ../../../framework/build_runner'));
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
