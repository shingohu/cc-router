import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'canonical_directory_identity.dart';
import 'coordination_home.dart';

/// Terminal outcome of waiting for one wrapper-owned generation watch.
enum CCWatchStartupOutcome {
  /// The exact leased watch owns its build root and published session readiness.
  ready,

  /// The exact leased watch published a terminal startup failure.
  failed,

  /// The watch process did not publish its lease-bound status in time.
  unavailable,

  /// The watch started but did not complete initial generation in time.
  timedOut,
}

/// Immutable evidence returned by the Flutter wrapper startup handshake.
final class CCWatchStartupResult {
  /// Creates one bounded startup result.
  const CCWatchStartupResult({
    required this.outcome,
    required this.message,
    required this.elapsed,
    required this.logFile,
    this.pid,
    this.sessionId,
    this.diagnostics,
  });

  /// Terminal startup classification.
  final CCWatchStartupOutcome outcome;

  /// Concise developer-facing explanation.
  final String message;

  /// Wall time spent observing this exact lease.
  final Duration elapsed;

  /// Persistent watch log used for detailed diagnosis.
  final File logFile;

  /// Watch process ID from validated structured status, when available.
  final int? pid;

  /// Watch session identity from validated structured status, when available.
  final String? sessionId;

  /// Bounded failure diagnostics published by the watch, when available.
  final String? diagnostics;

  /// Whether Flutter may start while this leased watch remains active.
  bool get succeeded => outcome == CCWatchStartupOutcome.ready;
}

/// Waits for the exact wrapper lease to publish an owned, ready watch session.
///
/// [startupTimeout] bounds Dart/AOT entrypoint startup before any matching
/// status exists. [readyTimeout] separately bounds initial Builder and
/// aggregation work after launch. Existing or foreign status is never accepted.
Future<CCWatchStartupResult> waitForCCWatchStartup({
  required Directory hostRoot,
  required File leaseFile,
  Duration startupTimeout = const Duration(seconds: 30),
  Duration readyTimeout = const Duration(minutes: 5),
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final watchDirectory = Directory(
    path.join(hostRoot.path, '.dart_tool', 'ccrouter', 'v1', 'watch'),
  );
  final statusFile = File(path.join(watchDirectory.path, 'status.json'));
  final logFile = File(path.join(watchDirectory.path, 'flutter-run.log'));
  final watch = Stopwatch()..start();
  var observedLease = false;
  Duration? leaseObservedAt;
  Map<String, Object?>? latest;

  while (true) {
    if (!leaseFile.existsSync()) {
      watch.stop();
      return CCWatchStartupResult(
        outcome: CCWatchStartupOutcome.failed,
        message: 'watch lease disappeared before startup completed',
        elapsed: watch.elapsed,
        logFile: logFile,
        pid: latest?['pid'] as int?,
        sessionId: latest?['sessionId'] as String?,
      );
    }
    final status = await _readWatchStartupStatus(statusFile);
    if (status != null) {
      final statusHost = status['hostRoot'] as String;
      final statusLease = status['leasePath'];
      final matchesHost = hasSameDirectoryIdentity(statusHost, hostRoot.path);
      final matchesLease =
          statusLease is String &&
          hasSameFileIdentity(statusLease, leaseFile.path);
      if (matchesHost && matchesLease) {
        observedLease = true;
        leaseObservedAt ??= watch.elapsed;
        latest = status;
        final lastEvent = status['lastEvent'] as String;
        if (lastEvent == 'failed') {
          watch.stop();
          return CCWatchStartupResult(
            outcome: CCWatchStartupOutcome.failed,
            message: 'watch failed at ${status['failureStage'] ?? 'startup'}',
            diagnostics: status['failureDiagnostics'] as String?,
            elapsed: watch.elapsed,
            logFile: logFile,
            pid: status['pid'] as int?,
            sessionId: status['sessionId'] as String?,
          );
        }
        if (status['active'] != true) {
          watch.stop();
          return CCWatchStartupResult(
            outcome: CCWatchStartupOutcome.failed,
            message: 'watch stopped before its initial session became ready',
            diagnostics: status['failureDiagnostics'] as String?,
            elapsed: watch.elapsed,
            logFile: logFile,
            pid: status['pid'] as int?,
            sessionId: status['sessionId'] as String?,
          );
        }
        if (status['sessionReady'] == true &&
            await _watchStartupOwnerIsHeld(
              Directory(status['buildRoot'] as String),
            )) {
          watch.stop();
          return CCWatchStartupResult(
            outcome: CCWatchStartupOutcome.ready,
            message: 'watch session is ready',
            elapsed: watch.elapsed,
            logFile: logFile,
            pid: status['pid'] as int?,
            sessionId: status['sessionId'] as String?,
          );
        }
      } else if (observedLease) {
        watch.stop();
        return CCWatchStartupResult(
          outcome: CCWatchStartupOutcome.failed,
          message: 'watch startup status was replaced by another session',
          elapsed: watch.elapsed,
          logFile: logFile,
          pid: latest?['pid'] as int?,
          sessionId: latest?['sessionId'] as String?,
        );
      }
    }
    if (!observedLease && watch.elapsed >= startupTimeout) {
      watch.stop();
      return CCWatchStartupResult(
        outcome: CCWatchStartupOutcome.unavailable,
        message:
            'watch did not publish lease-bound startup status within '
            '${startupTimeout.inSeconds} seconds',
        elapsed: watch.elapsed,
        logFile: logFile,
      );
    }
    if (leaseObservedAt case final observedAt?
        when watch.elapsed - observedAt >= readyTimeout) {
      watch.stop();
      return CCWatchStartupResult(
        outcome: CCWatchStartupOutcome.timedOut,
        message:
            'watch did not complete initial generation within '
            '${_watchStartupDurationLabel(readyTimeout)}',
        diagnostics: latest?['failureDiagnostics'] as String?,
        elapsed: watch.elapsed,
        logFile: logFile,
        pid: latest?['pid'] as int?,
        sessionId: latest?['sessionId'] as String?,
      );
    }
    await Future<void>.delayed(pollInterval);
  }
}

/// Formats configured bounds without rounding short test and diagnostic values.
String _watchStartupDurationLabel(Duration duration) {
  if (duration.inMilliseconds % Duration.millisecondsPerMinute == 0) {
    return '${duration.inMinutes} minutes';
  }
  if (duration.inMilliseconds % Duration.millisecondsPerSecond == 0) {
    return '${duration.inSeconds} seconds';
  }
  return '${duration.inMilliseconds} milliseconds';
}

/// Reads only the status fields required to prove startup ownership.
Future<Map<String, Object?>?> _readWatchStartupStatus(File file) async {
  if (!file.existsSync()) return null;
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map ||
        decoded['schemaVersion'] != 1 ||
        decoded['active'] is! bool ||
        decoded['lastEvent'] is! String ||
        decoded['hostRoot'] is! String ||
        decoded['buildRoot'] is! String ||
        decoded['managedByLease'] != true ||
        decoded['leasePath'] is! String) {
      return null;
    }
    return decoded.cast<String, Object?>();
  } on Object {
    return null;
  }
}

/// Proves that the ready status still has a live exclusive watch owner.
Future<bool> _watchStartupOwnerIsHeld(Directory buildRoot) async {
  final owner = ccrouterWatchOwnerLockFile(buildRoot);
  if (!owner.existsSync()) return false;
  RandomAccessFile? opened;
  try {
    opened = await owner.open(mode: FileMode.append);
    await opened.lock(FileLock.shared);
    await opened.unlock();
    return false;
  } on FileSystemException {
    return true;
  } finally {
    await opened?.close();
  }
}
