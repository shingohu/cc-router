@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../ccrouter_generator/bin/src/coordination_home.dart';
import '../../ccrouter_generator/bin/src/pub_hook.dart';
import '../../ccrouter_generator/bin/src/pub_hook_watch_coordination.dart';
import 'support/real_workspace_test_lock.dart';

late Directory _testCoordinationHome;

void main() {
  serializeRealWorkspaceTests();

  setUpAll(() async {
    _testCoordinationHome = await Directory.systemTemp.createTemp(
      'ccrouter_pub_hook_coordination_',
    );
  });
  tearDownAll(() async {
    if (_testCoordinationHome.existsSync()) {
      await _testCoordinationHome.delete(recursive: true);
    }
  });

  test('failure rendering removes routine Builder progress after success', () {
    final lines = ccPubHookConciseFailureLines(const [
      (line: 'Generating Package artifacts for host...', isError: false),
      (
        line: '  0s ccrouter_generator:routes on 3 inputs: 3 skipped',
        isError: false,
      ),
      (
        line: '  Built with build_runner/aot in 1s; wrote 0 outputs.',
        isError: false,
      ),
      (
        line: 'error [ccrouter_host_component_owner_missing]: missing owner',
        isError: true,
      ),
      (line: '  fix: Restore its Package.', isError: true),
    ]);

    expect(lines, [
      '  Built with build_runner/aot in 1s; wrote 0 outputs.',
      'error [ccrouter_host_component_owner_missing]: missing owner',
      '  fix: Restore its Package.',
    ]);
  });

  test(
    'failure rendering preserves complete output before Builder success',
    () {
      final lines = ccPubHookConciseFailureLines(const [
        (line: 'Generating Package artifacts for host...', isError: false),
        (line: '  0s ccrouter_generator:routes on 3 inputs', isError: false),
        (line: 'Build failed.', isError: true),
      ]);

      expect(lines, [
        'Generating Package artifacts for host...',
        '  0s ccrouter_generator:routes on 3 inputs',
        'Build failed.',
      ]);
    },
  );

  test(
    'pub-hook install preserves an entrypoint when its rename fails',
    () async {
      final sdk = await Directory.systemTemp.createTemp(
        'ccrouter_pub_hook_rename_failure_',
      );
      addTearDown(() => sdk.delete(recursive: true));
      final bin = Directory(path.join(sdk.path, 'bin'))..createSync();
      final flutter = File(path.join(bin.path, 'flutter'))
        ..writeAsStringSync('#!/usr/bin/env bash\nexit 0\n');
      final originalBytes = flutter.readAsBytesSync();
      File(
        path.join(bin.path, 'flutter.bat'),
      ).writeAsStringSync('@echo off\r\nexit /b 0\r\n');
      File(
        path.join(bin.path, 'dart.bat'),
      ).writeAsStringSync('@echo off\r\nexit /b 0\r\n');
      await _writeFakeInnerDart(sdk, '#!/usr/bin/env bash\nexit 0\n');
      Directory(path.join(bin.path, 'flutter.ccrouter-original')).createSync();

      final installed = await _run(['pub-hook', 'install', '--sdk', sdk.path]);

      expect(installed.exitCode, 1);
      expect(flutter.existsSync(), isTrue);
      expect(flutter.readAsBytesSync(), originalBytes);
      expect(
        File(path.join(bin.path, '.ccrouter_pub_hook.json')).existsSync(),
        isFalse,
      );
    },
  );

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
    final dartBat = File(path.join(bin.path, 'dart.bat'))
      ..writeAsStringSync('@echo off\r\nexit /b 0\r\n');
    final innerDart = await _writeFakeInnerDart(
      sdk,
      '#!/usr/bin/env bash\nexit 0\n',
    );

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
    expect(
      File(path.join(bin.path, 'dart.ccrouter-original.bat')).existsSync(),
      isTrue,
    );
    expect(File('${innerDart.path}.ccrouter-original').existsSync(), isTrue);
    expect(
      innerDart.readAsStringSync(),
      allOf(
        contains('CCRouter Dart pub hook wrapper'),
        contains('CCROUTER_PUB_HOOK_NESTED_FLUTTER'),
        contains('--packages="\$PACKAGE_CONFIG"'),
      ),
    );
    expect(
      dartBat.readAsStringSync(),
      allOf(
        contains('CCRouter Dart pub hook wrapper'),
        contains('dart:%PUB_COMMAND%'),
        contains('CCROUTER_PUB_HOOK_NESTED_FLUTTER'),
        contains(':resolve_project_root'),
        contains('--directory='),
        contains('pushd "%PROJECT_ROOT%"'),
        contains(':parse_dart_invocation'),
      ),
    );
    expect(dartBat.readAsStringSync(), contains(':parse_pub_invocation'));
    expect(
      dartBat.readAsStringSync(),
      contains('--packages="%PACKAGE_CONFIG%"'),
    );
    expect(
      flutter.readAsStringSync(),
      allOf(
        contains('ccrouter_generator:ccrouter'),
        contains('CCROUTER_PUB_HOOK_NESTED_FLUTTER=1'),
        contains('--packages="\$PACKAGE_CONFIG"'),
      ),
    );
    expect(flutter.readAsStringSync(), contains('--launch-watch'));
    expect(
      flutter.readAsStringSync(),
      contains('ccrouter_generator:ccrouter_flutter_run_supervisor'),
    );
    expect(flutter.readAsStringSync(), contains('--reload-gate'));
    expect(
      flutterBat.readAsStringSync(),
      allOf(
        contains('ccrouter_generator:ccrouter'),
        contains('CCROUTER_PUB_HOOK_NESTED_FLUTTER=1'),
        contains(':resolve_project_root'),
        contains('--directory='),
        contains('pushd "%PROJECT_ROOT%"'),
        contains('ccrouter_generator:ccrouter_flutter_run_supervisor'),
        contains(':parse_flutter_invocation'),
      ),
    );
    expect(
      flutterBat.readAsStringSync(),
      contains('--packages="%PACKAGE_CONFIG%"'),
    );
    expect(flutterBat.readAsStringSync(), contains('--device-id'));
    expect(
      flutterBat.readAsStringSync(),
      contains('CCROUTER_DISABLE_WINDOWS_RUN_SUPERVISOR'),
    );
    expect(flutterBat.readAsStringSync(), contains('--watch=auto'));
    expect(flutterBat.readAsStringSync(), contains('CCRouter watch starting'));
    expect(flutterBat.readAsStringSync(), contains('status.json'));
    expect(
      flutterBat.readAsStringSync(),
      contains('ccrouter_generator:ccrouter_flutter_run_gate'),
    );
    expect(
      flutterBat.readAsStringSync(),
      contains('ccrouter_generator:ccrouter_watch_startup'),
    );

    final status = await _run(['pub-hook', 'status', '--sdk', sdk.path]);
    expect(status.exitCode, 0, reason: '${status.stderr}');
    expect('${status.stdout}', contains('installed'));
    expect('${status.stdout}', contains('clean guard: enabled'));
    expect('${status.stdout}', contains('machine reload gate: enabled'));
    expect('${status.stdout}', contains('watch startup handshake: enabled'));
    expect('${status.stdout}', contains('run supervisor: enabled'));
    expect('${status.stdout}', contains('dart pub post-hook: enabled'));

    final removed = await _run(['pub-hook', 'uninstall', '--sdk', sdk.path]);
    expect(removed.exitCode, 0, reason: '${removed.stderr}');
    expect(flutter.existsSync(), isTrue);
    expect(flutter.readAsStringSync(), contains('exit 0'));
    expect(innerDart.readAsStringSync(), contains('exit 0'));
    expect(dartBat.readAsStringSync(), contains('exit /b 0'));
    expect(flutterBat.existsSync(), isTrue);
    expect(
      File(path.join(bin.path, '.ccrouter_pub_hook.json')).existsSync(),
      isFalse,
    );
  });

  test(
    'pub-hook uninstall safely restores a verified schema 4 install',
    () async {
      final sdk = await Directory.systemTemp.createTemp(
        'ccrouter_pub_hook_legacy_',
      );
      addTearDown(() => sdk.delete(recursive: true));
      final bin = Directory(path.join(sdk.path, 'bin'))..createSync();
      final flutter = File(path.join(bin.path, 'flutter'))
        ..writeAsStringSync('#!/usr/bin/env bash\nexit 0\n');
      File(
        path.join(bin.path, 'flutter.bat'),
      ).writeAsStringSync('@echo off\r\nexit /b 0\r\n');
      final innerDart = await _writeFakeInnerDart(
        sdk,
        '#!/usr/bin/env bash\nexit 0\n',
      );
      final installed = await _run(['pub-hook', 'install', '--sdk', sdk.path]);
      expect(installed.exitCode, 0, reason: '${installed.stderr}');

      await innerDart.delete();
      await File('${innerDart.path}.ccrouter-original').rename(innerDart.path);
      File(path.join(bin.path, '.ccrouter_pub_hook.json')).writeAsStringSync(
        jsonEncode(<String, Object>{
          'schema': 4,
          'entrypoint': 'flutter',
          'generator': 'ccrouter_generator',
        }),
      );

      final status = await _run(['pub-hook', 'status', '--sdk', sdk.path]);
      expect(status.exitCode, 1);
      final removed = await _run(['pub-hook', 'uninstall', '--sdk', sdk.path]);
      expect(removed.exitCode, 0, reason: '${removed.stderr}');
      expect(flutter.readAsStringSync(), contains('exit 0'));
      expect(innerDart.readAsStringSync(), contains('exit 0'));
    },
  );

  test('schema 5 install is stale but remains safely uninstallable', () async {
    final sdk = await Directory.systemTemp.createTemp(
      'ccrouter_pub_hook_schema_5_',
    );
    addTearDown(() => sdk.delete(recursive: true));
    final bin = Directory(path.join(sdk.path, 'bin'))..createSync();
    final flutter = File(path.join(bin.path, 'flutter'))
      ..writeAsStringSync('#!/usr/bin/env bash\nexit 0\n');
    File(
      path.join(bin.path, 'flutter.bat'),
    ).writeAsStringSync('@echo off\r\nexit /b 0\r\n');
    final innerDart = await _writeFakeInnerDart(
      sdk,
      '#!/usr/bin/env bash\nexit 0\n',
    );
    final installed = await _run(['pub-hook', 'install', '--sdk', sdk.path]);
    expect(installed.exitCode, 0, reason: '${installed.stderr}');

    File(path.join(bin.path, '.ccrouter_pub_hook.json')).writeAsStringSync(
      jsonEncode(<String, Object>{
        'schema': 5,
        'entrypoints': <String>['flutter', 'dart'],
        'generator': 'ccrouter_generator',
      }),
    );

    final status = await _run(['pub-hook', 'status', '--sdk', sdk.path]);
    expect(status.exitCode, 1);
    final removed = await _run(['pub-hook', 'uninstall', '--sdk', sdk.path]);
    expect(removed.exitCode, 0, reason: '${removed.stderr}');
    expect(flutter.readAsStringSync(), contains('exit 0'));
    expect(innerDart.readAsStringSync(), contains('exit 0'));
  });

  test('schema 4 uninstall rejects unowned Dart backups', () async {
    final sdk = await Directory.systemTemp.createTemp(
      'ccrouter_pub_hook_legacy_conflict_',
    );
    addTearDown(() => sdk.delete(recursive: true));
    final bin = Directory(path.join(sdk.path, 'bin'))..createSync();
    final flutter = File(path.join(bin.path, 'flutter'))
      ..writeAsStringSync('#!/usr/bin/env bash\nexit 0\n');
    File(
      path.join(bin.path, 'flutter.bat'),
    ).writeAsStringSync('@echo off\r\nexit /b 0\r\n');
    final innerDart = await _writeFakeInnerDart(
      sdk,
      '#!/usr/bin/env bash\nexit 0\n',
    );
    final installed = await _run(['pub-hook', 'install', '--sdk', sdk.path]);
    expect(installed.exitCode, 0, reason: '${installed.stderr}');
    File(path.join(bin.path, '.ccrouter_pub_hook.json')).writeAsStringSync(
      jsonEncode(<String, Object>{
        'schema': 4,
        'entrypoint': 'flutter',
        'generator': 'ccrouter_generator',
      }),
    );

    final removed = await _run(['pub-hook', 'uninstall', '--sdk', sdk.path]);

    expect(removed.exitCode, 1);
    expect('${removed.stderr}', contains('unexpectedly has Dart backups'));
    expect(flutter.readAsStringSync(), contains('CCRouter pub hook wrapper'));
    expect(
      innerDart.readAsStringSync(),
      contains('CCRouter Dart pub hook wrapper'),
    );
    expect(File('${innerDart.path}.ccrouter-original').existsSync(), isTrue);
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
      await _writeFakeInnerDart(sdk, '#!/usr/bin/env bash\nexit 0\n');
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
    'installed wrapper never runs generation for help or dry-run Pub calls',
    () async {
      final sdk = await Directory.systemTemp.createTemp(
        'ccrouter_pub_hook_read_only_',
      );
      addTearDown(() => sdk.delete(recursive: true));
      final bin = Directory(path.join(sdk.path, 'bin'))..createSync();
      final argsFile = path.join(sdk.path, 'args.txt');
      final flutter = File(path.join(bin.path, 'flutter'))
        ..writeAsStringSync(
          '#!/usr/bin/env bash\nprintf "%s" "\$*" > "$argsFile"\nexit 0\n',
        );
      File(
        path.join(bin.path, 'flutter.bat'),
      ).writeAsStringSync('@echo off\r\nexit /b 0\r\n');
      await _writeFakeInnerDart(sdk, '#!/usr/bin/env bash\nexit 0\n');
      await Process.run('chmod', ['+x', flutter.path]);
      final installed = await _run(['pub-hook', 'install', '--sdk', sdk.path]);
      expect(installed.exitCode, 0, reason: '${installed.stderr}');

      final project = Directory(path.join(sdk.path, 'project'))..createSync();
      File(path.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: ccrouter_project
dependencies:
  ccrouter: any
dev_dependencies:
  ccrouter_generator: any
''');
      Directory(path.join(project.path, '.dart_tool')).createSync();
      File(
        path.join(project.path, '.dart_tool', 'package_config.json'),
      ).writeAsStringSync('''{"configVersion":2,"packages":[
  {"name":"ccrouter_generator","rootUri":"../missing_generator"}
]}''');

      for (final arguments in const <List<String>>[
        ['pub', 'get', '--help'],
        ['pub', 'get', '-h'],
        ['pub', 'get', '--dry-run'],
        ['pub', 'get', '-n'],
      ]) {
        final result = await Process.run(
          flutter.path,
          arguments,
          workingDirectory: project.path,
        );
        expect(
          result.exitCode,
          0,
          reason: 'arguments=$arguments stderr=${result.stderr}',
        );
        expect(
          File(path.join(sdk.path, 'args.txt')).readAsStringSync(),
          arguments.join(' '),
        );
        expect('${result.stdout}${result.stderr}', isNot(contains('CCRouter')));
      }
    },
  );

  test('Flutter wrapper locates only the real top-level command', () async {
    final sdk = await Directory.systemTemp.createTemp(
      'ccrouter_flutter_command_parser_',
    );
    addTearDown(() => sdk.delete(recursive: true));
    final bin = Directory(path.join(sdk.path, 'bin'))..createSync();
    final trace = path.join(sdk.path, 'command-trace.txt');
    final flutter = File(path.join(bin.path, 'flutter'))
      ..writeAsStringSync('''#!/usr/bin/env bash
printf "flutter:%s\\n" "\$*" >> "\$CCROUTER_TRACE"
exit 0
''');
    final dart = File(path.join(bin.path, 'dart'))
      ..writeAsStringSync('''#!/usr/bin/env bash
printf "dart:%s\\n" "\$*" >> "\$CCROUTER_TRACE"
exit "\${CCROUTER_FAKE_DART_EXIT:-0}"
''');
    File(
      path.join(bin.path, 'flutter.bat'),
    ).writeAsStringSync('@echo off\r\nexit /b 0\r\n');
    await _writeFakeInnerDart(sdk, '#!/usr/bin/env bash\nexit 0\n');
    await Process.run('chmod', ['+x', flutter.path, dart.path]);
    final installed = await _run(['pub-hook', 'install', '--sdk', sdk.path]);
    expect(installed.exitCode, 0, reason: '${installed.stderr}');

    final project = Directory(path.join(sdk.path, 'project'))..createSync();
    File(path.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: flutter_command_parser
dependencies:
  ccrouter: any
dev_dependencies:
  ccrouter_generator: any
''');
    Directory(path.join(project.path, '.dart_tool')).createSync();
    File(
      path.join(project.path, '.dart_tool', 'package_config.json'),
    ).writeAsStringSync('''{"configVersion":2,"packages":[
  {"name":"ccrouter_generator","rootUri":"../missing_generator"}
]}''');
    final environment = <String, String>{
      ...Platform.environment,
      'CCROUTER_TRACE': trace,
    };

    for (final arguments in const <List<String>>[
      ['create', 'run', 'build', 'pub', 'get'],
      ['--help', 'run'],
      ['--future-global-option', 'pub', 'get'],
    ]) {
      File(trace).writeAsStringSync('');
      final result = await Process.run(
        flutter.path,
        arguments,
        workingDirectory: project.path,
        environment: environment,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(File(trace).readAsLinesSync(), ['flutter:${arguments.join(' ')}']);
    }

    for (final arguments in const <List<String>>[
      ['-d', 'run', 'pub', 'get'],
      ['--packages', 'run', 'pub', 'get'],
      ['--no-color', 'pub', 'add', 'run'],
    ]) {
      File(trace).writeAsStringSync('');
      final result = await Process.run(
        flutter.path,
        arguments,
        workingDirectory: project.path,
        environment: environment,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final lines = File(trace).readAsLinesSync();
      expect(lines.first, 'flutter:${arguments.join(' ')}');
      expect(lines, hasLength(2));
      expect(lines.last, contains('ccrouter_generator:ccrouter pub-hook run'));
    }

    File(trace).writeAsStringSync('');
    final clean = await Process.run(
      flutter.path,
      const ['clean'],
      workingDirectory: project.path,
      environment: environment,
    );
    expect(clean.exitCode, 0, reason: '${clean.stderr}');
    expect(File(trace).readAsLinesSync(), [
      contains('ccrouter_generator:ccrouter pub-hook guard-clean'),
      'flutter:clean',
    ]);

    File(trace).writeAsStringSync('');
    final blocked = await Process.run(
      flutter.path,
      const ['clean'],
      workingDirectory: project.path,
      environment: {...environment, 'CCROUTER_FAKE_DART_EXIT': '23'},
    );
    expect(blocked.exitCode, 23);
    expect(
      '${blocked.stderr}',
      contains('CCRouter clean guard blocked flutter clean'),
    );
    expect(File(trace).readAsLinesSync(), [
      contains('ccrouter_generator:ccrouter pub-hook guard-clean'),
    ]);

    File(trace).writeAsStringSync('');
    final bypassed = await Process.run(
      flutter.path,
      const ['clean'],
      workingDirectory: project.path,
      environment: {
        ...environment,
        'CCROUTER_FAKE_DART_EXIT': '23',
        ccrouterFlutterCleanGuardKillSwitch: '1',
      },
    );
    expect(bypassed.exitCode, 0, reason: '${bypassed.stderr}');
    expect(File(trace).readAsLinesSync(), ['flutter:clean']);
  });

  test('clean guard rejects only a live watch owner', () async {
    final project = await _createWatchCoordinatedProject();
    addTearDown(() => project.delete(recursive: true));

    final idle = await _run([
      'pub-hook',
      'guard-clean',
      '--project-root',
      project.path,
    ]);
    expect(idle.exitCode, 0, reason: '${idle.stderr}');

    final owner = await _lockWatchOwner(project);
    try {
      final blocked = await _run([
        'pub-hook',
        'guard-clean',
        '--project-root',
        project.path,
      ]);
      expect(blocked.exitCode, 1);
      expect('${blocked.stderr}', contains('active CCRouter generation watch'));
      expect('${blocked.stderr}', contains('Stop the Flutter run/watch'));
      expect(
        '${blocked.stderr}',
        contains(ccrouterFlutterCleanGuardKillSwitch),
      );
    } finally {
      await owner.unlock();
      await owner.close();
    }
  });

  test('clean guard also rejects a live V1 watch owner', () async {
    final project = await _createWatchCoordinatedProject();
    addTearDown(() => project.delete(recursive: true));
    final legacy = legacyCCRouterWatchOwnerLockFile(project)
      ..parent.createSync(recursive: true);
    final owner = await legacy.open(mode: FileMode.append);
    await owner.lock(FileLock.exclusive);
    try {
      final blocked = await _run([
        'pub-hook',
        'guard-clean',
        '--project-root',
        project.path,
      ]);
      expect(blocked.exitCode, 1);
      expect('${blocked.stderr}', contains('active CCRouter generation watch'));
    } finally {
      await owner.unlock();
      await owner.close();
    }
  });

  test(
    'inner Dart wrapper runs post-pub once and preserves bypass semantics',
    () async {
      final sdk = await Directory.systemTemp.createTemp(
        'ccrouter_dart_pub_hook_',
      );
      addTearDown(() => sdk.delete(recursive: true));
      final bin = Directory(path.join(sdk.path, 'bin'))..createSync();
      File(
        path.join(bin.path, 'flutter'),
      ).writeAsStringSync('#!/usr/bin/env bash\nexit 0\n');
      File(
        path.join(bin.path, 'flutter.bat'),
      ).writeAsStringSync('@echo off\r\nexit /b 0\r\n');
      final trace = path.join(sdk.path, 'dart-trace.txt');
      final innerDart = await _writeFakeInnerDart(sdk, '''#!/usr/bin/env bash
printf "%s\\n" "\$*" >> "\$CCROUTER_TRACE"
exit "\${CCROUTER_FAKE_DART_EXIT:-0}"
''');
      final installed = await _run(['pub-hook', 'install', '--sdk', sdk.path]);
      expect(installed.exitCode, 0, reason: '${installed.stderr}');

      final project = Directory(path.join(sdk.path, 'project'))..createSync();
      File(path.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: dart_hook_project
dependencies:
  ccrouter: any
dev_dependencies:
  ccrouter_generator: any
''');
      Directory(path.join(project.path, '.dart_tool')).createSync();
      File(
        path.join(project.path, '.dart_tool', 'package_config.json'),
      ).writeAsStringSync('''{"configVersion":2,"packages":[
  {"name":"ccrouter_generator","rootUri":"../missing_generator"}
]}''');
      final environment = <String, String>{
        ...Platform.environment,
        'CCROUTER_TRACE': trace,
      };

      final generated = await Process.run(
        innerDart.path,
        ['pub', 'get'],
        workingDirectory: project.path,
        environment: environment,
      );
      expect(generated.exitCode, 0, reason: '${generated.stderr}');
      final generatedTrace = File(trace).readAsLinesSync();
      final canonicalProject = project.resolveSymbolicLinksSync();
      expect(generatedTrace, hasLength(2));
      expect(generatedTrace.first, 'pub get');
      expect(
        generatedTrace.last,
        allOf(
          contains(
            '--packages=${path.join(canonicalProject, '.dart_tool', 'package_config.json')}',
          ),
          contains('ccrouter_generator:ccrouter pub-hook run'),
          contains('--project-root '),
          contains('--pub-command dart:get'),
        ),
      );

      for (final arguments in const <List<String>>[
        ['run', 'tool.dart', 'pub', 'get'],
        ['--help', 'pub', 'get'],
        ['--future-global-option', 'pub', 'get'],
      ]) {
        File(trace).writeAsStringSync('');
        final ignored = await Process.run(
          innerDart.path,
          arguments,
          workingDirectory: project.path,
          environment: environment,
        );
        expect(ignored.exitCode, 0);
        expect(File(trace).readAsLinesSync(), [arguments.join(' ')]);
      }

      File(trace).writeAsStringSync('');
      final globalOption = await Process.run(
        innerDart.path,
        ['--verbose', 'pub', 'get'],
        workingDirectory: project.path,
        environment: environment,
      );
      expect(globalOption.exitCode, 0, reason: '${globalOption.stderr}');
      expect(File(trace).readAsLinesSync(), hasLength(2));

      for (final arguments in const [
        ['pub', 'get', '--help'],
        ['pub', 'get', '--dry-run'],
      ]) {
        File(trace).writeAsStringSync('');
        final readOnly = await Process.run(
          innerDart.path,
          arguments,
          workingDirectory: project.path,
          environment: environment,
        );
        expect(readOnly.exitCode, 0);
        expect(File(trace).readAsLinesSync(), [arguments.join(' ')]);
      }

      File(trace).writeAsStringSync('');
      final bypassed = await Process.run(
        innerDart.path,
        ['pub', 'get'],
        workingDirectory: project.path,
        environment: {...environment, 'CCROUTER_PUB_HOOK_DISABLE': '1'},
      );
      expect(bypassed.exitCode, 0);
      expect(File(trace).readAsLinesSync(), ['pub get']);

      File(trace).writeAsStringSync('');
      final failed = await Process.run(
        innerDart.path,
        ['pub', 'get'],
        workingDirectory: project.path,
        environment: {...environment, 'CCROUTER_FAKE_DART_EXIT': '7'},
      );
      expect(failed.exitCode, 7);
      expect(File(trace).readAsLinesSync(), ['pub get']);
    },
  );

  test('inner Dart wrapper runs generation from the Package root', () async {
    final sdk = await Directory.systemTemp.createTemp(
      'ccrouter_dart_pub_hook_cwd_',
    );
    addTearDown(() => sdk.delete(recursive: true));
    final bin = Directory(path.join(sdk.path, 'bin'))..createSync();
    File(
      path.join(bin.path, 'flutter'),
    ).writeAsStringSync('#!/usr/bin/env bash\nexit 0\n');
    File(
      path.join(bin.path, 'flutter.bat'),
    ).writeAsStringSync('@echo off\r\nexit /b 0\r\n');
    final trace = path.join(sdk.path, 'dart-cwd-trace.txt');
    final innerDart = await _writeFakeInnerDart(sdk, '''#!/usr/bin/env bash
printf "%s|%s\\n" "\$PWD" "\$*" >> "\$CCROUTER_TRACE"
exit 0
''');
    final installed = await _run(['pub-hook', 'install', '--sdk', sdk.path]);
    expect(installed.exitCode, 0, reason: '${installed.stderr}');

    final project = Directory(path.join(sdk.path, 'project'))..createSync();
    final library = Directory(path.join(project.path, 'lib'))..createSync();
    File(path.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: dart_hook_cwd_project
dependencies:
  ccrouter: any
dev_dependencies:
  ccrouter_generator: any
''');
    Directory(path.join(project.path, '.dart_tool')).createSync();
    File(
      path.join(project.path, '.dart_tool', 'package_config.json'),
    ).writeAsStringSync('''{"configVersion":2,"packages":[
  {"name":"ccrouter_generator","rootUri":"../missing_generator"}
]}''');

    final result = await Process.run(
      innerDart.path,
      ['pub', 'get'],
      workingDirectory: library.path,
      environment: {...Platform.environment, 'CCROUTER_TRACE': trace},
    );

    expect(result.exitCode, 0, reason: '${result.stderr}');
    final lines = File(trace).readAsLinesSync();
    final canonicalLibrary = library.resolveSymbolicLinksSync();
    final canonicalProject = project.resolveSymbolicLinksSync();
    final canonicalSdk = sdk.resolveSymbolicLinksSync();
    expect(lines, hasLength(2));
    expect(lines.first, '$canonicalLibrary|pub get');
    expect(
      lines.last,
      allOf(
        startsWith(
          '$canonicalProject|--packages=${path.join(canonicalProject, '.dart_tool', 'package_config.json')} run ',
        ),
        contains('ccrouter_generator:ccrouter pub-hook run'),
      ),
    );

    for (final arguments in <List<String>>[
      ['pub', '--directory', project.path, 'get'],
      ['pub', '--directory=${project.path}', 'get'],
      ['pub', 'get', '--directory', project.path],
      ['pub', 'get', '--directory=${project.path}'],
    ]) {
      File(trace).writeAsStringSync('');
      final directed = await Process.run(
        innerDart.path,
        arguments,
        workingDirectory: sdk.path,
        environment: {...Platform.environment, 'CCROUTER_TRACE': trace},
      );

      expect(directed.exitCode, 0, reason: '${directed.stderr}');
      final directedLines = File(trace).readAsLinesSync();
      expect(directedLines, hasLength(2));
      expect(directedLines.first, startsWith('$canonicalSdk|pub '));
      expect(
        directedLines.last,
        startsWith(
          '$canonicalProject|--packages=${path.join(canonicalProject, '.dart_tool', 'package_config.json')} run ',
        ),
      );
    }
  });

  test('Flutter wrapper suppresses nested Dart post-pub hooks', () async {
    final sdk = await Directory.systemTemp.createTemp(
      'ccrouter_nested_pub_hook_',
    );
    addTearDown(() => sdk.delete(recursive: true));
    final bin = Directory(path.join(sdk.path, 'bin'))..createSync();
    final flutter = File(path.join(bin.path, 'flutter'))
      ..writeAsStringSync('''#!/usr/bin/env bash
"\$CCROUTER_FAKE_INNER_DART" pub get
"\$CCROUTER_FAKE_INNER_DART" pub get
''');
    File(
      path.join(bin.path, 'flutter.bat'),
    ).writeAsStringSync('@echo off\r\nexit /b 0\r\n');
    final trace = path.join(sdk.path, 'dart-trace.txt');
    final innerDart = await _writeFakeInnerDart(sdk, '''#!/usr/bin/env bash
printf "%s\\n" "\$*" >> "\$CCROUTER_TRACE"
exit 0
''');
    final dart = File(path.join(bin.path, 'dart'))
      ..writeAsStringSync('''#!/usr/bin/env bash
exec "\$(cd -- "\$(dirname -- "\${BASH_SOURCE[0]}")" && pwd -P)/cache/dart-sdk/bin/dart" "\$@"
''');
    await Process.run('chmod', ['+x', dart.path]);
    await Process.run('chmod', ['+x', flutter.path]);
    final installed = await _run(['pub-hook', 'install', '--sdk', sdk.path]);
    expect(installed.exitCode, 0, reason: '${installed.stderr}');

    final project = Directory(path.join(sdk.path, 'project'))..createSync();
    File(path.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: nested_hook_project
dependencies:
  ccrouter: any
dev_dependencies:
  ccrouter_generator: any
''');
    Directory(path.join(project.path, '.dart_tool')).createSync();
    File(
      path.join(project.path, '.dart_tool', 'package_config.json'),
    ).writeAsStringSync('''{"configVersion":2,"packages":[
  {"name":"ccrouter_generator","rootUri":"../missing_generator"}
]}''');

    final result = await Process.run(
      flutter.path,
      ['pub', 'get'],
      workingDirectory: project.path,
      environment: {
        ...Platform.environment,
        'CCROUTER_TRACE': trace,
        'CCROUTER_FAKE_INNER_DART': innerDart.path,
      },
    );

    expect(result.exitCode, 0, reason: '${result.stderr}');
    final lines = File(trace).readAsLinesSync();
    expect(lines.where((line) => line == 'pub get'), hasLength(2));
    expect(
      lines.where(
        (line) => line.contains('ccrouter_generator:ccrouter pub-hook run'),
      ),
      hasLength(1),
    );
  });

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
    'post-pub hook runs package-local generation for participating Packages',
    () async {
      final workspace = _workspaceRoot();
      for (final packagePath in const [
        'demo/modules/navigation_lab',
        'demo/modules/web_contracts',
      ]) {
        final package = Directory(path.join(workspace.path, packagePath));
        final result = await _run([
          'pub-hook',
          'run',
          '--project-root',
          package.path,
          '--pub-command',
          'get',
        ]);
        final output = '${result.stdout}\n${result.stderr}';

        expect(result.exitCode, 0, reason: '$packagePath\n$output');
        expect(
          output,
          contains('CCRouter post-pub generation finished:'),
          reason: packagePath,
        );
        expect(
          output,
          isNot(contains('pub hook skipped')),
          reason: packagePath,
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('package-local post-pub reports a covering active Host watch', () async {
    final fixture = await _createPackageWatchFixture();
    addTearDown(() => fixture.workspace.delete(recursive: true));
    final owner = await _lockWatchOwner(fixture.workspace);
    addTearDown(() async {
      await owner.unlock();
      await owner.close();
    });
    await _writeBuildRootWatchStatus(
      fixture,
      targets: const ['watched_component'],
    );

    final result = await _run([
      'pub-hook',
      'run',
      '--project-root',
      fixture.package.path,
      '--pub-command',
      'get',
    ]);
    final output = '${result.stdout}\n${result.stderr}';

    expect(result.exitCode, 1, reason: output);
    expect(output, contains('active Host watch at "${fixture.host.path}"'));
    expect(output, contains('covers requested Package "watched_component"'));
    expect(output, contains('does not publish versioned Package'));
    expect(output, contains('stop the watch, then retry'));
    expect(output, isNot(contains('Generator diagnostics:')));
    expect(output, isNot(contains('active CCRouter generation watch owns')));
  });

  test(
    'package-local post-pub reuses exact active Host watch evidence',
    () async {
      final fixture = await _createPackageWatchFixture();
      addTearDown(() => fixture.workspace.delete(recursive: true));
      final owner = await _lockWatchOwner(fixture.workspace);
      addTearDown(() async {
        await owner.unlock();
        await owner.close();
      });
      await _writeBuildRootWatchStatus(
        fixture,
        targets: const ['watched_component'],
        packageCompletionEvidence: {
          'watched_component': await _packageWatchEvidence(fixture),
        },
      );

      final result = await _run([
        'pub-hook',
        'run',
        '--project-root',
        fixture.package.path,
        '--pub-command',
        'get',
      ]);
      final output = '${result.stdout}\n${result.stderr}';

      expect(result.exitCode, 0, reason: output);
      expect(output, contains('reused active watch cycle 2'));
      expect(output, contains('exact Package evidence'));
      expect(output, isNot(contains('active CCRouter generation watch owns')));
    },
  );

  test(
    'package-local post-pub fails fast when evidence is unavailable',
    () async {
      final fixture = await _createPackageWatchFixture();
      addTearDown(() => fixture.workspace.delete(recursive: true));
      final owner = await _lockWatchOwner(fixture.workspace);
      addTearDown(() async {
        await owner.unlock();
        await owner.close();
      });
      await _writeBuildRootWatchStatus(
        fixture,
        targets: const ['watched_component'],
        packageCompletionEvidence: const {},
      );

      final watch = Stopwatch()..start();
      final result = await _run([
        'pub-hook',
        'run',
        '--project-root',
        fixture.package.path,
        '--pub-command',
        'get',
      ]);
      watch.stop();
      final output = '${result.stdout}\n${result.stderr}';

      expect(result.exitCode, 1, reason: output);
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(output, contains('completed without exact Package evidence'));
    },
  );

  test(
    'package-local post-pub uses stable Builder session without local status',
    () async {
      final fixture = await _createPackageWatchFixture();
      addTearDown(() => fixture.workspace.delete(recursive: true));
      final owner = await _lockWatchOwner(fixture.workspace);
      addTearDown(() async {
        await owner.unlock();
        await owner.close();
      });
      await _writeBuildRootWatchStatus(
        fixture,
        targets: const ['watched_component'],
      );
      File(
        path.join(
          fixture.workspace.path,
          '.dart_tool',
          'ccrouter',
          'v1',
          'watch',
          'builder-status.json',
        ),
      ).deleteSync();

      final result = await _run([
        'pub-hook',
        'run',
        '--project-root',
        fixture.package.path,
        '--pub-command',
        'get',
      ]);
      final output = '${result.stdout}\n${result.stderr}';

      expect(result.exitCode, 1, reason: output);
      expect(output, contains('active Host watch at "${fixture.host.path}"'));
      expect(output, contains('covers requested Package "watched_component"'));
    },
  );

  test(
    'package-local post-pub reports an active Host watch without its target',
    () async {
      final fixture = await _createPackageWatchFixture();
      addTearDown(() => fixture.workspace.delete(recursive: true));
      final owner = await _lockWatchOwner(fixture.workspace);
      addTearDown(() async {
        await owner.unlock();
        await owner.close();
      });
      await _writeBuildRootWatchStatus(
        fixture,
        targets: const ['another_component'],
      );

      final result = await _run([
        'pub-hook',
        'run',
        '--project-root',
        fixture.package.path,
        '--pub-command',
        'get',
      ]);
      final output = '${result.stdout}\n${result.stderr}';

      expect(result.exitCode, 1, reason: output);
      expect(output, contains('active Host watch at "${fixture.host.path}"'));
      expect(
        output,
        contains('does not cover requested Package "watched_component"'),
      );
      expect(output, contains('stop the watch, then retry'));
      expect(output, isNot(contains('Generator diagnostics:')));
      expect(output, isNot(contains('active CCRouter generation watch owns')));
    },
  );

  test(
    'package-local post-pub ignores stale build-root watch status',
    () async {
      final fixture = await _createPackageWatchFixture();
      addTearDown(() => fixture.workspace.delete(recursive: true));
      await _writeBuildRootWatchStatus(
        fixture,
        targets: const ['watched_component'],
      );

      final result = await _run([
        'pub-hook',
        'run',
        '--project-root',
        fixture.package.path,
        '--pub-command',
        'get',
      ]);
      final output = '${result.stdout}\n${result.stderr}';

      expect(result.exitCode, 1, reason: output);
      expect(output, contains('exitCode='));
      expect(output, isNot(contains('active Host watch at')));
    },
  );

  test(
    'package-local post-pub rejects malformed or wrong-root watch evidence',
    () async {
      for (final malformed in [true, false]) {
        final fixture = await _createPackageWatchFixture();
        addTearDown(() => fixture.workspace.delete(recursive: true));
        final owner = await _lockWatchOwner(fixture.workspace);
        addTearDown(() async {
          await owner.unlock();
          await owner.close();
        });
        final status = await _writeBuildRootWatchStatus(
          fixture,
          targets: const ['watched_component'],
          buildRoot: malformed
              ? fixture.workspace
              : Directory(path.join(fixture.workspace.path, 'other-root')),
        );
        if (malformed) status.writeAsStringSync('{not-json\n');

        final result = await _run([
          'pub-hook',
          'run',
          '--project-root',
          fixture.package.path,
          '--pub-command',
          'get',
        ]);
        final output = '${result.stdout}\n${result.stderr}';

        expect(result.exitCode, 1, reason: output);
        expect(output, contains('exitCode='));
        expect(output, isNot(contains('active Host watch at')));
      }
    },
  );

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
      expect(preflightOutput, isNot(contains('CCRouter profile ')));
      expect(preflightOutput, contains('CCRouter preflight finished:'));
      expect(preflightOutput, matches(RegExp(r'elapsed=\d+ms\.')));
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

      final dartPostPub = await _run([
        'pub-hook',
        'run',
        '--project-root',
        demo.path,
        '--pub-command',
        'dart:get',
      ]);
      final dartPostPubOutput = '${dartPostPub.stdout}\n${dartPostPub.stderr}';
      expect(dartPostPub.exitCode, 0, reason: dartPostPubOutput);
      expect(
        dartPostPubOutput,
        contains('CCRouter post-pub generation started for `dart pub get`.'),
      );
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
    expect(output, contains('Generator diagnostics:'));
    expect(output, isNot(contains('CCRouter pub hook finished')));
  });

  test('post-pub hook waits for an active watch aggregation', () async {
    final project = await _createWatchCoordinatedProject();
    addTearDown(() => project.delete(recursive: true));
    final owner = await _lockWatchOwner(project);
    addTearDown(() async {
      await owner.unlock();
      await owner.close();
    });
    final staleFingerprint = await _writeWatchStatus(
      project,
      lastEvent: 'buildStarted',
      cycle: 2,
      updatedAt: DateTime.now().toUtc(),
    );
    File(
      path.join(project.path, 'pubspec.yaml'),
    ).writeAsStringSync('\n# resolution changed\n', mode: FileMode.append);

    final pending = _run([
      'pub-hook',
      'run',
      '--project-root',
      project.path,
      '--pub-command',
      'get',
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _writeWatchStatus(
      project,
      lastEvent: 'aggregationSucceeded',
      cycle: 2,
      updatedAt: DateTime.now().toUtc(),
      resolutionFingerprint: staleFingerprint,
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _writeWatchStatus(
      project,
      lastEvent: 'aggregationSucceeded',
      cycle: 3,
      updatedAt: DateTime.now().toUtc(),
    );
    final result = await pending;
    final output = '${result.stdout}\n${result.stderr}';

    expect(result.exitCode, 0, reason: output);
    expect(output, contains('reused active watch cycle 3'));
    expect(output, contains('post-pub generation finished'));
    expect(output, isNot(contains('active CCRouter generation watch owns')));
  });

  test('post-pub hook uses stable Host session without local status', () async {
    final project = await _createWatchCoordinatedProject();
    addTearDown(() => project.delete(recursive: true));
    final owner = await _lockWatchOwner(project);
    addTearDown(() async {
      await owner.unlock();
      await owner.close();
    });
    await _writeWatchStatus(
      project,
      lastEvent: 'ready',
      cycle: 2,
      sessionReady: true,
      updatedAt: DateTime.now().toUtc(),
    );
    File(
      path.join(
        project.path,
        '.dart_tool',
        'ccrouter',
        'v1',
        'watch',
        'status.json',
      ),
    ).deleteSync();

    final result = await _run([
      'pub-hook',
      'run',
      '--project-root',
      project.path,
      '--pub-command',
      'get',
    ]);
    final output = '${result.stdout}\n${result.stderr}';

    expect(result.exitCode, 0, reason: output);
    expect(output, contains('reused active watch cycle 2'));
  });

  test('post-pub hook reuses a watch through a symlinked Host path', () async {
    if (Platform.isWindows) return;
    final project = await _createWatchCoordinatedProject();
    final aliases = await Directory.systemTemp.createTemp(
      'ccrouter_pub_hook_alias_',
    );
    final alias = Directory(path.join(aliases.path, 'host'));
    await Link(alias.path).create(project.path);
    addTearDown(() => aliases.delete(recursive: true));
    addTearDown(() => project.delete(recursive: true));
    final owner = await _lockWatchOwner(project);
    addTearDown(() async {
      await owner.unlock();
      await owner.close();
    });
    await _writeWatchStatus(
      project,
      lastEvent: 'ready',
      cycle: 2,
      sessionReady: true,
      updatedAt: DateTime.now().toUtc(),
    );

    final result = await _run([
      'pub-hook',
      'run',
      '--project-root',
      alias.path,
      '--pub-command',
      'get',
    ]);
    final output = '${result.stdout}\n${result.stderr}';

    expect(result.exitCode, 0, reason: output);
    expect(output, contains('reused active watch cycle 2'));
    expect(output, isNot(contains('active CCRouter generation watch owns')));
  });

  test('post-pub hook surfaces active watch generation diagnostics', () async {
    final project = await _createWatchCoordinatedProject();
    addTearDown(() => project.delete(recursive: true));
    final owner = await _lockWatchOwner(project);
    addTearDown(() async {
      await owner.unlock();
      await owner.close();
    });
    await _writeWatchStatus(
      project,
      lastEvent: 'aggregationStarted',
      cycle: 3,
      updatedAt: DateTime.now().toUtc(),
    );

    final result = await _runAfterHookStarted(
      [
        'pub-hook',
        'run',
        '--project-root',
        project.path,
        '--pub-command',
        'get',
      ],
      () => _writeWatchStatus(
        project,
        lastEvent: 'failed',
        cycle: 3,
        eventRevision: 2,
        updatedAt: DateTime.now().toUtc(),
        failureStage: 'aggregation',
        failureDiagnostics:
            'error: Public route contract has no implementation.',
      ),
    );
    final output = '${result.stdout}\n${result.stderr}';

    expect(result.exitCode, 1, reason: output);
    expect(output, contains('active watch cycle 3 failed at aggregation'));
    expect(output, contains('Generator diagnostics:'));
    expect(
      output,
      contains('error: Public route contract has no implementation.'),
    );
    expect(output, isNot(contains('active CCRouter generation watch owns')));
  });

  test(
    'post-pub hook fails quickly when resolution changes during a failed cycle',
    () async {
      final project = await _createWatchCoordinatedProject();
      addTearDown(() => project.delete(recursive: true));
      final owner = await _lockWatchOwner(project);
      addTearDown(() async {
        await owner.unlock();
        await owner.close();
      });
      const sessionId = 'watch-session';
      await _writeWatchStatus(
        project,
        lastEvent: 'aggregationStarted',
        cycle: 4,
        eventRevision: 7,
        sessionId: sessionId,
        updatedAt: DateTime.now().toUtc(),
      );

      final stopwatch = Stopwatch()..start();
      final result = await _runAfterHookStarted(
        [
          'pub-hook',
          'run',
          '--project-root',
          project.path,
          '--pub-command',
          'get',
        ],
        () => _writeWatchStatus(
          project,
          lastEvent: 'failed',
          cycle: 4,
          eventRevision: 8,
          sessionId: sessionId,
          updatedAt: DateTime.now().toUtc(),
          includeResolutionFingerprint: false,
          cycleResolutionState: 'changed',
          failureStage: 'aggregation',
          failureDiagnostics: 'error: Host dependency closure is invalid.',
        ),
      );
      stopwatch.stop();
      final output = '${result.stdout}\n${result.stderr}';

      expect(result.exitCode, 1, reason: output);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(output, contains('Pub resolution changed during the cycle'));
      expect(output, contains('a new cycle or watch session is required'));
      expect(output, contains('Host dependency closure is invalid'));
      expect(output, isNot(contains('within 5 minutes')));
    },
  );

  test('post-pub hook does not reuse a historical watch failure', () async {
    final project = await _createWatchCoordinatedProject();
    addTearDown(() => project.delete(recursive: true));
    final owner = await _lockWatchOwner(project);
    addTearDown(() async {
      await owner.unlock();
      await owner.close();
    });
    const sessionId = 'watch-session';
    await _writeWatchStatus(
      project,
      lastEvent: 'failed',
      cycle: 3,
      eventRevision: 6,
      sessionId: sessionId,
      updatedAt: DateTime.now().toUtc(),
      failureStage: 'aggregation',
      failureDiagnostics: 'error: historical failure',
    );

    final result = await _runAfterHookStarted(
      [
        'pub-hook',
        'run',
        '--project-root',
        project.path,
        '--pub-command',
        'get',
      ],
      () => _writeWatchStatus(
        project,
        lastEvent: 'aggregationSucceeded',
        cycle: 4,
        eventRevision: 7,
        sessionId: sessionId,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    final output = '${result.stdout}\n${result.stderr}';

    expect(result.exitCode, 0, reason: output);
    expect(output, contains('reused active watch cycle 4'));
    expect(output, isNot(contains('historical failure')));
  });

  test('post-pub hook waits for ready after a watch session restart', () async {
    final project = await _createWatchCoordinatedProject();
    addTearDown(() => project.delete(recursive: true));
    final owner = await _lockWatchOwner(project);
    addTearDown(() async {
      await owner.unlock();
      await owner.close();
    });
    await _writeWatchStatus(
      project,
      lastEvent: 'aggregationStarted',
      cycle: 5,
      eventRevision: 9,
      sessionId: 'old-session',
      updatedAt: DateTime.now().toUtc(),
    );

    final result = await _runAfterHookStartedWithProcess(
      [
        'pub-hook',
        'run',
        '--project-root',
        project.path,
        '--pub-command',
        'get',
      ],
      (process) async {
        await _writeWatchStatus(
          project,
          lastEvent: 'aggregationSucceeded',
          cycle: 1,
          eventRevision: 4,
          sessionId: 'new-session',
          sessionReady: false,
          updatedAt: DateTime.now().toUtc(),
        );
        var completedBeforeReady = false;
        process.exitCode.then((_) => completedBeforeReady = true);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(completedBeforeReady, isFalse);
        await _writeWatchStatus(
          project,
          lastEvent: 'ready',
          cycle: 1,
          eventRevision: 5,
          sessionId: 'new-session',
          sessionReady: true,
          updatedAt: DateTime.now().toUtc(),
        );
      },
    );
    final output = '${result.stdout}\n${result.stderr}';

    expect(result.exitCode, 0, reason: output);
    expect(output, contains('reused active watch cycle 1'));
  });

  test(
    'post-pub hook fences a new failure from a legacy watch status',
    () async {
      final project = await _createWatchCoordinatedProject();
      addTearDown(() => project.delete(recursive: true));
      final owner = await _lockWatchOwner(project);
      addTearDown(() async {
        await owner.unlock();
        await owner.close();
      });
      await _writeWatchStatus(
        project,
        lastEvent: 'aggregationStarted',
        cycle: 5,
        updatedAt: DateTime.now().toUtc(),
        includeEventIdentity: false,
      );

      final result = await _runAfterHookStarted(
        [
          'pub-hook',
          'run',
          '--project-root',
          project.path,
          '--pub-command',
          'get',
        ],
        () => _writeWatchStatus(
          project,
          lastEvent: 'failed',
          cycle: 5,
          updatedAt: DateTime.now().toUtc().add(const Duration(seconds: 1)),
          includeEventIdentity: false,
          failureStage: 'aggregation',
          failureDiagnostics: 'error: legacy watch failure',
        ),
      );
      final output = '${result.stdout}\n${result.stderr}';

      expect(result.exitCode, 1, reason: output);
      expect(output, contains('active watch cycle 5 failed at aggregation'));
      expect(output, contains('legacy watch failure'));
    },
  );

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
if [[ "\$*" == *"ccrouter_generator:ccrouter_flutter_run_supervisor"* ]]; then
  if [[ "\${CCROUTER_DISABLE_WATCH_STARTUP_HANDSHAKE:-0}" != "1" ]] && \
     [[ "\${CCROUTER_WATCH_HANDSHAKE_EXIT:-0}" != "0" ]]; then
    echo "error: CCRouter watch startup failed" >&2
    exit "\${CCROUTER_WATCH_HANDSHAKE_EXIT}"
  fi
  echo "CCRouter watch starting (pid=123)."
  ORIGINAL=""
  while [[ "\$#" -gt 0 ]]; do
    if [[ "\$1" == "--original" ]]; then
      shift
      ORIGINAL="\$1"
    elif [[ "\$1" == "--" ]]; then
      shift
      break
    fi
    shift
  done
  "\$ORIGINAL" "\$@"
  exit "\$?"
fi
exit "\${CCROUTER_DART_EXIT:-0}"
''');
    await _writeFakeInnerDart(sdk, '#!/usr/bin/env bash\nexit 0\n');
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
    expect('${run.stdout}', contains('CCRouter watch starting'));
    expect('${run.stderr}', isNot(contains('CCRouter watch starting')));
    final runTrace = File(trace).readAsLinesSync();
    final canonicalProject = project.resolveSymbolicLinksSync();
    expect(
      runTrace.first,
      startsWith(
        'dart:--packages=${path.join(canonicalProject, '.dart_tool', 'package_config.json')} '
        'run --verbosity=error ccrouter_generator:ccrouter',
      ),
    );
    expect(runTrace.last, 'flutter:--no-color run -d macos');

    File(trace).writeAsStringSync('');
    final machineRun = await Process.run(
      flutter.path,
      <String>['run', '--machine', '-d', 'macos'],
      workingDirectory: project.path,
      environment: environment,
    );
    expect(machineRun.exitCode, 0, reason: '${machineRun.stderr}');
    final machineTrace = File(trace).readAsLinesSync();
    expect(
      machineTrace,
      contains(
        contains(
          'ccrouter_generator:ccrouter_flutter_run_supervisor '
          '--host-root ',
        ),
      ),
    );
    expect(machineTrace, contains('flutter:run --machine -d macos'));

    File(trace).writeAsStringSync('');
    final bypassedMachineRun = await Process.run(
      flutter.path,
      <String>['run', '--machine', '-d', 'macos'],
      workingDirectory: project.path,
      environment: <String, String>{
        ...environment,
        'CCROUTER_DISABLE_HOT_RELOAD_GATE': '1',
      },
    );
    expect(
      bypassedMachineRun.exitCode,
      0,
      reason: '${bypassedMachineRun.stderr}',
    );
    expect(
      File(trace).readAsLinesSync().last,
      'flutter:run --machine -d macos',
    );

    File(trace).writeAsStringSync('');
    final failedHandshake = await Process.run(
      flutter.path,
      <String>['run', '-d', 'macos'],
      workingDirectory: project.path,
      environment: <String, String>{
        ...environment,
        'CCROUTER_WATCH_HANDSHAKE_EXIT': '9',
      },
    );
    expect(failedHandshake.exitCode, 9);
    expect(
      '${failedHandshake.stderr}',
      contains('CCRouter watch startup failed'),
    );
    expect(
      File(
        trace,
      ).readAsLinesSync().where((line) => line.startsWith('flutter:')),
      isEmpty,
    );

    File(trace).writeAsStringSync('');
    final bypassedHandshake = await Process.run(
      flutter.path,
      <String>['run', '-d', 'macos'],
      workingDirectory: project.path,
      environment: <String, String>{
        ...environment,
        'CCROUTER_WATCH_HANDSHAKE_EXIT': '9',
        'CCROUTER_DISABLE_WATCH_STARTUP_HANDSHAKE': '1',
      },
    );
    expect(
      bypassedHandshake.exitCode,
      0,
      reason: '${bypassedHandshake.stderr}',
    );
    expect(File(trace).readAsLinesSync(), contains('flutter:run -d macos'));

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

Future<File> _writeFakeInnerDart(Directory sdk, String contents) async {
  final file = File(
    path.join(sdk.path, 'bin', 'cache', 'dart-sdk', 'bin', 'dart'),
  );
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
  await Process.run('chmod', ['+x', file.path]);
  return file;
}

Future<ProcessResult> _run(List<String> arguments) => Process.run(
  Platform.resolvedExecutable,
  ['run', 'ccrouter_generator:ccrouter', ...arguments],
  workingDirectory: Directory.current.path,
  environment: _testEnvironment,
);

Future<ProcessResult> _runAfterHookStarted(
  List<String> arguments,
  Future<void> Function() publishStatus,
) => _runAfterHookStartedWithProcess(arguments, (_) => publishStatus());

Future<ProcessResult> _runAfterHookStartedWithProcess(
  List<String> arguments,
  Future<void> Function(Process process) publishStatus,
) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['run', 'ccrouter_generator:ccrouter', ...arguments],
    workingDirectory: Directory.current.path,
    environment: _testEnvironment,
  );
  final stdoutLines = <String>[];
  final stderrLines = <String>[];
  final started = Completer<void>();
  final stdoutDone = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        stdoutLines.add(line);
        if (!started.isCompleted &&
            line.contains('CCRouter post-pub generation started')) {
          started.complete();
        }
      })
      .asFuture<void>();
  final stderrDone = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(stderrLines.add)
      .asFuture<void>();
  await started.future.timeout(const Duration(seconds: 15));
  await Future<void>.delayed(const Duration(milliseconds: 400));
  await publishStatus(process);
  final processExitCode = await process.exitCode;
  await Future.wait([stdoutDone, stderrDone]);
  return ProcessResult(
    process.pid,
    processExitCode,
    stdoutLines.join('\n'),
    stderrLines.join('\n'),
  );
}

Directory _workspaceRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (FileSystemEntity.typeSync(path.join(current.path, '.git')) !=
        FileSystemEntityType.notFound)
      return current;
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('CCRouter workspace root was not found.');
    }
    current = parent;
  }
}

final class _PackageWatchFixture {
  const _PackageWatchFixture({
    required this.workspace,
    required this.package,
    required this.host,
  });

  final Directory workspace;
  final Directory package;
  final Directory host;
}

Future<_PackageWatchFixture> _createPackageWatchFixture() async {
  final workspace = await Directory.systemTemp.createTemp(
    'ccrouter_pub_hook_package_watch_',
  );
  final package = Directory(path.join(workspace.path, 'packages', 'component'))
    ..createSync(recursive: true);
  final host = Directory(path.join(workspace.path, 'apps', 'host'))
    ..createSync(recursive: true);
  File(path.join(workspace.path, 'pubspec.yaml')).writeAsStringSync('''
name: package_watch_workspace
publish_to: none
environment:
  sdk: ^3.10.0
workspace:
  - packages/component
''');
  File(path.join(package.path, '.metadata')).writeAsStringSync('''
project_type: package
''');
  File(path.join(package.path, 'pubspec.yaml')).writeAsStringSync('''
name: watched_component
publish_to: none
resolution: workspace
environment:
  sdk: ^3.10.0
dependencies:
  ccrouter: any
dev_dependencies:
  ccrouter_generator: any
''');
  final dartTool = Directory(path.join(workspace.path, '.dart_tool'))
    ..createSync();
  File(path.join(dartTool.path, 'package_config.json')).writeAsStringSync('''
{"configVersion":2,"packages":[
  {"name":"ccrouter","rootUri":"../ccrouter"},
  {"name":"ccrouter_generator","rootUri":"../ccrouter_generator"}
]}
''');
  File(
    path.join(dartTool.path, 'package_graph.json'),
  ).writeAsStringSync('{}\n');
  File(path.join(workspace.path, 'pubspec.lock')).writeAsStringSync('{}\n');
  return _PackageWatchFixture(
    workspace: workspace,
    package: package,
    host: host,
  );
}

Future<File> _writeBuildRootWatchStatus(
  _PackageWatchFixture fixture, {
  required List<String> targets,
  Directory? buildRoot,
  Map<String, Map<String, Object?>>? packageCompletionEvidence,
}) async {
  final file = File(
    path.join(
      fixture.workspace.path,
      '.dart_tool',
      'ccrouter',
      'v1',
      'watch',
      'builder-status.json',
    ),
  )..parent.createSync(recursive: true);
  final document = <String, Object?>{
    'schemaVersion': 1,
    'active': true,
    'pid': pid,
    'sessionId': 'package-watch-session',
    'eventRevision': 4,
    'lastEvent': 'aggregationSucceeded',
    'cycleRevision': 2,
    'failureRevision': 0,
    'targets': targets,
    if (packageCompletionEvidence != null)
      'packageCompletionEvidenceVersion': 1,
    if (packageCompletionEvidence != null)
      'packageCompletionEvidenceState': packageCompletionEvidence.isEmpty
          ? 'unavailable'
          : 'available',
    if (packageCompletionEvidence != null)
      'packageCompletionEvidence': packageCompletionEvidence,
    'hostRoot': fixture.host.path,
    'buildRoot': (buildRoot ?? fixture.workspace).path,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };
  await file.writeAsString('${jsonEncode(document)}\n');
  await publishCCRouterBuilderSession(
    buildRoot: fixture.workspace,
    status: document,
    environment: _testEnvironment,
  );
  return CCRouterCoordinationPaths.forBuildRoot(
    fixture.workspace,
    environment: _testEnvironment,
  ).builderSessionDocument;
}

Future<Map<String, Object?>> _packageWatchEvidence(
  _PackageWatchFixture fixture,
) async => <String, Object?>{
  'schemaVersion': 1,
  'package': 'watched_component',
  'packageRoot': fixture.package.path,
  'pubResolutionFingerprint': await CCPubResolutionFingerprint.capture(
    hostRoot: fixture.package,
    buildRoot: fixture.workspace,
  ),
  'authoredInputFingerprint':
      await CCPackageWatchFingerprint.captureAuthoredInput(
        packageName: 'watched_component',
        packageRoot: fixture.package,
      ),
  'managedOutputFingerprint':
      await CCPackageWatchFingerprint.captureManagedOutput(fixture.package),
};

Future<Directory> _createWatchCoordinatedProject() async {
  final project = await Directory.systemTemp.createTemp(
    'ccrouter_pub_hook_watch_',
  );
  File(
    path.join(project.path, '.metadata'),
  ).writeAsStringSync('project_type: app\n');
  File(path.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: watch_host
dependencies:
  ccrouter: any
dev_dependencies:
  ccrouter_generator: any
''');
  final dartTool = Directory(path.join(project.path, '.dart_tool'))
    ..createSync();
  File(path.join(dartTool.path, 'package_config.json')).writeAsStringSync('''
{"configVersion":2,"packages":[
  {"name":"ccrouter","rootUri":"../ccrouter"},
  {"name":"ccrouter_generator","rootUri":"../ccrouter_generator"}
]}
''');
  File(
    path.join(dartTool.path, 'package_graph.json'),
  ).writeAsStringSync('{}\n');
  File(path.join(project.path, 'pubspec.lock')).writeAsStringSync('{}\n');
  return project;
}

Future<RandomAccessFile> _lockWatchOwner(Directory project) async {
  final paths = CCRouterCoordinationPaths.forBuildRoot(
    project,
    environment: _testEnvironment,
  );
  await paths.prepare();
  final file = paths.ownerLock..parent.createSync(recursive: true);
  final owner = await file.open(mode: FileMode.append);
  await owner.lock(FileLock.exclusive);
  return owner;
}

Map<String, String> get _testEnvironment => {
  ...Platform.environment,
  ccrouterHomeEnvironment: _testCoordinationHome.path,
};

Future<String> _writeWatchStatus(
  Directory project, {
  required String lastEvent,
  required int cycle,
  required DateTime updatedAt,
  int eventRevision = 1,
  String sessionId = 'test-watch-session',
  String? failureStage,
  String? failureDiagnostics,
  String? resolutionFingerprint,
  bool includeResolutionFingerprint = true,
  bool includeEventIdentity = true,
  bool? sessionReady,
  String? cycleResolutionState,
}) async {
  final file = File(
    path.join(
      project.path,
      '.dart_tool',
      'ccrouter',
      'v1',
      'watch',
      'status.json',
    ),
  )..parent.createSync(recursive: true);
  final effectiveResolutionFingerprint = includeResolutionFingerprint
      ? resolutionFingerprint ??
            await CCPubResolutionFingerprint.capture(
              hostRoot: project,
              buildRoot: project,
            )
      : null;
  final document = <String, Object?>{
    'schemaVersion': 1,
    'state': lastEvent == 'failed' ? 'failed' : 'building',
    'active': true,
    'lastEvent': lastEvent,
    'pid': pid,
    if (includeEventIdentity) 'sessionId': sessionId,
    if (includeEventIdentity) 'eventRevision': eventRevision,
    if (sessionReady != null) 'sessionReady': sessionReady,
    'cycle': cycle,
    'startedAt': updatedAt
        .subtract(const Duration(seconds: 1))
        .toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'hostRoot': project.path,
    'buildRoot': project.path,
    'managedByLease': false,
    if (effectiveResolutionFingerprint != null)
      'resolutionFingerprint': effectiveResolutionFingerprint,
    if (cycleResolutionState != null)
      'cycleResolutionState': cycleResolutionState,
    if (failureStage != null) 'failureStage': failureStage,
    if (failureDiagnostics != null) 'failureDiagnostics': failureDiagnostics,
  };
  file.writeAsStringSync('${jsonEncode(document)}\n');
  await publishCCRouterHostSession(
    hostRoot: project,
    buildRoot: project,
    status: document,
    environment: _testEnvironment,
  );
  return effectiveResolutionFingerprint ?? '';
}
