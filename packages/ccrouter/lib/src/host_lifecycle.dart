part of 'facade.dart';

/// Application Composition Root control of the process-default Runtime.
///
/// Import `package:ccrouter/ccrouter_host.dart` only in Host composition code.
/// Feature components use [CCRouter] and never initialize, stop, or open startup
/// Gates themselves. Multiple navigation Hosts share this Runtime; releasing
/// one navigation surface does not shut down the application Runtime.
abstract final class CCRouterHost {
  /// Shutdown operation currently in progress.
  static Future<void>? _shuttingDown;

  /// Releases Backend-owned resources after Runtime-owned Adapter disposal.
  static Future<void> Function()? _backendDisposer;

  /// Host tooling owned by the current process-default Runtime lifecycle.
  static List<CCHostToolIntegration> _hostToolIntegrations = const [];

  /// Backend-neutral routes owned by the current default Runtime lifecycle.
  static CCFlutterRouteCatalog? _hostRouteCatalog;

  /// Creates and initializes the process-default Runtime.
  ///
  /// Call this once during application startup with one complete [hostAssembly].
  /// Generated, handwritten, and test Hosts all use the same atomic snapshot so
  /// component, Contract, route, and tooling inputs cannot be mixed. Component
  /// manifests are validated and registered before the Runtime becomes
  /// observable, while navigation Backend binding remains the responsibility of
  /// the Flutter Host.
  /// Set [navigationDiagnosticCapacity] to bound each in-memory navigation
  /// diagnostic history independently; zero disables retained histories without
  /// disabling live listeners.
  ///
  /// Initialization is synchronous: successful return means the complete
  /// component graph is available, while configuration failures throw before
  /// any Runtime becomes observable. A second call before [shutdown] completes
  /// throws [CCRouterAlreadyInitializedError]. Initialization from inside a
  /// test Runtime overlay throws the same error because the Test Host owns that
  /// Runtime lifecycle.
  /// Global navigation interceptors are ordered by their stable IDs and run
  /// before route-declared interceptors. Navigation aspects are ordered by
  /// stable IDs and observe the same Runtime navigation pipeline.
  /// [deepLinkIngressPolicy] is Host-owned and defaults to rejecting every
  /// external authority and relative Path; configure exact rules only for URI
  /// namespaces the application intentionally owns.
  /// Generated Hosts pass their generated assembly directly. Handwritten Hosts
  /// and focused tests create the same value with
  /// [CCHostAssembly.fromComponents].
  ///
  /// The name describes framework Runtime initialization, not construction of
  /// a disposable object and not asynchronous InitTask execution. Page,
  /// component, Session, and navigation Host lifecycles must not call this
  /// method. [runInitTasks] separately opens one InitTask Gate, while
  /// [shutdown] is the matching application-owner operation that stops this
  /// default Runtime. Concrete Runtime, Adapter, Scope, and Service instances
  /// continue to use their owner-level `dispose` contracts internally.
  static void initialize({
    required CCHostAssembly hostAssembly,
    int traceCapacity = 1000,
    int navigationDiagnosticCapacity = 1000,
    CCDiagnosticsConfig diagnostics = const CCDiagnosticsConfig(),
    Iterable<CCGlobalNavigationInterceptor> globalInterceptors = const [],
    Iterable<CCGlobalPopGuard> globalPopGuards = const [],
    CCNavigationFailurePolicy? navigationFailurePolicy,
    Iterable<CCNavigationAspect> navigationAspects = const [],
    CCNavigationTelemetryContextProvider? telemetryContextProvider,
    CCRouteRestorationOpportunitySource? restorationOpportunitySource,
    CCNavigationConcurrencyPolicy navigationConcurrencyPolicy =
        CCNavigationConcurrencyPolicy.allow,
    CCDeepLinkIngressPolicy deepLinkIngressPolicy =
        CCDeepLinkIngressPolicy.denyAll,
  }) {
    if (_runtimeResolver.hasOverlayRuntime ||
        _runtimeResolver.defaultRuntime != null ||
        _shuttingDown != null) {
      throw const CCRouterAlreadyInitializedError();
    }

    final runtime = CCRouterRuntime.forHost(
      components: hostAssembly.componentManifests,
      contractBundle: hostAssembly.contractBundle,
      traceCapacity: traceCapacity,
      navigationDiagnosticCapacity: navigationDiagnosticCapacity,
      diagnostics: diagnostics,
      globalInterceptors: globalInterceptors,
      globalPopGuards: globalPopGuards,
      navigationFailurePolicy: navigationFailurePolicy,
      navigationAspects: navigationAspects,
      telemetryContextProvider: telemetryContextProvider,
      restorationOpportunitySource: restorationOpportunitySource,
      navigationConcurrencyPolicy: navigationConcurrencyPolicy,
      deepLinkIngressPolicy: deepLinkIngressPolicy,
    );
    runtime.initialize();
    _runtimeResolver.installDefault(runtime);
    _hostRouteCatalog = hostAssembly.routeCatalog;
    final integrations = hostAssembly.hostToolIntegrations;
    _hostToolIntegrations = integrations;
    for (final integration in integrations) {
      try {
        integration.onRuntimeReady();
      } catch (error) {
        runtime.recordHostToolLifecycleFailure(
          integrationId: integration.id,
          operation: 'hostToolStart',
          errorType: error.runtimeType.toString(),
        );
      }
    }
  }

  /// Opens the explicitly selected InitTask [gate] and awaits every newly ready
  /// task.
  ///
  /// This does not initialize or replace the framework Runtime. The Gate stays
  /// open for the Runtime lifetime, and one call may run zero, one, or multiple
  /// newly ready tasks. Call it after synchronous [initialize]. Ordinary
  /// startup uses [CCInitTaskGate.appStarted]; product conditions such as
  /// privacy consent use an explicit stable Gate. Overlapping calls share one
  /// DAG run, and completed tasks never execute twice. Task business failures
  /// are returned in [CCInitTaskRunResult] and skip only dependent branches;
  /// Runtime shutdown and cancellation still terminate the Future. A Host that
  /// intentionally requires fail-fast startup may call
  /// `result.throwIfRequiredFailed()` after awaiting this method.
  static Future<CCInitTaskRunResult> runInitTasks({
    required CCInitTaskGate gate,
  }) => CCRouter._runtime.runInitTasks(gate: gate);

  /// Shuts down the process-default Runtime and its owned resources.
  ///
  /// The application Composition Root uses this when ending the current default
  /// Runtime. A Host Backend registered through [CCRouterHostBinding] is
  /// released automatically after this call disposes the Runtime-owned
  /// navigation Adapter. A new [initialize] call is allowed only after this
  /// Future completes.
  ///
  /// Calling this method when no Runtime exists is a no-op. Calling it from a
  /// test Runtime overlay throws [StateError]; dispose the owning Test Host
  /// instead.
  ///
  /// This is intentionally named `shutdown`, rather than `dispose`, because
  /// [CCRouterHost] is static lifecycle control, not a disposable instance.
  /// Do not call it from Flutter `State.dispose`, Page Pop, component teardown,
  /// Session close, application backgrounding, or one navigation Host's
  /// disposal. Await it only when the Composition Root ends the default Runtime.
  /// Stopping and cancellation callbacks run behind the shutdown gate, so they
  /// cannot reinitialize early. Cleanup continues after notification failures;
  /// the Host receives the first structural failure after resources are released.
  static Future<void> shutdown() async {
    if (_runtimeResolver.hasOverlayRuntime) {
      throw StateError(
        'A CCRouter test Runtime is owned by CCRouterTestHost and cannot be '
        'shut down through CCRouterHost.',
      );
    }
    final existingShutdown = _shuttingDown;
    if (existingShutdown != null) return existingShutdown;
    final active = _runtimeResolver.takeDefault();
    final disposeBackend = _backendDisposer;
    final hostToolIntegrations = _hostToolIntegrations;
    _hostRouteCatalog = null;
    _hostToolIntegrations = const [];
    if (active == null &&
        disposeBackend == null &&
        hostToolIntegrations.isEmpty) {
      return;
    }

    final completion = Completer<void>();
    final shuttingDown = completion.future;
    _shuttingDown = shuttingDown;
    _backendDisposer = null;
    for (final integration in hostToolIntegrations) {
      try {
        integration.onRuntimeStopping();
      } catch (error) {
        active?.recordHostToolLifecycleFailure(
          integrationId: integration.id,
          operation: 'hostToolStop',
          errorType: error.runtimeType.toString(),
        );
      }
    }
    completion.complete(_disposeRuntimeAndBackend(active, disposeBackend));
    try {
      await shuttingDown;
    } finally {
      if (identical(_shuttingDown, shuttingDown)) _shuttingDown = null;
    }
  }

  /// Disposes Runtime-owned resources before Backend-owned resources.
  static Future<void> _disposeRuntimeAndBackend(
    CCRouterRuntime? runtime,
    Future<void> Function()? disposeBackend,
  ) async {
    Object? runtimeError;
    StackTrace? runtimeStackTrace;
    try {
      await runtime?.dispose();
    } catch (error, stackTrace) {
      runtimeError = error;
      runtimeStackTrace = stackTrace;
    }
    try {
      await disposeBackend?.call();
    } catch (error, stackTrace) {
      if (runtimeError == null) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    if (runtimeError != null) {
      Error.throwWithStackTrace(runtimeError, runtimeStackTrace!);
    }
  }
}
