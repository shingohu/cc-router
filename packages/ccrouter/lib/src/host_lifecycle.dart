part of 'facade.dart';

/// Application Composition Root control of the process-default Runtime.
///
/// Import `package:ccrouter/ccrouter_host.dart` only in Host composition code.
/// Feature components use [CCRouter] and never initialize, stop, or open startup
/// Gates themselves. Multiple navigation Hosts share this Runtime; releasing
/// one navigation surface does not shut down the application Runtime.
abstract final class CCRouterHost {
  /// Successful completion carrying optional failure data across error Zones.
  static Future<_CCHostCleanupFailure?>? _shuttingDown;

  /// Prevents optional attachment callbacks from reentering initialization.
  static bool _initializing = false;

  /// Releases Backend-owned resources after Runtime-owned Adapter disposal.
  static Future<void> Function()? _backendDisposer;

  /// Host tooling owned by the current process-default Runtime lifecycle.
  static List<CCHostToolIntegration> _hostToolIntegrations = const [];

  /// Backend-neutral routes owned by the current default Runtime lifecycle.
  static CCFlutterRouteCatalog? _hostRouteCatalog;

  /// Successfully attached optional capability bindings for this generation.
  static List<CCHostLifecycleBinding> _lifecycleBindings = const [];

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
  /// If a created Runtime fails initialization, the original error and stack
  /// are rethrown synchronously and the Host disposes that unpublished Runtime.
  /// Await [shutdown] to join rollback before retrying; initialization remains
  /// blocked until cleanup completes. Rollback errors do not replace the startup
  /// error or become unhandled; a joining [shutdown] observes structural cleanup
  /// errors. Failure before a Runtime is created still permits immediate retry.
  /// Global navigation interceptors are ordered by their stable IDs and run
  /// before route-declared interceptors. Navigation aspects are ordered by
  /// stable IDs and observe the same Runtime navigation pipeline. Active-route
  /// revalidation policies are also ordered by stable ID and run only after an
  /// explicit [CCRouter.revalidateActiveRoutes] trigger.
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
    Iterable<CCGlobalRouteRevalidationPolicy> routeRevalidationPolicies =
        const [],
    Iterable<CCGlobalPopGuard> globalPopGuards = const [],
    CCNavigationFailurePolicy? navigationFailurePolicy,
    Iterable<CCNavigationAspect> navigationAspects = const [],
    CCNavigationConcurrencyPolicy navigationConcurrencyPolicy =
        CCNavigationConcurrencyPolicy.allow,
    CCDeepLinkIngressPolicy deepLinkIngressPolicy =
        CCDeepLinkIngressPolicy.denyAll,
  }) {
    if (_initializing ||
        _runtimeResolver.hasOverlayRuntime ||
        _runtimeResolver.defaultRuntime != null ||
        _shuttingDown != null) {
      throw const CCRouterAlreadyInitializedError();
    }

    final attached = <CCHostLifecycleBinding>[];
    CCRouterRuntime? pendingRuntime;
    _initializing = true;
    try {
      for (final binding in hostAssembly.lifecycleBindings) {
        // Include partial attach in rollback; detach is explicitly idempotent.
        attached.add(binding);
        binding.attach();
      }
      final runtime = pendingRuntime = CCRouterRuntime.forHost(
        components: hostAssembly.componentManifests,
        contractBundle: hostAssembly.contractBundle,
        traceCapacity: traceCapacity,
        navigationDiagnosticCapacity: navigationDiagnosticCapacity,
        diagnostics: diagnostics,
        globalInterceptors: globalInterceptors,
        routeRevalidationPolicies: routeRevalidationPolicies,
        globalPopGuards: globalPopGuards,
        navigationFailurePolicy: navigationFailurePolicy,
        navigationAspects: navigationAspects,
        navigationConcurrencyPolicy: navigationConcurrencyPolicy,
        deepLinkIngressPolicy: deepLinkIngressPolicy,
      );
      runtime.initialize();
      _runtimeResolver.installDefault(runtime);
      pendingRuntime = null;
      _lifecycleBindings = List.unmodifiable(attached);
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
    } catch (_) {
      final failedRuntime = pendingRuntime;
      if (failedRuntime != null) {
        _rollbackInitialization(failedRuntime, attached);
      } else {
        for (final binding in attached.reversed) {
          try {
            binding.detach();
          } catch (_) {
            /* Preserve startup failure. */
          }
        }
      }
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  /// Releases an unpublished Runtime behind the shared shutdown gate.
  ///
  /// Install the gate before invoking detach or Runtime cancellation callbacks:
  /// they may synchronously reenter Host lifecycle APIs. Failures cross error
  /// Zones as data and become errors only for explicit shutdown callers.
  static void _rollbackInitialization(
    CCRouterRuntime runtime,
    List<CCHostLifecycleBinding> attached,
  ) {
    final completion = _beginCleanup();
    completion.complete(
      _captureCleanup(() async {
        Object? bindingError;
        StackTrace? bindingStack;
        for (final binding in attached.reversed) {
          try {
            binding.detach();
          } catch (error, stack) {
            bindingError ??= error;
            bindingStack ??= stack;
          }
        }
        await runtime.dispose();
        if (bindingError != null) {
          Error.throwWithStackTrace(bindingError, bindingStack!);
        }
      }),
    );
  }

  /// Establishes a cleanup generation before any reentrant lifecycle callbacks.
  ///
  /// The shared Future always succeeds, with failures stored as data, so callers
  /// in different error Zones can all join it. Register gate release first so
  /// initialization is allowed before any joining shutdown Future returns.
  static Completer<_CCHostCleanupFailure?> _beginCleanup() {
    final completion = Completer<_CCHostCleanupFailure?>();
    final cleanup = completion.future;
    _shuttingDown = cleanup;
    unawaited(
      cleanup.then<void>((_) {
        if (identical(_shuttingDown, cleanup)) _shuttingDown = null;
      }),
    );
    return completion;
  }

  /// Observes cleanup errors in their originating Zone and returns them as data.
  static Future<_CCHostCleanupFailure?> _captureCleanup(
    Future<void> Function() cleanup,
  ) async {
    try {
      await cleanup();
      return null;
    } catch (error, stackTrace) {
      return (error: error, stackTrace: stackTrace);
    }
  }

  /// Reports a completed cleanup failure in the joining caller's error Zone.
  static Future<void> _joinCleanup(
    Future<_CCHostCleanupFailure?> cleanup,
  ) async {
    final failure = await cleanup;
    if (failure != null) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
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
  /// Synchronous Gate reentry joins the same run; a task must not await its
  /// owning run. Calls from different error Zones receive cancellation in their
  /// own Zone, and [shutdown] can join the run across that boundary.
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
  /// Joins pending initialization rollback even though no default Runtime was
  /// published. Otherwise calling this method when no Runtime exists is a
  /// no-op. Calling it from a test Runtime overlay throws [StateError]; dispose
  /// the owning Test Host instead.
  ///
  /// This is intentionally named `shutdown`, rather than `dispose`, because
  /// [CCRouterHost] is static lifecycle control, not a disposable instance.
  /// Do not call it from Flutter `State.dispose`, Page Pop, component teardown,
  /// Session close, application backgrounding, or one navigation Host's
  /// disposal. Await it only when the Composition Root ends the default Runtime.
  /// Stopping and cancellation callbacks run behind the shutdown gate, so they
  /// cannot reinitialize early. Cleanup continues after notification failures;
  /// the Host receives the first structural failure after resources are released.
  /// Each caller joins cleanup from its own Zone, including a different error
  /// Zone from startup or the first shutdown call. Cleanup failures retain their
  /// original identity and stack and are thrown in each joining caller's Zone.
  /// Await or handle the returned Future in that Zone before passing its result
  /// across an error-Zone boundary, as required for any error-completing Future.
  static Future<void> shutdown() async {
    if (_runtimeResolver.hasOverlayRuntime) {
      throw StateError(
        'A CCRouter test Runtime is owned by CCRouterTestHost and cannot be '
        'shut down through CCRouterHost.',
      );
    }
    final existingShutdown = _shuttingDown;
    if (existingShutdown != null) return _joinCleanup(existingShutdown);
    final active = _runtimeResolver.takeDefault();
    final disposeBackend = _backendDisposer;
    final hostToolIntegrations = _hostToolIntegrations;
    final lifecycleBindings = _lifecycleBindings;
    _lifecycleBindings = const [];
    _hostRouteCatalog = null;
    _hostToolIntegrations = const [];
    if (active == null &&
        disposeBackend == null &&
        hostToolIntegrations.isEmpty &&
        lifecycleBindings.isEmpty) {
      return;
    }

    final completion = _beginCleanup();
    final shuttingDown = completion.future;
    _backendDisposer = null;
    Object? bindingError;
    StackTrace? bindingStack;
    for (final binding in lifecycleBindings.reversed) {
      try {
        binding.detach();
      } catch (error, stack) {
        bindingError ??= error;
        bindingStack ??= stack;
      }
    }
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
    completion.complete(
      _captureCleanup(() async {
        await _disposeRuntimeAndBackend(active, disposeBackend);
        if (bindingError != null) {
          Error.throwWithStackTrace(bindingError, bindingStack!);
        }
      }),
    );
    await _joinCleanup(shuttingDown);
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

/// Carries cleanup failure identity and stack across error Zones without throwing.
typedef _CCHostCleanupFailure = ({Object error, StackTrace stackTrace});
