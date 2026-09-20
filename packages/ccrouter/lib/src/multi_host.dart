import 'package:ccrouter_contracts/ccrouter_contracts.dart';

import 'app.dart';

/// Host-only Adapter registry for multi-window navigation backends.
///
/// Register one independently owned Adapter per Window or display Host, then
/// expose this registry through a `CCRouterAppBackend` initialized by
/// `CCRouterApp.managed`.
/// Requests with an explicit route Host remain pinned to that Host; routes
/// using the `default` placement resolve through [activeHostId]. Business code
/// should not retain this object or select a Host for ordinary navigation.
final class CCNavigationHostRegistry
    implements
        CCNavigationAdapter,
        CCNavigationAdapterHostBinding,
        CCNavigationAdapterCapabilitySource,
        CCNavigationHostCapabilitySource,
        CCNavigationBackendEventSource,
        CCNavigationManagedEntryReleaseSink,
        CCNavigationBackendSnapshotSource,
        CCNavigationPopCoordinator,
        CCNavigationPopGuardBinding,
        CCNavigationPredictiveBackSourceProvider,
        CCNavigationPredictiveBackSource {
  /// Creates a registry with an initial Host-to-Adapter mapping.
  ///
  /// [defaultHostId] must identify one supplied Adapter. The registry assumes
  /// ownership of every supplied Adapter and disposes each exactly once.
  CCNavigationHostRegistry({
    required String defaultHostId,
    required Map<String, CCNavigationAdapter> adapters,
  }) : _activeHostId = defaultHostId {
    if (defaultHostId.isEmpty) {
      throw ArgumentError.value(
        defaultHostId,
        'defaultHostId',
        'Default Host ID cannot be empty.',
      );
    }
    if (adapters.isEmpty || !adapters.containsKey(defaultHostId)) {
      throw ArgumentError.value(
        adapters,
        'adapters',
        'The default Host must have one registered Adapter.',
      );
    }
    for (final entry in adapters.entries) {
      _validateHost(entry.key, entry.value);
      _hosts[entry.key] = _CCNavigationHostAdapterRecord(entry.value);
    }
  }

  /// Host currently used to resolve routes with the `default` placement.
  String get activeHostId => _activeHostId;

  /// Immutable Host identities currently available for navigation.
  Set<String> get registeredHostIds => Set.unmodifiable(_hosts.keys);

  /// Immutable adaptive layout snapshots indexed by Host identity.
  Map<String, CCAdaptiveHostLayout> get adaptiveLayouts =>
      Map.unmodifiable(_adaptiveLayouts);

  /// Default Host identity consumed by Runtime request construction.
  @override
  String get hostId => _activeHostId;

  /// Conservative aggregate capabilities used for route-table validation.
  ///
  /// Structural capabilities use union semantics because explicit Host routes
  /// are validated by their selected child Adapter during initialization.
  /// Request-scoped visibility uses [capabilitiesForHost] instead.
  @override
  CCNavigationAdapterCapabilities get capabilities =>
      CCNavigationAdapterCapabilities(
        supportsBackendVisibilityObservation: false,
        supportsNestedNavigators: _anyCapability(
          (value) => value.supportsNestedNavigators,
        ),
        supportsStatefulShell: _anyCapability(
          (value) => value.supportsStatefulShell,
        ),
        supportsModalRoutes: _anyCapability(
          (value) => value.supportsModalRoutes,
        ),
        supportsPredictiveBack: _anyCapability(
          (value) => value.supportsPredictiveBack,
        ),
        supportsManagedPopObservation: _anyCapability(
          (value) => value.supportsManagedPopObservation,
        ),
      );

  /// Returns capabilities for one registered child Host.
  @override
  CCNavigationAdapterCapabilities? capabilitiesForHost(String hostId) {
    final adapter = _hosts[hostId]?.adapter;
    return adapter is CCNavigationAdapterCapabilitySource
        ? (adapter as CCNavigationAdapterCapabilitySource).capabilities
        : null;
  }

  /// Merged predictive-back source, or null when no child supports it.
  @override
  CCNavigationPredictiveBackSource? get predictiveBackSource =>
      capabilities.supportsPredictiveBack ? this : null;

  /// Makes [hostId] the target for subsequent default-placement requests.
  ///
  /// Window focus and display-host infrastructure call this when foreground
  /// ownership changes. Existing RouteEntries keep their original Host.
  void activateHost(String hostId) {
    _ensureAvailable();
    if (!_hosts.containsKey(hostId)) {
      throw CCNavigationAdapterError(
        'Navigation Host "$hostId" is not registered.',
      );
    }
    _activeHostId = hostId;
  }

  /// Resolves and publishes adaptive Outlet visibility for one Host Window.
  ///
  /// Call this from platform Window or Flutter layout infrastructure when
  /// width, display features, or fold posture changes. The operation never
  /// pushes, removes, or migrates routes; it only changes which retained
  /// Outlet tops are considered shown.
  CCAdaptiveHostLayout updateWindowMetrics(
    CCWindowMetrics metrics, {
    CCAdaptivePresentationPolicy presentationPolicy =
        const CCAdaptivePresentationPolicy(),
    required CCAdaptiveOutletPolicy outletPolicy,
    String? shellId,
  }) {
    _ensureAvailable();
    if (!_hosts.containsKey(metrics.hostId)) {
      throw CCNavigationAdapterError(
        'Navigation Host "${metrics.hostId}" is not registered.',
      );
    }
    final layout = presentationPolicy.select(metrics);
    final activeOutlets = outletPolicy.activeOutletsFor(layout);
    final snapshot = CCAdaptiveHostLayout(
      metrics: metrics,
      layout: layout,
      activeOutlets: activeOutlets,
    );
    _adaptiveLayouts[metrics.hostId] = snapshot;
    CCPageLifecycleHostBridge.setActiveOutlets(
      hostId: metrics.hostId,
      outlets: activeOutlets,
    );
    final sequence = _nextHostSequence(metrics.hostId);
    _publishBackendEvent(
      CCNavigationBackendEvent(
        kind: CCNavigationBackendEventKind.outletsChanged,
        timestamp: DateTime.now(),
        backendOperationId: '$_registryId-${metrics.hostId}-layout-$sequence',
        hostId: metrics.hostId,
        navigatorOutlet: activeOutlets.first,
        sequence: sequence,
        placement: CCRoutePlacement(
          hostId: metrics.hostId,
          shellId: shellId,
          navigatorOutlet: activeOutlets.first,
        ),
        activeNavigatorOutlets: activeOutlets,
      ),
    );
    for (final listener in _adaptiveLayoutListeners.toList()) {
      try {
        listener(snapshot);
      } catch (_) {
        // Layout telemetry must never interrupt Host navigation state.
      }
    }
    return snapshot;
  }

  /// Subscribes to adaptive Host layout changes.
  ///
  /// The returned callback removes the listener. Callbacks are observational
  /// and cannot modify the resolved active Outlet set for the current event.
  void Function() addAdaptiveLayoutListener(
    CCAdaptiveHostLayoutListener listener,
  ) {
    _adaptiveLayoutListeners.add(listener);
    return () => _adaptiveLayoutListeners.remove(listener);
  }

  /// Adds one Host Adapter, including after registry initialization.
  ///
  /// A dynamically added Adapter receives the cached route table before it is
  /// exposed to navigation. Failure leaves the registry unchanged and disposes
  /// the rejected Adapter because ownership transferred to this call.
  void registerHost(String hostId, CCNavigationAdapter adapter) =>
      _registerHost(hostId, adapter);

  /// Performs one atomic Host registration.
  void _registerHost(String hostId, CCNavigationAdapter adapter) {
    _ensureNotDisposed();
    _validateHost(hostId, adapter);
    if (_hosts.containsKey(hostId)) {
      throw CCNavigationAdapterError(
        'Navigation Host "$hostId" is already registered.',
      );
    }
    final record = _CCNavigationHostAdapterRecord(adapter);
    try {
      if (_initialized) _initializeRecord(hostId, record);
      _ensureNotDisposed();
      _hosts[hostId] = record;
      _bindRecord(hostId, record);
    } catch (_) {
      record.dispose();
      rethrow;
    }
  }

  /// Removes and disposes one Host Adapter without affecting other Hosts.
  ///
  /// The last Host cannot be removed from an initialized registry. Runtime is
  /// notified before disposal so entries owned by the removed Host close their
  /// Route Scopes. Live backend pages are never migrated implicitly.
  void unregisterHost(String hostId) => _unregisterHost(hostId);

  /// Performs one atomic Host removal.
  void _unregisterHost(String hostId) {
    _ensureAvailable();
    if (_hosts.length == 1) {
      throw const CCNavigationAdapterError(
        'An initialized Host registry must retain at least one Host.',
      );
    }
    final record = _hosts.remove(hostId);
    if (record == null) {
      throw CCNavigationAdapterError(
        'Navigation Host "$hostId" is not registered.',
      );
    }
    _unbindRecord(record);
    _hostByNavigationId.removeWhere((_, value) => value == hostId);
    _adaptiveLayouts.remove(hostId);
    if (_activeHostId == hostId) _activeHostId = _hosts.keys.first;
    final sequence = _nextHostSequence(hostId);
    _publishBackendEvent(
      CCNavigationBackendEvent(
        kind: CCNavigationBackendEventKind.hostDetached,
        timestamp: DateTime.now(),
        backendOperationId: '$_registryId-$hostId-detached-$sequence',
        hostId: hostId,
        sequence: sequence,
        placement: CCRoutePlacement(hostId: hostId),
      ),
    );
    _sequencesByHost.remove(hostId);
    record.dispose();
  }

  /// Initializes every registered Host with only its applicable routes.
  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) => _initialize(routes, shells: shells);

  /// Initializes child Hosts as one synchronous configuration transaction.
  void _initialize(
    List<CCNavigationRoute> routes, {
    required List<CCNavigationShell> shells,
  }) {
    _ensureNotDisposed();
    if (_initialized) {
      throw const CCNavigationAdapterError(
        'The navigation Host registry is already initialized.',
      );
    }
    _routes = List.unmodifiable(routes);
    _shells = List.unmodifiable(shells);
    for (final entry in _hosts.entries) {
      _initializeRecord(entry.key, entry.value);
      _ensureNotDisposed();
      _bindRecord(entry.key, entry.value);
    }
    _ensureNotDisposed();
    _initialized = true;
  }

  /// Executes one request on its resolved Host Adapter.
  @override
  Future<Object?> navigate(CCNavigationRequest request) {
    final adapter = _adapterForRequest(request);
    _hostByNavigationId[request.navigationId] = request.hostId;
    return adapter.navigate(request);
  }

  /// Asks the active Host to coordinate a conditional Pop.
  @override
  Future<bool> maybePop({Object? result}) async =>
      (await maybePopOutcome(result: result)).handled;

  /// Returns an ownership-aware Pop result from the active Host.
  @override
  Future<CCPopOutcome> maybePopOutcome({Object? result}) {
    final adapter = _activeAdapter;
    return adapter is CCNavigationPopCoordinator
        ? (adapter as CCNavigationPopCoordinator)
              .maybePopOutcome(result: result)
              .then((outcome) => outcome.copyWith(hostId: _activeHostId))
        : adapter
              .maybePop(result: result)
              .then(
                (handled) =>
                    CCPopOutcome(handled: handled, hostId: _activeHostId),
              );
  }

  /// Pops the current entry from the active Host.
  @override
  void pop({Object? result}) => _activeAdapter.pop(result: result);

  /// Pops the active Host and preserves backend ownership information.
  @override
  CCPopOutcome popOutcome({Object? result}) {
    final adapter = _activeAdapter;
    if (adapter is CCNavigationPopCoordinator) {
      return (adapter as CCNavigationPopCoordinator)
          .popOutcome(result: result)
          .copyWith(hostId: _activeHostId);
    }
    adapter.pop(result: result);
    return CCPopOutcome(handled: true, hostId: _activeHostId);
  }

  /// Whether the active Host backend can currently pop.
  @override
  bool canPop() => _activeAdapter.canPop();

  /// Reads initial stacks from every snapshot-capable Host.
  @override
  List<CCNavigationBackendEntrySnapshot> readInitialBackendSnapshot() {
    _ensureAvailable();
    final result = <CCNavigationBackendEntrySnapshot>[];
    for (final entry in _hosts.entries) {
      final adapter = entry.value.adapter;
      if (adapter is! CCNavigationBackendSnapshotSource) continue;
      final snapshots = (adapter as CCNavigationBackendSnapshotSource)
          .readInitialBackendSnapshot();
      result.addAll(
        snapshots.map((snapshot) => _snapshotForHost(entry.key, snapshot)),
      );
    }
    return List.unmodifiable(result);
  }

  /// Subscribes to backend events from every current and future Host.
  @override
  void Function() addBackendEventListener(
    CCNavigationBackendEventListener listener,
  ) {
    _backendListeners.add(listener);
    return () => _backendListeners.remove(listener);
  }

  /// Releases the Host routing index for a removed managed navigation.
  ///
  /// Runtime calls this after the corresponding RouteEntry leaves its live
  /// ledger. Backend-event-driven cleanup may have already removed the same
  /// identity, so this operation is intentionally idempotent.
  @override
  void releaseManagedNavigation(String navigationId) {
    _hostByNavigationId.remove(navigationId);
  }

  /// Subscribes to predictive-back phases from every integrated Host.
  @override
  void Function() addPredictiveBackListener(
    CCPredictiveBackEventListener listener,
  ) {
    _predictiveBackListeners.add(listener);
    return () => _predictiveBackListeners.remove(listener);
  }

  /// Installs Runtime Pop policy into every compatible Host Adapter.
  @override
  void bindPopGuardEvaluator(CCPopGuardEvaluator? evaluator) {
    _popGuardEvaluator = evaluator;
    for (final record in _hosts.values) {
      final adapter = record.adapter;
      if (adapter is CCNavigationPopGuardBinding) {
        (adapter as CCNavigationPopGuardBinding).bindPopGuardEvaluator(
          evaluator,
        );
      }
    }
  }

  /// Disposes every child Adapter and releases all listener bridges.
  @override
  void dispose() {
    if (_disposed) return;
    _dispose();
  }

  /// Performs final teardown of every synchronously owned child Adapter.
  void _dispose() {
    _disposed = true;
    _initialized = false;
    for (final record in _hosts.values) {
      _unbindRecord(record);
      final adapter = record.adapter;
      if (adapter is CCNavigationPopGuardBinding) {
        (adapter as CCNavigationPopGuardBinding).bindPopGuardEvaluator(null);
      }
    }
    final records = _hosts.values.toList();
    _hosts.clear();
    _hostByNavigationId.clear();
    _adaptiveLayouts.clear();
    _adaptiveLayoutListeners.clear();
    _sequencesByHost.clear();
    _backendListeners.clear();
    _predictiveBackListeners.clear();
    _popGuardEvaluator = null;
    _routes = const [];
    _shells = const [];
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final record in records) {
      try {
        record.dispose();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  /// Registered child Adapters indexed by concrete Host identity.
  final Map<String, _CCNavigationHostAdapterRecord> _hosts = {};

  /// Owning Host indexed by Runtime navigation identity.
  final Map<String, String> _hostByNavigationId = {};

  /// Runtime listeners receiving merged backend events.
  final Set<CCNavigationBackendEventListener> _backendListeners = {};

  /// Runtime listeners receiving merged predictive-back phases.
  final Set<CCPredictiveBackEventListener> _predictiveBackListeners = {};

  /// Latest adaptive layout state retained for each Host.
  final Map<String, CCAdaptiveHostLayout> _adaptiveLayouts = {};

  /// Observers receiving adaptive Host layout snapshots.
  final Set<CCAdaptiveHostLayoutListener> _adaptiveLayoutListeners = {};

  /// Monotonic merged event sequence assigned independently per Host.
  final Map<String, int> _sequencesByHost = {};

  /// Process-local identity prefix for registry-authored backend events.
  final String _registryId =
      '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(Object())}';

  /// Route table cached for dynamically registered Hosts.
  List<CCNavigationRoute> _routes = const [];

  /// Shell table cached for dynamically registered Hosts.
  List<CCNavigationShell> _shells = const [];

  /// Pop policy propagated to compatible child Adapters.
  CCPopGuardEvaluator? _popGuardEvaluator;

  /// Host selected for placement-default requests and active Pop commands.
  String _activeHostId;

  /// Whether all initial child Adapters accepted their route tables.
  bool _initialized = false;

  /// Whether registry ownership has permanently ended.
  bool _disposed = false;

  /// Active child Adapter used for non-targeted Pop operations.
  CCNavigationAdapter get _activeAdapter {
    _ensureAvailable();
    final adapter = _hosts[_activeHostId]?.adapter;
    if (adapter == null) {
      throw CCNavigationAdapterError(
        'Active navigation Host "$_activeHostId" is unavailable.',
      );
    }
    return adapter;
  }

  /// Resolves and validates the concrete child Adapter for [request].
  CCNavigationAdapter _adapterForRequest(CCNavigationRequest request) {
    _ensureAvailable();
    final adapter = _hosts[request.hostId]?.adapter;
    if (adapter == null) {
      throw CCNavigationAdapterError(
        'Navigation Host "${request.hostId}" is unavailable.',
      );
    }
    return adapter;
  }

  /// Initializes one child with its Host-specific route and Shell tables.
  void _initializeRecord(String hostId, _CCNavigationHostAdapterRecord record) {
    final routes = _routes
        .where(
          (route) =>
              route.placement.hostId == 'default' ||
              route.placement.hostId == hostId,
        )
        .toList(growable: false);
    final shellIds = routes
        .map((route) => route.placement.shellId)
        .whereType<String>()
        .toSet();
    final shells = _shells
        .where((shell) => shellIds.contains(shell.shellId))
        .toList(growable: false);
    record.adapter.initialize(routes, shells: shells);
  }

  /// Connects child backend and predictive sources to merged listeners.
  void _bindRecord(String hostId, _CCNavigationHostAdapterRecord record) {
    final adapter = record.adapter;
    if (adapter is CCNavigationBackendEventSource) {
      record.backendRemover = (adapter as CCNavigationBackendEventSource)
          .addBackendEventListener((event) {
            final normalized = _eventForHost(hostId, event);
            if ((normalized.kind == CCNavigationBackendEventKind.pop ||
                    normalized.kind == CCNavigationBackendEventKind.remove) &&
                normalized.navigationId != null) {
              _hostByNavigationId.remove(normalized.navigationId);
            }
            _publishBackendEvent(normalized);
          });
    }
    final predictiveSource = adapter is CCNavigationPredictiveBackSourceProvider
        ? (adapter as CCNavigationPredictiveBackSourceProvider)
              .predictiveBackSource
        : adapter is CCNavigationPredictiveBackSource
        ? adapter as CCNavigationPredictiveBackSource
        : null;
    if (predictiveSource != null) {
      record.predictiveRemover = predictiveSource.addPredictiveBackListener((
        event,
      ) {
        for (final listener in _predictiveBackListeners.toList()) {
          listener(event);
        }
      });
    }
    if (adapter is CCNavigationPopGuardBinding) {
      (adapter as CCNavigationPopGuardBinding).bindPopGuardEvaluator(
        _popGuardEvaluator,
      );
    }
  }

  /// Disconnects listener bridges without disposing the child Adapter.
  void _unbindRecord(_CCNavigationHostAdapterRecord record) {
    record.backendRemover?.call();
    record.backendRemover = null;
    record.predictiveRemover?.call();
    record.predictiveRemover = null;
  }

  /// Supplies a missing Host identity on one child backend event.
  CCNavigationBackendEvent _eventForHost(
    String hostId,
    CCNavigationBackendEvent event,
  ) => CCNavigationBackendEvent(
    kind: event.kind,
    timestamp: event.timestamp,
    backendEntryId: event.backendEntryId,
    backendOperationId: event.backendOperationId,
    previousBackendEntryId: event.previousBackendEntryId,
    hostId: event.hostId ?? hostId,
    navigatorOutlet: event.navigatorOutlet,
    sequence: _nextHostSequence(hostId),
    owner: event.owner,
    navigationId: event.navigationId,
    routeId: event.routeId,
    uri: event.uri,
    placement: event.placement.hostId == 'default'
        ? CCRoutePlacement(
            hostId: hostId,
            parentRouteId: event.placement.parentRouteId,
            shellId: event.placement.shellId,
            navigatorOutlet: event.placement.navigatorOutlet,
          )
        : event.placement,
    location: event.location,
    origin: event.origin,
    source: event.source,
    activeNavigatorOutlets: event.activeNavigatorOutlets,
  );

  /// Publishes a merged backend event while isolating Host observers.
  void _publishBackendEvent(CCNavigationBackendEvent event) {
    for (final listener in _backendListeners.toList()) {
      try {
        listener(event);
      } catch (_) {
        // Host diagnostics must never change navigation execution.
      }
    }
  }

  /// Allocates the next merged backend sequence for one Host.
  int _nextHostSequence(String hostId) =>
      _sequencesByHost.update(hostId, (value) => value + 1, ifAbsent: () => 1);

  /// Supplies a missing Host identity on one initial child snapshot.
  CCNavigationBackendEntrySnapshot _snapshotForHost(
    String hostId,
    CCNavigationBackendEntrySnapshot snapshot,
  ) => CCNavigationBackendEntrySnapshot(
    backendEntryId: snapshot.backendEntryId,
    owner: snapshot.owner,
    navigatorOutlet: snapshot.navigatorOutlet,
    visibilityState: snapshot.visibilityState,
    routeEntryId: snapshot.routeEntryId,
    routeId: snapshot.routeId,
    hostId: snapshot.hostId ?? hostId,
    location: snapshot.location,
    sequence: snapshot.sequence,
  );

  /// Returns whether any child declares one aggregate capability.
  bool _anyCapability(
    bool Function(CCNavigationAdapterCapabilities value) select,
  ) => _hosts.values.any((record) {
    final adapter = record.adapter;
    return adapter is CCNavigationAdapterCapabilitySource &&
        select((adapter as CCNavigationAdapterCapabilitySource).capabilities);
  });

  /// Validates one Host identity and its Adapter Host binding.
  void _validateHost(String hostId, CCNavigationAdapter adapter) {
    if (hostId.isEmpty) {
      throw ArgumentError.value(hostId, 'hostId', 'Host ID cannot be empty.');
    }
    if (adapter is CCNavigationAdapterHostBinding &&
        (adapter as CCNavigationAdapterHostBinding).hostId != hostId) {
      throw ArgumentError.value(
        adapter,
        'adapter',
        'Adapter Host binding does not match "$hostId".',
      );
    }
  }

  /// Rejects calls before initialization or after final disposal.
  void _ensureAvailable() {
    _ensureNotDisposed();
    if (!_initialized) {
      throw const CCNavigationAdapterError(
        'The navigation Host registry is not initialized.',
      );
    }
  }

  /// Rejects operations after final ownership teardown.
  void _ensureNotDisposed() {
    if (_disposed) {
      throw const CCNavigationAdapterError(
        'The navigation Host registry has been disposed.',
      );
    }
  }
}

/// Internal ownership record for one child Host Adapter.
final class _CCNavigationHostAdapterRecord {
  /// Creates a record before listener bridges are attached.
  _CCNavigationHostAdapterRecord(this.adapter);

  /// Adapter exclusively owned by the registry.
  final CCNavigationAdapter adapter;

  /// Removes the child backend-event subscription.
  void Function()? backendRemover;

  /// Removes the child predictive-back subscription.
  void Function()? predictiveRemover;

  /// Whether this record has already released its exclusively owned Adapter.
  bool _disposed = false;

  /// Disposes the exclusively owned Adapter exactly once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    adapter.dispose();
  }
}
