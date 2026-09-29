/// Host-owned optional tooling attached to the process-default Runtime.
///
/// Implementations may expose read-only development diagnostics, but must not
/// retain a Runtime, resolve business capabilities, navigate, or mutate
/// framework state. Lifecycle callbacks are synchronous and failure-isolated by
/// `CCRouter`; they must return quickly and perform no blocking I/O.
abstract interface class CCHostToolIntegration {
  /// Stable diagnostic identity used to reject duplicate integrations.
  String get id;

  /// Starts or refreshes the tool after the default Runtime becomes observable.
  void onRuntimeReady();

  /// Stops payload delivery before Runtime-owned resources are released.
  ///
  /// The callback may be invoked even when [onRuntimeReady] failed, so cleanup
  /// must be idempotent and tolerate partially initialized tool state.
  void onRuntimeStopping();
}
