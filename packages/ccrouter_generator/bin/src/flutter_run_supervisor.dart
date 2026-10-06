import 'dart:async';
import 'dart:io';

import 'flutter_run_reload_gate.dart';
import 'flutter_run_watch_lease.dart';

/// Owns the original Flutter process and its wrapper-created watch lease.
final class CCFlutterRunSupervisor {
  /// Creates a supervisor for one Hook-started Flutter run.
  const CCFlutterRunSupervisor({
    required this.originalFlutter,
    required this.flutterArguments,
    required this.hostRoot,
    required this.watchLease,
    required this.coordinateMachineReloads,
    this.environment = const <String, String>{},
  });

  /// Original SDK entrypoint preserved by Pub Hook installation.
  final String originalFlutter;

  /// Exact arguments originally passed to the Flutter wrapper.
  final List<String> flutterArguments;

  /// CCRouter Host associated with this Flutter run.
  final Directory hostRoot;

  /// Wrapper-created lease controlling the background watch.
  final File watchLease;

  /// Whether machine restart requests pass through the generation gate.
  final bool coordinateMachineReloads;

  /// Environment supplied to the original Flutter process.
  final Map<String, String> environment;

  /// Runs Flutter until the child or lease heartbeat fails.
  Future<int> run() {
    if (coordinateMachineReloads) {
      return CCFlutterMachineRunProxy(
        originalFlutter: originalFlutter,
        flutterArguments: flutterArguments,
        hostRoot: hostRoot,
        watchLease: watchLease,
        environment: environment,
      ).run();
    }
    return _CCFlutterInheritedRunProxy(
      originalFlutter: originalFlutter,
      flutterArguments: flutterArguments,
      watchLease: watchLease,
      environment: environment,
    ).run();
  }
}

final class _CCFlutterInheritedRunProxy {
  const _CCFlutterInheritedRunProxy({
    required this.originalFlutter,
    required this.flutterArguments,
    required this.watchLease,
    required this.environment,
  });

  final String originalFlutter;
  final List<String> flutterArguments;
  final File watchLease;
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
    final leaseOwner = CCFlutterRunWatchLeaseOwner(watchLease);
    try {
      await leaseOwner.start(
        onFailure: (error, _) {
          heartbeatFailure ??= error;
          process.kill();
        },
      );
    } on Object {
      process.kill();
      await process.exitCode;
      await leaseOwner.close();
      rethrow;
    }
    final signalSubscriptions = _forwardTerminationSignals(process);
    try {
      final childExitCode = await process.exitCode;
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
      await leaseOwner.close();
    }
  }
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
