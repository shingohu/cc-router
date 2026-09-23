part of 'runtime.dart';

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
    CCDeepLinkIngressPolicy deepLinkIngressPolicy =
        CCDeepLinkIngressPolicy.denyAll,
  }) => CCRouterRuntime._(
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
    CCDeepLinkIngressPolicy deepLinkIngressPolicy =
        CCDeepLinkIngressPolicy.denyAll,
    Iterable<CCServiceOverrideEntry<Object>> serviceOverrides = const [],
  }) => CCRouterRuntime._(
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
    deepLinkIngressPolicy: deepLinkIngressPolicy,
    serviceOverrides: serviceOverrides,
  );

  /// Creates a Runtime with validated configuration and installed components.
  /// Global navigation interceptors are ordered by stable ID before navigation
  /// begins; component route interceptors are registered by their registrars.
  CCRouterRuntime._({
    this.traceCapacity = 1000,
    this.navigationDiagnosticCapacity = 1000,
    Iterable<CCComponentManifest> components = const [],
    CCNavigationAdapter? navigationAdapter,
    Iterable<CCGlobalNavigationInterceptor> globalInterceptors = const [],
    Iterable<CCGlobalPopGuard> globalPopGuards = const [],
    this.navigationFailurePolicy,
    Iterable<CCNavigationAspect> navigationAspects = const [],
    this.telemetryContextProvider,
    this.restorationOpportunitySource,
    required this.navigationConcurrencyPolicy,
    required CCDeepLinkIngressPolicy deepLinkIngressPolicy,
    Iterable<CCServiceOverrideEntry<Object>> serviceOverrides = const [],
  }) {
    _deepLinkIngressPolicy = deepLinkIngressPolicy;
    _navigationAdapter = navigationAdapter;
    _globalInterceptors = _validateGlobalInterceptors(globalInterceptors);
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
    _installComponents(components);
    _applyServiceOverrides(serviceOverrides);
  }

  /// Zone key carrying the current invocation and its parent trace.
  static final Object _invocationZoneKey = Object();

  /// Zone key carrying the Scope of a service under construction.
  static final Object _constructionZoneKey = Object();

  /// Zone key preventing navigation from asynchronous framework callbacks.
  static final Object _navigationCallbackZoneKey = Object();

  /// Maximum number of trace and subscriber error records retained.
  final int traceCapacity;

  /// Maximum retained records in each bounded navigation diagnostic history.
  ///
  /// The limit applies independently to lifecycle, failure, capability
  /// fallback, visibility, Route Entry, Backend, and restoration histories.
  /// Active structural state is not evicted by this value. Zero disables
  /// retained histories while live listeners and navigation behavior remain
  /// active.
  final int navigationDiagnosticCapacity;

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

  /// Optional Host SPI used to snapshot anonymous analytics identity.
  ///
  /// Runtime calls it only when a navigation observation begins. Business code
  /// and route implementations never receive the provider itself.
  final CCNavigationTelemetryContextProvider? telemetryContextProvider;

  /// Optional Host SPI that reports evidence of unmet restoration demand.
  ///
  /// The source remains Host-owned. Runtime records sanitized events and only
  /// owns the subscription installed during initialization.
  final CCRouteRestorationOpportunitySource? restorationOpportunitySource;

  /// Runtime-specific prefix preventing trace identifiers from colliding.
  final String _runtimeId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  /// Service providers grouped by contract type.
  final Map<Type, List<_Provider>> _providers = {};

  /// Promoted service providers grouped by stable cross-package identity.
  final Map<String, List<_Provider>> _providersByContractId = {};

  /// Single command handler indexed by command type.
  final Map<Type, _Handler> _commands = {};

  /// Single query handler indexed by query type.
  final Map<Type, _Handler> _queries = {};

  /// Action handlers indexed by action type and stable handler identifier.
  final Map<Type, Map<String, _Handler>> _actions = {};

  /// Event subscribers indexed by event type and stable subscriber identifier.
  final Map<Type, Map<String, _Handler>> _events = {};

  /// Component-owned Shell definitions indexed by stable Shell ID.
  final _ShellRegistry _shellRegistry = _ShellRegistry();

  /// Component-owned route definitions indexed by stable route ID.
  late final _RouteRegistry _routeRegistry = _RouteRegistry(
    _shellRegistry,
    _deepLinkIngressPolicy,
  );

  /// Concrete Route Entries currently retained by the Runtime.
  final List<_RouteEntryRecord> _routeEntries = [];

  /// Bounded Route Entry lifecycle transitions retained for diagnostics.
  final Queue<CCRouteEntryLifecycleEvent> _routeEntryEvents = Queue();

  /// Subscribers receiving Route Entry lifecycle transitions.
  final Set<CCRouteEntryLifecycleListener> _routeEntryListeners = {};

  /// Bounded Route Entry visibility observations retained for diagnostics.
  final Queue<CCRouteVisibilityEvent> _routeVisibilityEvents = Queue();

  /// Subscribers receiving Route Entry visibility observations.
  final Set<CCRouteVisibilityListener> _routeVisibilityListeners = {};

  /// Route Scope close operations that Runtime must await during shutdown.
  final List<Future<void>> _routeEntryCloseFutures = [];

  /// Optional adapter that executes Runtime-validated navigation requests.
  CCNavigationAdapter? _navigationAdapter;

  /// Stable, application-owned interceptors executed before route policies.
  late final List<CCGlobalNavigationInterceptor> _globalInterceptors;

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

  /// Bounded evidence that a prior route state could have been restored.
  final Queue<CCRouteRestorationOpportunityEvent>
  _restorationOpportunityEvents = Queue();

  /// Observers exporting sanitized restoration-demand telemetry.
  final Set<CCRouteRestorationOpportunityListener>
  _restorationOpportunityListeners = {};

  /// Removes the Runtime subscription from the Host evidence source.
  void Function()? _restorationOpportunityRemover;

  /// Futures for requests that have not completed or been rejected.
  final Map<_NavigationConcurrencyKey, Future<Object?>> _inFlightNavigation =
      {};

  /// Runtime-owned continuations waiting for an external policy decision.
  final Map<String, _PendingNavigationRecord> _pendingNavigations = {};

  /// Active or retained observation state indexed by navigation identity.
  final Map<String, _CCNavigationAspectRecord> _navigationAspectRecords = {};

  /// Subscribers receiving Runtime navigation lifecycle events.
  final Set<CCNavigationLifecycleListener> _navigationListeners = {};

  /// Subscribers receiving sanitized navigation failure outcomes.
  final Set<CCNavigationFailureListener> _navigationFailureListeners = {};

  /// Subscribers receiving safe Adapter capability fallback observations.
  final Set<CCNavigationCapabilityFallbackListener>
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
  final Set<CCNavigationBackendDiagnosticListener> _backendNavigationListeners =
      {};

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

  /// Component-owned Service Scopes keyed by stable component ID.
  final Map<String, CCScope> _componentScopes = {};

  /// Whether each compiled-in component currently accepts new resolutions.
  final Map<String, bool> _componentActive = {};

  /// Serialized Component activation/deactivation operations.
  final Map<String, Future<void>> _componentTransitions = {};

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

  /// Monotonic sequence used in Component Scope identities.
  int _componentScopeSequence = 0;

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

  /// Immutable snapshot of sanitized Event subscriber failures.
  List<CCInvocationError> get subscriberErrors =>
      List.unmodifiable(_subscriberErrors);

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
    _validateRouteConfiguration();
    _validateNavigationAdapterCapabilities();
    _navigationAdapter?.initialize(
      _navigationRoutesForAdapter(),
      shells: _shellRegistry.navigationShells,
    );
    final adapter = _navigationAdapter;
    if (adapter is CCNavigationPopGuardBinding) {
      (adapter as CCNavigationPopGuardBinding).bindPopGuardEvaluator(
        _evaluatePopGuardsForActiveEntry,
      );
    }
    _attachBackendNavigationSource();
    _readInitialBackendSnapshot();
    _initialized = true;
    _attachRestorationOpportunitySource();
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
      if (adapter is CCNavigationPopGuardBinding) {
        (adapter as CCNavigationPopGuardBinding).bindPopGuardEvaluator(
          _evaluatePopGuardsForActiveEntry,
        );
      }
      _attachBackendNavigationSource();
      _readInitialBackendSnapshot();
    } catch (_) {
      if (adapter is CCNavigationPopGuardBinding) {
        (adapter as CCNavigationPopGuardBinding).bindPopGuardEvaluator(null);
      }
      _backendNavigationRemover?.call();
      _backendNavigationRemover = null;
      _predictiveBackRemover?.call();
      _predictiveBackRemover = null;
      _backendEntries.clear();
      _processedBackendOperations.clear();
      _backendSequencesByHost.clear();
      _desynchronizedBackendHosts.clear();
      _navigationAdapter = null;
      rethrow;
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
    if (provider.scope == CCServiceScope.route) {
      throw const CCRegistrationError('Route scopes are not implemented yet.');
    }
    if (provider.scope == CCServiceScope.component &&
        ownerComponentId.isEmpty) {
      throw const CCRegistrationError(
        'Component-scoped Services must be registered by a component.',
      );
    }
    final providers = _providers[T] ?? <_Provider>[];
    final contractId = provider.contract?.id;
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
    );
    providers.add(normalized);
    _providers[T] = providers;
    if (contractProviders != null) {
      contractProviders.add(normalized);
      _providersByContractId[contractId!] = contractProviders;
    }
  }

  /// Registers the single handler for command type [C].
  ///
  /// This low-level entry point exists for Core tests; components use the
  /// component-bound [CCRegistry].
  void registerCommand<C extends CCCommand<R>, R>(CCHandler<C, R> handler) {
    _registerCommandForComponent('', handler);
  }

  /// Registers a command while retaining the component owner internally.
  void _registerCommandForComponent<C extends CCCommand<R>, R>(
    String ownerComponentId,
    CCHandler<C, R> handler,
  ) {
    _registerSingle(
      _commands,
      C,
      (message, context) => handler(message as C, context),
    );
  }

  /// Registers the single handler for query type [Q].
  ///
  /// This low-level entry point exists for Core tests; components use the
  /// component-bound [CCRegistry].
  void registerQuery<Q extends CCQuery<R>, R>(CCHandler<Q, R> handler) {
    _registerQueryForComponent('', handler);
  }

  /// Registers a query while retaining the component owner internally.
  void _registerQueryForComponent<Q extends CCQuery<R>, R>(
    String ownerComponentId,
    CCHandler<Q, R> handler,
  ) {
    _registerSingle(
      _queries,
      Q,
      (message, context) => handler(message as Q, context),
    );
  }

  /// Registers an action [handler] under a globally unique [id].
  ///
  /// This low-level entry point exists for Core tests; components use the
  /// component-bound [CCRegistry].
  void registerAction<A extends CCAction>(
    String id,
    CCHandler<A, void> handler,
  ) {
    _registerActionForComponent('', id, handler);
  }

  /// Registers an action while retaining the component owner internally.
  void _registerActionForComponent<A extends CCAction>(
    String ownerComponentId,
    String id,
    CCHandler<A, void> handler,
  ) {
    _registerMultiple(_actions, A, id, (message, context) async {
      await handler(message as A, context);
      return null;
    });
  }

  /// Registers an Event [handler] under a globally unique [id].
  ///
  /// This low-level entry point exists for Core tests; components use the
  /// component-bound [CCRegistry].
  void registerEvent<E extends CCEvent>(String id, CCHandler<E, void> handler) {
    _registerEventForComponent('', id, handler);
  }

  /// Registers an event subscriber while retaining the component owner.
  void _registerEventForComponent<E extends CCEvent>(
    String ownerComponentId,
    String id,
    CCHandler<E, void> handler,
  ) {
    _registerMultiple(_events, E, id, (message, context) async {
      await handler(message as E, context);
      return null;
    });
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

  /// Activates a component and creates a fresh Component Service Scope.
  ///
  /// Activation waits for any previous transition of the same component. A
  /// closed Scope is never reopened, so old Service instances cannot leak into
  /// a later activation. Routes and Shells become available only after the new
  /// Scope exists. Unknown component IDs fail with [CCRegistrationError].
  Future<void> activateComponent(String componentId) {
    _ensureInitialized();
    _requireComponent(componentId);
    return _enqueueComponentTransition(componentId, () async {
      final current = _componentScopes[componentId];
      if (current != null && current.state == CCScopeState.active) return;
      _componentScopes[componentId] = _newComponentScope(componentId);
      _componentActive[componentId] = true;
      _shellRegistry.activateComponent(componentId);
      _routeRegistry.activateComponent(componentId);
    });
  }

  /// Deactivates a component and asynchronously closes its Service Scope.
  ///
  /// Routes and Shells are made unavailable before the returned Future waits
  /// for disposable Services. New resolutions fail immediately, active Scope
  /// work receives cancellation, and disposal proceeds in reverse construction
  /// order. This is not an authorization or logout API.
  Future<void> deactivateComponent(String componentId) {
    _ensureInitialized();
    _requireComponent(componentId);
    _componentActive[componentId] = false;
    _routeRegistry.deactivateComponent(componentId);
    _shellRegistry.deactivateComponent(componentId);
    return _enqueueComponentTransition(componentId, () async {
      // A queued activation may have run after this request closed the public
      // entry points. Re-apply the requested terminal state when this
      // transition owns the queue so call order remains authoritative.
      _componentActive[componentId] = false;
      _routeRegistry.deactivateComponent(componentId);
      _shellRegistry.deactivateComponent(componentId);
      final scope = _componentScopes[componentId];
      if (scope == null || scope.state == CCScopeState.closed) return;
      await scope.close();
    });
  }

  /// Serializes transitions for one component without blocking other
  /// components. A failed transition does not prevent the next explicit
  /// lifecycle request from being attempted.
  Future<void> _enqueueComponentTransition(
    String componentId,
    Future<void> Function() operation,
  ) {
    final previous = _componentTransitions[componentId];
    final transition = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // The new request is an explicit lifecycle decision and may retry.
        }
      }
      await operation();
    }();
    _componentTransitions[componentId] = transition;
    void clearTransition() {
      if (identical(_componentTransitions[componentId], transition)) {
        _componentTransitions.remove(componentId);
      }
    }

    transition.then<void>(
      (_) => clearTransition(),
      onError: (Object _, StackTrace __) => clearTransition(),
    );
    return transition;
  }

  /// Validates that [componentId] belongs to this Runtime.
  void _requireComponent(String componentId) {
    if (!_componentActive.containsKey(componentId)) {
      throw CCRegistrationError('Unknown component "$componentId".');
    }
  }

  /// Creates a unique Scope for one Component activation.
  CCScope _newComponentScope(String componentId) =>
      CCScope('component-$componentId-${++_componentScopeSequence}');

  /// Resolves the default or keyed service implementation for [T].
  ///
  /// [contract] selects the stable identity used after cross-package promotion;
  /// omitting it preserves the legacy type-based lookup path.
  /// Throws [CCServiceNotFoundError] when no matching Provider exists,
  /// [CCServiceTypeMismatchError] when a Token is used with the wrong type, or
  /// [CCServiceScopeUnavailableError] when the Provider's required Scope is
  /// inactive.
  T service<T extends Object>({
    CCServiceToken<T>? contract,
    CCServiceKey<T>? key,
  }) {
    _ensureInitialized();
    final provider = _findProvider<T>(contract: contract, key: key);
    if (provider == null)
      throw CCServiceNotFoundError(
        contract?.id ?? T.toString(),
        key: key?.name,
      );
    return _resolve(provider) as T;
  }

  /// Resolves [T], returning null only when no matching provider exists.
  ///
  /// Use [contract] for optional promoted capabilities and omit it for internal
  /// services that intentionally remain coupled to their Dart type.
  T? serviceOrNull<T extends Object>({
    CCServiceToken<T>? contract,
    CCServiceKey<T>? key,
  }) {
    _ensureInitialized();
    final provider = _findProvider<T>(contract: contract, key: key);
    return provider == null ? null : _resolve(provider) as T;
  }

  /// Whether a provider for [T] and [key] is registered.
  ///
  /// [contract] performs discovery by stable ID without instantiating a service.
  bool hasService<T extends Object>({
    CCServiceToken<T>? contract,
    CCServiceKey<T>? key,
  }) {
    _ensureInitialized();
    return _findProvider<T>(contract: contract, key: key) != null;
  }

  /// Resolves all implementations of [T] in deterministic key order.
  ///
  /// [contract] selects all providers attached to one promoted service API.
  List<T> services<T extends Object>({CCServiceToken<T>? contract}) {
    _ensureInitialized();
    final providers = List<_Provider>.of(_providersFor<T>(contract))
      ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
    return List.unmodifiable(
      providers.map((provider) => _resolve(provider) as T),
    );
  }

  /// Dispatches [command] with optional timeout and cancellation constraints.
  Future<R> command<R>(
    CCCommand<R> command, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => _dispatch<R>('command', command, _commands, timeout, cancellation);

  /// Dispatches [query] with optional timeout and cancellation constraints.
  Future<R> query<R>(
    CCQuery<R> query, {
    Duration? timeout,
    CCCancellationToken? cancellation,
  }) => _dispatch<R>('query', query, _queries, timeout, cancellation);

  /// Runs matching Action handlers serially in stable identifier order.
  Future<CCActionReport> action(CCAction action) =>
      _invoke('action', action.runtimeType.toString(), (context) async {
        final handlers = _sortedHandlers(_actions[action.runtimeType]);
        for (final handler in handlers) {
          await handler(action, context);
        }
        return CCActionReport(handled: handlers.length);
      });

  /// Publishes [event] concurrently while isolating subscriber failures.
  Future<void> event(CCEvent event) =>
      _invoke('event', event.runtimeType.toString(), (context) async {
        final handlers = _sortedHandlers(_events[event.runtimeType]);
        await Future.wait(
          handlers.map((handler) async {
            try {
              await handler(event, context);
            } catch (error) {
              if (traceCapacity > 0) {
                if (_subscriberErrors.length == traceCapacity)
                  _subscriberErrors.removeAt(0);
                _subscriberErrors.add(
                  CCInvocationError('Subscriber failed: ${error.runtimeType}'),
                );
              }
            }
          }),
        );
      });

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
    _sessionScope = CCScope(sessionId);
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
  Future<void> dispose() {
    if (_disposeFuture != null) return _disposeFuture!;
    _disposed = true;
    _initialized = false;
    return _disposeFuture = _closeScopes();
  }

  /// Cancels Runtime work before disposing Session and App Scopes.
  Future<void> _closeScopes() async {
    // Stop invocations before awaiting any service disposal.
    appScope.cancellation.cancel();
    _cancelAllPendingNavigations(code: 'runtime_disposed');
    _removeAllRouteEntries(reason: 'runtimeDispose');
    await Future.wait(_routeEntryCloseFutures);
    try {
      final adapter = _navigationAdapter;
      if (adapter is CCNavigationPopGuardBinding) {
        (adapter as CCNavigationPopGuardBinding).bindPopGuardEvaluator(null);
      }
      _backendNavigationRemover?.call();
      _backendNavigationRemover = null;
      _predictiveBackRemover?.call();
      _predictiveBackRemover = null;
      _restorationOpportunityRemover?.call();
      _restorationOpportunityRemover = null;
      _navigationAdapter?.dispose();
    } finally {
      _disposeNavigationObservations();
      _componentActive.updateAll((componentId, _) => false);
      await Future.wait(_componentTransitions.values);
      await Future.wait(_componentScopes.values.map((scope) => scope.close()));
      await _sessionScope?.close();
      await appScope.close();
      _navigationAdapter = null;
      _sessionScope = null;
      _session = null;
      _componentScopes.clear();
      _componentActive.clear();
      _componentTransitions.clear();
      _navigationListeners.clear();
      _navigationEvents.clear();
      _navigationFailureListeners.clear();
      _navigationFailures.clear();
      _pendingResumeFailures.clear();
      _navigationCapabilityFallbackListeners.clear();
      _navigationCapabilityFallbacks.clear();
      _restorationOpportunityListeners.clear();
      _restorationOpportunityEvents.clear();
      _routeEntryListeners.clear();
      _routeEntryEvents.clear();
      _routeVisibilityListeners.clear();
      _routeVisibilityEvents.clear();
      _routeEntryCloseFutures.clear();
      _backendNavigationListeners.clear();
      _backendNavigationEvents.clear();
      _backendEntries.clear();
      _processedBackendOperations.clear();
      _backendSequencesByHost.clear();
      _desynchronizedBackendHosts.clear();
      _inFlightNavigation.clear();
      for (final record in _navigationAspectRecords.values) {
        record.clock.stop();
      }
      _navigationAspectRecords.clear();
    }
  }

  /// Resolves one normalized [provider] in its effective owner Scope.
  Object _resolve(_Provider provider) {
    final owner = Zone.current[_constructionZoneKey];
    final ownerScope =
        owner is (CCRouterRuntime, CCServiceScope) && identical(owner.$1, this)
        ? owner.$2
        : null;
    if (ownerScope == CCServiceScope.app &&
        provider.scope != CCServiceScope.app) {
      throw const CCResolutionError(
        'An App service cannot depend on a narrower Service scope.',
      );
    }
    if (ownerScope == CCServiceScope.session &&
        provider.scope == CCServiceScope.component) {
      throw const CCResolutionError(
        'A Session service cannot depend on a Component service.',
      );
    }
    final parentScope = switch (ownerScope) {
      CCServiceScope.app => appScope,
      CCServiceScope.session => _sessionScope,
      CCServiceScope.component =>
        _componentActive[provider.ownerComponentId] == true
            ? _componentScopes[provider.ownerComponentId]
            : null,
      CCServiceScope.route || null => null,
    };
    final CCScope? scope;
    if (provider.creationPolicy == CCServiceCreationPolicy.factory &&
        provider.scope == CCServiceScope.app &&
        parentScope != null) {
      scope = parentScope;
    } else {
      scope = switch (provider.scope) {
        CCServiceScope.app => appScope,
        CCServiceScope.session => _sessionScope,
        CCServiceScope.component =>
          _componentActive[provider.ownerComponentId] == true
              ? _componentScopes[provider.ownerComponentId]
              : null,
        CCServiceScope.route => null,
      };
    }
    if (scope == null) {
      throw CCServiceScopeUnavailableError(provider.scope);
    }
    if (scope.state != CCScopeState.active) throw CCScopeClosedError(scope.id);
    final context = _context(scope.id, cancellation: scope.cancellation);
    Object create() => runZoned(
      () => provider.factory(context),
      zoneValues: {
        _invocationZoneKey: (this, context),
        _constructionZoneKey: (
          this,
          provider.creationPolicy == CCServiceCreationPolicy.factory
              ? ownerScope ?? CCServiceScope.app
              : provider.scope,
        ),
      },
    );
    return scope.resolve(
      (provider.contractId ?? provider.type, provider.name),
      create,
      cache: provider.creationPolicy == CCServiceCreationPolicy.singleton,
    );
  }

  /// Finds a provider by stable promoted contract or legacy Dart type.
  _Provider? _findProvider<T extends Object>({
    required CCServiceToken<T>? contract,
    required CCServiceKey<T>? key,
  }) {
    final providers = _providersFor<T>(contract);
    for (final provider in providers) {
      if (key == null ? provider.isDefault : provider.name == key.name)
        return provider;
    }
    return null;
  }

  /// Selects a service provider group and rejects forged token type mismatches.
  List<_Provider> _providersFor<T extends Object>(CCServiceToken<T>? contract) {
    final providers = contract == null
        ? _providers[T] ?? <_Provider>[]
        : _providersByContractId[contract.id] ?? <_Provider>[];
    if (contract != null && providers.isNotEmpty && providers.first.type != T) {
      throw CCServiceTypeMismatchError(
        contract.id,
        providers.first.type.toString(),
      );
    }
    return providers;
  }

  /// Resolves a single message handler and invokes it through [_invoke].
  Future<R> _dispatch<R>(
    String operation,
    Object message,
    Map<Type, _Handler> registry,
    Duration? timeout,
    CCCancellationToken? cancellation,
  ) => _invoke(
    operation,
    message.runtimeType.toString(),
    (context) async {
      final handler = registry[message.runtimeType];
      if (handler == null)
        throw CCResolutionError(
          'No $operation handler for ${message.runtimeType}.',
        );
      return await handler(message, context) as R;
    },
    timeout: timeout,
    cancellation: cancellation,
  );

  /// Executes [body] with tracing, inherited deadline, and cancellation.
  Future<R> _invoke<R>(
    String operation,
    String target,
    FutureOr<R> Function(CCInvocationContext) body, {
    Duration? timeout,
    CCCancellationToken? cancellation,
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
      parent?.scopeId ?? appScope.id,
      deadline: deadline,
    );
    final cancelled = Completer<R>();
    final removers = <void Function()>[];
    for (final token in [
      appScope.cancellation,
      parent?.cancellation,
      cancellation,
    ]) {
      if (token != null)
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
        if (context.cancellation.isCancelled)
          throw const CCInvocationCancelledError();
        if (deadline != null && !deadline.isAfter(DateTime.now()))
          throw const CCInvocationTimeoutError();
        return runZoned(
          () => body(context),
          zoneValues: {_invocationZoneKey: (this, context)},
        );
      });
      final result = Future.any([work, cancelled.future]);
      if (deadline == null) return await result;
      final remaining = deadline.difference(DateTime.now());
      return await result.timeout(
        remaining.isNegative ? Duration.zero : remaining,
        onTimeout: () {
          throw const CCInvocationTimeoutError();
        },
      );
    } catch (error) {
      status = error is CCInvocationCancelledError
          ? 'cancelled'
          : error is CCInvocationTimeoutError
          ? 'timedOut'
          : 'failed';
      errorType = error.runtimeType.toString();
      if (status == 'timedOut') context.cancellation.cancel();
      rethrow;
    } finally {
      for (final remove in removers) {
        remove();
      }
      watch.stop();
      if (traceCapacity > 0) {
        if (_traces.length == traceCapacity) _traces.removeFirst();
        _traces.add(
          CCTraceRecord(
            context: CCTraceContextSnapshot.from(context),
            operation: operation,
            target: target,
            startedAt: now,
            duration: watch.elapsed,
            status: status,
            errorType: errorType,
          ),
        );
      }
    }
  }

  /// Parent invocation carried by the current Zone for this Runtime.
  CCInvocationContext? get _parentContext {
    final current = Zone.current[_invocationZoneKey];
    return current is (CCRouterRuntime, CCInvocationContext) &&
            identical(current.$1, this)
        ? current.$2
        : null;
  }

  /// Creates a child-aware invocation context for [scopeId].
  CCInvocationContext _context(
    String scopeId, {
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
      scopeId: scopeId,
      deadline: deadline,
      cancellation: cancellation,
    );
  }

  /// Returns handlers sorted by their stable identifiers.
  List<_Handler> _sortedHandlers(Map<String, _Handler>? handlers) {
    if (handlers == null) return [];
    final ids = handlers.keys.toList()..sort();
    return ids.map((id) => handlers[id]!).toList();
  }

  /// Inserts one type-indexed handler and rejects duplicate types.
  void _registerSingle(
    Map<Type, _Handler> registry,
    Type type,
    _Handler handler,
  ) {
    _ensureConfigurable();
    if (registry.containsKey(type))
      throw CCRegistrationError('Duplicate handler for $type.');
    registry[type] = handler;
  }

  /// Inserts one ID-indexed handler and rejects empty or duplicate IDs.
  void _registerMultiple(
    Map<Type, Map<String, _Handler>> registry,
    Type type,
    String id,
    _Handler handler,
  ) {
    _ensureConfigurable();
    if (id.isEmpty ||
        registry.values.any((handlers) => handlers.containsKey(id))) {
      throw CCRegistrationError('Empty or duplicate handler ID "$id".');
    }
    registry.putIfAbsent(type, () => {})[id] = handler;
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
    final visiting = <String>{};
    final visited = <String>{};
    void visit(String id) {
      if (visited.contains(id)) return;
      if (!visiting.add(id))
        throw CCRegistrationError('Component dependency cycle at "$id".');
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
    for (final component in _components) {
      _componentScopes[component.id] = _newComponentScope(component.id);
      _componentActive[component.id] = true;
    }
    // Validate the entire dependency graph before executing any registrar.
    for (final component in _components) {
      component.registrar.register(
        _CCComponentRegistry(runtime: this, ownerComponentId: component.id),
      );
    }
  }

  /// Replaces already registered Providers for an isolated test Runtime.
  ///
  /// Replacement happens after all component registrars have run, so the test
  /// selects the same Provider identity that production would resolve. The
  /// original lifecycle Scope and creation policy remain in force; a test
  /// cannot accidentally turn a Session service into an App service or bypass
  /// disposal ownership. Missing or repeated targets fail during construction.
  void _applyServiceOverrides(
    Iterable<CCServiceOverrideEntry<Object>> overrides,
  ) {
    final replaced = <_Provider>{};
    for (final override in overrides) {
      final candidates = override.contract == null
          ? (_providers[override.type] ?? const <_Provider>[])
          : (_providersByContractId[override.contract!.id] ??
                const <_Provider>[]);
      if (override.contract != null &&
          candidates.isNotEmpty &&
          candidates.any((provider) => provider.type != override.type)) {
        throw CCRegistrationError(
          'Service override contract "${override.contract!.id}" has a type '
          'mismatch.',
        );
      }
      final target = candidates.where((provider) {
        if (override.key == null) return provider.isDefault;
        return provider.name == override.key!.name;
      }).toList();
      if (target.length != 1) {
        final identity = override.contract?.id ?? override.type.toString();
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
        final identity = override.contract?.id ?? override.type.toString();
        throw CCRegistrationError(
          'Service Provider "$identity" was overridden more than once.',
        );
      }
      final replacement = original.replacingFactory(
        (context) => override.factory(context),
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
