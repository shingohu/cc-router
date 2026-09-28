@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

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

      final packageRoot = Directory(path.join(parent.path, 'demo_inventory'));
      final page = await _run([
        'create',
        'page',
        'InventoryPage',
        packageRoot.path,
      ]);
      expect(page.exitCode, 0, reason: '${page.stderr}');

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
      expect(source, contains('@CCServiceContract('));
      expect(source, contains('@CCService()'));
      expect(source, contains('@CCCommandContract('));
      expect(source, contains('@CCCommandHandler()'));
      expect(source, contains('@CCEventContract('));
      expect(source, contains('@CCEventSubscription()'));
      expect(source, contains('@CCInitTask(contract:'));

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
