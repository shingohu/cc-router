import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';

/// Owns one isolated Runtime for framework and integration tests.
///
/// A test host is useful when a test needs to exercise component registration,
/// RouteEntry lifecycle, services, or a supplied navigation adapter without
/// touching the process-wide [CCRouter] facade. The host owns the Runtime and
/// the optional adapter passed to it; [dispose] releases both through the
/// Runtime's normal shutdown path.
final class CCRouterTestHost {
  /// Creates an isolated test host from immutable component and adapter input.
  ///
  /// The host does not initialize synchronously. Call [initialize] before
  /// using [runtime], then call [dispose] in test teardown even when setup
  /// fails part way through.
  factory CCRouterTestHost({
    int traceCapacity = 1000,
    int navigationEventCapacity = 1000,
    Iterable<CCComponentManifest> components = const [],
    CCNavigationAdapter? navigationAdapter,
    Iterable<CCGlobalNavigationInterceptor> globalInterceptors = const [],
    Iterable<CCNavigationAspect> navigationAspects = const [],
    CCNavigationConcurrencyPolicy navigationConcurrencyPolicy =
        CCNavigationConcurrencyPolicy.allow,
  }) => CCRouterTestHost._(
    CCRouterRuntime.forHost(
      traceCapacity: traceCapacity,
      navigationEventCapacity: navigationEventCapacity,
      components: components,
      navigationAdapter: navigationAdapter,
      globalInterceptors: globalInterceptors,
      navigationAspects: navigationAspects,
      navigationConcurrencyPolicy: navigationConcurrencyPolicy,
    ),
  );

  CCRouterTestHost._(this.runtime);

  /// Runtime owned exclusively by this test host.
  ///
  /// This is intentionally exposed from the dedicated test package rather
  /// than the business facade so tests can inspect lifecycle and diagnostics
  /// without making those controls part of the application API.
  final CCRouterRuntime runtime;

  /// Whether [initialize] has completed and the Runtime is usable.
  bool get isInitialized => runtime.isInitialized;

  bool _disposed = false;

  /// Initializes the owned Runtime and its navigation adapter.
  ///
  /// Initialization errors are forwarded unchanged so tests can assert the
  /// same configuration failures that an application host would receive.
  Future<void> initialize() async {
    if (_disposed) {
      throw StateError('CCRouterTestHost has been disposed.');
    }
    await runtime.initialize();
  }

  /// Disposes the Runtime and all resources owned by this test host.
  ///
  /// Teardown is idempotent, which makes it safe to register [dispose] with
  /// `addTearDown` before an asynchronous test setup has finished.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await runtime.dispose();
  }
}
