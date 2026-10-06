@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../ccrouter_generator/bin/src/pub_hook_watch_coordination.dart';

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
      contains('CCRouter Dart pub hook wrapper'),
    );
    expect(
      dartBat.readAsStringSync(),
      allOf(
        contains('CCRouter Dart pub hook wrapper'),
        contains('dart:%PUB_COMMAND%'),
      ),
    );
    expect(flutter.readAsStringSync(), contains('ccrouter_generator:ccrouter'));
    expect(flutter.readAsStringSync(), contains('--watch=auto'));
    expect(flutter.readAsStringSync(), contains('--watch-lease'));
    expect(flutter.readAsStringSync(), contains('CCRouter watch starting'));
    expect(flutter.readAsStringSync(), contains('status.json'));
    expect(
      flutter.readAsStringSync(),
      contains('ccrouter_generator:ccrouter_flutter_run_gate'),
    );
    expect(
      flutter.readAsStringSync(),
      contains('ccrouter_generator:ccrouter_watch_startup'),
    );
    expect(
      flutterBat.readAsStringSync(),
      contains('ccrouter_generator:ccrouter'),
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
    expect('${status.stdout}', contains('machine reload gate: enabled'));
    expect('${status.stdout}', contains('watch startup handshake: enabled'));
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
      expect(generatedTrace, hasLength(2));
      expect(generatedTrace.first, 'pub get');
      expect(
        generatedTrace.last,
        allOf(
          contains('ccrouter_generator:ccrouter pub-hook run'),
          contains('--project-root '),
          contains('--pub-command dart:get'),
        ),
      );

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
    expect(output, contains('Generator output:'));
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
    expect(output, contains('Generator output:'));
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
if [[ "\$*" == *"ccrouter_generator:ccrouter_watch_startup"* ]]; then
  exit "\${CCROUTER_WATCH_HANDSHAKE_EXIT:-0}"
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
    expect(
      runTrace.first,
      startsWith('dart:run --verbosity=error ccrouter_generator:ccrouter'),
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
          'ccrouter_generator:ccrouter_flutter_run_gate '
          '--host-root ',
        ),
      ),
    );
    expect(machineTrace.where((line) => line.startsWith('flutter:')), isEmpty);

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
      contains('watch startup blocked flutter run'),
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
);

Future<ProcessResult> _runAfterHookStarted(
  List<String> arguments,
  Future<void> Function() publishStatus,
) => _runAfterHookStartedWithProcess(arguments, (_) => publishStatus());

Future<ProcessResult> _runAfterHookStartedWithProcess(
  List<String> arguments,
  Future<void> Function(Process process) publishStatus,
) async {
  final process = await Process.start(Platform.resolvedExecutable, [
    'run',
    'ccrouter_generator:ccrouter',
    ...arguments,
  ], workingDirectory: Directory.current.path);
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
    if (Directory(path.join(current.path, '.git')).existsSync()) return current;
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('CCRouter workspace root was not found.');
    }
    current = parent;
  }
}

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
  final file = File(
    path.join(
      project.path,
      '.dart_tool',
      'ccrouter',
      'v1',
      'watch',
      'owner.lock',
    ),
  )..parent.createSync(recursive: true);
  final owner = await file.open(mode: FileMode.append);
  await owner.lock(FileLock.exclusive);
  return owner;
}

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
  file.writeAsStringSync(
    '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'state': lastEvent == 'failed' ? 'failed' : 'building', 'active': true, 'lastEvent': lastEvent, 'pid': pid, if (includeEventIdentity) 'sessionId': sessionId, if (includeEventIdentity) 'eventRevision': eventRevision, if (sessionReady != null) 'sessionReady': sessionReady, 'cycle': cycle, 'startedAt': updatedAt.subtract(const Duration(seconds: 1)).toIso8601String(), 'updatedAt': updatedAt.toIso8601String(), 'hostRoot': project.path, 'buildRoot': project.path, 'managedByLease': false, if (effectiveResolutionFingerprint != null) 'resolutionFingerprint': effectiveResolutionFingerprint, if (cycleResolutionState != null) 'cycleResolutionState': cycleResolutionState, if (failureStage != null) 'failureStage': failureStage, if (failureDiagnostics != null) 'failureDiagnostics': failureDiagnostics})}\n',
  );
  return effectiveResolutionFingerprint ?? '';
}
