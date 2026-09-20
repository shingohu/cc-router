part of 'runtime.dart';

/// Records safe behavior selected for unavailable Adapter capabilities.
extension CCRouterRuntimeNavigationCapabilityDiagnostics on CCRouterRuntime {
  /// Returns a bounded immutable snapshot of capability fallback usage.
  ///
  /// This history is appropriate for local diagnostics and aggregate telemetry;
  /// it contains stable routing identities but no concrete navigation payload.
  List<CCNavigationCapabilityFallbackEvent>
  get recentNavigationCapabilityFallbacks =>
      List.unmodifiable(_navigationCapabilityFallbacks);

  /// Subscribes to capability fallback observations.
  ///
  /// Events use the Runtime observer queue, so callbacks run on a later event
  /// loop turn and cannot block or alter navigation. The returned callback
  /// removes the listener and cancels deliveries that have not started.
  void Function() addNavigationCapabilityFallbackListener(
    CCNavigationCapabilityFallbackListener listener,
  ) {
    _ensureInitialized();
    _navigationCapabilityFallbackListeners.add(listener);
    return () => _navigationCapabilityFallbackListeners.remove(listener);
  }

  /// Retains and publishes one sanitized capability fallback event.
  void _emitNavigationCapabilityFallback(
    CCNavigationRequest request, {
    required CCNavigationCapabilityType capability,
    required CCNavigationCapabilityFallbackBehavior behavior,
  }) {
    final event = CCNavigationCapabilityFallbackEvent(
      navigationId: request.navigationId,
      operation: request.operation,
      routeId: request.routeId,
      hostId: request.hostId,
      navigatorOutlet: request.placement.navigatorOutlet,
      capability: capability,
      behavior: behavior,
      timestamp: DateTime.now(),
    );
    if (navigationDiagnosticCapacity > 0) {
      if (_navigationCapabilityFallbacks.length ==
          navigationDiagnosticCapacity) {
        _navigationCapabilityFallbacks.removeFirst();
      }
      _navigationCapabilityFallbacks.add(event);
    }
    _enqueueNavigationObserverBatch(
      _navigationCapabilityFallbackListeners,
      (listener) => listener(event),
      isActive: _navigationCapabilityFallbackListeners.contains,
      failureLabel: 'Navigation capability fallback listener',
    );
  }
}
