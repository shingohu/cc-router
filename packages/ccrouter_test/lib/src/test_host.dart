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
  /// Call [initialize] before using [runtime], then await [dispose] in test
  /// teardown so asynchronous Scope resources are released even when setup
  /// fails part way through.
  factory CCRouterTestHost({
    int traceCapacity = 1000,
    int navigationDiagnosticCapacity = 1000,
    Iterable<CCComponentManifest> components = const [],
    CCNavigationAdapter? navigationAdapter,
    Iterable<CCGlobalNavigationInterceptor> globalInterceptors = const [],
    Iterable<CCGlobalPopGuard> globalPopGuards = const [],
    CCNavigationFailurePolicy? navigationFailurePolicy,
    Iterable<CCNavigationAspect> navigationAspects = const [],
    CCNavigationTelemetryContextProvider? telemetryContextProvider,
    CCRouteRestorationOpportunitySource? restorationOpportunitySource,
    CCNavigationConcurrencyPolicy navigationConcurrencyPolicy =
        CCNavigationConcurrencyPolicy.allow,
  }) => CCRouterTestHost._(
    CCRouterRuntime.forHost(
      traceCapacity: traceCapacity,
      navigationDiagnosticCapacity: navigationDiagnosticCapacity,
      components: components,
      navigationAdapter: navigationAdapter,
      globalInterceptors: globalInterceptors,
      globalPopGuards: globalPopGuards,
      navigationFailurePolicy: navigationFailurePolicy,
      navigationAspects: navigationAspects,
      telemetryContextProvider: telemetryContextProvider,
      restorationOpportunitySource: restorationOpportunitySource,
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
  void initialize() {
    if (_disposed) {
      throw StateError('CCRouterTestHost has been disposed.');
    }
    runtime.initialize();
  }

  /// Disposes the Runtime and all resources owned by this test host.
  ///
  /// Teardown is idempotent, which makes it safe to register [dispose] with
  /// `addTearDown` before the test starts resolving scoped resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await runtime.dispose();
  }
}
