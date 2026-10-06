import 'dart:async';
import 'dart:io';

import 'package:ccrouter_generator/src/project_context.dart';
import 'package:path/path.dart' as path;

import 'bounded_process_shutdown.dart';
import 'coordination_home.dart';
import 'flutter_run_reload_gate.dart';
import 'flutter_run_watch_lease.dart';
import 'watch_startup_handshake.dart';

/// Owns the original Flutter process and its wrapper-created watch lease.
final class CCFlutterRunSupervisor {
  /// Creates a supervisor for one Hook-started Flutter run.
  const CCFlutterRunSupervisor({
    required this.originalFlutter,
    required this.flutterArguments,
    required this.hostRoot,
    required this.coordinateMachineReloads,
    this.watchLease,
    this.launchWatch = false,
    this.dartExecutable,
    this.environment = const <String, String>{},
  });

  /// Original SDK entrypoint preserved by Pub Hook installation.
  final String originalFlutter;

  /// Exact arguments originally passed to the Flutter wrapper.
  final List<String> flutterArguments;

  /// CCRouter Host associated with this Flutter run.
  final Directory hostRoot;

  /// Existing lease used by legacy callers that launch the watch themselves.
  final File? watchLease;

  /// Whether this process owns watch startup, readiness, and shutdown.
  final bool launchWatch;

  /// Dart executable used to launch the managed generation watch.
  final String? dartExecutable;

  /// Whether machine restart requests pass through the generation gate.
  final bool coordinateMachineReloads;

  /// Environment supplied to the original Flutter process.
  final Map<String, String> environment;

  /// Runs Flutter and, when requested, its complete generation-watch lifecycle.
  Future<int> run() async {
    if (launchWatch) {
      if (watchLease != null) {
        throw ArgumentError('launchWatch cannot reuse an existing watchLease.');
      }
      return _runWithManagedWatch();
    }
    final lease = watchLease;
    if (lease == null) {
      throw ArgumentError('watchLease is required when launchWatch is false.');
    }
    return _runFlutter(lease);
  }

  Future<int> _runFlutter(File? lease, {Future<void>? abortSignal}) {
    if (coordinateMachineReloads) {
      return CCFlutterMachineRunProxy(
        originalFlutter: originalFlutter,
        flutterArguments: flutterArguments,
        hostRoot: hostRoot,
        watchLease: lease,
        abortSignal: abortSignal,
        environment: environment,
      ).run();
    }
    return _CCFlutterInheritedRunProxy(
      originalFlutter: originalFlutter,
      flutterArguments: flutterArguments,
      watchLease: lease,
      abortSignal: abortSignal,
      environment: environment,
    ).run();
  }

  Future<int> _runWithManagedWatch() async {
    final context = CCProjectContext.resolve(hostRoot);
    final canonicalHost = context.requestedRoot;
    final buildRoot = context.resolutionRoot;
    final lease = await _allocateWatchLease(canonicalHost, buildRoot);
    final logFile = File(
      path.join(
        canonicalHost.path,
        '.dart_tool',
        'ccrouter',
        'v1',
        'watch',
        'flutter-run.log',
      ),
    );
    IOSink? log;
    try {
      await logFile.parent.create(recursive: true);
      log = logFile.openWrite(mode: FileMode.append);
    } on FileSystemException catch (error) {
      stderr.writeln(
        'warning: CCRouter watch log is unavailable at ${logFile.path}: '
        '$error',
      );
    }
    final leaseOwner = CCFlutterRunWatchLeaseOwner(lease);
    Process? watchProcess;
    StreamSubscription<List<int>>? watchStdout;
    StreamSubscription<List<int>>? watchStderr;
    Object? heartbeatFailure;
    final heartbeatAbort = Completer<void>();
    try {
      await leaseOwner.start(
        onFailure: (error, _) {
          heartbeatFailure ??= error;
          watchProcess?.kill();
          if (!heartbeatAbort.isCompleted) heartbeatAbort.complete();
        },
      );
      watchProcess = await Process.start(
        dartExecutable ?? Platform.resolvedExecutable,
        <String>[
          'run',
          '--verbosity=error',
          'ccrouter_generator:ccrouter',
          'generate',
          canonicalHost.path,
          '--watch=auto',
          '--machine',
          '--watch-lease',
          lease.path,
        ],
        workingDirectory: buildRoot.path,
        environment: environment,
        runInShell: Platform.isWindows,
      );
      watchStdout = _forwardWatchOutput(watchProcess.stdout, log);
      watchStderr = _forwardWatchOutput(watchProcess.stderr, log);
      stdout.writeln(
        'CCRouter watch starting (pid=${watchProcess.pid}). '
        'Status: ${path.join(canonicalHost.path, '.dart_tool', 'ccrouter', 'v1', 'watch', 'status.json')}; '
        'log: ${logFile.path}',
      );

      if (environment['CCROUTER_DISABLE_WATCH_STARTUP_HANDSHAKE'] != '1') {
        final startup = await waitForCCWatchStartup(
          hostRoot: canonicalHost,
          leaseFile: lease,
        );
        if (!startup.succeeded) {
          stderr.writeln(
            'error: CCRouter watch startup failed: ${startup.message}.',
          );
          if (startup.diagnostics case final diagnostics?) {
            stderr.writeln(diagnostics);
          }
          stderr.writeln('Watch log: ${startup.logFile.path}');
          return 1;
        }
        stdout.writeln(
          'CCRouter watch ready: elapsed=${startup.elapsed.inMilliseconds}ms.',
        );
      }
      if (heartbeatFailure != null) {
        stderr.writeln(
          'error: CCRouter Flutter-run watch lease heartbeat failed: '
          '$heartbeatFailure',
        );
        return 1;
      }

      final result = await _runFlutter(
        null,
        abortSignal: heartbeatAbort.future,
      );
      if (heartbeatFailure != null) {
        stderr.writeln(
          'error: CCRouter Flutter-run watch lease heartbeat failed: '
          '$heartbeatFailure',
        );
        return 1;
      }
      return result;
    } finally {
      await leaseOwner.close();
      if (watchProcess case final process?) {
        try {
          await stopProcessWithEscalation(process);
        } on Object catch (error) {
          stderr.writeln(
            'warning: failed to stop CCRouter generation watch: $error',
          );
        }
      }
      await watchStdout?.cancel();
      await watchStderr?.cancel();
      await log?.flush();
      await log?.close();
    }
  }

  Future<File> _allocateWatchLease(
    Directory canonicalHost,
    Directory buildRoot,
  ) async {
    final nonce = DateTime.now().microsecondsSinceEpoch;
    if (usesLegacyCCRouterCoordination(environment: environment)) {
      final directory = Directory(
        path.join(canonicalHost.path, '.dart_tool', 'ccrouter', 'v1', 'watch'),
      );
      await directory.create(recursive: true);
      return File(path.join(directory.path, 'flutter-run-$pid-$nonce.lease'));
    }
    final coordination = CCRouterCoordinationPaths.forBuildRoot(
      buildRoot,
      environment: environment,
    );
    await coordination.prepare();
    final lease = coordination.newFlutterRunLease(
      canonicalHost,
      ownerPid: pid,
      nonce: nonce,
    );
    await lease.parent.create(recursive: true);
    return lease;
  }
}

StreamSubscription<List<int>> _forwardWatchOutput(
  Stream<List<int>> source,
  IOSink? log,
) => source.listen((bytes) {
  try {
    log?.add(bytes);
  } on Object {
    // The watch result and status remain authoritative if logging is removed.
  }
}, onError: (_) {});

final class _CCFlutterInheritedRunProxy {
  const _CCFlutterInheritedRunProxy({
    required this.originalFlutter,
    required this.flutterArguments,
    required this.watchLease,
    this.abortSignal,
    required this.environment,
  });

  final String originalFlutter;
  final List<String> flutterArguments;
  final File? watchLease;
  final Future<void>? abortSignal;
  final Map<String, String> environment;

  Future<int> run() async {
    final process = await Process.start(
      originalFlutter,
      flutterArguments,
      workingDirectory: Directory.current.path,
      environment: environment,
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
    Object? heartbeatFailure;
    final leaseOwner = watchLease == null
        ? null
        : CCFlutterRunWatchLeaseOwner(watchLease!);
    try {
      await leaseOwner?.start(
        onFailure: (error, _) {
          heartbeatFailure ??= error;
          process.kill();
        },
      );
    } on Object {
      process.kill();
      await process.exitCode;
      await leaseOwner?.close();
      rethrow;
    }
    final signalSubscriptions = _forwardTerminationSignals(process);
    try {
      final childExitCode = await _waitForProcessOrAbort(process, abortSignal);
      if (heartbeatFailure != null) {
        stderr.writeln(
          'error: CCRouter Flutter-run watch lease heartbeat failed: '
          '$heartbeatFailure',
        );
        return 1;
      }
      return childExitCode;
    } finally {
      for (final subscription in signalSubscriptions) {
        await subscription.cancel();
      }
      await leaseOwner?.close();
    }
  }
}

Future<int> _waitForProcessOrAbort(Process process, Future<void>? abortSignal) {
  if (abortSignal == null) return process.exitCode;
  return Future.any<int>(<Future<int>>[
    process.exitCode,
    abortSignal.then((_) async {
      process.kill();
      return process.exitCode;
    }),
  ]);
}

List<StreamSubscription<ProcessSignal>> _forwardTerminationSignals(
  Process process,
) {
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  for (final signal in <ProcessSignal>[
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ]) {
    try {
      subscriptions.add(
        signal.watch().listen((_) {
          if (Platform.isWindows) {
            process.kill();
          } else {
            process.kill(signal);
          }
        }),
      );
    } on Object {
      // A platform may not expose every signal.
    }
  }
  return subscriptions;
}
