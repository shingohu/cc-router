part of 'runtime.dart';

/// Non-owning context propagated while constructing one Service.
///
/// Nested resolution uses the concrete [instanceScope] and optional
/// [routeEntry] instead of guessing from global Runtime state. This keeps
/// new-instance disposal with its consumer while preserving exact Route ownership.
/// Detached callbacks retain identity and closed-owner errors, never the Runtime
/// or an ended Scope's payload graph. Runtime owns active and exiting Entries.
final class _ServiceConstructionOwner {
  /// Creates the construction context for one selected provider instance.
  _ServiceConstructionOwner({
    required this.runtimeIdentity,
    required this.serviceScope,
    required CCScope instanceScope,
    required this.ownerComponentId,
    required _RouteEntryRecord? routeEntry,
  }) : _instanceScope = WeakReference(instanceScope),
       _scopeId = instanceScope.id,
       _routeEntry = serviceScope == CCServiceScope.route && routeEntry != null
           ? WeakReference(routeEntry)
           : null;

  /// Exact Runtime identity without a back-reference to the Runtime itself.
  final Object runtimeIdentity;

  /// Logical lifetime used to validate nested dependencies.
  final CCServiceScope serviceScope;

  /// Concrete owner remains strongly owned only by its Runtime lifecycle.
  final WeakReference<CCScope> _instanceScope;

  /// Stable label used to reject callbacks after the owner has been collected.
  final String _scopeId;

  /// Exact Entry identity, absent for App and Session construction contexts.
  final WeakReference<_RouteEntryRecord>? _routeEntry;

  /// Resolves the original Scope without substituting a later active owner.
  CCScope get instanceScope =>
      _instanceScope.target ?? (throw CCScopeClosedError(_scopeId));

  /// Component that owns the logical consumer being constructed.
  final String ownerComponentId;

  /// Resolves the exact Route Entry, failing closed after it has been collected.
  ///
  /// App/Session providers never inherit their first caller's Route Entry.
  _RouteEntryRecord? get routeEntry {
    final reference = _routeEntry;
    if (reference == null) return null;
    return reference.target ?? (throw CCScopeClosedError(_scopeId));
  }
}

/// Stateful execution kernel used by the framework host and core tests.
///
/// Production applications access it only through the `ccrouter` facade.
/// Framework hosts use it to isolate one component graph per Dart isolate;
/// low-level tests may create independent instances to verify Runtime behavior.
final class CCRouterRuntime {
  /// Creates a Runtime owned by the public framework host.
  ///
  /// Application business code must initialize the framework through the
  /// `ccrouter` facade instead of constructing this low-level engine directly.
  /// This constructor exists for the facade's application-host integration. A
  /// supplied navigation adapter is initialized and disposed by this Runtime.
  factory CCRouterRuntime.forHost({
    int traceCapacity = 1000,
    int navigationDiagnosticCapacity = 1000,
    CCDiagnosticsConfig diagnostics = const CCDiagnosticsConfig(),
    Iterable<CCComponentManifest> components = const [],
    CCContractBundleDescriptor? contractBundle,
    CCNavigationAdapter? navigationAdapter,
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
  }) => CCRouterRuntime._(
    traceCapacity: traceCapacity,
    navigationDiagnosticCapacity: navigationDiagnosticCapacity,
    diagnostics: diagnostics,
    components: components,
    contractBundle: contractBundle,
    navigationAdapter: navigationAdapter,
    globalInterceptors: globalInterceptors,
    routeRevalidationPolicies: routeRevalidationPolicies,
    globalPopGuards: globalPopGuards,
    navigationFailurePolicy: navigationFailurePolicy,
    navigationAspects: navigationAspects,
    navigationConcurrencyPolicy: navigationConcurrencyPolicy,
    deepLinkIngressPolicy: deepLinkIngressPolicy,
  );

  /// Creates an independently owned Runtime for low-level core tests.
  ///
  /// Use this only when testing Core semantics without the static business
  /// facade; application tests will eventually use the `ccrouter_test` host. A
  /// supplied adapter belongs exclusively to this test Runtime.
  @visibleForTesting
  factory CCRouterRuntime.forTesting({
    int traceCapacity = 1000,
    int navigationDiagnosticCapacity = 1000,
    CCDiagnosticsConfig diagnostics = const CCDiagnosticsConfig(),
    Iterable<CCComponentManifest> components = const [],
    CCContractBundleDescriptor? contractBundle,
    CCNavigationAdapter? navigationAdapter,
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
    Iterable<CCServiceOverrideEntry<Object>> serviceOverrides = const [],
  }) => CCRouterRuntime._(
    traceCapacity: traceCapacity,
    navigationDiagnosticCapacity: navigationDiagnosticCapacity,
    diagnostics: diagnostics,
    components: components,
    contractBundle: contractBundle,
    navigationAdapter: navigationAdapter,
    globalInterceptors: globalInterceptors,
    routeRevalidationPolicies: routeRevalidationPolicies,
    globalPopGuards: globalPopGuards,
    navigationFailurePolicy: navigationFailurePolicy,
    navigationAspects: navigationAspects,
    navigationConcurrencyPolicy: navigationConcurrencyPolicy,
    deepLinkIngressPolicy: deepLinkIngressPolicy,
    serviceOverrides: serviceOverrides,
  );

  /// Creates a Runtime with validated configuration and installed components.
  /// Global navigation interceptors are ordered by stable ID before navigation
  /// begins; component route interceptors are registered by their registrars.
  /// Construction failure terminates diagnostic delivery after one deferred
  /// best-effort final batch because no Runtime is returned for Host disposal.
  CCRouterRuntime._({
    this.traceCapacity = 1000,
    this.navigationDiagnosticCapacity = 1000,
    this.diagnostics = const CCDiagnosticsConfig(),
    Iterable<CCComponentManifest> components = const [],
    CCContractBundleDescriptor? contractBundle,
    CCNavigationAdapter? navigationAdapter,
    Iterable<CCGlobalNavigationInterceptor> globalInterceptors = const [],
    Iterable<CCGlobalRouteRevalidationPolicy> routeRevalidationPolicies =
        const [],
    Iterable<CCGlobalPopGuard> globalPopGuards = const [],
    this.navigationFailurePolicy,
    Iterable<CCNavigationAspect> navigationAspects = const [],
    required this.navigationConcurrencyPolicy,
    required CCDeepLinkIngressPolicy deepLinkIngressPolicy,
    Iterable<CCServiceOverrideEntry<Object>> serviceOverrides = const [],
  }) {
    _deepLinkIngressPolicy = deepLinkIngressPolicy;
    _navigationAdapter = navigationAdapter;
    if (contractBundle != null) {
      final issues = CCContractBundleDescriptor.validate([contractBundle]);
      if (issues.isNotEmpty) {
        throw CCContractCompatibilityError(issues);
      }
    }
    _globalInterceptors = _validateGlobalInterceptors(globalInterceptors);
    _routeRevalidationPolicies = _validateRouteRevalidationPolicies(
      routeRevalidationPolicies,
    );
    _globalPopGuards = _validateGlobalPopGuards(globalPopGuards);
    _navigationAspects = _validateNavigationAspects(navigationAspects);
    if (traceCapacity < 0) {
      throw ArgumentError.value(traceCapacity, 'traceCapacity');
    }
    if (navigationDiagnosticCapacity < 0) {
      throw ArgumentError.value(
        navigationDiagnosticCapacity,
        'navigationDiagnosticCapacity',
      );
    }
    _diagnosticPolicies = _validateDiagnosticPolicies(diagnostics);
    final diagnosticQueueCapacity =
        diagnostics.queueCapacity ?? max(64, navigationDiagnosticCapacity);
    if (diagnosticQueueCapacity <= 0) {
      throw ArgumentError.value(
        diagnosticQueueCapacity,
        'diagnostics.queueCapacity',
      );
    }
    _diagnosticDelivery = _DiagnosticDelivery(
      sink: diagnostics.sink,
      capacity: diagnosticQueueCapacity,
    );
    try {
      _installComponents(components);
      _applyServiceOverrides(serviceOverrides);
    } on Object {
      _diagnosticDelivery.closeDeferred();
      rethrow;
    }
  }

  /// Zone key carrying invocation tracing and immutable admission ownership.
  static final Object _invocationZoneKey = Object();

  /// Zone key carrying the Scope of a service under construction.
  static final Object _constructionZoneKey = Object();

  /// Zone key carrying provider identities in a readiness dependency chain.
  static final Object _readinessZoneKey = Object();

  /// Active initializer node used to join waits from independent root calls.
  static final Object _readinessOwnerZoneKey = Object();

  /// Zone key preventing navigation from asynchronous framework callbacks.
  static final Object _navigationCallbackZoneKey = Object();

  /// Zone key carrying one navigation's non-reusable Host registrations.
  static final Object _navigationOwnershipZoneKey = Object();

  /// Maximum number of trace and subscriber error records retained.
  final int traceCapacity;

  /// Maximum retained records in each bounded navigation diagnostic history.
  ///
  /// The limit applies independently to lifecycle, failure, capability
  /// fallback, visibility, Route Entry, and Backend histories.
  /// Active structural state is not evicted by this value. Zero disables
  /// retained histories while live listeners and navigation behavior remain
  /// active.
  final int navigationDiagnosticCapacity;

  /// Host-owned structured diagnostic delivery configuration.
  ///
  /// The Sink receives only sanitized immutable events. Runtime behavior and
  /// internal bounded histories remain active when external delivery is off.
  final CCDiagnosticsConfig diagnostics;

  /// Policy for overlapping requests with the same structured navigation key.
  ///
  /// [CCNavigationConcurrencyPolicy.allow] is the default and preserves
  /// ordinary repeated pushes. The other policies only affect requests that
  /// are still pending; completed navigation never remains in this gate.
  /// Requests carrying process-local Extra always execute independently
  /// because Runtime cannot derive a stable equality key for arbitrary values.
  final CCNavigationConcurrencyPolicy navigationConcurrencyPolicy;

  /// Host-owned trust boundary applied to every external URI resolution.
  ///
  /// The Runtime retains the immutable policy for its complete lifetime so a
  /// component or navigation callback cannot broaden accepted authorities.
  late final CCDeepLinkIngressPolicy _deepLinkIngressPolicy;

  /// Optional Host policy for sanitized route failure recovery.
  ///
  /// The policy is immutable for the Runtime lifetime. It receives no route
  /// parameters or backend objects and must return a decision rather than
  /// invoking navigation directly.
  final CCNavigationFailurePolicy? navigationFailurePolicy;

  /// Runtime-specific prefix preventing trace identifiers from colliding.
  final String _runtimeId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  /// Private Zone identity that cannot keep this Runtime reachable on its own.
  final Object _zoneIdentity = Object();

  /// Service providers grouped by contract type.
  final Map<Type, List<_Provider>> _providers = {};

  /// Promoted service providers grouped by stable cross-package identity.
  final Map<String, List<_Provider>> _providersByContractId = {};

  /// InitTasks indexed by globally stable task identity.
  final Map<String, _InitTaskRecord> _initTasks = {};

  /// Gates explicitly opened by the application host.
  final Set<String> _openedInitTaskGates = {};

  /// Active DAG drain shared by concurrent Gate triggers.
  _InitTaskDrain? _initTaskRun;

  /// Whether an overlapping Gate open requires another DAG quiescence pass.
  bool _initTaskDrainRequested = false;

  /// Single command handler indexed by command type.
  final Map<Type, _RegisteredCommandHandler> _commands = {};

  /// Event subscribers indexed by event type and stable subscriber identifier.
  final Map<Type, Map<String, _RegisteredEventSubscriber>> _events = {};

  /// Component-owned Shell definitions indexed by stable Shell ID.
  final _ShellRegistry _shellRegistry = _ShellRegistry();

  /// Component-owned route definitions indexed by stable route ID.
  late final _RouteRegistry _routeRegistry = _RouteRegistry(
    _shellRegistry,
    _deepLinkIngressPolicy,
  );

  /// Concrete Route Entries currently retained by the Runtime.
  final List<_RouteEntryRecord> _routeEntries = [];

  /// Removed entries whose outgoing rendering still owns a usable Route Scope.
  final Map<String, _RouteEntryRecord> _exitingRouteEntries = {};

  /// Detachable render waits forcibly released before Runtime shutdown joins.
  final Map<String, void Function()> _routeExitWaiters = {};

  /// Bounded Route Entry lifecycle transitions retained for diagnostics.
  final Queue<CCRouteEntryLifecycleEvent> _routeEntryEvents = Queue();

  /// Subscribers receiving Route Entry lifecycle transitions.
  final Map<CCRouteEntryLifecycleListener, Object> _routeEntryListeners = {};

  /// Bounded Route Entry visibility observations retained for diagnostics.
  final Queue<CCRouteVisibilityEvent> _routeVisibilityEvents = Queue();

  /// Subscribers receiving Route Entry visibility observations.
  final Map<CCRouteVisibilityListener, Object> _routeVisibilityListeners = {};

  /// Route Scope close operations that Runtime must await during shutdown.
  final List<Future<void>> _routeEntryCloseFutures = [];

  /// Optional adapter that executes Runtime-validated navigation requests.
  CCNavigationAdapter? _navigationAdapter;

  /// Stable, application-owned interceptors executed before route policies.
  late final List<CCGlobalNavigationInterceptor> _globalInterceptors;

  /// Stable Host policies that reconcile retained Entries after state changes.
  late final List<CCGlobalRouteRevalidationPolicy> _routeRevalidationPolicies;

  /// Active tail used to serialize explicit active-route policy passes.
  ///
  /// Null keeps unused Runtimes free of a Zone-bound Future and is restored
  /// after the last queued pass reaches a terminal state.
  Future<void>? _routeRevalidationTail;

  /// Monotonic identity assigned when a serialized pass starts evaluating.
  int _routeRevalidationRevision = 0;

  /// Stable, application-owned navigation AOP registrations.
  late final List<CCNavigationAspect> _navigationAspects;

  /// Component-owned route interceptors indexed by stable ID.
  final Map<String, _RegisteredNavigationInterceptor> _routeInterceptors = {};

  /// Stable application-owned Pop guards evaluated before route-local guards.
  late final List<CCGlobalPopGuard> _globalPopGuards;

  /// Component-owned route Pop guards indexed by stable ID.
  final Map<String, _RegisteredPopGuard> _routePopGuards = {};

  /// Maximum number of redirects followed for one navigation request.
  static const int maxNavigationRedirects = 8;

  /// Bounded completed invocation trace buffer.
  final Queue<CCTraceRecord> _traces = Queue();

  /// Monotonic diagnostic change hint, independent of external Sink filtering.
  int _diagnosticRevision = 0;

  /// Lifetime invocation observations, including disabled trace retention.
  int _traceTotal = 0;

  /// Lifetime navigation lifecycle observations, independent of Sink policy.
  int _navigationEventTotal = 0;

  /// Lifetime sanitized failure observations, including rotated history.
  int _navigationFailureTotal = 0;

  /// Lifetime capability fallback observations, including disabled retention.
  int _navigationFallbackTotal = 0;

  /// Lifetime Entry transitions, independent of observer delivery.
  int _routeEntryEventTotal = 0;

  /// Lifetime visibility transitions, including rotated history.
  int _routeVisibilityEventTotal = 0;

  /// Lifetime backend observations accepted into diagnostic history.
  int _backendNavigationEventTotal = 0;

  /// Last immutable health value; retains scalar DTOs, never live event data.
  CCDiagnosticSnapshot? _diagnosticSnapshot;

  /// Validated per-category external diagnostic policies.
  late final Map<CCDiagnosticCategory, CCDiagnosticCategoryPolicy>
  _diagnosticPolicies;

  /// Independent delivery owner so unfinished Sink Futures retain no Runtime.
  late final _DiagnosticDelivery _diagnosticDelivery;

  /// Pseudo-random source used only for non-critical diagnostic sampling.
  final Random _diagnosticRandom = Random();

  /// Bounded Runtime navigation lifecycle event buffer.
  final Queue<CCNavigationLifecycleEvent> _navigationEvents = Queue();

  /// Bounded sanitized navigation failures and optional recovery outcomes.
  final Queue<CCNavigationFailureEvent> _navigationFailures = Queue();

  /// Navigation IDs whose deferred resume failed before the original Future
  /// completed. The outer navigation pipeline consumes this marker so one
  /// failure produces one event with the correct attempt category.
  final Set<String> _pendingResumeFailures = {};

  /// Bounded records of safe behavior selected for missing Adapter capability.
  final Queue<CCNavigationCapabilityFallbackEvent>
  _navigationCapabilityFallbacks = Queue();

  /// Cross-Zone completion data for requests that have not yet terminated.
  final Map<_NavigationConcurrencyKey, _SharedResult<Object?>>
  _inFlightNavigation = {};

  /// Live logical Host registrations; detach replaces their token identity.
  final Map<String, CCCancellationToken> _navigationHostRegistrations = {};

  /// Host execution context for owned resources, never a later caller Zone.
  ///
  /// Results cross back as data so independent caller error Zones receive their
  /// own errors. Pending Adapter callbacks must not retain a consumer's Zone.
  final Zone _hostZone = Zone.current;

  /// Runtime-owned continuations waiting for an external policy decision.
  final Map<String, _PendingNavigationRecord> _pendingNavigations = {};

  /// Active or retained observation state indexed by navigation identity.
  final Map<String, _CCNavigationAspectRecord> _navigationAspectRecords = {};

  /// Subscribers receiving Runtime navigation lifecycle events.
  final Map<CCNavigationLifecycleListener, Object> _navigationListeners = {};

  /// Subscribers receiving sanitized navigation failure outcomes.
  final Map<CCNavigationFailureListener, Object> _navigationFailureListeners =
      {};

  /// Subscribers receiving safe Adapter capability fallback observations.
  final Map<CCNavigationCapabilityFallbackListener, Object>
  _navigationCapabilityFallbackListeners = {};

  /// Bounded backend Navigator observations collected from the adapter.
  final Queue<CCNavigationBackendDiagnosticEvent> _backendNavigationEvents =
      Queue();

  /// Backend route identities observed by the Runtime ledger.
  final Map<String, _BackendEntryRecord> _backendEntries = {};

  /// Adapter operation IDs already reconciled by the backend ledger.
  final Set<String> _processedBackendOperations = {};

  /// Last monotonic backend event sequence observed for each Host.
  final Map<String, int> _backendSequencesByHost = {};

  /// Hosts whose backend event stream skipped at least one sequence.
  final Set<String> _desynchronizedBackendHosts = {};

  /// Subscribers receiving backend Navigator observations.
  final Map<CCNavigationBackendDiagnosticListener, Object>
  _backendNavigationListeners = {};

  /// FIFO batches waiting for isolated observer delivery.
  final Queue<_QueuedNavigationObservation> _navigationObservationQueue =
      Queue();

  /// Event-loop task currently scheduled to drain observer batches.
  Timer? _navigationObservationTimer;

  /// Whether a queue drain is already active on this Runtime.
  bool _drainingNavigationObservations = false;

  /// Whether event producers may enqueue new observer batches.
  bool _acceptingNavigationObservations = true;

  /// Whether the current drain cycle already recorded an overflow diagnostic.
  bool _navigationObservationOverflowRecorded = false;

  /// Removes the Runtime subscription from the adapter backend event source.
  void Function()? _backendNavigationRemover;

  /// Removes the Runtime subscription from predictive-back phase events.
  void Function()? _predictiveBackRemover;

  /// Bounded sanitized failures from isolated Event subscribers.
  final List<CCInvocationError> _subscriberErrors = [];

  /// Installed components in deterministic dependency order.
  final List<CCComponentManifest> _components = [];

  /// Scope that owns Runtime-wide service instances.
  final CCScope appScope = CCScope('app');

  /// Scope that owns services for the active authenticated Session.
  CCScope? _sessionScope;

  /// Immutable information for the active authenticated Session.
  CCSession? _session;

  /// Whether initialization completed and operations are accepted.
  bool _initialized = false;

  /// Whether shutdown permanently closed this Runtime.
  bool _disposed = false;

  /// Monotonic sequence used in invocation and span identifiers.
  int _sequence = 0;

  /// Monotonic sequence used in Session identifiers.
  int _sessionSequence = 0;

  /// Monotonic sequence used in navigation identifiers.
  int _navigationSequence = 0;

  /// Monotonic sequence used in Route Entry identities.
  int _routeEntrySequence = 0;

  /// Memoized shutdown operation that makes disposal idempotent.
  Future<void>? _disposeFuture;

  /// Maximum queued observation batches before overflow policy is applied.
  ///
  /// A small diagnostic history setting must not make ordinary multi-phase
  /// navigation synchronously invoke observers, so the queue keeps a minimum
  /// operational capacity independent from retained history.
  int get _navigationObservationCapacity =>
      max(64, navigationDiagnosticCapacity);

  /// Whether this Runtime currently accepts framework operations.
  bool get isInitialized => _initialized;

  /// Immutable installed component list.
  List<CCComponentManifest> get components => List.unmodifiable(_components);

  /// Active Session Scope, exposed only to low-level core tests.
  CCScope? get sessionScope => _sessionScope;

  /// Immutable information for the active Session.
  CCSession? get session => _session;

  /// Immutable snapshot of the bounded trace buffer.
  List<CCTraceRecord> get recentTraces => List.unmodifiable(_traces);

  /// Payload-free external delivery state for capacity and slow-Sink diagnosis.
  CCDiagnosticDeliverySnapshot get diagnosticDeliverySnapshot =>
      _diagnosticDelivery.snapshot;

  /// Returns the retained invocation records for one trace identity.
  ///
  /// The result is empty when the trace has already rotated out of the bounded
  /// history. This method never reconstructs payloads or live Runtime state.
  CCTraceBundle traceBundle(String traceId) => CCTraceBundle(
    traceId: traceId,
    records: List.unmodifiable(
      _traces.where((record) => record.context.traceId == traceId),
    ),
  );

  /// Immutable snapshot of sanitized Event subscriber failures.
  List<CCInvocationError> get subscriberErrors =>
      List.unmodifiable(_subscriberErrors);

  /// Immutable initialization task snapshots ordered by stable task ID.
  List<CCInitTaskSnapshot> get initTasks {
    final ids = _initTasks.keys.toList()..sort();
    return List.unmodifiable(ids.map((id) => _initTasks[id]!.snapshot));
  }

  /// Starts the Runtime with its validated framework-wide configuration.
  ///
  /// Component manifests supplied to the constructor are installed before this
  /// call, so initialization validates one complete graph atomically. Hosts may
  /// bind an Adapter afterward; direct registry mutation remains frozen once
  /// initialization completes. Successful return means the Runtime is ready;
  /// this method never schedules asynchronous initialization work.
  void initialize() {
    if (_disposed) throw const CCScopeClosedError('runtime');
    if (_initialized) return;
    final startedAt = DateTime.now();
    var failureStage = 'configurationValidation';
    _emitInitializationDiagnostic(
      occurredAt: startedAt,
      operation: 'runtimeInitialize',
      status: 'started',
      level: CCDiagnosticLevel.debug,
    );
    try {
      _validateInitTasks();
      _validateRouteConfiguration();
      _validateNavigationAdapterCapabilities();
      failureStage = 'adapterInitialization';
      _navigationAdapter?.initialize(
        _navigationRoutesForAdapter(),
        shells: _shellRegistry.navigationShells,
      );
      final adapter = _navigationAdapter;
      if (adapter != null) {
        failureStage = 'popGuardBinding';
        _bindNavigationPopGuards(adapter);
      }
      failureStage = 'backendAttachment';
      _attachBackendNavigationSource();
      _readInitialBackendEntries();
      _initialized = true;
    } on Object catch (error) {
      _emitInitializationDiagnostic(
        occurredAt: startedAt,
        operation: 'runtimeInitialize',
        status: 'failed',
        level: CCDiagnosticLevel.error,
        duration: DateTime.now().difference(startedAt),
        failureStage: failureStage,
        errorType: error.runtimeType.toString(),
      );
      rethrow;
    }
    _emitInitializationDiagnostic(
      occurredAt: startedAt,
      operation: 'runtimeInitialize',
      status: 'succeeded',
      level: CCDiagnosticLevel.info,
      duration: DateTime.now().difference(startedAt),
    );
  }

  /// Attaches and initializes the single navigation Adapter for this Runtime.
  ///
  /// Application Host integration calls this after Runtime initialization. The
  /// operation synchronously validates capabilities, configures the Adapter,
  /// and imports its initial stack. The Runtime takes ownership only after all
  /// steps succeed and disposes the Adapter during [dispose]. Business and
  /// component code must not bind navigation infrastructure directly.
  void attachNavigationAdapter(CCNavigationAdapter adapter) {
    _ensureInitialized();
    if (_navigationAdapter != null) {
      throw const CCNavigationAdapterError(
        'A navigation adapter is already bound to this Runtime.',
      );
    }
    _navigationAdapter = adapter;
    try {
      _validateNavigationAdapterCapabilities();
      adapter.initialize(
        _navigationRoutesForAdapter(),
        shells: _shellRegistry.navigationShells,
      );
      _bindNavigationPopGuards(adapter);
      _attachBackendNavigationSource();
      _readInitialBackendEntries();
    } catch (error, stackTrace) {
      try {
        _bindNavigationPopGuards(adapter, clear: true);
      } catch (_) {
        // Preserve the attachment failure after best-effort policy cleanup.
      }
      final backendNavigationRemover = _backendNavigationRemover;
      _backendNavigationRemover = null;
      try {
        backendNavigationRemover?.call();
      } catch (_) {
        // Preserve the attachment failure after best-effort listener cleanup.
      }
      final predictiveBackRemover = _predictiveBackRemover;
      _predictiveBackRemover = null;
      try {
        predictiveBackRemover?.call();
      } catch (_) {
        // Preserve the attachment failure after best-effort listener cleanup.
      }
      _backendEntries.clear();
      _processedBackendOperations.clear();
      _backendSequencesByHost.clear();
      _desynchronizedBackendHosts.clear();
      _navigationAdapter = null;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Builds the adapter route snapshot with Runtime-wide Pop policy metadata.
  ///
  /// Route-local guard ownership remains in the private route registry. A
  /// global guard, however, applies to every managed route, so adapters need a
  /// single boolean hint to install a platform back gate without receiving
  /// guard IDs or mutable Runtime state.
  List<CCNavigationRoute> _navigationRoutesForAdapter() {
    final routes = _routeRegistry.navigationRoutes;
    if (_globalPopGuards.isEmpty) return routes;
    return List.unmodifiable(
      routes.map(
        (route) => route.hasPopGuard
            ? route
            : CCNavigationRoute(
                routeId: route.routeId,
                patterns: route.patterns,
                presentation: route.presentation,
                deepLink: route.deepLink,
                hasPopGuard: true,
                placement: route.placement,
              ),
      ),
    );
  }

  /// Validates initialization dependencies and rejects cycles before startup.
  void _validateInitTasks() {
    for (final record in _initTasks.values) {
      for (final dependency in record.task.dependsOn) {
        if (!_initTasks.containsKey(dependency)) {
          throw CCRegistrationError(
            'InitTask "${record.task.id}" requires missing '
            'task "$dependency".',
          );
        }
      }
    }
    final visiting = <String>{};
    final visited = <String>{};
    void visit(String id) {
      if (visited.contains(id)) return;
      if (!visiting.add(id)) {
        throw CCRegistrationError('InitTask dependency cycle at "$id".');
      }
      final dependencies = _initTasks[id]!.task.dependsOn.toList()..sort();
      for (final dependency in dependencies) {
        visit(dependency);
      }
      visiting.remove(id);
      visited.add(id);
    }

    final ids = _initTasks.keys.toList()..sort();
    for (final id in ids) {
      visit(id);
    }

    String? findOptional(String id, Set<String> visited) {
      if (!visited.add(id)) return null;
      final record = _initTasks[id]!;
      if (record.task.failurePolicy == CCInitTaskFailurePolicy.optional) {
        return id;
      }
      for (final dependency in record.task.dependsOn) {
        final optional = findOptional(dependency, visited);
        if (optional != null) return optional;
      }
      return null;
    }

    for (final record in _initTasks.values) {
      if (record.task.failurePolicy != CCInitTaskFailurePolicy.required) {
        continue;
      }
      for (final dependency in record.task.dependsOn) {
        final optional = findOptional(dependency, <String>{});
        if (optional != null) {
          throw CCRegistrationError(
            'Required InitTask "${record.task.id}" cannot depend directly or '
            'indirectly on optional InitTask "$optional".',
          );
        }
      }
    }
  }

  /// Validates cross-route placement and policy references after registration.
  void _validateRouteConfiguration() {
    _routeRegistry.validatePlacements();
    _routeRegistry.validateInterceptors({
      for (final entry in _routeInterceptors.entries)
        entry.key: entry.value.ownerComponentId,
    });
    _routeRegistry.validatePopGuards({
      for (final entry in _routePopGuards.entries)
        entry.key: entry.value.ownerComponentId,
    });
  }

  /// Rejects static navigation structures unsupported by a capability-aware
  /// Adapter before that Adapter mutates its backend state.
  ///
  /// Older adapters may omit [CCNavigationAdapterCapabilitySource]; those
  /// adapters retain their historical behavior and report unsupported
  /// operations at their own boundary. A capability-aware adapter must fail
  /// initialization explicitly instead of silently flattening Shell or modal
  /// semantics into an unrelated backend route.
  void _validateNavigationAdapterCapabilities() {
    final adapter = _navigationAdapter;
    final capabilitySource = adapter is CCNavigationAdapterCapabilitySource
        ? adapter as CCNavigationAdapterCapabilitySource
        : null;
    if (capabilitySource == null) return;
    final capabilities = capabilitySource.capabilities;
    final missing = <String>{};
    final predictiveSource = adapter is CCNavigationPredictiveBackSourceProvider
        ? (adapter as CCNavigationPredictiveBackSourceProvider)
              .predictiveBackSource
        : adapter is CCNavigationPredictiveBackSource
        ? adapter as CCNavigationPredictiveBackSource
        : null;
    if (predictiveSource != null && !capabilities.supportsPredictiveBack) {
      missing.add('supportsPredictiveBack');
    }
    final routes = _routeRegistry.navigationRoutes;
    final hasModalRoute = routes.any(
      (route) =>
          route.presentation is CCModalBottomSheetPresentation ||
          route.presentation is CCDialogPresentation,
    );
    if (hasModalRoute && !capabilities.supportsModalRoutes) {
      missing.add('supportsModalRoutes');
    }
    final shells = _shellRegistry.navigationShells;
    final hasNestedPlacement =
        shells.isNotEmpty ||
        routes.any(
          (route) =>
              route.placement.parentRouteId != null ||
              route.placement.shellId != null ||
              route.placement.navigatorOutlet != 'root',
        );
    if (hasNestedPlacement && !capabilities.supportsNestedNavigators) {
      missing.add('supportsNestedNavigators');
    }
    if (shells.any((shell) => shell.type == CCShellType.statefulBranches) &&
        !capabilities.supportsStatefulShell) {
      missing.add('supportsStatefulShell');
    }
    if (missing.isNotEmpty) {
      final names = missing.toList()..sort();
      throw CCNavigationAdapterError(
        'Navigation adapter lacks required capabilities: ${names.join(', ')}.',
      );
    }
  }

  /// Registers [provider] after validating key and default conflicts.
  ///
  /// This low-level entry point exists for Core tests. Components must register
  /// through the restricted [CCRegistry] supplied to their Registrar.
  void registerService<T extends Object>(CCServiceProvider<T> provider) {
    _registerServiceForComponent('', provider);
  }

  /// Registers [provider] while retaining the component owner internally.
  void _registerServiceForComponent<T extends Object>(
    String ownerComponentId,
    CCServiceProvider<T> provider,
  ) {
    _ensureConfigurable();
    if (provider.scope == CCServiceScope.route && ownerComponentId.isEmpty) {
      throw const CCRegistrationError(
        'Route-scoped Services must be registered by a component.',
      );
    }
    final providers = _providers[T] ?? <_Provider>[];
    final contractId = provider.contractToken?.id;
    if (contractId != null && !_isStableIdentifier(contractId)) {
      throw CCRegistrationError(
        'Service contract ID "$contractId" is invalid.',
      );
    }
    final contractProviders = contractId == null
        ? null
        : _providersByContractId[contractId] ?? <_Provider>[];
    final name = provider.key?.name;
    if (name != null && !_isStableIdentifier(name)) {
      throw CCRegistrationError('Service key "$name" is invalid.');
    }
    final isDefault = provider.isDefault || name == null;
    if (contractProviders != null &&
        contractProviders.any((item) => item.type != T)) {
      throw CCRegistrationError(
        'Service contract ID "$contractId" is already registered for '
        '${contractProviders.first.type}, not $T.',
      );
    }
    if (providers.any((item) => item.name == name)) {
      throw CCRegistrationError('Duplicate service key ($T, $name).');
    }
    if (isDefault && providers.any((item) => item.isDefault)) {
      throw CCRegistrationError('Multiple default providers for $T.');
    }
    if (contractProviders != null &&
        contractProviders.any((item) => item.name == name)) {
      throw CCRegistrationError(
        'Duplicate service contract key ($contractId, $name).',
      );
    }
    if (contractProviders != null &&
        isDefault &&
        contractProviders.any((item) => item.isDefault)) {
      throw CCRegistrationError(
        'Multiple default providers for service contract "$contractId".',
      );
    }
    final normalized = _Provider(
      T,
      contractId,
      name,
      ownerComponentId,
      provider.scope,
      provider.creationPolicy,
      isDefault,
      provider.factory,
      provider.initializer == null
          ? null
          : (service, context) => provider.initializer!(service as T, context),
    );
    providers.add(normalized);
    _providers[T] = providers;
    if (contractProviders != null) {
      contractProviders.add(normalized);
      _providersByContractId[contractId!] = contractProviders;
    }
  }

  /// Registers an initialization task for low-level Runtime tests.
  ///
  /// Components use [CCRegistry.registerInitTask] so the Runtime can
  /// attach a trusted owner. The complete DAG is validated by [initialize].
  void registerInitTask(CCInitTaskDefinition task) {
    _registerInitTaskForComponent('', task);
  }

  /// Registers one component-owned initialization task before Runtime startup.
  void _registerInitTaskForComponent(
    String ownerComponentId,
    CCInitTaskDefinition task,
  ) {
    _ensureConfigurable();
    if (!_isStableIdentifier(task.id)) {
      throw CCRegistrationError('Invalid InitTask ID "${task.id}".');
    }
    if (!_isStableIdentifier(task.gate.id)) {
      throw CCRegistrationError('Invalid InitTask Gate ID "${task.gate.id}".');
    }
    if (task.timeout != null && task.timeout! <= Duration.zero) {
      throw CCRegistrationError(
        'InitTask "${task.id}" timeout must be positive.',
      );
    }
    final dependencies = <String>{};
    for (final dependency in task.dependsOn) {
      if (!_isStableIdentifier(dependency) ||
          dependency == task.id ||
          !dependencies.add(dependency)) {
        throw CCRegistrationError(
          'InitTask "${task.id}" has an invalid, duplicate, or '
          'self dependency "$dependency".',
        );
      }
    }
    if (_initTasks.containsKey(task.id)) {
      throw CCRegistrationError('Duplicate InitTask ID "${task.id}".');
    }
    _initTasks[task.id] = _InitTaskRecord(
      ownerComponentId: ownerComponentId,
      task: task,
    );
  }

  /// Registers the single handler for command type [C].
  ///
  /// This low-level entry point exists for Core tests; components use the
  /// component-bound [CCRegistry].
  void registerCommand<C extends CCCommand<R>, R>(
    FutureOr<R> Function(C command, CCInvocationContext context) handler, {
    String? commandId,
  }) {
    _registerCommandForComponent('', handler, commandId: commandId);
  }

  /// Registers a command while retaining the component owner internally.
  void _registerCommandForComponent<C extends CCCommand<R>, R>(
    String ownerComponentId,
    FutureOr<R> Function(C command, CCInvocationContext context) handler, {
    String? commandId,
  }) {
    if (commandId != null && !_isStableIdentifier(commandId)) {
      throw CCRegistrationError('Invalid Command ID "$commandId".');
    }
    _registerSingle(
      _commands,
      C,
      _RegisteredCommandHandler(
        ownerComponentId: ownerComponentId,
        commandId: commandId,
        callback: (message, context) => handler(message as C, context),
      ),
    );
  }

  /// Registers an Event [handler] under a globally unique [id].
  ///
  /// This low-level entry point exists for Core tests; components use the
  /// component-bound [CCRegistry].
  void registerEvent<E extends CCEvent>(String id, CCEventHandler<E> handler) {
    _registerEventForComponent('', id, handler);
  }

  /// Registers a typed Event subscriber for low-level Runtime tests.
  ///
  /// Components should use [CCRegistry.registerEventSubscriber] so Runtime
  /// retains the trusted component owner.
  void registerEventSubscriber<E extends CCEvent>(
    CCEventSubscriber<E> subscriber,
  ) {
    _registerTypedEventForComponent('', subscriber);
  }

  /// Registers an event subscriber while retaining the component owner.
  void _registerEventForComponent<E extends CCEvent>(
    String ownerComponentId,
    String id,
    CCEventHandler<E> handler,
  ) {
    _registerEventSubscriber(
      E,
      _RegisteredEventSubscriber(
        id: id,
        eventId: null,
        ownerComponentId: ownerComponentId,
        callback: (message, context) async {
          await handler(message as E, context);
          return null;
        },
      ),
    );
  }

  /// Registers a typed Event subscriber while retaining its component owner.
  void _registerTypedEventForComponent<E extends CCEvent>(
    String ownerComponentId,
    CCEventSubscriber<E> subscriber,
  ) {
    final eventId = subscriber.eventId;
    if (eventId != null && !_isStableIdentifier(eventId)) {
      throw CCRegistrationError('Invalid Event ID "$eventId".');
    }
    _registerEventSubscriber(
      E,
      _RegisteredEventSubscriber(
        id: subscriber.id.value,
        eventId: eventId,
        ownerComponentId: ownerComponentId,
        callback: (message, context) async {
          await subscriber.handler(message as E, context);
          return null;
        },
      ),
    );
  }

  /// Registers a route directly for low-level Runtime tests.
  ///
  /// Components must use [CCRegistry.registerRoute] so the Runtime can inject a
  /// trustworthy component owner.
  void registerRoute<A, R>(CCRouteDefinition<A, R> definition) {
    _registerRouteForComponent('', definition);
  }

  /// Registers a route while retaining its trusted component owner.
  void _registerRouteForComponent<A, R>(
    String ownerComponentId,
    CCRouteDefinition<A, R> definition,
  ) {
    _ensureConfigurable();
    _routeRegistry.register(ownerComponentId, definition);
  }

  /// Registers a route interceptor for low-level Runtime tests.
  ///
  /// Components should register through [CCRegistry.registerRouteInterceptor]
  /// so Runtime retains the trusted component owner.
  void registerRouteInterceptor(
    String id,
    CCNavigationInterceptor interceptor, {
    Duration? timeout,
  }) {
    _registerRouteInterceptorForComponent(
      '',
      id,
      interceptor,
      timeout: timeout,
    );
  }

  /// Registers an interceptor while retaining its trusted component owner.
  void _registerRouteInterceptorForComponent(
    String ownerComponentId,
    String id,
    CCNavigationInterceptor interceptor, {
    Duration? timeout,
  }) {
    _ensureConfigurable();
    if (!_isStableIdentifier(id)) {
      throw CCRegistrationError('Route interceptor ID "$id" is invalid.');
    }
    if (_routeInterceptors.containsKey(id)) {
      throw CCRegistrationError('Duplicate route interceptor ID "$id".');
    }
    if (timeout != null && timeout <= Duration.zero) {
      throw CCRegistrationError(
        'Route interceptor "$id" timeout must be positive.',
      );
    }
    _routeInterceptors[id] = _RegisteredNavigationInterceptor(
      ownerComponentId: ownerComponentId,
      interceptor: interceptor,
      timeout: timeout,
    );
  }

  /// Registers a route Pop guard directly for low-level Runtime tests.
  ///
  /// Components should use [CCRegistry.registerRoutePopGuard] so Runtime keeps
  /// the trusted component owner associated with the guard.
  void registerRoutePopGuard(String id, CCPopGuard guard) {
    _registerRoutePopGuardForComponent('', id, guard);
  }

  /// Registers a synchronous Pop guard with its trusted component owner.
  void _registerRoutePopGuardForComponent(
    String ownerComponentId,
    String id,
    CCPopGuard guard,
  ) {
    _ensureConfigurable();
    if (!_isStableIdentifier(id)) {
      throw CCRegistrationError('Route Pop guard ID "$id" is invalid.');
    }
    if (_routePopGuards.containsKey(id)) {
      throw CCRegistrationError('Duplicate route Pop guard ID "$id".');
    }
    _routePopGuards[id] = _RegisteredPopGuard(
      ownerComponentId: ownerComponentId,
      guard: guard,
    );
  }

  /// Registers a Shell directly for low-level Runtime tests.
  ///
  /// Components must use [CCRegistry.registerShell] so Runtime can inject a
  /// trustworthy component owner.
  void registerShell(CCShellDefinition definition) {
    _registerShellForComponent('', definition);
  }

  /// Registers a Shell while retaining its trusted component owner.
  void _registerShellForComponent(
    String ownerComponentId,
    CCShellDefinition definition,
  ) {
    _ensureConfigurable();
    _shellRegistry.register(ownerComponentId, definition);
  }

  /// Stable IDs of all installed route definitions.
  ///
  /// Low-level tests and diagnostics use this deterministic snapshot to inspect
  /// route assembly; business navigation must use generated Intents.
  List<String> get registeredRouteIds => _routeRegistry.routeIds;

  /// Stable IDs of all installed Shell definitions.
  ///
  /// Low-level tests and diagnostics use this deterministic snapshot; business
  /// navigation targets generated routes rather than resolving Shell IDs.
  List<String> get registeredShellIds => _shellRegistry.shellIds;

  /// Resolves an internal or external URI to a normalized route location.
  ///
  /// Navigation adapters use this for URI and deep-link matching. Business code
  /// should navigate through `CCRouter.navigator` instead of resolving strings.
  CCRouteLocation resolveRoute(String location, {bool external = false}) {
    _ensureInitialized();
    return _routeRegistry.resolve(location, external: external);
  }

  /// Decodes a resolved route location into its generated argument type.
  ///
  /// Navigation adapters use this after [resolveRoute] to inject typed page
  /// arguments; business code should not depend on the type-erased result.
  Object decodeRouteArguments(CCRouteLocation location, {Object? extra}) {
    _ensureInitialized();
    return _routeRegistry.decode(location, extra: extra);
  }

  /// Resolves the default or keyed service implementation for [T].
  ///
  /// [contractToken] is a low-level generated/test selector for a stable promoted
  /// identity. Business Facades omit it and resolve through the contract type.
  /// Throws [CCServiceNotFoundError] when no matching Provider exists,
  /// [CCServiceTypeMismatchError] when a Token is used with the wrong type, or
  /// [CCServiceScopeUnavailableError] when the Provider's required Scope is
  /// inactive. A cancelled or expired parent invocation, an ended original
  /// Scope in its call chain, or an ended Service construction owner cannot
  /// resolve a dependency into a later Scope, even after a method returned.
  T service<T extends Object>({
    CCServiceToken<T>? contractToken,
    CCServiceKey<T>? key,
  }) {
    _ensureInitialized();
    final provider = _findProvider<T>(contractToken: contractToken, key: key);
    if (provider == null)
      throw CCServiceNotFoundError(
        contractToken?.id ?? T.toString(),
        key: key?.name,
      );
    return _resolve(provider) as T;
  }

  /// Resolves [T], returning null only when no matching provider exists.
  ///
  /// Use [contractToken] for optional promoted capabilities and omit it for internal
  /// services that intentionally remain coupled to their Dart type.
  T? serviceOrNull<T extends Object>({
    CCServiceToken<T>? contractToken,
    CCServiceKey<T>? key,
  }) {
    _ensureInitialized();
    final provider = _findProvider<T>(contractToken: contractToken, key: key);
    return provider == null ? null : _resolve(provider) as T;
  }

  /// Resolves [T] and awaits its optional lazy readiness initializer.
  ///
  /// Existing synchronous Providers complete without an asynchronous setup
  /// step. Providers with an initializer use one single-flight operation per
  /// singleton and Scope; new-instance Providers initialize every new instance.
  Future<T> serviceAsync<T extends Object>({
    CCServiceToken<T>? contractToken,
    CCServiceKey<T>? key,
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) {
    _ensureInitialized();
    final provider = _findProvider<T>(contractToken: contractToken, key: key);
    if (provider == null) {
      throw CCServiceNotFoundError(
        contractToken?.id ?? T.toString(),
        key: key?.name,
      );
    }
    return _readyService<T>(
      provider,
      contractToken: contractToken,
      timeout: timeout,
      cancellation: cancellation,
    );
  }

  /// Resolves optional [T] asynchronously, returning null only when absent.
  ///
  /// Initialization, lifecycle, timeout, and cancellation failures propagate
  /// unchanged and are never converted to null.
  Future<T?> serviceOrNullAsync<T extends Object>({
    CCServiceToken<T>? contractToken,
    CCServiceKey<T>? key,
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) {
    _ensureInitialized();
    final provider = _findProvider<T>(contractToken: contractToken, key: key);
    if (provider == null) return Future<T?>.value();
    return _readyService<T>(
      provider,
      contractToken: contractToken,
      timeout: timeout,
      cancellation: cancellation,
    );
  }

  /// Resolves a Route-scoped Service for one exact managed navigation.
  ///
  /// Flutter Host integration obtains [navigationId] from the backend payload
  /// attached by the Adapter. The ID must identify an active Entry or a removed
  /// Entry whose backend still owns an outgoing render lifetime. Runtime never
  /// falls back to the visible or top Entry. Ordinary
  /// business code uses the Flutter facade rather than calling this Host bridge.
  T serviceForRoute<T extends Object>({
    required String navigationId,
    CCServiceToken<T>? contractToken,
    CCServiceKey<T>? key,
  }) {
    _ensureInitialized();
    final provider = _findProvider<T>(contractToken: contractToken, key: key);
    if (provider == null) {
      throw CCServiceNotFoundError(
        contractToken?.id ?? T.toString(),
        key: key?.name,
      );
    }
    if (provider.scope != CCServiceScope.route) {
      throw const CCResolutionError(
        'Route-bound resolution requires a Route-scoped Service provider.',
      );
    }
    final entry = _routeServiceEntryForNavigation(navigationId);
    if (entry == null) {
      throw const CCServiceScopeUnavailableError(CCServiceScope.route);
    }
    return _resolve(provider, routeEntry: entry) as T;
  }

  /// Resolves an optional Route-scoped Service for one exact navigation.
  ///
  /// Null is returned only when the Provider is absent. A missing, fully exited,
  /// or disposed RouteEntry remains a lifecycle error so callers cannot silently
  /// retain a Service beyond its owning page.
  T? serviceForRouteOrNull<T extends Object>({
    required String navigationId,
    CCServiceToken<T>? contractToken,
    CCServiceKey<T>? key,
  }) {
    _ensureInitialized();
    final provider = _findProvider<T>(contractToken: contractToken, key: key);
    if (provider == null) return null;
    if (provider.scope != CCServiceScope.route) {
      throw const CCResolutionError(
        'Route-bound resolution requires a Route-scoped Service provider.',
      );
    }
    final entry = _routeServiceEntryForNavigation(navigationId);
    if (entry == null) {
      throw const CCServiceScopeUnavailableError(CCServiceScope.route);
    }
    return _resolve(provider, routeEntry: entry) as T;
  }

  /// Resolves and readies a Route Service for one exact managed navigation.
  ///
  /// [navigationId] must identify an active or backend-retained outgoing Entry
  /// when lookup begins. Closing its Scope after rendering cancels pending
  /// initialization and prevents the instance from becoming ready afterward.
  Future<T> serviceForRouteAsync<T extends Object>({
    required String navigationId,
    CCServiceToken<T>? contractToken,
    CCServiceKey<T>? key,
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) {
    _ensureInitialized();
    final provider = _findProvider<T>(contractToken: contractToken, key: key);
    if (provider == null) {
      throw CCServiceNotFoundError(
        contractToken?.id ?? T.toString(),
        key: key?.name,
      );
    }
    if (provider.scope != CCServiceScope.route) {
      throw const CCResolutionError(
        'Route-bound resolution requires a Route-scoped Service provider.',
      );
    }
    final entry = _routeServiceEntryForNavigation(navigationId);
    if (entry == null) {
      throw const CCServiceScopeUnavailableError(CCServiceScope.route);
    }
    return _readyService<T>(
      provider,
      contractToken: contractToken,
      routeEntry: entry,
      timeout: timeout,
      cancellation: cancellation,
    );
  }

  /// Resolves an optional Route Service asynchronously for one exact Entry.
  ///
  /// Null means only that the Provider is absent. Missing Route ownership and
  /// readiness failures remain explicit errors.
  Future<T?> serviceForRouteOrNullAsync<T extends Object>({
    required String navigationId,
    CCServiceToken<T>? contractToken,
    CCServiceKey<T>? key,
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) {
    _ensureInitialized();
    final provider = _findProvider<T>(contractToken: contractToken, key: key);
    if (provider == null) return Future<T?>.value();
    if (provider.scope != CCServiceScope.route) {
      throw const CCResolutionError(
        'Route-bound resolution requires a Route-scoped Service provider.',
      );
    }
    final entry = _routeServiceEntryForNavigation(navigationId);
    if (entry == null) {
      throw const CCServiceScopeUnavailableError(CCServiceScope.route);
    }
    return _readyService<T>(
      provider,
      contractToken: contractToken,
      routeEntry: entry,
      timeout: timeout,
      cancellation: cancellation,
    );
  }

  /// Whether a provider for [T] and [key] is registered.
  ///
  /// [contractToken] performs discovery by stable ID without instantiating a service.
  bool hasService<T extends Object>({
    CCServiceToken<T>? contractToken,
    CCServiceKey<T>? key,
  }) {
    _ensureInitialized();
    return _findProvider<T>(contractToken: contractToken, key: key) != null;
  }

  /// Resolves all implementations of [T] in deterministic key order.
  ///
  /// [contractToken] selects all providers attached to one promoted service API.
  List<T> services<T extends Object>({CCServiceToken<T>? contractToken}) {
    _ensureInitialized();
    final providers = List<_Provider>.of(_providersFor<T>(contractToken))
      ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
    return List.unmodifiable(
      providers.map((provider) => _resolve(provider) as T),
    );
  }

  /// Resolves every implementation of [T] and awaits optional readiness.
  ///
  /// Providers retain deterministic key order in the returned list. Readiness
  /// may proceed concurrently because each Provider has independent Scope and
  /// single-flight state; one failure completes the aggregate with that error.
  Future<List<T>> servicesAsync<T extends Object>({
    CCServiceToken<T>? contractToken,
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) async {
    _ensureInitialized();
    final providers = List<_Provider>.of(_providersFor<T>(contractToken))
      ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
    final services = await Future.wait(
      providers.map(
        (provider) => _readyService<T>(
          provider,
          contractToken: contractToken,
          timeout: timeout,
          cancellation: cancellation,
        ),
      ),
    );
    return List.unmodifiable(services);
  }

  /// Invokes one generated method on a promoted Service contract.
  ///
  /// Generated cross-component proxies use this boundary to resolve the exact
  /// Provider, propagate deadlines and cooperative cancellation, and create a
  /// method-level trace. Ordinary component-local services should keep using
  /// [service] because wrapping every local method would add cost without a
  /// package-boundary diagnostic benefit.
  ///
  /// [methodId] and [callerComponentId] must be stable identifiers. A Route
  /// Service requires the exact managed [navigationId]; non-Route Services
  /// reject one so stale page identity cannot be silently ignored. Arguments
  /// and return values are never added to the invocation context or trace.
  /// Cancellation, owner closure and deadlines are rechecked after readiness
  /// before entering the method, including Services without an initializer.
  /// Detached callbacks keep the original Scope lineage after methods return;
  /// closing an original Scope cancels pending children and fences fresh calls.
  /// Once entered, application work remains cooperatively cancellable.
  Future<R> invokeService<T extends Object, R>({
    CCServiceToken<T>? contractToken,
    CCServiceKey<T>? key,
    required String methodId,
    String? callerComponentId,
    String? navigationId,
    Duration? timeout,
    CCCancellationToken? cancellation,
    required FutureOr<R> Function(T service, CCInvocationContext context) call,
  }) {
    final invocation = _prepareServiceInvocation(
      contractToken: contractToken,
      key: key,
      methodId: methodId,
      callerComponentId: callerComponentId,
      navigationId: navigationId,
    );
    return _invoke(
      'service',
      invocation.target,
      (context) async {
        final resolved =
            await _resolveReady(
                  invocation.provider,
                  context,
                  routeEntry: invocation.routeEntry,
                )
                as T;
        _ensureInvocationCanEnter(context, ownerScope: invocation.scope);
        return call(resolved, context);
      },
      ownerScope: invocation.scope,
      timeout: timeout,
      cancellation: cancellation,
      callerComponentId: callerComponentId,
      targetComponentId: invocation.provider.ownerComponentId.isEmpty
          ? null
          : invocation.provider.ownerComponentId,
    );
  }

  /// Invokes one synchronous generated method on a promoted Service contract.
  ///
  /// Generated proxies use this boundary only for methods whose declared
  /// return type is synchronous. It preserves the contract signature and
  /// records the same ownership trace as [invokeService], but it never starts
  /// asynchronous readiness work. A Provider with an unfinished initializer
  /// therefore fails with [CCServiceNotReadyError]. Synchronous work cannot be
  /// preempted, so this API intentionally exposes no timeout or caller
  /// cancellation parameter.
  R invokeServiceSync<T extends Object, R>({
    CCServiceToken<T>? contractToken,
    CCServiceKey<T>? key,
    required String methodId,
    String? callerComponentId,
    String? navigationId,
    required R Function(T service, CCInvocationContext context) call,
  }) {
    final invocation = _prepareServiceInvocation(
      contractToken: contractToken,
      key: key,
      methodId: methodId,
      callerComponentId: callerComponentId,
      navigationId: navigationId,
    );
    return _invokeSync(
      'service',
      invocation.target,
      (context) {
        final resolved =
            _resolve(invocation.provider, routeEntry: invocation.routeEntry)
                as T;
        return call(resolved, context);
      },
      ownerScope: invocation.scope,
      callerComponentId: callerComponentId,
      targetComponentId: invocation.provider.ownerComponentId.isEmpty
          ? null
          : invocation.provider.ownerComponentId,
    );
  }

  /// Validates and resolves stable ownership for one generated Service call.
  ({
    _Provider provider,
    _RouteEntryRecord? routeEntry,
    CCScope scope,
    String target,
  })
  _prepareServiceInvocation<T extends Object>({
    CCServiceToken<T>? contractToken,
    CCServiceKey<T>? key,
    required String methodId,
    String? callerComponentId,
    String? navigationId,
  }) {
    _ensureInitialized();
    if (!_isStableIdentifier(methodId)) {
      throw const CCInvocationError(
        'The Service invocation method ID is invalid.',
      );
    }
    if (callerComponentId != null &&
        !_isComponentIdentifier(callerComponentId)) {
      throw const CCInvocationError(
        'The Service invocation caller component ID is invalid.',
      );
    }
    final provider = _findProvider<T>(contractToken: contractToken, key: key);
    final contractId = contractToken?.id ?? provider?.contractId;
    if (provider == null) {
      throw CCServiceNotFoundError(
        contractToken?.id ?? T.toString(),
        key: key?.name,
      );
    }
    if (callerComponentId != null && provider.ownerComponentId.isNotEmpty) {
      _validateGeneratedComponentAccess(
        callerComponentId: callerComponentId,
        targetComponentId: provider.ownerComponentId,
        capability: 'Service',
      );
    }
    if (contractId == null || !_isStableIdentifier(contractId)) {
      throw const CCInvocationError(
        'Generated Service invocation requires a promoted stable contract.',
      );
    }
    final routeEntry = provider.scope == CCServiceScope.route
        ? navigationId == null
              ? null
              : _routeServiceEntryForNavigation(navigationId)
        : null;
    if (provider.scope == CCServiceScope.route && routeEntry == null) {
      throw const CCServiceScopeUnavailableError(CCServiceScope.route);
    }
    if (provider.scope != CCServiceScope.route && navigationId != null) {
      throw const CCInvocationError(
        'Only a Route-scoped Service accepts a navigation ID.',
      );
    }
    final scope = _scopeForProvider(provider, routeEntry);
    if (scope == null) {
      throw CCServiceScopeUnavailableError(provider.scope);
    }
    if (scope.state != CCScopeState.active) {
      throw CCScopeClosedError(scope.id);
    }
    return (
      provider: provider,
      routeEntry: routeEntry,
      scope: scope,
      target: _serviceInvocationTarget(
        contractId: contractId,
        key: key?.name,
        methodId: methodId,
      ),
    );
  }

  /// Dispatches [command] with optional timeout and cancellation constraints.
  Future<R> command<R>(
    CCCommand<R> command, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => _dispatch<R>('command', command, _commands, timeout, cancellation);

  /// Dispatches one generated Command with validated stable identities.
  ///
  /// Generated framework bindings supply [commandId] and [callerComponentId].
  /// Business code uses its generated component Client rather than this SPI.
  Future<R> invokeGeneratedCommand<R>(
    CCCommand<R> command, {
    required String commandId,
    required String callerComponentId,
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) {
    _ensureInitialized();
    if (!_isStableIdentifier(commandId)) {
      throw const CCInvocationError('The generated Command ID is invalid.');
    }
    if (!_isComponentIdentifier(callerComponentId)) {
      throw const CCInvocationError(
        'The generated Command caller component ID is invalid.',
      );
    }
    final registration = _commands[command.runtimeType];
    if (registration != null && registration.ownerComponentId.isNotEmpty) {
      _validateGeneratedComponentAccess(
        callerComponentId: callerComponentId,
        targetComponentId: registration.ownerComponentId,
        capability: 'Command',
      );
    } else {
      _requireInstalledGeneratedComponent(callerComponentId, role: 'caller');
    }
    return _dispatch<R>(
      'command',
      command,
      _commands,
      timeout,
      cancellation,
      commandId: commandId,
      callerComponentId: callerComponentId,
    );
  }

  /// Publishes [event] concurrently and awaits all matching subscribers.
  ///
  /// A subscriber failure is isolated and recorded as a sanitized bounded
  /// diagnostic. Caller cancellation, an expired deadline, or Runtime shutdown
  /// still terminates the publish operation and propagates cooperative
  /// cancellation to subscriber contexts. Publishing with no subscribers is a
  /// successful no-op that remains visible in Trace.
  Future<void> event(
    CCEvent event, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) {
    final publisherComponentId =
        _parentContext?.targetComponentId ?? _parentContext?.callerComponentId;
    return _publishEvent(
      event,
      eventId: event.runtimeType.toString(),
      publisherComponentId: publisherComponentId,
      timeout: timeout,
      cancellation: cancellation,
    );
  }

  /// Publishes one generated Event with stable publisher identity.
  ///
  /// Generated component clients provide [eventId] and [publisherComponentId].
  /// Runtime validates any installed generated subscriptions before dispatch.
  Future<void> invokeGeneratedEvent(
    CCEvent event, {
    required String eventId,
    required String publisherComponentId,
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) {
    _ensureInitialized();
    if (!_isStableIdentifier(eventId)) {
      throw const CCInvocationError('The generated Event ID is invalid.');
    }
    if (!_isComponentIdentifier(publisherComponentId)) {
      throw const CCInvocationError(
        'The generated Event publisher component ID is invalid.',
      );
    }
    _requireInstalledGeneratedComponent(
      publisherComponentId,
      role: 'publisher',
    );
    final subscribers = _events[event.runtimeType]?.values ?? const [];
    if (subscribers.any(
      (subscriber) =>
          subscriber.eventId != null && subscriber.eventId != eventId,
    )) {
      throw CCResolutionError(
        'Event contract "$eventId" does not match registered subscriptions for ${event.runtimeType}.',
      );
    }
    for (final subscriber in subscribers) {
      final subscriberComponentId = subscriber.ownerComponentId;
      if (subscriberComponentId.isEmpty) continue;
      _validateGeneratedComponentAccess(
        callerComponentId: subscriberComponentId,
        targetComponentId: publisherComponentId,
        capability: 'Event subscription',
        allowOptionalDependency: true,
      );
    }
    return _publishEvent(
      event,
      eventId: eventId,
      publisherComponentId: publisherComponentId,
      timeout: timeout,
      cancellation: cancellation,
    );
  }

  /// Executes one Event fan-out through the shared traced Runtime path.
  Future<void> _publishEvent(
    CCEvent event, {
    required String eventId,
    required String? publisherComponentId,
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) {
    return _invoke(
      'event',
      eventId,
      (context) async {
        final subscribers = _sortedEventSubscribers(_events[event.runtimeType]);
        await Future.wait(
          subscribers.map((subscriber) async {
            try {
              await _invoke<void>(
                'eventSubscriber',
                '$eventId.${subscriber.id}',
                _eventSubscriberBody(subscriber, event),
                callerComponentId: context.callerComponentId,
                targetComponentId: subscriber.ownerComponentId.isEmpty
                    ? null
                    : subscriber.ownerComponentId,
                eventId: eventId,
                subscriberId: subscriber.id,
              );
            } catch (error) {
              if (_isEventPublishTermination(error, context)) rethrow;
              _recordSubscriberError(subscriber.id, error);
            }
          }),
        );
      },
      timeout: timeout,
      cancellation: cancellation,
      callerComponentId: publisherComponentId,
      eventId: eventId,
    );
  }

  /// Opens the explicitly selected [gate] and runs every newly ready InitTask
  /// exactly once.
  ///
  /// Calls that overlap share one DAG drain. Tasks whose Gates remain closed
  /// stay pending; successful and failed tasks are never retried implicitly.
  /// Task failures are returned as sanitized snapshots and skip only dependent
  /// branches. Runtime shutdown and cancellation still terminate this Future.
  /// Synchronous Gate reentry joins the already published drain. A task must
  /// not await its own drain. Failures are delivered in each caller's error
  /// Zone while shutdown joins the shared completion without rethrowing it.
  Future<CCInitTaskRunResult> runInitTasks({required CCInitTaskGate gate}) {
    _ensureInitialized();
    if (!_isStableIdentifier(gate.id)) {
      throw CCRegistrationError('Invalid InitTask Gate ID "${gate.id}".');
    }
    _openedInitTaskGates.add(gate.id);
    final active = _initTaskRun;
    if (active != null) {
      _initTaskDrainRequested = true;
      return active.future;
    }
    final run = _InitTaskDrain();
    _initTaskRun = run;
    unawaited(_drainAndReleaseInitTasks(run));
    return run.future;
  }

  /// Runs ready DAG layers and clears the single-flight marker on completion.
  Future<void> _drainAndReleaseInitTasks(_InitTaskDrain run) async {
    try {
      do {
        _initTaskDrainRequested = false;
        await _drainInitTasks();
      } while (_initTaskDrainRequested);
      run.result.complete(CCInitTaskRunResult._(initTasks));
    } catch (error, stack) {
      run.result.fail(error, stack);
    } finally {
      if (identical(_initTaskRun, run)) {
        _initTaskDrainRequested = false;
        _initTaskRun = null;
      }
    }
  }

  /// Executes ready task layers until all opened Gates become quiescent.
  Future<void> _drainInitTasks() async {
    while (true) {
      _skipBlockedInitTasks();
      final ready =
          _initTasks.values
              .where(
                (record) =>
                    record.state == CCInitTaskState.pending &&
                    _openedInitTaskGates.contains(record.task.gate.id) &&
                    record.task.dependsOn.every(
                      (dependency) =>
                          _initTasks[dependency]!.state ==
                          CCInitTaskState.succeeded,
                    ),
              )
              .toList()
            ..sort((left, right) => left.task.id.compareTo(right.task.id));
      if (ready.isEmpty) return;
      final failures = (await Future.wait(
        ready.map(_runInitTask),
      )).whereType<_InitTaskFailure>().toList();
      if (appScope.cancellation.isCancelled) {
        final cancellation = failures
            .map((failure) => failure.error)
            .whereType<CCInvocationCancelledError>()
            .firstOrNull;
        if (cancellation != null) throw cancellation;
      }
    }
  }

  /// Executes one task inside the shared invocation and cancellation pipeline.
  Future<_InitTaskFailure?> _runInitTask(_InitTaskRecord record) async {
    record.state = CCInitTaskState.running;
    _diagnosticRevision++;
    final watch = Stopwatch()..start();
    try {
      await _invoke<void>(
        'initTask',
        record.task.id,
        (context) async {
          await record.task.run(context);
          if (context.cancellation.isCancelled) {
            throw const CCInvocationCancelledError();
          }
        },
        timeout: record.task.timeout,
        targetComponentId: record.ownerComponentId.isEmpty
            ? null
            : record.ownerComponentId,
      );
      record.state = CCInitTaskState.succeeded;
      return null;
    } catch (error) {
      record.state = CCInitTaskState.failed;
      record.errorType = error.runtimeType.toString();
      return _InitTaskFailure(record, error);
    } finally {
      watch.stop();
      record.duration = watch.elapsed;
      _diagnosticRevision++;
    }
  }

  /// Marks tasks blocked by failed or skipped dependencies without executing.
  void _skipBlockedInitTasks() {
    var changed = true;
    while (changed) {
      changed = false;
      for (final record in _initTasks.values) {
        if (record.state != CCInitTaskState.pending) continue;
        for (final dependency in record.task.dependsOn) {
          final dependencyState = _initTasks[dependency]!.state;
          if (dependencyState == CCInitTaskState.failed ||
              dependencyState == CCInitTaskState.skipped) {
            record.state = CCInitTaskState.skipped;
            record.blockedByTaskId = dependency;
            _diagnosticRevision++;
            changed = true;
            break;
          }
        }
      }
    }
  }

  /// Opens an authenticated account Session and creates its owning Scope.
  void openSession({
    required String accountId,
    Map<String, Object?> metadata = const {},
  }) {
    _ensureInitialized();
    if (accountId.trim().isEmpty) {
      throw const CCResolutionError('Session accountId must not be empty.');
    }
    if (_sessionScope != null)
      throw const CCResolutionError(
        'Close the current Session before opening another.',
      );
    final sessionId = '$_runtimeId-session-${++_sessionSequence}';
    _sessionScope = _hostZone.run(() => CCScope(sessionId));
    _session = CCSession._(
      sessionId: sessionId,
      accountId: accountId,
      openedAt: DateTime.now(),
      metadata: metadata,
    );
  }

  /// Closes the active Session and releases Session-owned resources.
  Future<void> closeSession() async {
    _ensureInitialized();
    _cancelAllPendingNavigations(code: 'session_closed');
    final scope = _sessionScope;
    if (scope == null) return;
    await scope.close();
    if (identical(_sessionScope, scope)) {
      _sessionScope = null;
      _session = null;
    }
  }

  /// Permanently shuts down this Runtime and all of its Scopes.
  ///
  /// Hosts use this for final isolate teardown; use [closeSession] for logout so
  /// App-scoped services remain available.
  /// Callback failures do not skip subsequent cleanup. The first structural
  /// cleanup error is returned after teardown, including an App cancellation
  /// notification failure. Reentrant calls share the same disposal Future.
  Future<void> dispose() {
    if (_disposeFuture != null) return _disposeFuture!;
    final completion = Completer<void>();
    _disposeFuture = completion.future;
    _disposed = true;
    _initialized = false;
    completion.complete(_closeScopes());
    return completion.future;
  }

  /// Cancels Runtime work before disposing Session and App Scopes.
  Future<void> _closeScopes() async {
    Object? firstError;
    StackTrace? firstStackTrace;

    void capture(Object error, StackTrace stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    // Stop invocations before awaiting any service disposal.
    for (final release in _routeExitWaiters.values.toList()) {
      try {
        release();
      } catch (error, stackTrace) {
        capture(error, stackTrace);
      }
    }
    try {
      appScope.cancellation.cancel();
    } catch (error, stackTrace) {
      capture(error, stackTrace);
    }
    // A revalidation can be waiting on an interceptor-deferred continuation.
    // Cancel those continuations before joining the serialized revalidation tail.
    _cancelAllPendingNavigations(code: 'runtime_disposed');
    final routeRevalidationTail = _routeRevalidationTail;
    if (routeRevalidationTail != null) {
      try {
        await routeRevalidationTail;
      } catch (_) {
        // Each caller observes its own error; shutdown only waits for quiescence.
      }
    }
    final initTaskRun = _initTaskRun;
    if (initTaskRun != null) {
      // Wait for quiescence as data: an error Future created by another Gate
      // caller cannot deliver errors across Dart error Zone boundaries.
      await initTaskRun.result.settled;
    }
    try {
      _removeAllRouteEntries(reason: 'runtimeDispose');
    } catch (error, stackTrace) {
      capture(error, stackTrace);
    }
    try {
      await Future.wait(_routeEntryCloseFutures);
    } catch (error, stackTrace) {
      capture(error, stackTrace);
    }

    final adapter = _navigationAdapter;
    if (adapter != null) {
      try {
        _bindNavigationPopGuards(adapter, clear: true);
      } catch (error, stackTrace) {
        capture(error, stackTrace);
      }
    }
    final backendNavigationRemover = _backendNavigationRemover;
    _backendNavigationRemover = null;
    try {
      backendNavigationRemover?.call();
    } catch (error, stackTrace) {
      capture(error, stackTrace);
    }
    final predictiveBackRemover = _predictiveBackRemover;
    _predictiveBackRemover = null;
    try {
      predictiveBackRemover?.call();
    } catch (error, stackTrace) {
      capture(error, stackTrace);
    }
    try {
      adapter?.dispose();
    } catch (error, stackTrace) {
      capture(error, stackTrace);
    }
    try {
      _disposeNavigationObservations();
    } catch (error, stackTrace) {
      capture(error, stackTrace);
    }
    try {
      _disposeDiagnostics();
    } catch (error, stackTrace) {
      capture(error, stackTrace);
    }
    try {
      await _sessionScope?.close();
    } catch (error, stackTrace) {
      capture(error, stackTrace);
    }
    try {
      await appScope.close();
    } catch (error, stackTrace) {
      capture(error, stackTrace);
    }
    _navigationAdapter = null;
    _sessionScope = null;
    _session = null;
    _navigationListeners.clear();
    _navigationEvents.clear();
    _navigationFailureListeners.clear();
    _navigationFailures.clear();
    _pendingResumeFailures.clear();
    _navigationCapabilityFallbackListeners.clear();
    _navigationCapabilityFallbacks.clear();
    _routeEntryListeners.clear();
    _routeEntryEvents.clear();
    _routeVisibilityListeners.clear();
    _routeVisibilityEvents.clear();
    _routeEntryCloseFutures.clear();
    _exitingRouteEntries.clear();
    _routeExitWaiters.clear();
    _backendNavigationListeners.clear();
    _backendNavigationEvents.clear();
    // Scope disposal can read health after delivery closes but before history
    // cleanup. Invalidate that snapshot even when no further event is emitted.
    _diagnosticRevision++;
    _backendEntries.clear();
    _processedBackendOperations.clear();
    _backendSequencesByHost.clear();
    _desynchronizedBackendHosts.clear();
    _inFlightNavigation.clear();
    _navigationHostRegistrations.clear();
    for (final record in _navigationAspectRecords.values) {
      record.clock.stop();
    }
    _navigationAspectRecords.clear();
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
  }

  /// Awaits one Provider's readiness inside a traced Scope-owned invocation.
  Future<T> _readyService<T extends Object>(
    _Provider provider, {
    required CCServiceToken<T>? contractToken,
    _RouteEntryRecord? routeEntry,
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) {
    final zoneOwner = Zone.current[_constructionZoneKey];
    final owner =
        zoneOwner is _ServiceConstructionOwner &&
            identical(zoneOwner.runtimeIdentity, _zoneIdentity)
        ? zoneOwner
        : null;
    _validateServiceDependency(owner, provider);
    final effectiveRouteEntry = routeEntry ?? owner?.routeEntry;
    final providerScope = _scopeForProvider(provider, effectiveRouteEntry);
    final useParentScope =
        provider.creationPolicy == CCServiceCreationPolicy.newInstance &&
        owner != null &&
        provider.scope != owner.serviceScope;
    final scope = useParentScope ? owner.instanceScope : providerScope;
    if (scope == null) {
      throw CCServiceScopeUnavailableError(provider.scope);
    }
    if (scope.state != CCScopeState.active) {
      throw CCScopeClosedError(scope.id);
    }
    final target = _serviceInvocationTarget(
      contractId:
          contractToken?.id ?? provider.contractId ?? provider.type.toString(),
      key: provider.name,
      methodId: 'ready',
    );
    return _invoke(
      'serviceReady',
      target,
      (context) async =>
          await _resolveReady(
                provider,
                context,
                routeEntry: effectiveRouteEntry,
              )
              as T,
      ownerScope: scope,
      timeout: timeout,
      cancellation: cancellation,
      targetComponentId: provider.ownerComponentId.isEmpty
          ? null
          : provider.ownerComponentId,
    );
  }

  /// Resolves one normalized [provider] in its effective owner Scope.
  ///
  /// Admission is checked before cache/factory access and again before handing
  /// the instance back, because a factory may synchronously end its caller.
  Object _resolve(
    _Provider provider, {
    _RouteEntryRecord? routeEntry,
    bool allowUnready = false,
  }) {
    final zoneOwner = Zone.current[_constructionZoneKey];
    final owner =
        zoneOwner is _ServiceConstructionOwner &&
            identical(zoneOwner.runtimeIdentity, _zoneIdentity)
        ? zoneOwner
        : null;
    _ensureServiceResolutionCanEnter(owner);
    _validateServiceDependency(owner, provider);
    final effectiveRouteEntry = routeEntry ?? owner?.routeEntry;
    final providerScope = _scopeForProvider(provider, effectiveRouteEntry);
    final useParentScope =
        provider.creationPolicy == CCServiceCreationPolicy.newInstance &&
        owner != null &&
        provider.scope != owner.serviceScope;
    final scope = useParentScope ? owner.instanceScope : providerScope;
    if (scope == null) {
      throw CCServiceScopeUnavailableError(provider.scope);
    }
    if (scope.state != CCScopeState.active) throw CCScopeClosedError(scope.id);
    final providerKey = _providerKey(provider);
    if (!allowUnready &&
        provider.initializer != null &&
        (provider.creationPolicy == CCServiceCreationPolicy.newInstance ||
            !scope.isServiceReady(providerKey))) {
      throw CCServiceNotReadyError(_providerIdentity(provider));
    }
    final context = _context(scope.id, cancellation: scope.cancellation);
    final constructionValues = <Object, Object?>{
      ..._invocationZoneValues(
        context,
        ownerScope: scope,
        inheritOwnership: false,
      ),
      _constructionZoneKey: _ServiceConstructionOwner(
        runtimeIdentity: _zoneIdentity,
        serviceScope: useParentScope ? owner.serviceScope : provider.scope,
        instanceScope: scope,
        ownerComponentId: useParentScope
            ? owner.ownerComponentId
            : provider.ownerComponentId,
        routeEntry: effectiveRouteEntry,
      ),
      _readinessZoneKey: Zone.current[_readinessZoneKey],
      _readinessOwnerZoneKey: Zone.current[_readinessOwnerZoneKey],
      _navigationCallbackZoneKey: Zone.current[_navigationCallbackZoneKey],
    };
    // The factory owns Scope work, not its first consumer's arbitrary Zone.
    // Explicit framework lineage preserves dependency cycles and reentrancy.
    Object create() => _hostZone.run(
      () => runZoned(
        () => provider.factory(context),
        zoneValues: constructionValues,
      ),
    );
    final instance = scope.resolve(
      providerKey,
      create,
      cache: provider.creationPolicy == CCServiceCreationPolicy.singleton,
    );
    _ensureServiceResolutionCanEnter(owner);
    return instance;
  }

  /// Rejects fresh resolution from an ended owner or invocation continuation.
  ///
  /// Session lookup uses the currently active Scope; it must never turn old
  /// work into a caller of the replacement account, including detached work
  /// from successfully returned methods. Root delivery also rechecks Runtime
  /// shutdown after a reentrant factory. Singleton initializers carry their
  /// Scope context independently of the first waiter,
  /// so cancelling that waiter still permits shared initialization to continue.
  void _ensureServiceResolutionCanEnter(_ServiceConstructionOwner? owner) {
    if (_disposed) throw const CCInvocationCancelledError();
    final parent = _parentContext;
    if (parent != null) _ensureInvocationCanEnter(parent);
    if (owner != null && owner.instanceScope.state != CCScopeState.active) {
      throw CCScopeClosedError(owner.instanceScope.id);
    }
  }

  /// Resolves one Service and completes its optional readiness initializer.
  Future<Object> _resolveReady(
    _Provider provider,
    CCInvocationContext context, {
    _RouteEntryRecord? routeEntry,
  }) async {
    final zoneOwner = Zone.current[_constructionZoneKey];
    final owner =
        zoneOwner is _ServiceConstructionOwner &&
            identical(zoneOwner.runtimeIdentity, _zoneIdentity)
        ? zoneOwner
        : null;
    _validateServiceDependency(owner, provider);
    final effectiveRouteEntry = routeEntry ?? owner?.routeEntry;
    final providerScope = _scopeForProvider(provider, effectiveRouteEntry);
    final useParentScope =
        provider.creationPolicy == CCServiceCreationPolicy.newInstance &&
        owner != null &&
        provider.scope != owner.serviceScope;
    final scope = useParentScope ? owner.instanceScope : providerScope;
    if (scope == null) {
      throw CCServiceScopeUnavailableError(provider.scope);
    }
    if (scope.state != CCScopeState.active) throw CCScopeClosedError(scope.id);
    final instance = _resolve(
      provider,
      routeEntry: effectiveRouteEntry,
      allowUnready: true,
    );
    final initializer = provider.initializer;
    if (initializer == null) return instance;

    final providerKey = _providerKey(provider);
    final inheritedChain = Zone.current[_readinessZoneKey];
    final chain = inheritedChain is Map<Object, _ServiceReadinessRecord>
        ? inheritedChain
        : const <Object, _ServiceReadinessRecord>{};
    final scopedKey = (_runtimeId, scope.id, providerKey);
    if (provider.creationPolicy == CCServiceCreationPolicy.newInstance &&
        (chain[scopedKey]?.active ?? false)) {
      throw CCCircularServiceDependencyError(_providerIdentity(provider));
    }
    final readinessOwner =
        Zone.current[_readinessOwnerZoneKey] as _ServiceReadinessRecord?;
    final constructionOwner = _ServiceConstructionOwner(
      runtimeIdentity: _zoneIdentity,
      serviceScope: useParentScope ? owner.serviceScope : provider.scope,
      instanceScope: scope,
      ownerComponentId: useParentScope
          ? owner.ownerComponentId
          : provider.ownerComponentId,
      routeEntry: effectiveRouteEntry,
    );

    final initializerContext =
        provider.creationPolicy == CCServiceCreationPolicy.singleton
        ? _context(
            scope.id,
            operation: 'serviceInitialize',
            target: _serviceInvocationTarget(
              contractId: _providerContractIdentity(provider),
              key: provider.name,
              methodId: 'ready',
            ),
            targetComponentId: provider.ownerComponentId.isEmpty
                ? null
                : provider.ownerComponentId,
            cancellation: scope.cancellation,
          )
        : context;

    // Scope ownership is independent of the first waiter, while framework
    // decisions must retain their navigation-reentrancy prohibition.
    final navigationCallback = Zone.current[_navigationCallbackZoneKey];

    Future<void> initialize(_ServiceReadinessRecord record) =>
        _runServiceInitializer(
          initializer: initializer,
          instance: instance,
          context: initializerContext,
          identity: _providerIdentity(provider),
          zoneValues: {
            ..._invocationZoneValues(
              initializerContext,
              ownerScope: scope,
              inheritOwnership:
                  provider.creationPolicy != CCServiceCreationPolicy.singleton,
            ),
            _constructionZoneKey: constructionOwner,
            _readinessZoneKey: {...chain, scopedKey: record},
            _readinessOwnerZoneKey: record,
            if (navigationCallback != null)
              _navigationCallbackZoneKey: navigationCallback,
          },
        );

    try {
      if (provider.creationPolicy == CCServiceCreationPolicy.singleton) {
        await scope.ensureServiceReady(
          providerKey,
          initialize,
          owner: readinessOwner,
          identity: _providerIdentity(provider),
          waitCancellation: context.cancellation,
        );
      } else {
        final record = _ServiceReadinessRecord();
        final waiting = record.waitFor(
          readinessOwner,
          _providerIdentity(provider),
          context.cancellation,
        );
        record.start(() => initialize(record), context.cancellation, scope.id);
        await waiting;
      }
    } catch (_) {
      // Shared outcome delivery crosses error Zones; owner cancellation can
      // settle readiness before this waiter's invocation race observes it.
      // Preserve the same public cancellation outcome for every ended caller.
      if (context.cancellation.isCancelled) {
        throw const CCInvocationCancelledError();
      }
      rethrow;
    }
    if (context.cancellation.isCancelled) {
      throw const CCInvocationCancelledError();
    }
    return instance;
  }

  /// Returns the stable Scope cache key for one normalized Provider.
  Object _providerKey(_Provider provider) =>
      (provider.contractId ?? provider.type, provider.name);

  /// Returns a sanitized identity for Service readiness errors.
  String _providerIdentity(_Provider provider) {
    final contract = _providerContractIdentity(provider);
    return provider.name == null ? contract : '$contract#${provider.name}';
  }

  /// Returns the promoted Token ID or safe Dart type label for a Provider.
  String _providerContractIdentity(_Provider provider) =>
      provider.contractId ?? provider.type.toString();

  /// Returns the active concrete Scope selected by [provider].
  CCScope? _scopeForProvider(
    _Provider provider,
    _RouteEntryRecord? routeEntry,
  ) => switch (provider.scope) {
    CCServiceScope.app => appScope,
    CCServiceScope.session => _sessionScope,
    CCServiceScope.route => routeEntry?.scope,
  };

  /// Rejects dependencies whose lifetime can end before their consumer.
  void _validateServiceDependency(
    _ServiceConstructionOwner? owner,
    _Provider dependency,
  ) {
    final ownerScope = owner?.serviceScope;
    final dependencyScope = dependency.scope;
    final allowed = switch (ownerScope) {
      null => true,
      CCServiceScope.app => dependencyScope == CCServiceScope.app,
      CCServiceScope.session =>
        dependencyScope == CCServiceScope.app ||
            dependencyScope == CCServiceScope.session,
      CCServiceScope.route =>
        dependencyScope == CCServiceScope.app ||
            dependencyScope == CCServiceScope.route,
    };
    if (!allowed) {
      throw CCResolutionError(
        'A ${ownerScope!.name} Service cannot depend on the selected '
        '${dependencyScope.name} Service.',
      );
    }
  }

  /// Finds a provider by stable promoted contract or legacy Dart type.
  _Provider? _findProvider<T extends Object>({
    required CCServiceToken<T>? contractToken,
    required CCServiceKey<T>? key,
  }) {
    final providers = _providersFor<T>(contractToken);
    for (final provider in providers) {
      if (key == null ? provider.isDefault : provider.name == key.name)
        return provider;
    }
    return null;
  }

  /// Selects a service provider group and rejects forged token type mismatches.
  List<_Provider> _providersFor<T extends Object>(
    CCServiceToken<T>? contractToken,
  ) {
    final providers = contractToken == null
        ? _providers[T] ?? <_Provider>[]
        : _providersByContractId[contractToken.id] ?? <_Provider>[];
    if (contractToken != null &&
        providers.isNotEmpty &&
        providers.first.type != T) {
      throw CCServiceTypeMismatchError(
        contractToken.id,
        providers.first.type.toString(),
      );
    }
    return providers;
  }

  /// Resolves a single message handler and invokes it through [_invoke].
  Future<R> _dispatch<R>(
    String operation,
    Object message,
    Map<Type, _RegisteredCommandHandler> registry,
    Duration? timeout,
    CCCancellationToken? cancellation, {
    String? commandId,
    String? callerComponentId,
  }) {
    final registration = registry[message.runtimeType];
    final registeredCommandId = registration?.commandId;
    if (commandId != null && registeredCommandId != commandId) {
      throw CCResolutionError(
        registeredCommandId == null
            ? 'Command ${message.runtimeType} is not registered as generated contract "$commandId".'
            : 'Command contract "$commandId" does not match registered contract "$registeredCommandId".',
      );
    }
    return _invoke(
      operation,
      commandId ?? registeredCommandId ?? message.runtimeType.toString(),
      (context) async {
        if (registration == null) {
          throw CCResolutionError(
            'No $operation handler for ${message.runtimeType}.',
          );
        }
        return await registration.callback(message, context) as R;
      },
      timeout: timeout,
      cancellation: cancellation,
      callerComponentId: callerComponentId,
      targetComponentId: registration?.ownerComponentId.isEmpty ?? true
          ? null
          : registration!.ownerComponentId,
    );
  }

  /// Returns the installed manifest for one generated component identity.
  CCComponentManifest _requireInstalledGeneratedComponent(
    String componentId, {
    required String role,
  }) {
    for (final component in _components) {
      if (component.id == componentId) return component;
    }
    throw CCResolutionError(
      'Generated $role component "$componentId" is not installed.',
    );
  }

  /// Validates one generated cross-component capability relationship.
  ///
  /// Generated code supplies both identities, while Runtime rechecks the
  /// installed graph so stale or manually invoked bridges cannot forge Trace
  /// attribution or bypass declared Package contracts.
  void _validateGeneratedComponentAccess({
    required String callerComponentId,
    required String targetComponentId,
    required String capability,
    bool allowOptionalDependency = false,
  }) {
    final caller = _requireInstalledGeneratedComponent(
      callerComponentId,
      role: 'caller',
    );
    _requireInstalledGeneratedComponent(targetComponentId, role: 'target');
    if (callerComponentId == targetComponentId) return;
    final declared =
        caller.dependencies.contains(targetComponentId) ||
        allowOptionalDependency &&
            caller.optionalDependencies.contains(targetComponentId);
    if (!declared) {
      throw CCResolutionError(
        'Component "$callerComponentId" cannot use $capability owned by '
        '"$targetComponentId" without a declared component dependency.',
      );
    }
  }

  /// Executes a synchronous [body] with tracing and inherited invocation data.
  ///
  /// Cancellation and an inherited deadline are checked before execution.
  /// Dart cannot preempt synchronous work after [body] starts, so callers must
  /// not interpret this boundary as a synchronous timeout mechanism.
  R _invokeSync<R>(
    String operation,
    String target,
    R Function(CCInvocationContext) body, {
    CCScope? ownerScope,
    String? callerComponentId,
    String? targetComponentId,
  }) {
    _ensureInitialized();
    final parent = _parentContext;
    final now = DateTime.now();
    final context = _context(
      ownerScope?.id ?? parent?.scopeId ?? appScope.id,
      operation: operation,
      target: target,
      callerComponentId: callerComponentId,
      targetComponentId: targetComponentId,
      deadline: parent?.deadline,
    );
    final removers = <void Function()>[];
    final linkedTokens = <CCCancellationToken>{
      appScope.cancellation,
      if (ownerScope != null) ownerScope.cancellation,
      if (parent != null) parent.cancellation,
      ...?_currentInvocationOwnership?._tokens,
    };
    for (final token in linkedTokens) {
      removers.add(token.addListener(context.cancellation.cancel));
    }
    final watch = Stopwatch()..start();
    var status = 'succeeded';
    String? errorType;
    try {
      _ensureInvocationCanEnter(context, ownerScope: ownerScope);
      return runZoned(
        () => body(context),
        zoneValues: _invocationZoneValues(context, ownerScope: ownerScope),
      );
    } catch (error) {
      status = error is CCInvocationCancelledError
          ? 'cancelled'
          : error is CCInvocationTimeoutError
          ? 'timedOut'
          : 'failed';
      errorType = error.runtimeType.toString();
      rethrow;
    } finally {
      for (final remove in removers) {
        remove();
      }
      watch.stop();
      _recordTrace(
        context: context,
        operation: operation,
        target: target,
        startedAt: now,
        duration: watch.elapsed,
        status: status,
        errorType: errorType,
      );
    }
  }

  /// Rejects entry into business work after an asynchronous ownership handoff.
  ///
  /// Check immediately before calling application code, not only before
  /// readiness. A cancelled invocation cannot start a previously unentered
  /// method even when the resolved Service was already available. Original
  /// owners remain authoritative after parent methods return successfully.
  void _ensureInvocationCanEnter(
    CCInvocationContext context, {
    CCScope? ownerScope,
  }) {
    if (_disposed ||
        context.cancellation.isCancelled ||
        _currentInvocationOwnership?.isCancelled == true ||
        (ownerScope != null && ownerScope.state != CCScopeState.active)) {
      throw const CCInvocationCancelledError();
    }
    final deadline = context.deadline;
    if (deadline != null && !deadline.isAfter(DateTime.now())) {
      throw const CCInvocationTimeoutError();
    }
  }

  /// Executes [body] with tracing, inherited deadline, and cancellation.
  ///
  /// Deadline timer delays round up to whole milliseconds so Timer truncation
  /// cannot expire a child before its inherited wall-clock deadline.
  Future<R> _invoke<R>(
    String operation,
    String target,
    FutureOr<R> Function(CCInvocationContext) body, {
    CCScope? ownerScope,
    Duration? timeout,
    CCCancellationToken? cancellation,
    String? callerComponentId,
    String? targetComponentId,
    String? eventId,
    String? subscriberId,
  }) async {
    _ensureInitialized();
    final parent = _parentContext;
    final now = DateTime.now();
    final requestedDeadline = timeout == null ? null : now.add(timeout);
    final parentDeadline = parent?.deadline;
    final deadline = requestedDeadline == null
        ? parentDeadline
        : parentDeadline == null
        ? requestedDeadline
        : requestedDeadline.isBefore(parentDeadline)
        ? requestedDeadline
        : parentDeadline;
    final context = _context(
      ownerScope?.id ?? parent?.scopeId ?? appScope.id,
      operation: operation,
      target: target,
      callerComponentId: callerComponentId,
      targetComponentId: targetComponentId,
      deadline: deadline,
    );
    final cancelled = Completer<R>();
    final removers = <void Function()>[];
    final linkedTokens = <CCCancellationToken>{
      appScope.cancellation,
      if (ownerScope != null) ownerScope.cancellation,
      if (parent != null) parent.cancellation,
      if (cancellation != null) cancellation,
      ...?_currentInvocationOwnership?._tokens,
    };
    for (final token in linkedTokens) {
      removers.add(token.addListener(context.cancellation.cancel));
    }
    removers.add(
      context.cancellation.addListener(() {
        if (!cancelled.isCompleted)
          cancelled.completeError(const CCInvocationCancelledError());
      }),
    );
    final watch = Stopwatch()..start();
    var status = 'succeeded';
    String? errorType;
    try {
      final work = Future<R>.sync(() {
        _ensureInvocationCanEnter(context, ownerScope: ownerScope);
        return runZoned(
          () => body(context),
          zoneValues: _invocationZoneValues(context, ownerScope: ownerScope),
        );
      });
      final result = Future.any([work, cancelled.future]);
      if (deadline == null) return await result;
      final remainingMicros = deadline
          .difference(DateTime.now())
          .inMicroseconds;
      // Timer truncates fractional milliseconds. An early child timeout could
      // otherwise be isolated as a subscriber failure while its publisher's
      // shared deadline is still in the future, letting the Event succeed.
      final timerDelay = Duration(
        milliseconds: remainingMicros <= 0
            ? 0
            : (remainingMicros + Duration.microsecondsPerMillisecond - 1) ~/
                  Duration.microsecondsPerMillisecond,
      );
      final value = await result.timeout(
        timerDelay,
        onTimeout: () {
          throw const CCInvocationTimeoutError();
        },
      );
      // Cooperative cancellation can let [work] finish in the same event-loop
      // turn as the deadline timer. Preserve the deadline contract regardless
      // of which completion Future.any observes first.
      if (!deadline.isAfter(DateTime.now())) {
        throw const CCInvocationTimeoutError();
      }
      return value;
    } catch (error) {
      status = error is CCInvocationCancelledError
          ? 'cancelled'
          : error is CCInvocationTimeoutError
          ? 'timedOut'
          : 'failed';
      errorType = error.runtimeType.toString();
      if (status == 'timedOut') {
        try {
          context.cancellation.cancel();
        } catch (cleanupError) {
          _emitDiagnostic(
            category: CCDiagnosticCategory.lifecycle,
            level: CCDiagnosticLevel.error,
            operation: 'invocationCancellation',
            occurredAt: DateTime.now(),
            status: 'failed',
            duration: Duration.zero,
            errorType: cleanupError.runtimeType.toString(),
            invocationId: context.invocationId,
            scopeId: context.scopeId,
          );
        }
      }
      rethrow;
    } finally {
      for (final remove in removers) {
        remove();
      }
      watch.stop();
      _recordTrace(
        context: context,
        operation: operation,
        target: target,
        startedAt: now,
        duration: watch.elapsed,
        status: status,
        errorType: errorType,
        eventId: eventId,
        subscriberId: subscriberId,
      );
    }
  }

  /// Creates a child-aware invocation context for [scopeId].
  CCInvocationContext _context(
    String scopeId, {
    String? operation,
    String? target,
    String? callerComponentId,
    String? targetComponentId,
    DateTime? deadline,
    CCCancellationToken? cancellation,
  }) {
    final id = '$_runtimeId-$scopeId-${++_sequence}';
    final parent = _parentContext;
    return CCInvocationContext(
      invocationId: id,
      traceId: parent?.traceId ?? id,
      spanId: id,
      parentSpanId: parent?.spanId,
      operation: operation,
      target: target,
      callerComponentId: callerComponentId,
      targetComponentId: targetComponentId,
      scopeId: scopeId,
      deadline: deadline,
      cancellation: cancellation,
    );
  }

  /// Builds a sanitized trace target from validated Service identifiers.
  String _serviceInvocationTarget({
    required String contractId,
    required String? key,
    required String methodId,
  }) => key == null ? '$contractId.$methodId' : '$contractId.$key.$methodId';

  /// Returns Event subscribers sorted by stable identity before concurrent start.
  List<_RegisteredEventSubscriber> _sortedEventSubscribers(
    Map<String, _RegisteredEventSubscriber>? subscribers,
  ) {
    if (subscribers == null) return [];
    final ids = subscribers.keys.toList()..sort();
    return ids.map((id) => subscribers[id]!).toList();
  }

  /// Inserts one type-indexed handler and rejects duplicate types.
  void _registerSingle(
    Map<Type, _RegisteredCommandHandler> registry,
    Type type,
    _RegisteredCommandHandler handler,
  ) {
    _ensureConfigurable();
    if (registry.containsKey(type))
      throw CCRegistrationError('Duplicate handler for $type.');
    final commandId = handler.commandId;
    if (commandId != null &&
        registry.values.any((existing) => existing.commandId == commandId)) {
      throw CCRegistrationError('Duplicate Command ID "$commandId".');
    }
    registry[type] = handler;
  }

  /// Inserts one Event subscriber and rejects empty or globally duplicate IDs.
  void _registerEventSubscriber(
    Type type,
    _RegisteredEventSubscriber subscriber,
  ) {
    _ensureConfigurable();
    if (!_isStableIdentifier(subscriber.id) ||
        _events.values.any(
          (subscribers) => subscribers.containsKey(subscriber.id),
        )) {
      throw CCRegistrationError(
        'Invalid or duplicate subscriber ID "${subscriber.id}".',
      );
    }
    final eventId = subscriber.eventId;
    if (eventId != null) {
      for (final entry in _events.entries) {
        for (final existing in entry.value.values) {
          if (entry.key != type && existing.eventId == eventId) {
            throw CCRegistrationError(
              'Event ID "$eventId" is already bound to ${entry.key}.',
            );
          }
          if (entry.key == type &&
              existing.eventId != null &&
              existing.eventId != eventId) {
            throw CCRegistrationError(
              'Event type $type is already bound to "${existing.eventId}".',
            );
          }
        }
      }
    }
    _events.putIfAbsent(type, () => {})[subscriber.id] = subscriber;
  }

  /// Whether [error] represents termination of the enclosing Event publish.
  bool _isEventPublishTermination(Object error, CCInvocationContext context) =>
      error is CCInvocationCancelledError && context.cancellation.isCancelled ||
      error is CCInvocationTimeoutError &&
          context.deadline != null &&
          !context.deadline!.isAfter(DateTime.now());

  /// Records a sanitized Event subscriber failure in the bounded diagnostics.
  void _recordSubscriberError(String subscriberId, Object error) {
    if (traceCapacity == 0) return;
    if (_subscriberErrors.length == traceCapacity) {
      _subscriberErrors.removeAt(0);
    }
    _subscriberErrors.add(
      CCInvocationError(
        'Subscriber "$subscriberId" failed: ${error.runtimeType}.',
      ),
    );
  }

  /// Validates and deterministically orders host-provided global interceptors.
  List<CCGlobalNavigationInterceptor> _validateGlobalInterceptors(
    Iterable<CCGlobalNavigationInterceptor> interceptors,
  ) {
    final byId = <String, CCGlobalNavigationInterceptor>{};
    for (final interceptor in interceptors) {
      final id = interceptor.id;
      if (!_isStableIdentifier(id) || byId.containsKey(id)) {
        throw CCRegistrationError(
          'Invalid or duplicate global interceptor ID "$id".',
        );
      }
      final timeout = interceptor.timeout;
      if (timeout != null && timeout <= Duration.zero) {
        throw CCRegistrationError(
          'Global interceptor "$id" timeout must be positive.',
        );
      }
      byId[id] = interceptor;
    }
    final ids = byId.keys.toList()..sort();
    return List.unmodifiable(ids.map((id) => byId[id]!));
  }

  /// Validates and deterministically orders Host route-revalidation policies.
  List<CCGlobalRouteRevalidationPolicy> _validateRouteRevalidationPolicies(
    Iterable<CCGlobalRouteRevalidationPolicy> policies,
  ) {
    final byId = <String, CCGlobalRouteRevalidationPolicy>{};
    for (final policy in policies) {
      final id = policy.id;
      if (!_isStableIdentifier(id) || byId.containsKey(id)) {
        throw CCRegistrationError(
          'Invalid or duplicate route revalidation policy ID "$id".',
        );
      }
      final timeout = policy.timeout;
      if (timeout != null && timeout <= Duration.zero) {
        throw CCRegistrationError(
          'Route revalidation policy "$id" timeout must be positive.',
        );
      }
      byId[id] = policy;
    }
    final ids = byId.keys.toList()..sort();
    return List.unmodifiable(ids.map((id) => byId[id]!));
  }

  /// Validates and deterministically orders host-provided global Pop guards.
  List<CCGlobalPopGuard> _validateGlobalPopGuards(
    Iterable<CCGlobalPopGuard> guards,
  ) {
    final byId = <String, CCGlobalPopGuard>{};
    for (final guard in guards) {
      final id = guard.id;
      if (!_isStableIdentifier(id) || byId.containsKey(id)) {
        throw CCRegistrationError(
          'Invalid or duplicate global Pop guard ID "$id".',
        );
      }
      byId[id] = guard;
    }
    final ids = byId.keys.toList()..sort();
    return List.unmodifiable(ids.map((id) => byId[id]!));
  }

  /// Validates and deterministically orders global navigation aspects.
  List<CCNavigationAspect> _validateNavigationAspects(
    Iterable<CCNavigationAspect> aspects,
  ) {
    final byId = <String, CCNavigationAspect>{};
    for (final aspect in aspects) {
      final id = aspect.id;
      if (!_isStableIdentifier(id) || byId.containsKey(id)) {
        throw CCRegistrationError(
          'Invalid or duplicate navigation aspect ID "$id".',
        );
      }
      byId[id] = aspect;
    }
    final ids = byId.keys.toList()..sort();
    return List.unmodifiable(ids.map((id) => byId[id]!));
  }

  /// Validates category policies before the Runtime becomes observable.
  Map<CCDiagnosticCategory, CCDiagnosticCategoryPolicy>
  _validateDiagnosticPolicies(CCDiagnosticsConfig config) {
    _validateSampleRate(config.defaultSampleRate, 'defaultSampleRate');
    final policies = <CCDiagnosticCategory, CCDiagnosticCategoryPolicy>{};
    for (final policy in config.policies) {
      if (policies.containsKey(policy.category)) {
        throw CCRegistrationError(
          'Duplicate diagnostic policy for ${policy.category.name}.',
        );
      }
      _validateSampleRate(policy.sampleRate, policy.category.name);
      policies[policy.category] = policy;
    }
    return Map.unmodifiable(policies);
  }

  /// Validates one diagnostic sampling fraction.
  void _validateSampleRate(double value, String name) {
    if (value.isNaN || value < 0 || value > 1) {
      throw CCRegistrationError('Diagnostic $name must be between 0 and 1.');
    }
  }

  /// Maps a Runtime invocation operation to its observability category.
  CCDiagnosticCategory _diagnosticCategory(String operation) =>
      switch (operation) {
        'command' => CCDiagnosticCategory.command,
        'event' || 'eventSubscriber' => CCDiagnosticCategory.event,
        'service' || 'serviceReady' => CCDiagnosticCategory.service,
        'initTask' => CCDiagnosticCategory.initialization,
        _ => CCDiagnosticCategory.performance,
      };

  /// Selects a conservative severity from an invocation terminal status.
  CCDiagnosticLevel _diagnosticLevel(String status) => switch (status) {
    'succeeded' => CCDiagnosticLevel.info,
    'cancelled' || 'timedOut' => CCDiagnosticLevel.warning,
    _ => CCDiagnosticLevel.error,
  };

  /// Returns whether an event should be forwarded to the external Sink.
  bool _shouldDeliverDiagnostic(
    CCDiagnosticCategory category,
    CCDiagnosticLevel level,
  ) {
    final policy = _diagnosticPolicies[category];
    final enabled = policy?.enabled ?? diagnostics.defaultEnabled;
    if (!enabled) return false;
    final minimum = policy?.minimumLevel ?? diagnostics.defaultMinimumLevel;
    if (level.index < minimum.index) return false;
    final sampleRate = policy?.sampleRate ?? diagnostics.defaultSampleRate;
    if (level == CCDiagnosticLevel.error || sampleRate >= 1) return true;
    return sampleRate > 0 && _diagnosticRandom.nextDouble() < sampleRate;
  }

  /// Adds one completed invocation to the bounded trace and Sink queue.
  void _recordTrace({
    required CCInvocationContext context,
    required String operation,
    required String target,
    required DateTime startedAt,
    required Duration duration,
    required String status,
    String? errorType,
    String? eventId,
    String? subscriberId,
  }) {
    final record = CCTraceRecord(
      context: CCTraceContextSnapshot.from(context),
      operation: operation,
      target: target,
      startedAt: startedAt,
      duration: duration,
      status: status,
      errorType: errorType,
    );
    _traceTotal++;
    _retainDiagnostic(_traces, record, traceCapacity);
    final category = _diagnosticCategory(operation);
    final level = _diagnosticLevel(status);
    _emitDiagnostic(
      category: category,
      level: level,
      occurredAt: startedAt,
      operation: operation,
      status: status,
      duration: duration,
      traceId: context.traceId,
      spanId: context.spanId,
      parentSpanId: context.parentSpanId,
      invocationId: context.invocationId,
      target: target,
      callerComponentId: context.callerComponentId,
      targetComponentId: context.targetComponentId,
      scopeId: context.scopeId,
      eventId: eventId,
      subscriberId: subscriberId,
      errorType: errorType,
    );
  }

  /// Emits one sanitized non-invocation observation to the configured Sink.
  void _emitDiagnostic({
    required CCDiagnosticCategory category,
    required CCDiagnosticLevel level,
    required DateTime occurredAt,
    required String operation,
    required String status,
    required Duration duration,
    String? traceId,
    String? spanId,
    String? parentSpanId,
    String? invocationId,
    String? target,
    String? callerComponentId,
    String? targetComponentId,
    String? scopeId,
    String? navigationId,
    String? routeId,
    String? eventId,
    String? subscriberId,
    String? hostId,
    String? outlet,
    String? failureStage,
    String? failureReason,
    String? failureAttempt,
    int? recoveryDepth,
    String? errorType,
    String? fallbackKind,
  }) {
    _diagnosticRevision++;
    if (diagnostics.sink == null ||
        !_shouldDeliverDiagnostic(category, level)) {
      return;
    }
    _enqueueDiagnostic(
      CCDiagnosticEvent(
        category: category,
        level: level,
        occurredAt: occurredAt,
        operation: operation,
        status: status,
        duration: duration,
        runtimeId: _runtimeId,
        traceId: traceId,
        spanId: spanId,
        parentSpanId: parentSpanId,
        invocationId: invocationId,
        target: target,
        callerComponentId: callerComponentId,
        targetComponentId: targetComponentId,
        scopeId: scopeId,
        navigationId: navigationId,
        routeId: routeId,
        eventId: eventId,
        subscriberId: subscriberId,
        hostId: hostId,
        outlet: outlet,
        failureStage: failureStage,
        failureReason: failureReason,
        failureAttempt: failureAttempt,
        recoveryDepth: recoveryDepth,
        errorType: errorType,
        fallbackKind: fallbackKind,
      ),
    );
  }

  /// Emits one sanitized component-assembly or Runtime-startup observation.
  ///
  /// These events use the existing asynchronous diagnostic boundary so Host
  /// logging never participates in registration or initialization outcomes.
  void _emitInitializationDiagnostic({
    required DateTime occurredAt,
    required String operation,
    required String status,
    required CCDiagnosticLevel level,
    Duration duration = Duration.zero,
    String? target,
    String? targetComponentId,
    String? failureStage,
    String? errorType,
  }) {
    _emitDiagnostic(
      category: CCDiagnosticCategory.initialization,
      level: level,
      occurredAt: occurredAt,
      operation: operation,
      status: status,
      duration: duration,
      target: target,
      targetComponentId: targetComponentId,
      failureStage: failureStage,
      errorType: errorType,
    );
  }

  /// Records a failure isolated at an optional Host tooling boundary.
  ///
  /// Host integrations contain no business payload and identify themselves by
  /// a stable generated ID. The original exception and message are deliberately
  /// discarded so application diagnostics receive only its concrete type.
  void recordHostToolLifecycleFailure({
    required String integrationId,
    required String operation,
    required String errorType,
  }) {
    _emitInitializationDiagnostic(
      occurredAt: DateTime.now(),
      operation: operation,
      status: 'failed',
      level: CCDiagnosticLevel.error,
      target: integrationId,
      failureStage: 'hostToolLifecycle',
      errorType: errorType,
    );
  }

  /// Queues one Sink event without blocking the framework operation.
  void _enqueueDiagnostic(CCDiagnosticEvent event) =>
      _diagnosticDelivery.enqueue(event);

  /// Releases waiting diagnostics without awaiting an application-owned write.
  void _disposeDiagnostics() => _diagnosticDelivery.close();

  /// Ensures capability registration has not been frozen or disposed.
  void _ensureConfigurable() {
    if (_initialized || _disposed)
      throw const CCRegistrationError('Runtime registration is frozen.');
  }

  /// Ensures this Runtime currently accepts framework operations.
  void _ensureInitialized() {
    if (!_initialized) throw const CCRouterNotInitializedError();
  }

  /// Validates, topologically orders, and executes component registrars.
  void _installComponents(Iterable<CCComponentManifest> components) {
    final graphStartedAt = DateTime.now();
    var failureStage = 'manifestValidation';
    _emitInitializationDiagnostic(
      occurredAt: graphStartedAt,
      operation: 'componentGraph',
      status: 'started',
      level: CCDiagnosticLevel.debug,
    );
    try {
      final byId = <String, CCComponentManifest>{};
      for (final component in components) {
        if (!_isComponentIdentifier(component.id) ||
            byId.containsKey(component.id)) {
          throw CCRegistrationError(
            'Invalid or duplicate component ID "${component.id}".',
          );
        }
        if (!_semanticVersionPattern.hasMatch(component.version)) {
          throw CCRegistrationError(
            'Component "${component.id}" must use a SemVer 2.0 version.',
          );
        }
        final declaredDependencies = <String>{};
        for (final dependency in [
          ...component.dependencies,
          ...component.optionalDependencies,
        ]) {
          if (!_isComponentIdentifier(dependency) ||
              dependency == component.id ||
              !declaredDependencies.add(dependency)) {
            throw CCRegistrationError(
              'Component "${component.id}" has an invalid, duplicate, or '
              'self dependency "$dependency".',
            );
          }
        }
        byId[component.id] = component;
      }
      failureStage = 'dependencyResolution';
      final visiting = <String>{};
      final visited = <String>{};
      void visit(String id) {
        if (visited.contains(id)) return;
        if (!visiting.add(id)) {
          throw CCRegistrationError('Component dependency cycle at "$id".');
        }
        final component = byId[id]!;
        final dependencies = <String>{
          ...component.dependencies,
          ...component.optionalDependencies.where(byId.containsKey),
        }.toList()..sort();
        for (final dependency in dependencies) {
          if (!byId.containsKey(dependency)) {
            throw CCRegistrationError(
              'Component "$id" requires missing "$dependency".',
            );
          }
          visit(dependency);
        }
        visiting.remove(id);
        visited.add(id);
        _components.add(component);
      }

      final ids = byId.keys.toList()..sort();
      for (final id in ids) {
        visit(id);
      }
      // Validate the entire dependency graph before executing any registrar.
      failureStage = 'registrar';
      for (final component in _components) {
        final registrationStartedAt = DateTime.now();
        _emitInitializationDiagnostic(
          occurredAt: registrationStartedAt,
          operation: 'componentRegistration',
          status: 'started',
          level: CCDiagnosticLevel.debug,
          target: component.id,
          targetComponentId: component.id,
        );
        try {
          component.registrar.register(
            _CCComponentRegistry(runtime: this, ownerComponentId: component.id),
          );
        } on Object catch (error) {
          _emitInitializationDiagnostic(
            occurredAt: registrationStartedAt,
            operation: 'componentRegistration',
            status: 'failed',
            level: CCDiagnosticLevel.error,
            duration: DateTime.now().difference(registrationStartedAt),
            target: component.id,
            targetComponentId: component.id,
            failureStage: 'registrar',
            errorType: error.runtimeType.toString(),
          );
          rethrow;
        }
        _emitInitializationDiagnostic(
          occurredAt: registrationStartedAt,
          operation: 'componentRegistration',
          status: 'succeeded',
          level: CCDiagnosticLevel.info,
          duration: DateTime.now().difference(registrationStartedAt),
          target: component.id,
          targetComponentId: component.id,
        );
      }
    } on Object catch (error) {
      _emitInitializationDiagnostic(
        occurredAt: graphStartedAt,
        operation: 'componentGraph',
        status: 'failed',
        level: CCDiagnosticLevel.error,
        duration: DateTime.now().difference(graphStartedAt),
        failureStage: failureStage,
        errorType: error.runtimeType.toString(),
      );
      rethrow;
    }
    _emitInitializationDiagnostic(
      occurredAt: graphStartedAt,
      operation: 'componentGraph',
      status: 'succeeded',
      level: CCDiagnosticLevel.info,
      duration: DateTime.now().difference(graphStartedAt),
    );
  }

  /// Replaces already registered Providers for an isolated test Runtime.
  ///
  /// Replacement happens after all component registrars have run, so the test
  /// selects the same Provider identity that production would resolve. The
  /// original lifecycle Scope and creation policy remain in force; a test
  /// cannot accidentally turn a Session service into an App service or bypass
  /// disposal ownership. Production readiness is removed unless the override
  /// supplies its own initializer. Missing or repeated targets fail during
  /// construction.
  void _applyServiceOverrides(
    Iterable<CCServiceOverrideEntry<Object>> overrides,
  ) {
    final replaced = <_Provider>{};
    for (final override in overrides) {
      final candidates = override.contractToken == null
          ? (_providers[override.type] ?? const <_Provider>[])
          : (_providersByContractId[override.contractToken!.id] ??
                const <_Provider>[]);
      if (override.contractToken != null &&
          candidates.isNotEmpty &&
          candidates.any((provider) => provider.type != override.type)) {
        throw CCRegistrationError(
          'Service override contract "${override.contractToken!.id}" has a type '
          'mismatch.',
        );
      }
      final target = candidates.where((provider) {
        if (override.key == null) return provider.isDefault;
        return provider.name == override.key!.name;
      }).toList();
      if (target.length != 1) {
        final identity = override.contractToken?.id ?? override.type.toString();
        final keySuffix = override.key == null
            ? ''
            : ' with key "${override.key!.name}"';
        throw CCRegistrationError(
          'Service override target "$identity"$keySuffix was not found '
          'or is ambiguous.',
        );
      }
      final original = target.single;
      if (!replaced.add(original)) {
        final identity = override.contractToken?.id ?? override.type.toString();
        throw CCRegistrationError(
          'Service Provider "$identity" was overridden more than once.',
        );
      }
      final replacement = original.replacing(
        factory: (context) => override.factory(context),
        initializer: override.initializer,
      );
      replaced.add(replacement);
      final providers = _providers[original.type];
      if (providers != null) {
        final index = providers.indexOf(original);
        if (index >= 0) providers[index] = replacement;
      }
      if (original.contractId != null) {
        final contractProviders = _providersByContractId[original.contractId!];
        if (contractProviders != null) {
          final index = contractProviders.indexOf(original);
          if (index >= 0) contractProviders[index] = replacement;
        }
      }
    }
  }
}

/// Internal route interceptor registration with trusted component ownership.
final class _RegisteredNavigationInterceptor {
  /// Creates an owned route interceptor entry.
  _RegisteredNavigationInterceptor({
    required this.ownerComponentId,
    required this.interceptor,
    required this.timeout,
  });

  /// Component ID captured during registration.
  final String ownerComponentId;

  /// Interceptor implementation invoked by Runtime navigation.
  final CCNavigationInterceptor interceptor;

  /// Optional maximum duration allowed for one interception pass.
  final Duration? timeout;
}

/// Internal route Pop guard registration with trusted component ownership.
final class _RegisteredPopGuard {
  /// Creates an owned route Pop guard entry.
  _RegisteredPopGuard({required this.ownerComponentId, required this.guard});

  /// Component ID captured during registration.
  final String ownerComponentId;

  /// Synchronous guard evaluated before the backend receives a managed Pop.
  final CCPopGuard guard;
}
