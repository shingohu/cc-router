import 'dart:async';
import 'dart:io';

/// Versioned contents written while a supervised Flutter run owns its watch.
const String ccrouterFlutterRunLeaseHeartbeatMarker =
    'ccrouter-flutter-run-lease-v1';

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
