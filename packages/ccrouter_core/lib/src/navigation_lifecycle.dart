part of 'runtime.dart';

/// Exposes Runtime-owned navigation lifecycle telemetry.
extension CCRouterRuntimeNavigationLifecycle on CCRouterRuntime {
  /// Returns a bounded immutable snapshot of recent navigation events.
  ///
  /// Use this for local diagnostics and exporting sanitized navigation
  /// telemetry. The snapshot contains route identity and attribution metadata,
  /// but never typed arguments, URI fragments supplied as payloads, or Pop
  /// results.
  List<CCNavigationLifecycleEvent> get recentNavigationEvents =>
      List.unmodifiable(_navigationEvents);

  /// Subscribes to Runtime navigation lifecycle events.
  ///
  /// Use this at the application host boundary to forward navigation metrics
  /// to an analytics or diagnostics pipeline. The returned callback removes the
  /// listener; listener failures are isolated from navigation execution.
  void Function() addNavigationListener(
    CCNavigationLifecycleListener listener,
  ) {
    _ensureInitialized();
    _navigationListeners.add(listener);
    return () => _navigationListeners.remove(listener);
  }

  /// Emits a lifecycle event for one Runtime-validated request.
  void _emitNavigationEvent(
    CCNavigationRequest request,
    CCNavigationLifecyclePhase phase, {
    String? errorType,
  }) {
    final event = CCNavigationLifecycleEvent(
      navigationId: request.navigationId,
      phase: phase,
      operation: request.operation,
      routeId: request.routeId,
      uri: request.uri,
      placement: request.placement,
      origin: request.origin,
      source: request.source,
      timestamp: DateTime.now(),
      errorType: errorType,
    );
    if (navigationEventCapacity > 0) {
      if (_navigationEvents.length == navigationEventCapacity) {
        _navigationEvents.removeFirst();
      }
      _navigationEvents.add(event);
    }
    for (final listener in _navigationListeners.toList()) {
      try {
        listener(event);
      } catch (error) {
        if (traceCapacity > 0) {
          if (_subscriberErrors.length == traceCapacity) {
            _subscriberErrors.removeAt(0);
          }
          _subscriberErrors.add(
            CCInvocationError(
              'Navigation listener failed: ${error.runtimeType}',
            ),
          );
        }
      }
    }
  }
}
