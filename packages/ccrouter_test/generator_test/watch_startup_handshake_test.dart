@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../ccrouter_generator/bin/src/coordination_home.dart';
import '../../ccrouter_generator/bin/src/flutter_run_watch_lease.dart';

void main() {
  test('accepts only the exact ready lease with a live owner', () async {
    final fixture = await _HandshakeFixture.create();
    addTearDown(fixture.dispose);
    final owner = await fixture.lockOwner();
    addTearDown(() async {
      await owner.unlock();
      await owner.close();
    });
    fixture.writeStatus(lastEvent: 'ready', active: true, sessionReady: true);

    final result = await fixture.run();

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}', contains('CCRouter watch ready'));
    expect('${result.stdout}', contains('pid=4242'));
  });

  test('reports a watch ownership conflict immediately', () async {
    final fixture = await _HandshakeFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeStatus(
      lastEvent: 'failed',
      active: false,
      sessionReady: false,
      failureStage: 'watch-lock',
      failureDiagnostics: 'another watch owns this build root',
    );
    final watch = Stopwatch()..start();

    final result = await fixture.run();
    watch.stop();

    expect(result.exitCode, 1);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect('${result.stderr}', contains('watch failed at watch-lock'));
    expect('${result.stderr}', contains('another watch owns this build root'));
    expect('${result.stderr}', contains('flutter-run.log'));
  });

  test('does not accept stale status from another lease', () async {
    final fixture = await _HandshakeFixture.create();
    addTearDown(fixture.dispose);
    final staleLease = File(
      path.join(fixture.watchDirectory.path, 'stale.lease'),
    )..writeAsStringSync('');
    fixture.writeStatus(
      lastEvent: 'ready',
      active: true,
      sessionReady: true,
      leasePath: staleLease.path,
    );

    final result = await fixture.run(startupTimeoutMs: 50);

    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('lease-bound startup status'));
  });

  test('accepts an exact lease acknowledged by an existing watch', () async {
    final fixture = await _HandshakeFixture.create();
    addTearDown(fixture.dispose);
    final owner = await fixture.lockOwner();
    addTearDown(() async {
      await owner.unlock();
      await owner.close();
    });
    final primaryLease = File(
      path.join(fixture.watchDirectory.path, 'primary.lease'),
    )..writeAsStringSync('');
    fixture.writeStatus(
      lastEvent: 'ready',
      active: true,
      sessionReady: true,
      leasePath: primaryLease.path,
    );
    ccrouterFlutterRunLeaseAttachmentFile(fixture.leaseFile).writeAsStringSync(
      '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'marker': ccrouterFlutterRunLeaseAttachmentMarker, 'watchPid': 4242})}\n',
    );

    final result = await fixture.run();

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}', contains('CCRouter watch reused'));
  });

  test('rejects an attachment acknowledged by a different watch PID', () async {
    final fixture = await _HandshakeFixture.create();
    addTearDown(fixture.dispose);
    final owner = await fixture.lockOwner();
    addTearDown(() async {
      await owner.unlock();
      await owner.close();
    });
    final primaryLease = File(
      path.join(fixture.watchDirectory.path, 'primary.lease'),
    )..writeAsStringSync('');
    fixture.writeStatus(
      lastEvent: 'ready',
      active: true,
      sessionReady: true,
      leasePath: primaryLease.path,
    );
    ccrouterFlutterRunLeaseAttachmentFile(fixture.leaseFile).writeAsStringSync(
      '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'marker': ccrouterFlutterRunLeaseAttachmentMarker, 'watchPid': 9999})}\n',
    );

    final result = await fixture.run(startupTimeoutMs: 50);

    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('lease-bound startup status'));
  });

  test('does not accept ready status after ownership was released', () async {
    final fixture = await _HandshakeFixture.create();
    addTearDown(fixture.dispose);
    fixture.ownerFile.createSync(recursive: true);
    fixture.writeStatus(lastEvent: 'ready', active: true, sessionReady: true);

    final result = await fixture.run(readyTimeoutMs: 100);

    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('initial generation'));
  });

  test('rejects ready status backed only by a legacy V1 owner', () async {
    final fixture = await _HandshakeFixture.create();
    addTearDown(fixture.dispose);
    final owner = await fixture.lockLegacyOwner();
    addTearDown(() async {
      await owner.unlock();
      await owner.close();
    });
    fixture.writeStatus(lastEvent: 'ready', active: true, sessionReady: true);
    final watch = Stopwatch()..start();

    final result = await fixture.run();
    watch.stop();

    expect(result.exitCode, 1);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect('${result.stderr}', contains('legacy CCRouter generation owner'));
    expect('${result.stderr}', contains('reinstall the current Pub Hook'));
  });

  test(
    'accepts the legacy owner when legacy coordination is selected',
    () async {
      final fixture = await _HandshakeFixture.create();
      addTearDown(fixture.dispose);
      final owner = await fixture.lockLegacyOwner();
      addTearDown(() async {
        await owner.unlock();
        await owner.close();
      });
      fixture.writeStatus(lastEvent: 'ready', active: true, sessionReady: true);

      final result = await fixture.run(useLegacyCoordination: true);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}', contains('CCRouter watch ready'));
    },
  );

  test('fails immediately when the wrapper lease disappears', () async {
    final fixture = await _HandshakeFixture.create();
    addTearDown(fixture.dispose);
    fixture.leaseFile.deleteSync();

    final result = await fixture.run();

    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('watch lease disappeared'));
  });
}

final class _HandshakeFixture {
  _HandshakeFixture._({
    required this.host,
    required this.watchDirectory,
    required this.leaseFile,
    required this.statusFile,
    required this.ownerFile,
    required this.coordinationHome,
  });

  final Directory host;
  final Directory watchDirectory;
  final File leaseFile;
  final File statusFile;
  final File ownerFile;
  final Directory coordinationHome;

  static Future<_HandshakeFixture> create() async {
    final host = await Directory.systemTemp.createTemp(
      'ccrouter-watch-startup-',
    );
    final watchDirectory = Directory(
      path.join(host.path, '.dart_tool', 'ccrouter', 'v1', 'watch'),
    )..createSync(recursive: true);
    final leaseFile = File(path.join(watchDirectory.path, 'flutter-run.lease'))
      ..writeAsStringSync('');
    final coordinationHome = Directory(path.join(host.path, 'coordination'));
    final coordination = CCRouterCoordinationPaths.forBuildRoot(
      host,
      environment: {ccrouterHomeEnvironment: coordinationHome.path},
    );
    await coordination.prepare();
    return _HandshakeFixture._(
      host: host,
      watchDirectory: watchDirectory,
      leaseFile: leaseFile,
      statusFile: File(path.join(watchDirectory.path, 'status.json')),
      ownerFile: coordination.ownerLock,
      coordinationHome: coordinationHome,
    );
  }

  Future<RandomAccessFile> lockOwner() async {
    return _lock(ownerFile);
  }

  Future<RandomAccessFile> lockLegacyOwner() => _lock(
    legacyCCRouterWatchOwnerLockFile(host)..parent.createSync(recursive: true),
  );

  Future<RandomAccessFile> _lock(File file) async {
    final owner = await file.open(mode: FileMode.append);
    await owner.lock(FileLock.exclusive);
    return owner;
  }

  void writeStatus({
    required String lastEvent,
    required bool active,
    required bool sessionReady,
    String? leasePath,
    String? failureStage,
    String? failureDiagnostics,
  }) {
    statusFile.writeAsStringSync(
      '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'state': lastEvent, 'active': active, 'lastEvent': lastEvent, 'pid': 4242, 'sessionId': 'session-1', 'eventRevision': 1, 'sessionReady': sessionReady, 'cycle': 1, 'hostRoot': host.path, 'buildRoot': host.path, 'managedByLease': true, 'leasePath': leasePath ?? leaseFile.path, if (failureStage != null) 'failureStage': failureStage, if (failureDiagnostics != null) 'failureDiagnostics': failureDiagnostics})}\n',
    );
  }

  Future<ProcessResult> run({
    int startupTimeoutMs = 500,
    int readyTimeoutMs = 1000,
    bool useLegacyCoordination = false,
  }) => Process.run(
    Platform.resolvedExecutable,
    <String>[
      'run',
      '--verbosity=error',
      'ccrouter_generator:ccrouter_watch_startup',
      '--host-root',
      host.path,
      '--watch-lease',
      leaseFile.path,
      '--startup-timeout-ms',
      '$startupTimeoutMs',
      '--ready-timeout-ms',
      '$readyTimeoutMs',
    ],
    workingDirectory: Directory.current.path,
    environment: {
      ...Platform.environment,
      ccrouterHomeEnvironment: coordinationHome.path,
      if (useLegacyCoordination) ccrouterLegacyCoordinationEnvironment: '1',
    },
  );

  Future<void> dispose() => host.delete(recursive: true);
}
