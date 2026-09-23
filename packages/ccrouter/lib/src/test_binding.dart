part of 'facade.dart';

/// Test-only bridge that overlays one isolated Runtime for a Zone.
///
/// The dedicated `ccrouter_test` package owns this boundary. Application code
/// must not import it or use it to replace the process-default Runtime.
abstract final class CCRouterTestBinding {
  /// Runs [body] with Facade calls resolved against [runtime].
  ///
  /// The Runtime must already be initialized and remains owned by its test
  /// host. Synchronous and asynchronous descendants inherit the overlay through
  /// Dart Zones; nested calls restore the previous overlay automatically.
  /// The callback must await every asynchronous descendant it starts before
  /// the owning host is disposed. This method never initializes or disposes
  /// [runtime].
  static R runWithRuntime<R>(CCRouterRuntime runtime, R Function() body) {
    if (!runtime.isInitialized) {
      throw StateError(
        'The CCRouter test Runtime must be initialized before use.',
      );
    }
    return runZoned(body, zoneValues: {_runtimeOverlayZoneKey: runtime});
  }
}
