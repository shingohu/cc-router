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
  /// Cleanup is idempotent and never removes a later re-add of this callback.
  /// Simultaneous duplicate adds still share one subscription.
  void Function() addNavigationCapabilityFallbackListener(
    CCNavigationCapabilityFallbackListener listener,
  ) {
    _ensureInitialized();
    return _subscribeNavigationObserver(
      _navigationCapabilityFallbackListeners,
      listener,
    );
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
    _navigationFallbackTotal++;
    _retainDiagnostic(
      _navigationCapabilityFallbacks,
      event,
      navigationDiagnosticCapacity,
    );
    _enqueueRegisteredNavigationObserverBatch(
      _navigationCapabilityFallbackListeners,
      (listener) => listener(event),
      failureLabel: 'Navigation capability fallback listener',
    );
    _emitDiagnostic(
      category: CCDiagnosticCategory.backend,
      level: CCDiagnosticLevel.warning,
      occurredAt: event.timestamp,
      operation: event.operation.name,
      status: 'fallback',
      duration: Duration.zero,
      navigationId: event.navigationId,
      routeId: event.routeId,
      hostId: event.hostId,
      outlet: event.navigatorOutlet,
      fallbackKind: event.behavior.name,
    );
  }
}
