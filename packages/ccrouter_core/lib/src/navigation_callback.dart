part of 'runtime.dart';

/// Centralizes navigation callback isolation and reentrancy enforcement.
extension CCRouterRuntimeNavigationCallbacks on CCRouterRuntime {
  /// Throws when a framework-owned callback attempts to start navigation.
  ///
  /// Decision callbacks and observers execute in a Runtime-specific Zone. The
  /// Zone also follows asynchronous work spawned by the callback, preventing a
  /// delayed recursive operation from bypassing the same ownership boundary.
  void _ensureNavigationCanStart() {
    if (identical(
      Zone.current[CCRouterRuntime._navigationCallbackZoneKey],
      this,
    )) {
      throw const CCNavigationReentrancyError();
    }
  }

  /// Executes one synchronous framework decision inside the protected Zone.
  ///
  /// Errors remain visible to the owning policy pipeline, which decides
  /// whether to fail closed, wrap the failure, or propagate it.
  T _runNavigationDecisionCallback<T>(T Function() callback) => runZoned(
    callback,
    zoneValues: {CCRouterRuntime._navigationCallbackZoneKey: this},
  );

  /// Executes one asynchronous framework decision inside the protected Zone.
  ///
  /// The returned Future preserves the callback result and error so timeout,
  /// cancellation, and recovery remain the responsibility of the caller.
  Future<T> _runAsyncNavigationDecisionCallback<T>(
    FutureOr<T> Function() callback,
  ) => runZoned(
    () => Future<T>.sync(callback),
    zoneValues: {CCRouterRuntime._navigationCallbackZoneKey: this},
  );

  /// Delivers one observation without allowing it to alter navigation.
  ///
  /// Synchronous observer failures are converted to bounded sanitized
  /// diagnostics. Observer contracts return void and must not start unawaited
  /// asynchronous work; keeping the parent error Zone ensures a navigation
  /// Future rejected for reentrancy can still be observed by its caller.
  /// [failureLabel] must identify only the framework callback kind and must
  /// never contain business data.
  void _notifyNavigationObserver(
    void Function() callback, {
    required String failureLabel,
  }) {
    try {
      runZoned(
        callback,
        zoneValues: {CCRouterRuntime._navigationCallbackZoneKey: this},
      );
    } catch (error) {
      _recordNavigationCallbackFailure(
        '$failureLabel failed: ${error.runtimeType}.',
      );
    }
  }
}
