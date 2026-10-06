@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test(
    'watch status reports a missing local state without creating it',
    () async {
      final host = await Directory.systemTemp.createTemp(
        'ccrouter_watch_status_missing_',
      );
      addTearDown(() => host.delete(recursive: true));

      final result = await _run(['watch', 'status', host.path]);

      expect(result.exitCode, 1);
      expect('${result.stderr}', contains('watch status is unavailable'));
      expect(host.listSync(recursive: true), isEmpty);
    },
  );

  test('watch status and follow read an atomically published state', () async {
    final host = await Directory.systemTemp.createTemp(
      'ccrouter_watch_status_read_',
    );
    addTearDown(() => host.delete(recursive: true));
    final file = File(
      path.join(
        host.path,
        '.dart_tool',
        'ccrouter',
        'v1',
        'watch',
        'status.json',
      ),
    )..parent.createSync(recursive: true);
    final document = <String, Object?>{
      'schemaVersion': 1,
      'state': 'stopped',
      'active': false,
      'lastEvent': 'stopped',
      'pid': 123,
      'cycle': 4,
      'startedAt': '2026-10-05T10:00:00.000Z',
      'updatedAt': '2026-10-05T10:00:04.000Z',
      'hostRoot': host.path,
      'buildRoot': host.path,
      'managedByLease': true,
      'lastBuildElapsedMs': 900,
      'lastBuildRunnerMs': 800,
      'lastAggregationElapsedMs': 700,
      'lastCycleMode': 'inProcess',
    };
    final original = '${jsonEncode(document)}\n';
    file.writeAsStringSync(original);

    final status = await _run(['watch', 'status', host.path]);
    expect(status.exitCode, 0, reason: '${status.stderr}');
    expect('${status.stdout}', contains('CCRouter watch status: inactive'));
    expect('${status.stdout}', contains('state: stopped'));
    expect('${status.stdout}', contains('build_runner: 800ms'));
    expect('${status.stdout}', contains('cycle mode: inProcess'));

    final follow = await _run(['watch', 'follow', host.path]);
    expect(follow.exitCode, 0, reason: '${follow.stderr}');
    expect('${follow.stdout}', contains('state=stopped'));
    expect('${follow.stdout}', contains('build_runner=800ms'));
    expect(file.readAsStringSync(), original);
  });

  test('watch follow exits after an inactive startup failure', () async {
    final host = await Directory.systemTemp.createTemp(
      'ccrouter_watch_status_failed_',
    );
    addTearDown(() => host.delete(recursive: true));
    final file = File(
      path.join(
        host.path,
        '.dart_tool',
        'ccrouter',
        'v1',
        'watch',
        'status.json',
      ),
    )..parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'state': 'failed', 'active': false, 'lastEvent': 'failed', 'pid': 123, 'cycle': 0, 'startedAt': '2026-10-05T10:00:00.000Z', 'updatedAt': '2026-10-05T10:00:01.000Z', 'hostRoot': host.path, 'buildRoot': host.path, 'managedByLease': false, 'lastFailureAt': '2026-10-05T10:00:01.000Z', 'failureStage': 'watch-start', 'lastBuildElapsedMs': 950, 'lastBuildRunnerMs': 820})}\n',
    );

    final follow = await _run(['watch', 'follow', host.path]);

    expect(follow.exitCode, 0, reason: '${follow.stderr}');
    expect('${follow.stdout}', contains('state=failed'));
    expect('${follow.stdout}', contains('failure=watch-start'));
    expect('${follow.stdout}', contains('build=950ms'));
    expect('${follow.stdout}', contains('build_runner=820ms'));
  });

  test('watch status rejects malformed local state', () async {
    final host = await Directory.systemTemp.createTemp(
      'ccrouter_watch_status_malformed_',
    );
    addTearDown(() => host.delete(recursive: true));
    final file = File(
      path.join(
        host.path,
        '.dart_tool',
        'ccrouter',
        'v1',
        'watch',
        'status.json',
      ),
    )..parent.createSync(recursive: true);
    file.writeAsStringSync('{"schemaVersion":1,"state":"ready"}\n');

    final result = await _run(['watch', 'status', host.path]);

    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('watch status is unavailable'));
  });

  test('watch status persists failure diagnostics', () async {
    final host = await Directory.systemTemp.createTemp(
      'ccrouter_watch_status_diagnostics_',
    );
    addTearDown(() => host.delete(recursive: true));
    File(path.join(host.path, 'pubspec.yaml')).writeAsStringSync('''
name: broken_watch_host
environment:
  sdk: ^3.10.0
dependencies:
  ccrouter: any
''');
    File(
      path.join(host.path, '.metadata'),
    ).writeAsStringSync('project_type: app\n');

    final result = await _run([
      'generate',
      host.path,
      '--watch=auto',
      '--machine',
    ]);
    final statusFile = File(
      path.join(
        host.path,
        '.dart_tool',
        'ccrouter',
        'v1',
        'watch',
        'status.json',
      ),
    );
    final status = jsonDecode(statusFile.readAsStringSync()) as Map;
    final diagnostics =
        jsonDecode(
              File(
                path.join(
                  host.path,
                  '.dart_tool',
                  'ccrouter',
                  'v1',
                  'watch',
                  'diagnostics.json',
                ),
              ).readAsStringSync(),
            )
            as Map;

    expect(result.exitCode, 1);
    expect(status['lastEvent'], 'failed');
    expect(status['sessionId'], isA<String>());
    expect((status['sessionId'] as String), isNotEmpty);
    expect(status['eventRevision'], isA<int>());
    expect(status['eventRevision'], greaterThan(0));
    expect(status['failureStage'], 'workspace');
    expect(
      status['failureDiagnostics'],
      contains('Resolved Package graph is missing'),
    );
    expect(diagnostics['schemaVersion'], 1);
    expect(diagnostics['hostRoot'], status['hostRoot']);
    expect(diagnostics['buildRoot'], status['buildRoot']);
    expect(diagnostics['sessionId'], status['sessionId']);
    expect(diagnostics['eventRevision'], status['eventRevision']);
    expect(diagnostics['cycle'], status['cycle']);
    expect(diagnostics['lastEvent'], status['lastEvent']);
    expect(diagnostics['diagnostics'], isEmpty);
  });

  test('watch status verifies active records against the owner lock', () async {
    final host = await Directory.systemTemp.createTemp(
      'ccrouter_watch_status_liveness_',
    );
    addTearDown(() => host.delete(recursive: true));
    final watchDirectory = Directory(
      path.join(host.path, '.dart_tool', 'ccrouter', 'v1', 'watch'),
    )..createSync(recursive: true);
    final statusFile = File(path.join(watchDirectory.path, 'status.json'));
    statusFile.writeAsStringSync(
      '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'state': 'ready', 'active': true, 'lastEvent': 'ready', 'pid': 123, 'cycle': 1, 'startedAt': '2026-10-05T10:00:00.000Z', 'updatedAt': '2026-10-05T10:00:01.000Z', 'hostRoot': host.path, 'buildRoot': host.path, 'managedByLease': false})}\n',
    );
    final owner = await File(
      path.join(watchDirectory.path, 'owner.lock'),
    ).open(mode: FileMode.append);
    await owner.lock(FileLock.exclusive);
    try {
      final active = await _run(['watch', 'status', host.path]);
      expect(active.exitCode, 0, reason: '${active.stderr}');
      expect('${active.stdout}', contains('watch status: active'));
      expect('${active.stdout}', contains('state: ready'));
    } finally {
      await owner.unlock();
      await owner.close();
    }

    final stale = await _run(['watch', 'status', host.path]);
    expect(stale.exitCode, 0, reason: '${stale.stderr}');
    expect('${stale.stdout}', contains('watch status: inactive'));
    expect('${stale.stdout}', contains('state: stale'));
    expect('${stale.stdout}', contains('recorded state: ready'));

    final follow = await _run(['watch', 'follow', host.path]);
    expect(follow.exitCode, 0, reason: '${follow.stderr}');
    expect('${follow.stdout}', contains('state=stale'));
  });

  test('watch rejects unsupported observation actions and options', () async {
    final action = await _run(['watch', 'start']);
    expect(action.exitCode, 2);
    expect('${action.stderr}', contains('watch requires `status` or `follow`'));

    final option = await _run(['watch', 'status', '--machine']);
    expect(option.exitCode, 2);
    expect(
      '${option.stderr}',
      contains('watch status accepts one optional Host root'),
    );
  });
}

Future<ProcessResult> _run(List<String> arguments) => Process.run(
  Platform.resolvedExecutable,
  ['run', 'ccrouter_generator:ccrouter', ...arguments],
  workingDirectory: Directory.current.path,
);
