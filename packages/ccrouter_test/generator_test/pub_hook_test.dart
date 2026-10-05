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
    expect(flutter.readAsStringSync(), contains('--watch=auto'));
    expect(flutter.readAsStringSync(), contains('--watch-lease'));
    expect(flutter.readAsStringSync(), contains('CCRouter watch starting'));
    expect(flutter.readAsStringSync(), contains('status.json'));
    expect(
      flutterBat.readAsStringSync(),
      contains('ccrouter_generator:ccrouter'),
    );
    expect(flutterBat.readAsStringSync(), contains('--watch=auto'));
    expect(flutterBat.readAsStringSync(), contains('CCRouter watch starting'));
    expect(flutterBat.readAsStringSync(), contains('status.json'));

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

  test('pub-hook run skips a Workspace aggregator', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'ccrouter_pub_hook_workspace_',
    );
    addTearDown(() => workspace.delete(recursive: true));
    File(path.join(workspace.path, 'pubspec.yaml')).writeAsStringSync('''
name: workspace_aggregator
publish_to: none
environment:
  sdk: ^3.10.0
workspace:
  - packages/host
''');
    Directory(path.join(workspace.path, '.dart_tool')).createSync();
    File(
      path.join(workspace.path, '.dart_tool', 'package_config.json'),
    ).writeAsStringSync('''{"configVersion":2,"packages":[
  {"name":"ccrouter","rootUri":"../ccrouter"},
  {"name":"ccrouter_generator","rootUri":"../ccrouter_generator"}
]}''');

    final result = await _run([
      'pub-hook',
      'run',
      '--project-root',
      workspace.path,
      '--pub-command',
      'get',
    ]);
    final output = '${result.stdout}\n${result.stderr}';

    expect(result.exitCode, 0, reason: output);
    expect(output, contains('Workspace aggregators are not Hosts'));
    expect(output, isNot(contains('post-pub generation started')));
  });

  test(
    'run and pub hooks emit concise phase-specific generation logs',
    () async {
      final demo = Directory(path.join(_workspaceRoot().path, 'demo'));
      final preflight = await _run([
        'pub-hook',
        'run',
        '--project-root',
        demo.path,
        '--pub-command',
        'run',
      ]);
      final preflightOutput = '${preflight.stdout}\n${preflight.stderr}';
      expect(preflight.exitCode, 0, reason: preflightOutput);
      expect(
        preflightOutput,
        contains('CCRouter preflight started for `flutter run`.'),
      );
      expect(preflightOutput, contains('CCRouter profile '));
      expect(preflightOutput, contains('CCRouter preflight finished:'));
      expect(preflightOutput, isNot(contains('CCRouter pub hook started')));
      expect(preflightOutput, isNot(contains('Generating Package artifacts')));
      expect(
        preflightOutput,
        isNot(contains('ccrouter_generator:service_contracts')),
      );

      final postPub = await _run([
        'pub-hook',
        'run',
        '--project-root',
        demo.path,
        '--pub-command',
        'get',
      ]);
      final postPubOutput = '${postPub.stdout}\n${postPub.stderr}';
      expect(postPub.exitCode, 0, reason: postPubOutput);
      expect(
        postPubOutput,
        contains('CCRouter post-pub generation started for `flutter pub get`.'),
      );
      expect(postPubOutput, contains('CCRouter post-pub generation finished:'));
      expect(postPubOutput, isNot(contains('Generating Package artifacts')));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('failed hook preserves actionable generator diagnostics', () async {
    final project = await Directory.systemTemp.createTemp(
      'ccrouter_pub_hook_failure_',
    );
    addTearDown(() => project.delete(recursive: true));
    File(path.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: invalid_ccrouter_host
environment:
  sdk: ^3.10.0
dependencies:
  ccrouter: any
dev_dependencies:
  ccrouter_generator: any
''');
    Directory(path.join(project.path, '.dart_tool')).createSync();
    File(
      path.join(project.path, '.dart_tool', 'package_config.json'),
    ).writeAsStringSync('''{"configVersion":2,"packages":[
  {"name":"ccrouter","rootUri":"../ccrouter"},
  {"name":"ccrouter_generator","rootUri":"../ccrouter_generator"}
]}''');

    final result = await _run([
      'pub-hook',
      'run',
      '--project-root',
      project.path,
      '--pub-command',
      'build',
    ]);
    final output = '${result.stdout}\n${result.stderr}';

    expect(result.exitCode, 1, reason: output);
    expect(output, contains('CCRouter preflight started'));
    expect(output, contains('CCRouter preflight failed'));
    expect(output, contains('Generator output:'));
    expect(output, isNot(contains('CCRouter pub hook finished')));
  });

  test('run and build execute a generation preflight before Flutter', () async {
    final sdk = await Directory.systemTemp.createTemp(
      'ccrouter_pub_hook_preflight_ sdk',
    );
    addTearDown(() => sdk.delete(recursive: true));
    final bin = Directory(path.join(sdk.path, 'bin'))..createSync();
    final trace = path.join(sdk.path, 'trace.txt');
    final flutter = File(path.join(bin.path, 'flutter'))
      ..writeAsStringSync('''#!/usr/bin/env bash
printf "flutter:%s\\n" "\$*" >> "\$CCROUTER_TRACE"
exit 0
''');
    final dart = File(path.join(bin.path, 'dart'))
      ..writeAsStringSync('''#!/usr/bin/env bash
printf "dart:%s\\n" "\$*" >> "\$CCROUTER_TRACE"
exit "\${CCROUTER_DART_EXIT:-0}"
''');
    await Process.run('chmod', ['+x', flutter.path, dart.path]);
    await _run(['pub-hook', 'install', '--sdk', sdk.path]);

    final project = Directory(path.join(sdk.path, 'project'))
      ..createSync(recursive: true);
    File(
      path.join(project.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: preflight_project\n');
    Directory(path.join(project.path, '.dart_tool')).createSync();
    File(
      path.join(project.path, '.dart_tool', 'package_config.json'),
    ).writeAsStringSync('''{"packages":[
  {"name":"ccrouter"},
  {"name":"ccrouter_generator"}
]}''');
    final environment = <String, String>{
      ...Platform.environment,
      'CCROUTER_TRACE': trace,
    };

    final run = await Process.run(
      flutter.path,
      ['--no-color', 'run', '-d', 'macos'],
      workingDirectory: project.path,
      environment: environment,
    );
    expect(run.exitCode, 0, reason: '${run.stderr}');
    expect('${run.stderr}', contains('CCRouter watch starting'));
    final runTrace = File(trace).readAsLinesSync();
    expect(
      runTrace.first,
      startsWith('dart:run --verbosity=error ccrouter_generator:ccrouter'),
    );
    expect(runTrace.last, 'flutter:--no-color run -d macos');

    File(trace).writeAsStringSync('');
    final failedDart = File(path.join(bin.path, 'dart'))
      ..writeAsStringSync('''#!/usr/bin/env bash
printf "dart:%s\\n" "\$*" >> "\$CCROUTER_TRACE"
exit 7
''');
    await Process.run('chmod', ['+x', failedDart.path]);
    final build = await Process.run(
      flutter.path,
      ['build', 'macos'],
      workingDirectory: project.path,
      environment: {...environment, 'CCROUTER_DART_EXIT': '7'},
    );
    expect(build.exitCode, 7);
    expect(File(trace).readAsLinesSync(), hasLength(1));
    expect(File(trace).readAsStringSync(), startsWith('dart:'));
  });
}

Future<ProcessResult> _run(List<String> arguments) => Process.run(
  Platform.resolvedExecutable,
  ['run', 'ccrouter_generator:ccrouter', ...arguments],
  workingDirectory: Directory.current.path,
);

Directory _workspaceRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (Directory(path.join(current.path, '.git')).existsSync()) return current;
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('CCRouter workspace root was not found.');
    }
    current = parent;
  }
}
