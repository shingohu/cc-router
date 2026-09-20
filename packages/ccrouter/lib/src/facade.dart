import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';

part 'navigation.dart';
part 'deep_link.dart';

/// Static business-facing entry point for all CCRouter capabilities.
///
/// Applications initialize this facade once per isolate and use it for
/// component services, messages, Sessions, diagnostics, and navigation. Do not
/// construct or retain the lower-level Runtime in business code.
abstract final class CCRouter {
  /// Process-local navigation facade backed by the active Runtime.
  static final CCNavigator _navigator = _CCNavigator();

  /// Runtime owned by the current isolate's application host.
  static CCRouterRuntime? _defaultRuntime;

  /// Shutdown operation currently in progress.
  static Future<void>? _shuttingDown;

  /// Releases Backend-owned resources after Runtime-owned Adapter disposal.
  static Future<void> Function()? _backendDisposer;

  /// Returns the active Runtime or fails when the host is not initialized.
  static CCRouterRuntime get _runtime {
    final active = _defaultRuntime;
    if (active == null) throw const CCRouterNotInitializedError();
    return active;
  }

  /// Whether the default Runtime has completed initialization.
  ///
  /// Use this only for host status and diagnostics; normal business code should
  /// rely on application startup ordering instead of polling it.
  static bool get isInitialized => _defaultRuntime?.isInitialized ?? false;

  /// Snapshot of the active authenticated Session, if one exists.
  ///
  /// Use this for immutable account and Session diagnostics, not as mutable
  /// authentication state or a replacement for the application's user model.
  static CCSession? get session => _runtime.session;

  /// Component manifests installed in deterministic dependency order.
  ///
  /// Hosts and diagnostics use this snapshot to inspect application assembly;
  /// business features should not branch on it for authorization.
  static List<CCComponentManifest> get registeredComponents =>
      _runtime.components;

  /// Bounded immutable snapshot of recent invocation traces.
  ///
  /// Use this for local diagnostics and observability export, not for storing
  /// business events or sensitive request payloads.
  static List<CCTraceRecord> get recentTraces => _runtime.recentTraces;

  /// Bounded snapshot of recent Runtime navigation lifecycle events.
  ///
  /// Use this for local diagnostics and sanitized telemetry export. Events do
  /// not contain typed route arguments, widget instances, or Pop results.
  static List<CCNavigationLifecycleEvent> get recentNavigationEvents =>
      _runtime.recentNavigationEvents;

  /// Bounded snapshot of sanitized navigation failures and recovery choices.
  ///
  /// Events contain stable routing identities and error types only. They never
  /// expose URI parameters, typed arguments, Pop results, or `extra` values.
  static List<CCNavigationFailureEvent> get recentNavigationFailures =>
      _runtime.recentNavigationFailures;

  /// Bounded evidence that a previous route state could have been restored.
  ///
  /// Events always report `unsupported`; they measure demand and contain no
  /// replayable navigation state, URI parameters, arguments, or account IDs.
  static List<CCRouteRestorationOpportunityEvent>
  get recentRouteRestorationOpportunities =>
      _runtime.recentRouteRestorationOpportunities;

  /// Bounded snapshot of managed Route Entry visibility transitions.
  ///
  /// Use this for page exposure, focus restoration, and diagnostics. Flutter
  /// application lifecycle changes remain available through
  /// [CCRouterApp.onLifecycleChanged] and are not represented as Route
  /// visibility events.
  static List<CCRouteVisibilityEvent> get recentRouteVisibilityEvents =>
      _runtime.recentRouteVisibilityEvents;

  /// Snapshot of currently retained managed Route Entries in stack order.
  ///
  /// Each snapshot exposes an exact [CCRouteEntrySnapshot.handle] for targeted
  /// removal. The snapshots do not expose Route Scopes, Widgets, or backend
  /// Navigator objects.
  static List<CCRouteEntrySnapshot> get activeRouteEntries =>
      _runtime.activeRouteEntries;

  /// Bounded snapshot of backend Navigator transitions observed by the adapter.
  ///
  /// Use this for system back, gesture, and backend-owned stack diagnostics.
  /// Route metadata can be absent when application code bypasses CCRouter.
  static List<CCNavigationBackendEvent> get recentBackendNavigationEvents =>
      _runtime.recentBackendNavigationEvents;

  /// Snapshot of the adapter-neutral backend Entry ledger.
  ///
  /// Use this for hybrid-navigation diagnostics. Foreign and opaque entries
  /// are immutable observations and cannot be popped or mutated through this
  /// API.
  static List<CCBackendEntry> get backendEntries => _runtime.backendEntries;

  /// Snapshot of backend Entries currently active in observed stacks.
  static List<CCBackendEntry> get activeBackendEntries =>
      _runtime.activeBackendEntries;

  /// Returns backend entries isolated to an optional Host and Outlet.
  ///
  /// Use this for multi-Host, foldable-pane, Shell-branch, or embedded
  /// Navigator diagnostics. Null filters match every Host or Outlet, and the
  /// result remains observational only.
  static List<CCBackendEntry> backendEntriesFor({
    String? hostId,
    String? navigatorOutlet,
    bool activeOnly = false,
  }) => _runtime.backendEntriesFor(
    hostId: hostId,
    navigatorOutlet: navigatorOutlet,
    activeOnly: activeOnly,
  );

  /// Subscribes to Runtime navigation lifecycle events.
  ///
  /// Use this at the application host boundary for navigation metrics. The
  /// returned callback removes the listener; listener failures do not fail
  /// navigation operations.
  static void Function() addNavigationListener(
    CCNavigationLifecycleListener listener,
  ) => _runtime.addNavigationListener(listener);

  /// Subscribes to sanitized navigation failure decisions.
  ///
  /// Use this at the application Host boundary for failure-rate telemetry. The
  /// returned callback removes the listener, and listener failures are isolated.
  static void Function() addNavigationFailureListener(
    CCNavigationFailureListener listener,
  ) => _runtime.addNavigationFailureListener(listener);

  /// Subscribes to sanitized route-restoration demand observations.
  ///
  /// Analytics hosts use this to estimate whether full restoration is valuable.
  /// The returned callback removes the listener without affecting the source.
  static void Function() addRouteRestorationOpportunityListener(
    CCRouteRestorationOpportunityListener listener,
  ) => _runtime.addRouteRestorationOpportunityListener(listener);

  /// Subscribes to managed Route Entry visibility transitions.
  ///
  /// The returned callback removes the listener. Listener failures are
  /// isolated from navigation execution.
  static void Function() addRouteVisibilityListener(
    CCRouteVisibilityListener listener,
  ) => _runtime.addRouteVisibilityListener(listener);

  /// Subscribes to backend Navigator transitions observed by the adapter.
  ///
  /// The returned callback removes the listener. Adapters without backend
  /// observation support do not produce events.
  static void Function() addBackendNavigationListener(
    CCNavigationBackendEventListener listener,
  ) => _runtime.addBackendNavigationListener(listener);

  /// Unified business-facing navigation entry point.
  ///
  /// The returned object is stable across Runtime restarts and resolves the
  /// currently active Runtime for each operation. Calls before [initialize]
  /// fail with [CCRouterNotInitializedError].
  static CCNavigator get navigator => _navigator;

  /// Snapshot of navigation requests paused by an external policy.
  ///
  /// Authentication, consent, onboarding, and device-unlock hosts may inspect
  /// these IDs and later call [resumePendingNavigation] or
  /// [cancelPendingNavigation]. Typed arguments remain Runtime-owned.
  static List<CCPendingNavigation> get pendingNavigations =>
      _runtime.pendingNavigations;

  /// Resumes a pending navigation through the complete Runtime pipeline.
  static Future<Object?> resumePendingNavigation(String navigationId) =>
      _runtime.resumePendingNavigation(navigationId);

  /// Cancels a pending navigation and completes its original Future with a
  /// standard [CCRouteCancelledError].
  static bool cancelPendingNavigation(
    String navigationId, {
    String code = 'pending_cancelled',
  }) => _runtime.cancelPendingNavigation(navigationId, code: code);

  /// Initializes the default Runtime with configuration and startup components.
  ///
  /// Call this once during application startup with the complete [components]
  /// assembly. Component manifests are validated and registered before the
  /// Runtime becomes observable, while navigation Backend binding remains the
  /// responsibility of the Flutter Host. Set [navigationDiagnosticCapacity] to
  /// bound each in-memory navigation diagnostic history independently; zero
  /// disables retained histories without disabling live listeners.
  ///
  /// Initialization is synchronous: successful return means the complete
  /// component graph is available, while configuration failures throw before
  /// any Runtime becomes observable. A second call before [shutdown] completes
  /// throws [CCRouterAlreadyInitializedError].
  /// Global navigation interceptors are ordered by their stable IDs and run
  /// before route-declared interceptors. Navigation aspects are ordered by
  /// stable IDs and observe the same Runtime navigation pipeline.
  /// [deepLinkIngressPolicy] is Host-owned and defaults to rejecting every
  /// external authority and relative Path; configure exact rules only for URI
  /// namespaces the application intentionally owns.
  static void initialize({
    required Iterable<CCComponentManifest> components,
    int traceCapacity = 1000,
    int navigationDiagnosticCapacity = 1000,
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
    if (_defaultRuntime != null || _shuttingDown != null) {
      throw const CCRouterAlreadyInitializedError();
    }

    final runtime = CCRouterRuntime.forHost(
      components: components,
      traceCapacity: traceCapacity,
      navigationDiagnosticCapacity: navigationDiagnosticCapacity,
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
    _defaultRuntime = runtime;
  }

  /// Resolves the default or keyed implementation of service contract [T].
  ///
  /// Use [contract] after an internal service is promoted across packages; omit
  /// it for legacy or component-internal type lookup. Absence is a configuration
  /// error in either mode.
  static T service<T extends Object>({
    CCServiceToken<T>? contract,
    CCServiceKey<T>? key,
  }) => _runtime.service<T>(contract: contract, key: key);

  /// Resolves service contract [T], returning null only when it is unregistered.
  ///
  /// Pass [contract] for a promoted cross-package capability. Use this only for
  /// genuinely optional integrations; factory and lifecycle failures still
  /// propagate and are not converted to null.
  static T? serviceOrNull<T extends Object>({
    CCServiceToken<T>? contract,
    CCServiceKey<T>? key,
  }) => _runtime.serviceOrNull<T>(contract: contract, key: key);

  /// Resolves every registered implementation of service contract [T].
  ///
  /// Pass [contract] when implementations share a promoted stable identity.
  /// Use when a caller intentionally composes all installed implementations.
  static List<T> services<T extends Object>({CCServiceToken<T>? contract}) =>
      _runtime.services<T>(contract: contract);

  /// Whether service contract [T] has a matching registration.
  ///
  /// Pass [contract] for promoted cross-package capability discovery without
  /// constructing the service instance.
  static bool hasService<T extends Object>({
    CCServiceToken<T>? contract,
    CCServiceKey<T>? key,
  }) => _runtime.hasService<T>(contract: contract, key: key);

  /// Dispatches [command] to its single handler.
  ///
  /// Use for one-to-one operations that intentionally change business state.
  static Future<R> command<R>(
    CCCommand<R> command, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => _runtime.command(command, timeout: timeout, cancellation: cancellation);

  /// Dispatches [query] to its single handler.
  ///
  /// Use for one-to-one reads that should not intentionally change state.
  static Future<R> query<R>(
    CCQuery<R> query, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => _runtime.query(query, timeout: timeout, cancellation: cancellation);

  /// Dispatches [action] to its handlers in stable identifier order.
  ///
  /// Use when multiple components may participate and the caller must await a
  /// deterministic aggregate completion report.
  static Future<CCActionReport> action(CCAction action) =>
      _runtime.action(action);

  /// Publishes [event] to isolated subscribers and awaits their completion.
  ///
  /// Use to announce an already completed fact without coupling the publisher
  /// to subscriber results; subscriber failures are isolated diagnostics.
  static Future<void> event(CCEvent event) => _runtime.event(event);

  /// Opens one authenticated account Session.
  ///
  /// Call after login succeeds or a persisted login is restored. Do not call on
  /// page changes, App backgrounding, or for anonymous request correlation.
  ///
  /// The existing Session must be fully closed before another can be opened.
  static void openSession({
    required String accountId,
    Map<String, Object?> metadata = const {},
  }) => _runtime.openSession(accountId: accountId, metadata: metadata);

  /// Closes the active Session and disposes all Session-owned resources.
  ///
  /// Call on logout, account switch, token invalidation, or forced sign-out;
  /// normal navigation and App backgrounding must not close the Session.
  static Future<void> closeSession() => _runtime.closeSession();

  /// Stops the default Runtime and releases all lifecycle-owned resources.
  ///
  /// Application hosts use this when permanently tearing down the framework.
  /// A Host Backend registered through [CCRouterHostBinding] is released
  /// automatically after this call disposes the Runtime-owned navigation
  /// Adapter.
  ///
  /// Calling this method when no Runtime exists is a no-op.
  static Future<void> shutdown() async {
    final existingShutdown = _shuttingDown;
    if (existingShutdown != null) return existingShutdown;
    final active = _defaultRuntime;
    final disposeBackend = _backendDisposer;
    if (active == null && disposeBackend == null) {
      return;
    }

    _defaultRuntime = null;
    _backendDisposer = null;
    final shuttingDown = _disposeRuntimeAndBackend(active, disposeBackend);
    _shuttingDown = shuttingDown;
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

/// Host-only bridge that binds navigation infrastructure to [CCRouter].
///
/// Adapter packages and application composition roots use this after
/// `CCRouter.initialize` installs the startup components. Business and component
/// code must navigate through `CCRouter.navigator` and must never access this
/// ownership boundary.
abstract final class CCRouterHostBinding {
  /// Synchronously transfers one ready [adapter] into the active Runtime.
  ///
  /// The Runtime configures the Adapter from the registered route table and
  /// imports its initial stack before this method returns. It owns Adapter
  /// disposal after success. A failed binding leaves Adapter cleanup with the
  /// caller so Backend-specific resources can be released deterministically.
  /// When supplied, [disposeBackend] is retained until `CCRouter.shutdown` and
  /// runs only after Runtime disposal.
  static void attachNavigationAdapter(
    CCNavigationAdapter adapter, {
    Future<void> Function()? disposeBackend,
  }) {
    if (CCRouter._backendDisposer != null) {
      throw const CCNavigationAdapterError(
        'A navigation Backend is already bound to CCRouter.',
      );
    }
    CCRouter._runtime.attachNavigationAdapter(adapter);
    CCRouter._backendDisposer = disposeBackend;
  }
}
