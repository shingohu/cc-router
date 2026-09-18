part of 'runtime.dart';

/// Exposes backend Navigator observations collected by Runtime.
extension CCRouterRuntimeNavigationBackend on CCRouterRuntime {
  /// Returns a bounded immutable snapshot of backend stack events.
  ///
  /// Use this to correlate system back, gestures, or backend-owned stack
  /// changes with Runtime request telemetry. Events may omit route metadata
  /// when the application changed its backend stack independently.
  List<CCNavigationBackendEvent> get recentBackendNavigationEvents =>
      List.unmodifiable(_backendNavigationEvents);

  /// Subscribes to backend Navigator observations from the configured adapter.
  ///
  /// The returned callback removes the listener. This capability is optional;
  /// adapters without backend observation support simply produce no events.
  void Function() addBackendNavigationListener(
    CCNavigationBackendEventListener listener,
  ) {
    _ensureInitialized();
    _backendNavigationListeners.add(listener);
    return () => _backendNavigationListeners.remove(listener);
  }

  /// Connects an optional adapter backend event source during initialization.
  void _attachBackendNavigationSource() {
    final adapter = _navigationAdapter;
    if (adapter is CCNavigationBackendEventSource) {
      _backendNavigationRemover = (adapter as CCNavigationBackendEventSource)
          .addBackendEventListener(_recordBackendNavigationEvent);
    }
  }

  /// Stores and publishes one adapter-observed backend event.
  void _recordBackendNavigationEvent(CCNavigationBackendEvent event) {
    if (navigationEventCapacity > 0) {
      if (_backendNavigationEvents.length == navigationEventCapacity) {
        _backendNavigationEvents.removeFirst();
      }
      _backendNavigationEvents.add(event);
    }
    for (final listener in _backendNavigationListeners.toList()) {
      try {
        listener(event);
      } catch (error) {
        if (traceCapacity > 0) {
          if (_subscriberErrors.length == traceCapacity) {
            _subscriberErrors.removeAt(0);
          }
          _subscriberErrors.add(
            CCInvocationError(
              'Backend navigation listener failed: ${error.runtimeType}',
            ),
          );
        }
      }
    }
  }
}
