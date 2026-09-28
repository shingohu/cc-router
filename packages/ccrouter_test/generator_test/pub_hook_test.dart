@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('pub-hook install, status, and uninstall are reversible', () async {
    final sdk = await Directory.systemTemp.createTemp('ccrouter_pub_hook_sdk_');
    addTearDown(() => sdk.delete(recursive: true));
    final bin = Directory(path.join(sdk.path, 'bin'))..createSync();
    final argsFile = path.join(sdk.path, 'args.txt');
    final flutter = File(path.join(bin.path, 'flutter'))
      ..writeAsStringSync(
        '#!/usr/bin/env bash\nprintf "%s" "\$*" > "$argsFile"\nexit 0\n',
      );
    final flutterBat = File(path.join(bin.path, 'flutter.bat'))
      ..writeAsStringSync('@echo off\r\nexit /b 0\r\n');

    final installed = await _run(['pub-hook', 'install', '--sdk', sdk.path]);
    expect(installed.exitCode, 0, reason: '${installed.stderr}');
    expect(
      File(path.join(bin.path, 'flutter.ccrouter-original')).existsSync(),
      isTrue,
    );
    expect(
      File(path.join(bin.path, 'flutter.ccrouter-original.bat')).existsSync(),
      isTrue,
    );
    expect(flutter.readAsStringSync(), contains('ccrouter_generator:ccrouter'));
    expect(
      flutterBat.readAsStringSync(),
      contains('ccrouter_generator:ccrouter'),
    );

    final status = await _run(['pub-hook', 'status', '--sdk', sdk.path]);
    expect(status.exitCode, 0, reason: '${status.stderr}');
    expect('${status.stdout}', contains('installed'));

    final removed = await _run(['pub-hook', 'uninstall', '--sdk', sdk.path]);
    expect(removed.exitCode, 0, reason: '${removed.stderr}');
    expect(flutter.existsSync(), isTrue);
    expect(flutter.readAsStringSync(), contains('exit 0'));
    expect(flutterBat.existsSync(), isTrue);
    expect(
      File(path.join(bin.path, '.ccrouter_pub_hook.json')).existsSync(),
      isFalse,
    );
  });

  test(
    'installed wrapper preserves successful pub exit and skips plain projects',
    () async {
      final sdk = await Directory.systemTemp.createTemp(
        'ccrouter_pub_hook_run_',
      );
      addTearDown(() => sdk.delete(recursive: true));
      final bin = Directory(path.join(sdk.path, 'bin'))..createSync();
      final argsFile = path.join(sdk.path, 'args.txt');
      final flutter = File(path.join(bin.path, 'flutter'))
        ..writeAsStringSync(
          '#!/usr/bin/env bash\nprintf "%s" "\$*" > "$argsFile"\nexit 0\n',
        );
      final flutterBat = File(path.join(bin.path, 'flutter.bat'))
        ..writeAsStringSync('@echo off\r\nexit /b 0\r\n');
      await Process.run('chmod', ['+x', flutter.path]);
      await _run(['pub-hook', 'install', '--sdk', sdk.path]);

      final project = Directory(path.join(sdk.path, 'project'))..createSync();
      File(
        path.join(project.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: plain_project\n');
      final result = await Process.run(flutter.path, [
        'pub',
        'get',
      ], workingDirectory: project.path);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        File(path.join(sdk.path, 'args.txt')).readAsStringSync(),
        'pub get',
      );
      expect('${result.stdout}', isNot(contains('CCRouter pub hook started')));

      final removed = await _run(['pub-hook', 'uninstall', '--sdk', sdk.path]);
      expect(removed.exitCode, 0, reason: '${removed.stderr}');
      expect(flutterBat.existsSync(), isTrue);
    },
  );

  test(
    'pub-hook run skips a project without resolved CCRouter packages',
    () async {
      final project = await Directory.systemTemp.createTemp(
        'ccrouter_pub_hook_project_',
      );
      addTearDown(() => project.delete(recursive: true));
      File(
        path.join(project.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: plain_project\n');
      Directory(path.join(project.path, '.dart_tool')).createSync();
      File(
        path.join(project.path, '.dart_tool', 'package_config.json'),
      ).writeAsStringSync('{"packages": []}');

      final result = await _run([
        'pub-hook',
        'run',
        '--project-root',
        project.path,
        '--pub-command',
        'get',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}', contains('does not use CCRouter'));
    },
  );
}

Future<ProcessResult> _run(List<String> arguments) => Process.run(
  Platform.resolvedExecutable,
  ['run', 'ccrouter_generator:ccrouter', ...arguments],
  workingDirectory: Directory.current.path,
);
