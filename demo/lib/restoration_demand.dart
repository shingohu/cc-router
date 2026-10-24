/// Demo-owned evidence categories for evaluating a future restoration feature.
/// These values do not describe an implemented CCRouter restoration capability.
enum DemoRestorationReason {
  androidActivityRecreated,
  appleStateRestoration,
  desktopWindowReopened,
  uncleanPreviousSession,
  unknown,
}

/// Application input supplied by a platform bridge or persisted Host marker.
final class DemoRestorationSignal {
  const DemoRestorationSignal({
    required this.reason,
    required this.occurredAt,
    this.previousTopRouteId,
    this.previousHostCount,
    this.previousOutletCount,
    this.previousComponentCatalogFingerprint,
    this.applicationVersion,
  });

  final DemoRestorationReason reason;
  final DateTime occurredAt;
  final String? previousTopRouteId;
  final int? previousHostCount;
  final int? previousOutletCount;
  final String? previousComponentCatalogFingerprint;
  final String? applicationVersion;
}

/// Sanitized application observation, containing no restorable navigation state.
final class DemoRestorationDemand {
  const DemoRestorationDemand({required this.signal, required this.recordedAt});

  final DemoRestorationSignal signal;
  final DateTime recordedAt;

  /// This sample measures demand only; it never attempts restoration.
  String get outcome => 'unsupported';
}

/// Optional application recorder, independent of CCRouter startup and shutdown.
///
/// The Host owns this object and calls [record] from genuine platform evidence.
/// Ordinary cold starts/foreground transitions are not restoration demand.
/// No persistence, platform listener, upload queue or Runtime subscription is
/// created automatically. An exporter owns its own Consent and delivery policy.
final class DemoRestorationDemandRecorder {
  DemoRestorationDemandRecorder({
    this.capacity = 64,
    void Function(DemoRestorationDemand event)? onRecorded,
    Iterable<DemoRestorationSignal> initialSignals = const [],
  }) : _onRecorded = onRecorded {
    if (capacity <= 0) throw ArgumentError.value(capacity, 'capacity');
    for (final signal in initialSignals) {
      record(signal);
    }
  }

  final int capacity;

  /// Synchronous application callback; failures are isolated from the Host.
  void Function(DemoRestorationDemand event)? _onRecorded;
  final List<DemoRestorationDemand> _events = [];
  bool _disposed = false;

  List<DemoRestorationDemand> get events => List.unmodifiable(_events);

  /// Drops invalid labels/counts and bounds the in-memory evidence history.
  bool record(DemoRestorationSignal signal) {
    if (_disposed) return false;
    final event = DemoRestorationDemand(
      recordedAt: DateTime.now(),
      signal: DemoRestorationSignal(
        reason: signal.reason,
        occurredAt: signal.occurredAt,
        previousTopRouteId: _label(signal.previousTopRouteId),
        previousHostCount: _count(signal.previousHostCount),
        previousOutletCount: _count(signal.previousOutletCount),
        previousComponentCatalogFingerprint: _label(
          signal.previousComponentCatalogFingerprint,
        ),
        applicationVersion: _label(signal.applicationVersion),
      ),
    );
    if (_events.length == capacity) _events.removeAt(0);
    _events.add(event);
    try {
      _onRecorded?.call(event);
    } on Object {
      // Demand collection must never change application lifecycle behavior.
    }
    return true;
  }

  /// Releases all evidence and fences late platform callbacks; idempotent.
  void dispose() {
    _disposed = true;
    _events.clear();
    _onRecorded = null;
  }

  static int? _count(int? value) => value == null || value < 0 ? null : value;

  static String? _label(String? value) =>
      value != null &&
          value.length <= 256 &&
          RegExp(r'^[A-Za-z0-9_.:+()\-]+$').hasMatch(value)
      ? value
      : null;
}
