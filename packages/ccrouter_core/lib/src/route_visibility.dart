part of 'runtime.dart';

/// Exposes managed Route Entry visibility observations from Runtime.
extension CCRouterRuntimeRouteVisibility on CCRouterRuntime {
  /// Returns the bounded immutable visibility event history.
  ///
  /// Use this for page exposure, focus restoration, and lifecycle diagnostics.
  /// App/Host background transitions are not represented here; those remain a
  /// separate Flutter Host lifecycle concern.
  List<CCRouteVisibilityEvent> get recentRouteVisibilityEvents =>
      List.unmodifiable(_routeVisibilityEvents);

  /// Subscribes to managed Route Entry visibility transitions.
  ///
  /// The returned callback removes the listener. Removing the callback is
  /// required when a long-lived diagnostic subscriber outlives its Host.
  void Function() addRouteVisibilityListener(
    CCRouteVisibilityListener listener,
  ) {
    _ensureInitialized();
    _routeVisibilityListeners.add(listener);
    return () => _routeVisibilityListeners.remove(listener);
  }

  /// Emits a visibility observation while isolating subscriber failures.
  void _emitRouteVisibility(
    _RouteEntryRecord entry,
    CCRouteVisibilityPhase phase, {
    String? reason,
  }) {
    final event = CCRouteVisibilityEvent(
      entry: entry.snapshot,
      phase: phase,
      timestamp: DateTime.now(),
      reason: reason,
    );
    if (navigationDiagnosticCapacity > 0) {
      if (_routeVisibilityEvents.length == navigationDiagnosticCapacity) {
        _routeVisibilityEvents.removeFirst();
      }
      _routeVisibilityEvents.add(event);
    }
    for (final listener in _routeVisibilityListeners.toList()) {
      _notifyNavigationObserver(
        () => listener(event),
        failureLabel: 'Route visibility listener',
      );
    }
  }
}
