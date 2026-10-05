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
    expect('${run.stdout}', contains('CCRouter watch starting'));
    expect('${run.stderr}', isNot(contains('CCRouter watch starting')));
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

Future<ProcessResult> _runAfterHookStarted(
  List<String> arguments,
  Future<void> Function() publishStatus,
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
  await publishStatus();
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
    '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'state': lastEvent == 'failed' ? 'failed' : 'building', 'active': true, 'lastEvent': lastEvent, 'pid': pid, if (includeEventIdentity) 'sessionId': sessionId, if (includeEventIdentity) 'eventRevision': eventRevision, 'cycle': cycle, 'startedAt': updatedAt.subtract(const Duration(seconds: 1)).toIso8601String(), 'updatedAt': updatedAt.toIso8601String(), 'hostRoot': project.path, 'buildRoot': project.path, 'managedByLease': false, if (effectiveResolutionFingerprint != null) 'resolutionFingerprint': effectiveResolutionFingerprint, if (cycleResolutionState != null) 'cycleResolutionState': cycleResolutionState, if (failureStage != null) 'failureStage': failureStage, if (failureDiagnostics != null) 'failureDiagnostics': failureDiagnostics})}\n',
  );
  return effectiveResolutionFingerprint ?? '';
}
