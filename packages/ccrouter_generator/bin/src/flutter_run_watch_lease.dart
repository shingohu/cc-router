import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Versioned contents written while a supervised Flutter run owns its watch.
const String ccrouterFlutterRunLeaseHeartbeatMarker =
    'ccrouter-flutter-run-lease-v1';

/// Versioned acknowledgement proving that a watch accepted one run lease.
const String ccrouterFlutterRunLeaseAttachmentMarker =
    'ccrouter-flutter-run-lease-attachment-v1';

/// Sidecar written by the shared Host watch after observing [leaseFile].
File ccrouterFlutterRunLeaseAttachmentFile(File leaseFile) =>
    File('${leaseFile.absolute.path}.attached.json');

/// Returns whether the live watch process accepted [leaseFile].
bool ccrouterFlutterRunLeaseIsAttached(
  File leaseFile, {
  required int watchPid,
}) => ccrouterFlutterRunLeaseAttachmentWatchPid(leaseFile) == watchPid;

/// Returns the watch PID that accepted [leaseFile], when proven by its sidecar.
int? ccrouterFlutterRunLeaseAttachmentWatchPid(File leaseFile) {
  final attachment = ccrouterFlutterRunLeaseAttachmentFile(leaseFile);
  if (!attachment.existsSync()) return null;
  try {
    final decoded = jsonDecode(attachment.readAsStringSync());
    if (decoded is Map &&
        decoded['schemaVersion'] == 1 &&
        decoded['marker'] == ccrouterFlutterRunLeaseAttachmentMarker &&
        decoded['watchPid'] is int) {
      return decoded['watchPid'] as int;
    }
    return null;
  } on Object {
    return null;
  }
}

/// Refreshes a wrapper-created watch lease while the Flutter child is alive.
final class CCFlutterRunWatchLeaseOwner {
  /// Creates an owner for [leaseFile].
  CCFlutterRunWatchLeaseOwner(
    this.leaseFile, {
    this.heartbeatInterval = const Duration(seconds: 1),
  });

  /// Lease created by the Flutter wrapper before watch startup.
  final File leaseFile;

  /// Cadence used to prove the supervisor remains alive.
  final Duration heartbeatInterval;

  Timer? _timer;

  /// Starts the heartbeat and reports a later refresh failure exactly once.
  Future<void> start({
    required void Function(Object error, StackTrace stackTrace) onFailure,
  }) async {
    if (_timer != null) {
      throw StateError('Flutter run watch lease heartbeat already started.');
    }
    await leaseFile.writeAsString(
      '$ccrouterFlutterRunLeaseHeartbeatMarker\n',
      flush: true,
    );
    var failed = false;
    _timer = Timer.periodic(heartbeatInterval, (_) {
      if (failed) return;
      try {
        leaseFile.setLastModifiedSync(DateTime.now());
      } on Object catch (error, stackTrace) {
        failed = true;
        _timer?.cancel();
        onFailure(error, stackTrace);
      }
    });
  }

  /// Stops refreshing and removes the lease when possible.
  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
    try {
      if (await leaseFile.exists()) await leaseFile.delete();
    } on FileSystemException {
      // Watch independently expires a stale heartbeat if cleanup is denied.
    }
  }
}

/// Stops a generation watch when a supervised Flutter run stops heartbeating.
///
/// Empty and unrecognized leases retain the legacy existence-only protocol so
/// direct watch callers and POSIX wrappers remain backward compatible.
final class CCFlutterRunWatchLeaseMonitor {
  CCFlutterRunWatchLeaseMonitor._(
    this.leaseFile,
    this.onExpired, {
    required this.pollInterval,
    required this.staleAfter,
  });

  /// Starts monitoring one wrapper-owned lease.
  static CCFlutterRunWatchLeaseMonitor start(
    File leaseFile,
    void Function() onExpired, {
    Duration pollInterval = const Duration(seconds: 1),
    Duration staleAfter = const Duration(seconds: 5),
  }) {
    final monitor = CCFlutterRunWatchLeaseMonitor._(
      leaseFile,
      onExpired,
      pollInterval: pollInterval,
      staleAfter: staleAfter,
    );
    monitor._check();
    if (!monitor._expired) {
      monitor._timer = Timer.periodic(pollInterval, (_) => monitor._check());
    }
    return monitor;
  }

  /// Lease whose existence and optional heartbeat prove ownership.
  final File leaseFile;

  /// Callback invoked once after deletion or heartbeat expiry.
  final void Function() onExpired;

  /// File observation cadence.
  final Duration pollInterval;

  /// Maximum accepted age after the heartbeat protocol is observed.
  final Duration staleAfter;

  Timer? _timer;
  bool _heartbeatObserved = false;
  bool _expired = false;
  DateTime? _lastHeartbeatModified;
  DateTime? _heartbeatUnchangedSince;
  DateTime? _lastCheck;

  void _check() {
    if (_expired) return;
    final now = DateTime.now();
    final previousCheck = _lastCheck;
    _lastCheck = now;
    if (previousCheck != null && now.difference(previousCheck) > staleAfter) {
      // The watcher itself may have been suspended with the machine. Grant a
      // fresh observation window instead of treating sleep as owner death.
      _heartbeatUnchangedSince = now;
    }
    if (!leaseFile.existsSync()) {
      _expire();
      return;
    }
    if (!_heartbeatObserved) {
      try {
        _heartbeatObserved =
            leaseFile.readAsStringSync().trim() ==
            ccrouterFlutterRunLeaseHeartbeatMarker;
      } on FileSystemException {
        return;
      }
      if (!_heartbeatObserved) return;
      try {
        _lastHeartbeatModified = leaseFile.lastModifiedSync();
        _heartbeatUnchangedSince = now;
      } on FileSystemException {
        _expire();
      }
      return;
    }
    try {
      final modified = leaseFile.lastModifiedSync();
      if (modified != _lastHeartbeatModified) {
        _lastHeartbeatModified = modified;
        _heartbeatUnchangedSince = now;
        return;
      }
      final unchangedSince = _heartbeatUnchangedSince ?? now;
      _heartbeatUnchangedSince ??= now;
      if (now.difference(unchangedSince) <= staleAfter) return;
      try {
        leaseFile.deleteSync();
      } on FileSystemException {
        // Expiry is authoritative even when the stale sentinel cannot be removed.
      }
      _expire();
    } on FileSystemException {
      _expire();
    }
  }

  void _expire() {
    if (_expired) return;
    _expired = true;
    _timer?.cancel();
    onExpired();
  }

  /// Stops monitoring without changing the lease.
  void close() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Keeps one shared Host watch alive while any sibling run lease is healthy.
final class CCFlutterRunWatchLeaseGroupMonitor {
  CCFlutterRunWatchLeaseGroupMonitor._(
    this.seedLease,
    this.onExpired, {
    required this.pollInterval,
    required this.staleAfter,
  });

  /// Starts observing every `.lease` file in the seed lease directory.
  static CCFlutterRunWatchLeaseGroupMonitor start(
    File seedLease,
    void Function() onExpired, {
    Duration pollInterval = const Duration(seconds: 1),
    Duration staleAfter = const Duration(seconds: 5),
  }) {
    final monitor = CCFlutterRunWatchLeaseGroupMonitor._(
      seedLease.absolute,
      onExpired,
      pollInterval: pollInterval,
      staleAfter: staleAfter,
    );
    monitor._check();
    if (!monitor._expired) {
      monitor._timer = Timer.periodic(pollInterval, (_) => monitor._check());
    }
    return monitor;
  }

  /// Initial lease used to select the Host-scoped lease directory.
  final File seedLease;

  /// Callback invoked once after every observed lease is gone or stale.
  final void Function() onExpired;

  /// Directory rescan cadence.
  final Duration pollInterval;

  /// Maximum unchanged heartbeat age.
  final Duration staleAfter;

  final Map<String, _CCFlutterRunLeaseObservation> _observations = {};
  final Set<String> _attachments = {};
  Timer? _timer;
  bool _expired = false;
  DateTime? _lastCheck;

  void _check() {
    if (_expired) return;
    final now = DateTime.now();
    final previousCheck = _lastCheck;
    _lastCheck = now;
    final resumedAfterSuspension =
        previousCheck != null && now.difference(previousCheck) > staleAfter;
    final candidates = <String, File>{};
    final directory = seedLease.parent;
    try {
      if (directory.existsSync()) {
        for (final entity in directory.listSync(followLinks: false)) {
          if (entity is File && path.extension(entity.path) == '.lease') {
            candidates[entity.absolute.path] = entity.absolute;
          }
        }
      }
    } on FileSystemException {
      return;
    }
    if (seedLease.existsSync()) {
      candidates[seedLease.path] = seedLease;
    }

    final active = <String>{};
    for (final entry in candidates.entries) {
      final observation = _observations.putIfAbsent(
        entry.key,
        _CCFlutterRunLeaseObservation.new,
      );
      if (resumedAfterSuspension) observation.unchangedSince = now;
      if (_isActive(entry.value, observation, now)) {
        active.add(entry.key);
        _writeAttachment(entry.value);
      } else {
        _removeAttachment(entry.value);
      }
    }
    for (final missing
        in _observations.keys
            .where((item) => !candidates.containsKey(item))
            .toList(growable: false)) {
      _observations.remove(missing);
      _removeAttachment(File(missing));
    }
    if (active.isEmpty) _expire();
  }

  bool _isActive(
    File lease,
    _CCFlutterRunLeaseObservation observation,
    DateTime now,
  ) {
    if (!lease.existsSync()) return false;
    if (!observation.heartbeatObserved) {
      try {
        observation.heartbeatObserved =
            lease.readAsStringSync().trim() ==
            ccrouterFlutterRunLeaseHeartbeatMarker;
      } on FileSystemException {
        return true;
      }
      if (!observation.heartbeatObserved) return true;
      try {
        observation.lastModified = lease.lastModifiedSync();
        observation.unchangedSince = now;
      } on FileSystemException {
        return false;
      }
      return true;
    }
    try {
      final modified = lease.lastModifiedSync();
      if (modified != observation.lastModified) {
        observation.lastModified = modified;
        observation.unchangedSince = now;
        return true;
      }
      observation.unchangedSince ??= now;
      if (now.difference(observation.unchangedSince!) <= staleAfter) {
        return true;
      }
      try {
        lease.deleteSync();
      } on FileSystemException {
        // Expiry remains authoritative when cleanup is denied.
      }
      return false;
    } on FileSystemException {
      return false;
    }
  }

  void _writeAttachment(File lease) {
    final attachment = ccrouterFlutterRunLeaseAttachmentFile(lease);
    final contents =
        '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'marker': ccrouterFlutterRunLeaseAttachmentMarker, 'watchPid': pid})}\n';
    try {
      if (attachment.existsSync() &&
          attachment.readAsStringSync() == contents) {
        _attachments.add(attachment.path);
        return;
      }
      final temporary = File(
        '${attachment.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
      );
      temporary.writeAsStringSync(contents, flush: true);
      try {
        temporary.renameSync(attachment.path);
      } on FileSystemException {
        if (attachment.existsSync()) {
          attachment.deleteSync();
          temporary.renameSync(attachment.path);
        } else {
          rethrow;
        }
      } finally {
        if (temporary.existsSync()) temporary.deleteSync();
      }
      _attachments.add(attachment.path);
    } on FileSystemException {
      // Attachment failure prevents reuse but does not weaken lease expiry.
    }
  }

  void _removeAttachment(File lease) {
    final attachment = ccrouterFlutterRunLeaseAttachmentFile(lease);
    _attachments.remove(attachment.path);
    try {
      if (attachment.existsSync()) attachment.deleteSync();
    } on FileSystemException {
      // A stale sidecar cannot pass the watch-PID handshake for a later watch.
    }
  }

  void _expire() {
    if (_expired) return;
    _expired = true;
    _timer?.cancel();
    _timer = null;
    onExpired();
  }

  /// Stops observation and removes only this watch process's sidecars.
  void close() {
    _timer?.cancel();
    _timer = null;
    for (final attachmentPath in _attachments.toList(growable: false)) {
      final attachment = File(attachmentPath);
      try {
        if (ccrouterFlutterRunLeaseIsAttached(
          File(attachmentPath.substring(0, attachmentPath.length - 14)),
          watchPid: pid,
        )) {
          attachment.deleteSync();
        }
      } on FileSystemException {
        // Best-effort cleanup; the PID identity prevents stale attachment reuse.
      }
    }
    _attachments.clear();
  }
}

final class _CCFlutterRunLeaseObservation {
  bool heartbeatObserved = false;
  DateTime? lastModified;
  DateTime? unchangedSince;
}
