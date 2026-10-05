@TestOn('vm')
@Timeout(Duration(minutes: 20))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'support/real_workspace_test_lock.dart';

void main() {
  serializeRealWorkspaceTests();

  test(
    'Host Catalog descriptions round-trip as compiled Dart literals',
    () async {
      final root = Directory.current.path;
      final source = File(
        path.join(root, 'demo/modules/navigation_lab/lib/src/stack_page.dart'),
      );
      final original = source.readAsStringSync();
      const before = '交互验证 Push、Replace、Pop、Go 与 Reset。';
      const description =
          'Price \$currency \${literal} quote" slash\\ newline\n中文';
      expect(original, contains("description: '$before'"));
      final temporary = Directory.systemTemp.createTempSync(
        'ccrouter-catalog-literal-',
      );
      Future<ProcessResult> generate() => Process.run(
        Platform.resolvedExecutable,
        ['run', 'ccrouter_generator:ccrouter', 'generate', 'demo'],
        workingDirectory: root,
      );
      addTearDown(() async {
        source.writeAsStringSync(original);
        final restored = await generate();
        expect(
          restored.exitCode,
          0,
          reason: '${restored.stdout}\n${restored.stderr}',
        );
        temporary.deleteSync(recursive: true);
      });
      source.writeAsStringSync(
        original.replaceFirst(
          "description: '$before'",
          'description: ${jsonEncode(description).replaceAll(r'$', r'\$')}',
        ),
      );
      final generated = await generate();
      expect(
        generated.exitCode,
        0,
        reason: '${generated.stdout}\n${generated.stderr}',
      );
      final host = File(
        path.join(
          root,
          'demo/lib/src/ccrouter_generated/host/ccrouter_host.routes.g.dart',
        ),
      ).readAsStringSync();
      final catalog = host.substring(
        host.indexOf('final ccrouterGeneratedDevToolsCatalog ='),
        host.indexOf('/// Validated generated Package graph'),
      );
      final program = File(path.join(temporary.path, 'main.dart'));
      program.writeAsStringSync('''
import 'package:ccrouter_devtools_protocol/ccrouter_devtools_protocol.dart';
$catalog
void main() {
  final record = ccrouterGeneratedDevToolsCatalog.records.singleWhere((r) => r.id == 'demo_navigation_lab.stack');
  if (record.description != ${jsonEncode(description).replaceAll(r'$', r'\$')}) {
    throw StateError('Description changed');
  }
}
''');
      final compiled = await Process.run(Platform.resolvedExecutable, [
        '--packages=${path.join(root, '.dart_tool/package_config.json')}',
        program.path,
      ]);
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
