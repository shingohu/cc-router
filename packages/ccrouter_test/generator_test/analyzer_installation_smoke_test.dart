@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test(
    'real remote Git install, upgrade, doctor and uninstall in a temporary Flutter Host',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'ccrouter-analyzer-network-',
      );
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      void write(String relative, String content) {
        final file = File(path.join(root.path, relative));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(content);
      }

      // The fixture tests installation plumbing, not Runtime. Its minimal local
      // ccrouter dependency avoids requiring an unpublished framework release.
      write(
        'framework/pubspec.yaml',
        'name: ccrouter\nversion: 0.1.0\nenvironment:\n  sdk: ^3.10.0\n',
      );
      write('app/pubspec.yaml', '''name: smoke_host
environment:
  sdk: ^3.10.0
dependencies:
  flutter:
    sdk: flutter
  ccrouter:
    path: ../framework
''');
      write('app/.metadata', 'project_type: app\n');
      write('app/lib/main.dart', 'void main() {}\n');
      write(
        'app/analysis_options.yaml',
        '# retain application rules\nanalyzer:\n  errors:\n    unused_import: warning\n',
      );
      final app = path.join(root.path, 'app');
      Future<ProcessResult> run(List<String> args) async {
        final process = await Process.start(
          Platform.resolvedExecutable,
          [
            'run',
            '--verbosity=error',
            'ccrouter_generator:ccrouter',
            'analyzer',
            args.first,
            app,
            ...args.skip(1),
          ],
          environment: const {'CCROUTER_PUB_HOOK_DISABLE': '1'},
        );
        final output = process.stdout.transform(utf8.decoder).join();
        final errors = process.stderr.transform(utf8.decoder).join();
        try {
          final code = await process.exitCode.timeout(
            const Duration(minutes: 5),
          );
          final result = ProcessResult(
            process.pid,
            code,
            await output,
            await errors,
          );
          expect(code, 0, reason: '${result.stdout}\n${result.stderr}');
          return result;
        } finally {
          process.kill();
          await process.exitCode;
        }
      }

      const previous = '97c72daae65d0dd01e1ecd5263c647d6b213f814';
      const current = 'a275d1d46ddfdded6678ecbf1d2d23818cdbdfdc';
      final gitUrl =
          Platform.environment['CCROUTER_ANALYZER_GIT_URL'] ??
          'https://github.com/shingohu/cc-router.git';
      await run([
        'install',
        '--source',
        'git',
        '--url',
        gitUrl,
        '--ref',
        previous,
      ]);
      await run(['status']);
      final repeat = await run([
        'install',
        '--source',
        'git',
        '--url',
        gitUrl,
        '--ref',
        previous,
      ]);
      expect('${repeat.stdout}', contains('Already installed'));
      await run(['upgrade', '--ref', current]);
      await run(['doctor']);
      await run(['uninstall']);
      expect(
        File(path.join(app, 'analysis_options.yaml')).readAsStringSync(),
        contains('unused_import: warning'),
      );
      expect(
        Directory(
          path.join(app, 'tools', 'ccrouter_analyzer_host'),
        ).existsSync(),
        isFalse,
      );
    },
    skip: Platform.environment['CCROUTER_ANALYZER_NETWORK_SMOKE'] != '1'
        ? 'Opt in with CCROUTER_ANALYZER_NETWORK_SMOKE=1; requires remote Git/Pub and a Flutter SDK.'
        : false,
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
