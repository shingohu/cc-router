part of 'runtime.dart';

/// Records Host evidence of unmet route-restoration demand.
extension CCRouterRuntimeRestorationDiagnostics on CCRouterRuntime {
  /// Returns bounded, sanitized restoration-opportunity events.
  ///
  /// These events are diagnostics only. They contain no replayable stack state
  /// and every outcome is `unsupported` until a separate restoration design is
  /// deliberately implemented.
  List<CCRouteRestorationOpportunityEvent>
  get recentRouteRestorationOpportunities =>
      List.unmodifiable(_restorationOpportunityEvents);

  /// Subscribes to restoration-demand events at the application Host boundary.
  ///
  /// The returned callback removes the listener. Listener failures are isolated
  /// and never affect startup, navigation, or platform lifecycle processing.
  void Function() addRouteRestorationOpportunityListener(
    CCRouteRestorationOpportunityListener listener,
  ) {
    _ensureInitialized();
    _restorationOpportunityListeners.add(listener);
    return () => _restorationOpportunityListeners.remove(listener);
  }

  /// Attaches the optional Host source and drains evidence captured at startup.
  void _attachRestorationOpportunitySource() {
    final source = restorationOpportunitySource;
    if (source == null) return;
    try {
      _restorationOpportunityRemover = source.addListener(
        _recordRestorationOpportunity,
      );
      final initial = source.takeInitialSignals();
      for (final signal in initial) {
        _recordRestorationOpportunity(signal);
      }
    } catch (error) {
      _recordNavigationCallbackFailure(
        'Route restoration diagnostics failed: ${error.runtimeType}.',
      );
    }
  }

  /// Sanitizes one Host signal and publishes its unsupported outcome.
  void _recordRestorationOpportunity(
    CCRouteRestorationOpportunitySignal signal,
  ) {
    if (_disposed) return;
    final previousTopRouteId = _safeRestorationLabel(
      signal.previousTopRouteId,
      field: 'previousTopRouteId',
    );
    final previousFingerprint = _safeRestorationLabel(
      signal.previousComponentCatalogFingerprint,
      field: 'previousComponentCatalogFingerprint',
    );
    final applicationVersion = _safeRestorationLabel(
      signal.applicationVersion,
      field: 'applicationVersion',
    );
    final hostCount = _safeRestorationCount(
      signal.previousHostCount,
      field: 'previousHostCount',
    );
    final outletCount = _safeRestorationCount(
      signal.previousOutletCount,
      field: 'previousOutletCount',
    );
    final event = CCRouteRestorationOpportunityEvent(
      reason: signal.reason,
      occurredAt: signal.occurredAt,
      recordedAt: DateTime.now(),
      outcome: CCRouteRestorationOpportunityOutcome.unsupported,
      previousTopRouteId: previousTopRouteId,
      previousHostCount: hostCount,
      previousOutletCount: outletCount,
      previousComponentCatalogFingerprint: previousFingerprint,
      currentComponentCatalogFingerprint: _componentCatalogFingerprint(),
      applicationVersion: applicationVersion,
      telemetryContext: _snapshotTelemetryContext(),
    );
    if (navigationDiagnosticCapacity > 0) {
      if (_restorationOpportunityEvents.length ==
          navigationDiagnosticCapacity) {
        _restorationOpportunityEvents.removeFirst();
      }
      _restorationOpportunityEvents.add(event);
    }
    for (final listener in _restorationOpportunityListeners.toList()) {
      try {
        listener(event);
      } catch (error) {
        _recordNavigationCallbackFailure(
          'Route restoration listener failed: ${error.runtimeType}.',
        );
      }
    }
  }

  /// Returns one bounded label or drops invalid Host-provided text.
  String? _safeRestorationLabel(String? value, {required String field}) {
    if (value == null) return null;
    final valid =
        value.isNotEmpty &&
        value == value.trim() &&
        value.length <= 256 &&
        RegExp(r'^[A-Za-z0-9_.:+()\-]+$').hasMatch(value);
    if (valid) return value;
    _recordNavigationCallbackFailure(
      'Route restoration signal contained invalid $field.',
    );
    return null;
  }

  /// Returns one non-negative count or drops malformed Host evidence.
  int? _safeRestorationCount(int? value, {required String field}) {
    if (value == null || value >= 0) return value;
    _recordNavigationCallbackFailure(
      'Route restoration signal contained invalid $field.',
    );
    return null;
  }

  /// Computes a deterministic non-security fingerprint of installed components.
  String _componentCatalogFingerprint() {
    final identities =
        _components
            .map((component) => '${component.id}@${component.version}')
            .toList()
          ..sort();
    var hash = 0x811c9dc5;
    for (final codeUnit in identities.join('|').codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
