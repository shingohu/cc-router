/// Host-only lifecycle SPI for optional, prevalidated capability bindings.
///
/// Bindings cannot access the Runtime. They attach synchronously before Runtime
/// construction, detach on initialization failure, and detach before shutdown.
/// Implementations must perform no I/O, navigation, or business resolution.
abstract interface class CCHostLifecycleBinding {
  /// Unique identity within one immutable Host Assembly.
  String get id;

  /// Installs one fresh lifecycle generation; must reject concurrent reuse.
  void attach();

  /// Invalidates that generation and releases references; must be idempotent.
  void detach();
}
