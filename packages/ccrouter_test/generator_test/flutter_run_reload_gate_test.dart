@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../ccrouter_generator/bin/src/canonical_directory_identity.dart';
import '../../ccrouter_generator/bin/src/flutter_run_reload_gate.dart';
import '../../ccrouter_generator/bin/src/flutter_run_supervisor.dart';
import '../../ccrouter_generator/bin/src/flutter_run_watch_lease.dart';

void main() {
  test(
    'canonical identity resolves the macOS temporary-directory alias',
    () {
      expect(hasSameDirectoryIdentity('/tmp', '/private/tmp'), isTrue);
    },
    skip: Platform.isMacOS ? false : 'macOS filesystem alias only',
  );

  test('reload waits for the cycle covering the observed input', () async {
    final host = await _createHost();
    addTearDown(() => host.delete(recursive: true));
    _writeStatus(
      host,
      lastEvent: 'inputChanged',
      inputRevision: 1,
      completedInputRevision: 0,
    );
    final wait = _gate(host).wait(fullRestart: false);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    _writeStatus(
      host,
      lastEvent: 'aggregationSucceeded',
      inputRevision: 1,
      completedInputRevision: 1,
      cycleResolutionState: 'matched',
    );

    final result = await wait;
    expect(result.outcome, CCFlutterReloadGateOutcome.ready);
    expect(result.sessionId, 'session-1');
  });

  test('reload does not accept an older cycle after a second save', () async {
    final host = await _createHost();
    addTearDown(() => host.delete(recursive: true));
    _writeStatus(
      host,
      lastEvent: 'inputChanged',
      inputRevision: 1,
      completedInputRevision: 0,
    );
    final wait = _gate(host).wait(fullRestart: false);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    _writeStatus(
      host,
      lastEvent: 'aggregationSucceeded',
      inputRevision: 2,
      completedInputRevision: 1,
      cycleResolutionState: 'matched',
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));
    _writeStatus(
      host,
      lastEvent: 'aggregationSucceeded',
      inputRevision: 2,
      completedInputRevision: 2,
      cycleResolutionState: 'matched',
    );

    final result = await wait;
    expect(result.outcome, CCFlutterReloadGateOutcome.ready);
    expect(result.message, contains('revision 2'));
  });

  test('generation failure blocks the matching reload', () async {
    final host = await _createHost();
    addTearDown(() => host.delete(recursive: true));
    _writeStatus(
      host,
      lastEvent: 'failed',
      inputRevision: 3,
      completedInputRevision: 2,
      failedInputRevision: 3,
      failureStage: 'aggregation',
      failureDiagnostics: 'error: missing demo_order owner',
      cycleResolutionState: 'matched',
    );

    final result = await _gate(host).wait(fullRestart: false);

    expect(result.outcome, CCFlutterReloadGateOutcome.failed);
    expect(result.message, contains('aggregation'));
    expect(result.diagnostics, contains('missing demo_order owner'));
  });

  test('topology change rejects reload but permits explicit restart', () async {
    final host = await _createHost();
    addTearDown(() => host.delete(recursive: true));
    _writeStatus(
      host,
      lastEvent: 'ready',
      inputRevision: 0,
      completedInputRevision: 0,
      cycleResolutionState: 'matched',
      hotRestartRequired: true,
    );
    final gate = _gate(host);

    final reload = await gate.wait(fullRestart: false);
    final restart = await gate.wait(fullRestart: true);
    final acknowledged = await gate.wait(
      fullRestart: false,
      acknowledgedHotRestartSessionId: 'session-1',
    );

    expect(reload.outcome, CCFlutterReloadGateOutcome.hotRestartRequired);
    expect(restart.outcome, CCFlutterReloadGateOutcome.ready);
    expect(acknowledged.outcome, CCFlutterReloadGateOutcome.ready);
  });

  test(
    'host identity accepts a symbolic-link alias',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ccrouter_reload_gate_alias_',
      );
      addTearDown(() => root.delete(recursive: true));
      final host = Directory(path.join(root.path, 'host'))..createSync();
      final alias = Link(path.join(root.path, 'host-alias'));
      await alias.create(host.path);
      final aliasedHost = Directory(alias.path);
      _statusFile(aliasedHost).parent.createSync(recursive: true);
      _writeStatus(
        aliasedHost,
        lastEvent: 'ready',
        inputRevision: 1,
        completedInputRevision: 1,
        cycleResolutionState: 'matched',
      );

      final result = await _gate(aliasedHost).wait(fullRestart: false);

      expect(result.outcome, CCFlutterReloadGateOutcome.ready);
    },
    skip: Platform.isWindows ? 'symbolic-link setup is not portable' : false,
  );

  test('missing versioned input evidence fails within the bound', () async {
    final host = await _createHost();
    addTearDown(() => host.delete(recursive: true));
    final file = _statusFile(host);
    file.writeAsStringSync(
      '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'active': true, 'hostRoot': host.path, 'sessionId': 'old-watch', 'lastEvent': 'ready'})}\n',
    );

    final result = await CCFlutterReloadGate(
      hostRoot: host,
      observationWindow: Duration.zero,
      pollInterval: const Duration(milliseconds: 5),
      timeout: const Duration(milliseconds: 40),
    ).wait(fullRestart: false);

    expect(result.outcome, CCFlutterReloadGateOutcome.timedOut);
  });

  test('machine proxy forwards reload only after matching success', () async {
    final host = await _createHost();
    addTearDown(() => host.delete(recursive: true));
    _writeStatus(
      host,
      lastEvent: 'ready',
      inputRevision: 1,
      completedInputRevision: 1,
      cycleResolutionState: 'matched',
    );
    final trace = File(path.join(host.path, 'machine-input.txt'));
    final original = await _fakeFlutter(host, trace);
    final process = await _startProxy(host, original);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    final request = jsonEncode(<Object?>[
      <String, Object?>{
        'id': 7,
        'method': 'app.restart',
        'params': <String, Object?>{'fullRestart': false},
      },
    ]);

    process.stdin.writeln(request);
    await process.stdin.flush();
    final result = await process.exitCode.timeout(const Duration(seconds: 10));

    expect(result, 0, reason: await errors);
    expect(trace.readAsStringSync().trim(), request);
    expect(await output, isEmpty);
  });

  test('machine proxy forwards parent stdin EOF to Flutter', () async {
    final host = await _createHost();
    addTearDown(() => host.delete(recursive: true));
    final trace = File(path.join(host.path, 'machine-eof.txt'));
    final original = await _fakeFlutterWaitingForEof(host, trace);
    final process = await _startProxy(host, original);
    final errors = process.stderr.transform(utf8.decoder).join();

    await process.stdin.close();
    final result = await process.exitCode.timeout(const Duration(seconds: 10));

    expect(result, 0, reason: await errors);
    expect(trace.readAsStringSync(), 'eof\n');
  });

  test(
    'Flutter run supervisor preserves exit and removes its lease',
    () async {
      final host = await _createHost();
      addTearDown(() => host.delete(recursive: true));
      final lease = File(path.join(host.path, 'flutter-run.lease'))
        ..writeAsStringSync('');
      final original = File(path.join(host.path, 'fake-flutter-exit'))
        ..writeAsStringSync('#!/usr/bin/env bash\nexit 23\n');
      final chmod = await Process.run('chmod', <String>['+x', original.path]);
      expect(chmod.exitCode, 0, reason: '${chmod.stderr}');

      final result = await CCFlutterRunSupervisor(
        originalFlutter: original.path,
        flutterArguments: const <String>['run'],
        hostRoot: host,
        watchLease: lease,
        coordinateMachineReloads: false,
        environment: Platform.environment,
      ).run();

      expect(result, 23);
      expect(lease.existsSync(), isFalse);
    },
    skip: Platform.isWindows ? 'POSIX fixture executable' : false,
  );

  test(
    'interactive supervisor reports that terminal reload is ungated',
    () async {
      final host = await _createHost();
      addTearDown(() => host.delete(recursive: true));
      final lease = File(path.join(host.path, 'flutter-run.lease'))
        ..writeAsStringSync('');
      final original = File(path.join(host.path, 'fake-flutter-exit'))
        ..writeAsStringSync('#!/usr/bin/env bash\nexit 0\n');
      final chmod = await Process.run('chmod', <String>['+x', original.path]);
      expect(chmod.exitCode, 0, reason: '${chmod.stderr}');

      final process = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        'ccrouter_generator:ccrouter_flutter_run_supervisor',
        '--host-root',
        host.path,
        '--original',
        original.path,
        '--watch-lease',
        lease.path,
        '--',
        'run',
      ], workingDirectory: Directory.current.path);

      expect(process.exitCode, 0, reason: '${process.stderr}');
      expect(
        '${process.stdout}',
        allOf(contains('not generation-gated'), contains('pressing r or R')),
      );
      expect(lease.existsSync(), isFalse);
    },
    skip: Platform.isWindows ? 'POSIX fixture executable' : false,
  );

  test(
    'Flutter run supervisor cleans its lease after termination',
    () async {
      final host = await _createHost();
      addTearDown(() => host.delete(recursive: true));
      final lease = File(path.join(host.path, 'flutter-run-signal.lease'))
        ..writeAsStringSync('');
      final ready = File(path.join(host.path, 'flutter-ready'));
      final original = File(path.join(host.path, 'fake-flutter-wait'))
        ..writeAsStringSync('''#!/usr/bin/env bash
trap 'exit 0' INT TERM
touch "${ready.path}"
while true; do sleep 1; done
''');
      final chmod = await Process.run('chmod', <String>['+x', original.path]);
      expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
      final process = await Process.start(Platform.resolvedExecutable, <String>[
        'run',
        'ccrouter_generator:ccrouter_flutter_run_supervisor',
        '--host-root',
        host.path,
        '--original',
        original.path,
        '--watch-lease',
        lease.path,
        '--',
        'run',
      ], workingDirectory: Directory.current.path);
      final errors = process.stderr.transform(utf8.decoder).join();
      await _waitFor(() => ready.existsSync() && _hasHeartbeat(lease));

      expect(process.kill(ProcessSignal.sigterm), isTrue);
      final result = await process.exitCode.timeout(
        const Duration(seconds: 10),
      );

      expect(result, isNot(1), reason: await errors);
      expect(lease.existsSync(), isFalse);
    },
    skip: Platform.isWindows ? 'POSIX signal fixture' : false,
  );

  test('stale supervised lease expires an orphaned watch', () async {
    final host = await _createHost();
    addTearDown(() => host.delete(recursive: true));
    final lease = File(path.join(host.path, 'flutter-run-stale.lease'))
      ..writeAsStringSync('$ccrouterFlutterRunLeaseHeartbeatMarker\n');
    final expired = Completer<void>();
    final monitor = CCFlutterRunWatchLeaseMonitor.start(
      lease,
      () => expired.complete(),
      pollInterval: const Duration(milliseconds: 5),
      staleAfter: const Duration(milliseconds: 50),
    );
    addTearDown(monitor.close);
    sleep(const Duration(milliseconds: 120));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      expired.isCompleted,
      isFalse,
      reason: 'suspension is not owner death',
    );

    await expired.future.timeout(const Duration(seconds: 1));

    expect(lease.existsSync(), isFalse);
  });

  test(
    'machine proxy returns daemon error and withholds failed reload',
    () async {
      final host = await _createHost();
      addTearDown(() => host.delete(recursive: true));
      _writeStatus(
        host,
        lastEvent: 'failed',
        inputRevision: 2,
        completedInputRevision: 1,
        failedInputRevision: 2,
        failureStage: 'aggregation',
        failureDiagnostics: 'error: invalid Host graph',
        cycleResolutionState: 'matched',
      );
      final trace = File(path.join(host.path, 'machine-input.txt'));
      final original = await _fakeFlutter(host, trace);
      final process = await _startProxy(host, original);
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.transform(utf8.decoder).join();
      final reload = jsonEncode(<Object?>[
        <String, Object?>{
          'id': 11,
          'method': 'app.restart',
          'params': <String, Object?>{'fullRestart': false},
        },
      ]);
      final shutdown = jsonEncode(<Object?>[
        <String, Object?>{'id': 12, 'method': 'daemon.shutdown'},
      ]);

      process.stdin
        ..writeln(reload)
        ..writeln(shutdown);
      await process.stdin.flush();
      final result = await process.exitCode.timeout(
        const Duration(seconds: 10),
      );
      final proxyOutput = await output;
      final proxyErrors = await errors;

      expect(result, 0, reason: proxyErrors);
      expect(trace.readAsStringSync().trim(), shutdown);
      expect(proxyOutput, contains('"id":11'));
      expect(proxyOutput, contains('CCRouter generation failed'));
      expect(proxyErrors, contains('invalid Host graph'));
    },
  );
}

CCFlutterReloadGate _gate(Directory host) => CCFlutterReloadGate(
  hostRoot: host,
  observationWindow: const Duration(milliseconds: 10),
  pollInterval: const Duration(milliseconds: 5),
  timeout: const Duration(seconds: 1),
);

Future<Directory> _createHost() async {
  final host = await Directory.systemTemp.createTemp('ccrouter_reload_gate_');
  _statusFile(host).parent.createSync(recursive: true);
  return host;
}

File _statusFile(Directory host) => File(
  path.join(host.path, '.dart_tool', 'ccrouter', 'v1', 'watch', 'status.json'),
);

void _writeStatus(
  Directory host, {
  required String lastEvent,
  required int inputRevision,
  required int completedInputRevision,
  int? failedInputRevision,
  String? failureStage,
  String? failureDiagnostics,
  String? cycleResolutionState,
  bool hotRestartRequired = false,
}) {
  _statusFile(host).writeAsStringSync(
    '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'state': lastEvent, 'active': true, 'lastEvent': lastEvent, 'pid': pid, 'sessionId': 'session-1', 'eventRevision': 1, 'sessionReady': true, 'cycle': 1, 'inputRevision': inputRevision, 'cycleInputRevision': inputRevision, 'completedInputRevision': completedInputRevision, if (failedInputRevision != null) 'failedInputRevision': failedInputRevision, 'hotRestartRequired': hotRestartRequired, 'startedAt': DateTime.now().toUtc().toIso8601String(), 'updatedAt': DateTime.now().toUtc().toIso8601String(), 'hostRoot': host.path, 'buildRoot': host.path, 'managedByLease': true, if (failureStage != null) 'failureStage': failureStage, if (failureDiagnostics != null) 'failureDiagnostics': failureDiagnostics, if (cycleResolutionState != null) 'cycleResolutionState': cycleResolutionState})}\n',
  );
}

Future<File> _fakeFlutter(Directory host, File trace) async {
  final file = File(path.join(host.path, 'fake-flutter'));
  file.writeAsStringSync('''#!/usr/bin/env bash
IFS= read -r line
printf "%s\\n" "\$line" > "${trace.path}"
exit 0
''');
  final chmod = await Process.run('chmod', <String>['+x', file.path]);
  expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
  return file;
}

Future<File> _fakeFlutterWaitingForEof(Directory host, File trace) async {
  final file = File(path.join(host.path, 'fake-flutter-eof'));
  file.writeAsStringSync('''#!/usr/bin/env bash
cat >/dev/null
printf "eof\\n" > "${trace.path}"
''');
  final chmod = await Process.run('chmod', <String>['+x', file.path]);
  expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
  return file;
}

Future<Process> _startProxy(Directory host, File original) =>
    Process.start(Platform.resolvedExecutable, <String>[
      'run',
      'ccrouter_generator:ccrouter_flutter_run_gate',
      '--host-root',
      host.path,
      '--original',
      original.path,
      '--',
      'run',
      '--machine',
    ], workingDirectory: Directory.current.path);

Future<void> _waitFor(bool Function() predicate) async {
  final watch = Stopwatch()..start();
  while (!predicate()) {
    if (watch.elapsed > const Duration(seconds: 10)) {
      throw TimeoutException('Timed out waiting for test process readiness.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

bool _hasHeartbeat(File lease) {
  try {
    return lease.readAsStringSync().trim() ==
        ccrouterFlutterRunLeaseHeartbeatMarker;
  } on FileSystemException {
    return false;
  }
}
