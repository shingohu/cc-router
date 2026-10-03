@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test(
    'custom catalogs are compared and restored in docs and build',
    () async {
      for (final parent in ['demo/docs', 'build']) {
        final output = Directory(parent).createTempSync('ccrouter-check-');
        addTearDown(() => output.deleteSync(recursive: true));
        final unknown = File(path.join(output.path, 'notes.txt'))
          ..writeAsStringSync('owned by user');
        final fresh = await _generate(output);
        expect(fresh.exitCode, 1, reason: '${fresh.stdout}\n${fresh.stderr}');
        expect('${fresh.stderr}', contains('generated artifacts are stale'));
        expect(
          File(path.join(output.path, 'cc_routes.json')).existsSync(),
          false,
        );
        expect(
          File(path.join(output.path, 'cc_catalog.md')).existsSync(),
          false,
        );
        expect(unknown.readAsStringSync(), 'owned by user');

        final originals = {
          'cc_routes.json': '{"original":true}',
          'cc_catalog.md': 'original catalog',
          'cc_routes.md': '# CCRouter old routes\n',
          'cc_sources.md': '# CCRouter old sources\n',
        };
        for (final entry in originals.entries) {
          File(
            path.join(output.path, entry.key),
          ).writeAsStringSync(entry.value);
        }
        final existing = await _generate(output);
        expect(existing.exitCode, 1);
        expect('${existing.stderr}', contains('modified:'));
        expect('${existing.stderr}', contains('removed:'));
        for (final entry in originals.entries) {
          expect(
            File(path.join(output.path, entry.key)).readAsStringSync(),
            entry.value,
          );
        }
        expect(unknown.readAsStringSync(), 'owned by user');
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'custom catalog write failure restores earlier writes',
    () async {
      final output = Directory(
        'build',
      ).createTempSync('ccrouter-check-failure-');
      addTearDown(() => output.deleteSync(recursive: true));
      final original = File(path.join(output.path, 'cc_routes.json'))
        ..writeAsStringSync('original bytes');
      Directory(path.join(output.path, 'cc_catalog.md')).createSync();
      final failed = await _generate(output, check: false);
      expect(failed.exitCode, isNot(0));
      expect(original.readAsStringSync(), 'original bytes');
      expect(
        Directory(path.join(output.path, 'cc_catalog.md')).existsSync(),
        true,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<ProcessResult> _generate(Directory output, {bool check = true}) =>
    Process.run(Platform.resolvedExecutable, [
      'run',
      '--verbosity=error',
      'ccrouter_generator:ccrouter',
      'generate',
      'demo',
      if (check) '--check',
      '--output-dir',
      output.absolute.path,
      '--profile',
    ], workingDirectory: Directory.current.path);
