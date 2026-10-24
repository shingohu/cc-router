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
  /// Transitions are delivered by the bounded FIFO observer queue. The returned
  /// callback removes the listener and cancels its queued deliveries. Removing
  /// it is required when a diagnostic subscriber outlives its Host.
  /// Cleanup is idempotent and never removes a later re-add of this callback.
  /// Simultaneous duplicate adds still share one subscription.
  void Function() addRouteVisibilityListener(
    CCRouteVisibilityListener listener,
  ) {
    _ensureInitialized();
    return _subscribeNavigationObserver(_routeVisibilityListeners, listener);
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
    _routeVisibilityEventTotal++;
    _retainDiagnostic(
      _routeVisibilityEvents,
      event,
      navigationDiagnosticCapacity,
    );
    _enqueueRegisteredNavigationObserverBatch(
      _routeVisibilityListeners,
      (listener) => listener(event),
      failureLabel: 'Route visibility listener',
    );
    _emitDiagnostic(
      category: CCDiagnosticCategory.lifecycle,
      level: CCDiagnosticLevel.debug,
      occurredAt: event.timestamp,
      operation: 'routeVisibility',
      status: phase.name,
      duration: Duration.zero,
      navigationId: event.entry.navigationId,
      routeId: event.entry.routeId,
      targetComponentId: event.entry.ownerComponentId,
      hostId: event.entry.hostId,
      outlet: event.entry.placement.navigatorOutlet,
    );
  }
}
