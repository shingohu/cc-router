@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'support/real_workspace_test_lock.dart';

void main() {
  serializeRealWorkspaceTests();

  test(
    'CLI rejects alternate internal imports before changing artifacts',
    () async {
      const targetUri =
          'package:demo_navigation_lab/src/ccrouter_generated/component/demo_navigation_lab_component.route_api.g.dart';
      final target = File(
        'demo/modules/navigation_lab/lib/src/ccrouter_generated/component/demo_navigation_lab_component.route_api.g.dart',
      ).absolute;
      final probe = File('demo/lib/_ccrouter_uri_boundary_probe.dart');
      final alias = Link('demo/lib/_ccrouter_uri_boundary_alias.dart');
      expect(target.existsSync(), isTrue);
      expect(probe.existsSync(), isFalse);
      expect(
        FileSystemEntity.typeSync(alias.path, followLinks: false),
        FileSystemEntityType.notFound,
      );
      addTearDown(() {
        if (probe.existsSync()) probe.deleteSync();
        if (alias.existsSync()) alias.deleteSync();
      });
      if (!Platform.isWindows) alias.createSync(target.path);
      final tracked = await Process.run('git', [
        'ls-files',
        '-z',
        '--',
        'demo',
      ]);
      expect(tracked.exitCode, 0);
      final before = {
        for (final name in tracked.stdout.toString().split('\u0000'))
          if (name.contains('/ccrouter_generated/') && File(name).existsSync())
            name: File(name).readAsBytesSync(),
      };
      expect(before, isNotEmpty);
      for (final uri in [
        targetUri,
        target.uri.toString(),
        '$targetUri?query',
        targetUri.replaceFirst(
          'ccrouter_generated',
          r'\u0063\u0063router_generated',
        ),
        if (!Platform.isWindows) path.basename(alias.path),
      ]) {
        probe.writeAsStringSync('''
import '$uri';
void probe() {
  // ignore: invalid_use_of_internal_member
  DemoNavigationLabRoutes.detail(id: 1);
}
''');
        final result = await Process.run(
          Platform.resolvedExecutable,
          [
            'run',
            '--verbosity=error',
            'ccrouter_generator:ccrouter',
            'generate',
            'demo',
            '--check',
          ],
          environment: {
            'FLUTTER_ROOT': File(
              Platform.resolvedExecutable,
            ).parent.parent.parent.parent.parent.path,
          },
        );
        expect(
          result.exitCode,
          1,
          reason: '$uri\n${result.stdout}\n${result.stderr}',
        );
        expect(
          '${result.stderr}',
          contains('ccrouter_demo:lib/_ccrouter_uri_boundary_probe.dart:1'),
        );
        expect('${result.stderr}', contains('public Contract or Host barrel'));
        for (final entry in before.entries) {
          expect(
            File(entry.key).readAsBytesSync(),
            entry.value,
            reason: entry.key,
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
