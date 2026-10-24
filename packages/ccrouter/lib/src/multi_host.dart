import 'dart:collection';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';

import 'app.dart';

part 'multi_host_identity.dart';

/// Host-only Adapter multiplexer for independent navigation backends.
///
/// Register one independently owned Adapter per navigation Host, then
/// expose this adapter through a `CCRouterAppBackend` initialized by
/// `CCRouterApp.managed`.
/// Requests with an explicit route Host remain pinned to that Host; routes
/// using the `default` placement resolve through [activeHostId]. Business code
/// should not retain this object or select a Host for ordinary navigation.
/// Child backend Entry identities are local to their registration. This
/// aggregate exposes opaque, registration-qualified identities consistently
/// across snapshots, events, Pop targets, Guard callbacks and Pop outcomes.
final class CCMultiHostNavigationAdapter
    implements
        CCNavigationAdapter,
        CCNavigationDispatchAdapter,
        CCNavigationParentStackAdapter,
        CCNavigationTargetedCloseAdapter,
        CCNavigationAdapterHostBinding,
        CCNavigationAdapterCapabilitySource,
        CCNavigationHostCapabilitySource,
        CCNavigationBackendEventSource,
        CCNavigationManagedEntryReleaseSink,
        CCNavigationRouteExitBinding,
        CCNavigationBackendSnapshotSource,
        CCNavigationPopCoordinator,
        CCNavigationScopedPopCoordinator,
        CCNavigationPopTargetSource,
        CCNavigationScopedPopTargetSource,
        CCNavigationPopGuardBinding,
        CCNavigationScopedPopGuardBinding,
        CCNavigationPredictiveBackSourceProvider,
        CCNavigationPredictiveBackSource {
  /// Creates a multi-Host adapter with an initial Host-to-Adapter mapping.
  ///
  /// [defaultHostId] must identify one supplied Adapter. This object assumes
  /// ownership of every supplied Adapter and disposes each exactly once only
  /// after all input is valid. Every Host must have a distinct Adapter instance;
  /// invalid input is rejected without initializing or disposing any child.
  CCMultiHostNavigationAdapter({
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
    final identities = HashSet<CCNavigationAdapter>.identity();
    for (final entry in adapters.entries) {
      _validateHost(entry.key, entry.value);
      if (!identities.add(entry.value)) {
        throw CCNavigationAdapterError(
          'Each navigation Host must own a distinct Adapter instance.',
        );
      }
    }
    for (final entry in adapters.entries) {
      _hosts[entry.key] = _createRecord(entry.value);
    }
  }

  /// Host currently used to resolve routes with the `default` placement.
  String get activeHostId => _activeHostId;

  /// Immutable Host identities currently available for navigation.
  Set<String> get registeredHostIds => Set.unmodifiable(_hosts.keys);

  /// Default Host identity consumed by Runtime request construction.
  @override
  String get hostId => _activeHostId;

  /// Active child Adapter partition used for Pop Guard selection.
  @override
  CCNavigationPopTarget get activePopTarget {
    final adapter = _activeAdapter;
    final hostId = _activeHostId;
    final record = _hosts[hostId]!;
    final target = adapter is CCNavigationPopTargetSource
        ? (adapter as CCNavigationPopTargetSource).activePopTarget
        : null;
    return _targetForHost(
      hostId,
      record,
      CCNavigationPopTarget(
        hostId: hostId,
        navigatorOutlet: target?.navigatorOutlet ?? 'root',
        backendEntryId: target?.backendEntryId,
        owner: target?.owner,
        handlesPopInternally: target?.handlesPopInternally ?? false,
      ),
    );
  }

  @override
  /// Queries the exact child without consulting or changing the active Host.
  CCNavigationPopTarget? popTargetAt({
    required String hostId,
    required String navigatorOutlet,
  }) {
    _ensureAvailable();
    final record = _hosts[hostId];
    final adapter = record?.adapter;
    if (adapter is CCNavigationScopedPopTargetSource) {
      final target = (adapter as CCNavigationScopedPopTargetSource).popTargetAt(
        hostId: hostId,
        navigatorOutlet: navigatorOutlet,
      );
      return target == null ? null : _targetForHost(hostId, record!, target);
    }
    return null;
  }

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
  /// Composition-root infrastructure calls this when the default navigation
  /// surface changes. Existing RouteEntries keep their original Host.
  void activateHost(String hostId) {
    _ensureAvailable();
    if (!_hosts.containsKey(hostId) || _pendingHosts.containsKey(hostId)) {
      throw CCNavigationAdapterError('Navigation Host "$hostId" is not ready.');
    }
    _activeHostId = hostId;
  }

  /// Applies the Host application's resolved visible Outlet set.
  ///
  /// Layout, width breakpoints and fold policy belong to the application.
  /// This Host-only operation updates visibility without pushing, removing,
  /// migrating or disposing retained entries. The non-empty Outlet set must
  /// contain unique non-blank identities; validation precedes any mutation.
  /// Unknown Hosts throw [CCNavigationAdapterError]. The copied set is used by
  /// both page lifecycle and the backend event, independently of later changes
  /// to the caller's collection. Routes in other Hosts remain unchanged.
  /// Children implementing [CCNavigationOutletVisibilityBinding] own validation,
  /// Store synchronization and effective-visibility publication, including
  /// temporary overlay masking. Other children use lifecycle/event forwarding.
  void setActiveOutlets({
    required String hostId,
    required Iterable<String> outlets,
    String? shellId,
  }) {
    _ensureAvailable();
    if (!_hosts.containsKey(hostId)) {
      throw CCNavigationAdapterError(
        'Navigation Host "$hostId" is not registered.',
      );
    }
    final activeOutlets = List<String>.unmodifiable(outlets);
    if (activeOutlets.isEmpty ||
        activeOutlets.any((outlet) => outlet.trim().isEmpty) ||
        activeOutlets.toSet().length != activeOutlets.length) {
      throw ArgumentError.value(
        outlets,
        'outlets',
        'Active Outlets must be non-empty, unique identities.',
      );
    }
    final record = _hosts[hostId]!;
    final adapter = record.adapter;
    if (adapter is CCNavigationOutletVisibilityBinding) {
      (adapter as CCNavigationOutletVisibilityBinding).updateVisibleOutlets(
        activeOutlets,
      );
      return;
    }
    CCPageLifecycleHostBridge.setActiveOutlets(
      hostId: hostId,
      outlets: activeOutlets,
    );
    final sequence = ++record.eventSequence;
    _publishBackendEvent(
      CCNavigationBackendEvent(
        kind: CCNavigationBackendEventKind.outletsChanged,
        timestamp: DateTime.now(),
        backendOperationId: '${record.eventNamespace}-outlets-$sequence',
        hostId: hostId,
        navigatorOutlet: activeOutlets.first,
        sequence: sequence,
        placement: CCRoutePlacement(
          hostId: hostId,
          shellId: shellId,
          navigatorOutlet: activeOutlets.first,
        ),
        activeNavigatorOutlets: activeOutlets,
      ),
    );
  }

  /// Adds one Host Adapter, including after multi-Host initialization.
  ///
  /// A dynamically added Adapter receives the cached route table before it is
  /// exposed to navigation. After argument/lifetime validation, ownership of an
  /// unowned Adapter transfers to this call, including duplicate-ID rejection.
  /// Failure disposes only that Adapter and never removes a replacement Host.
  /// Reusing an already owned Adapter is rejected without disposing its owner.
  /// Same-ID initialization reentry is rejected; a binding callback may remove
  /// and replace its registration, but the retired registration cannot succeed.
  /// Registration during aggregate initialization is rejected. Before aggregate
  /// initialization, registration only adopts the Adapter; binding happens once
  /// when the complete aggregate is initialized.
  void registerHost(String hostId, CCNavigationAdapter adapter) =>
      _registerHost(hostId, adapter);

  @override
  /// Resolves the exiting surface by its original Host, independently of focus.
  void Function()? addRouteExitListener({
    required String navigationId,
    required String hostId,
    required void Function() onExited,
  }) {
    final adapter = _hosts[hostId]?.adapter;
    return adapter is CCNavigationRouteExitBinding
        ? (adapter as CCNavigationRouteExitBinding).addRouteExitListener(
            navigationId: navigationId,
            hostId: hostId,
            onExited: onExited,
          )
        : null;
  }

  /// Performs one atomic Host registration.
  void _registerHost(String hostId, CCNavigationAdapter adapter) {
    _ensureNotDisposed();
    _validateHost(hostId, adapter);
    if ([
      ..._hosts.values,
      ..._pendingHosts.values,
      ..._retiringHosts.values,
    ].any((record) => identical(record.adapter, adapter))) {
      throw CCNavigationAdapterError(
        'The Adapter is already owned by a navigation Host.',
      );
    }
    final record = _createRecord(adapter);
    try {
      if (_initializing ||
          _hosts.containsKey(hostId) ||
          _pendingHosts.containsKey(hostId) ||
          _retiringHosts.containsKey(hostId)) {
        throw CCNavigationAdapterError(
          'Navigation Host "$hostId" conflicts with an existing registration '
          'or initialization transaction.',
        );
      }
      _pendingHosts[hostId] = record;
      if (_initialized) _initializeRecord(hostId, record);
      _ensureNotDisposed();
      _hosts[hostId] = record;
      if (_initialized) _bindRecord(hostId, record);
      _ensureRegisteredRecord(hostId, record);
      _pendingHosts.remove(hostId);
    } catch (error, stackTrace) {
      if (identical(_pendingHosts[hostId], record))
        _pendingHosts.remove(hostId);
      if (identical(_hosts[hostId], record)) _hosts.remove(hostId);
      try {
        _unbindRecord(record);
      } catch (_) {
        // Preserve the registration failure after best-effort listener cleanup.
      }
      try {
        record.dispose();
      } catch (_) {
        // Preserve the registration failure after best-effort Adapter cleanup.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Removes and disposes one Host Adapter without affecting other Hosts.
  ///
  /// The last Host cannot be removed from an initialized multi-Host adapter.
  /// Runtime is notified before disposal so entries owned by the removed Host
  /// close their Route Scopes. Live backend pages are never migrated implicitly.
  /// Removing the active Host requires [replacementActiveHostId], which must
  /// identify a different registered Host; no replacement is selected by
  /// insertion order.
  /// Uncommitted Runtime work is cancelled with `host_detached`; registering
  /// the same logical ID never resumes those operations or their gates. Unmount
  /// the old CCRouterApp before mounting its replacement.
  /// Detach is delivered before listener-removal/disposal callbacks can create
  /// a replacement. Same-ID registration during detach delivery is rejected.
  void unregisterHost(String hostId, {String? replacementActiveHostId}) =>
      _unregisterHost(hostId, replacementActiveHostId: replacementActiveHostId);

  /// Performs one atomic Host removal.
  void _unregisterHost(
    String hostId, {
    required String? replacementActiveHostId,
  }) {
    _ensureAvailable();
    if (_hosts.length == 1) {
      throw const CCNavigationAdapterError(
        'An initialized multi-Host navigation adapter must retain at least '
        'one Host.',
      );
    }
    final record = _hosts[hostId];
    if (record == null) {
      throw CCNavigationAdapterError(
        'Navigation Host "$hostId" is not registered.',
      );
    }
    if (_activeHostId == hostId) {
      if (replacementActiveHostId == null ||
          replacementActiveHostId == hostId ||
          !_hosts.containsKey(replacementActiveHostId) ||
          _pendingHosts.containsKey(replacementActiveHostId)) {
        throw CCNavigationAdapterError(
          'Removing active navigation Host "$hostId" requires a different '
          'registered replacementActiveHostId.',
        );
      }
    } else if (replacementActiveHostId != null) {
      throw const CCNavigationAdapterError(
        'replacementActiveHostId is accepted only when removing the active '
        'navigation Host.',
      );
    }
    _hosts.remove(hostId);
    if (identical(_pendingHosts[hostId], record)) _pendingHosts.remove(hostId);
    if (_activeHostId == hostId) {
      _activeHostId = replacementActiveHostId!;
    }
    Object? cleanupError;
    StackTrace? cleanupStackTrace;
    _hostByNavigationId.removeWhere((_, value) => value == hostId);
    final sequence = ++record.eventSequence;
    _retiringHosts[hostId] = record;
    try {
      _publishBackendEvent(
        CCNavigationBackendEvent(
          kind: CCNavigationBackendEventKind.hostDetached,
          timestamp: DateTime.now(),
          backendOperationId: '${record.eventNamespace}-detached-$sequence',
          hostId: hostId,
          sequence: sequence,
          placement: CCRoutePlacement(hostId: hostId),
        ),
      );
    } finally {
      _retiringHosts.remove(hostId);
    }
    try {
      _unbindRecord(record);
    } catch (error, stackTrace) {
      cleanupError = error;
      cleanupStackTrace = stackTrace;
    }
    try {
      record.dispose();
    } catch (error, stackTrace) {
      cleanupError ??= error;
      cleanupStackTrace ??= stackTrace;
    }
    if (cleanupError != null) {
      Error.throwWithStackTrace(cleanupError, cleanupStackTrace!);
    }
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
    if (_initialized || _initializing) {
      throw const CCNavigationAdapterError(
        'The multi-Host navigation adapter is already initialized.',
      );
    }
    _initializing = true;
    try {
      _routes = List.unmodifiable(routes);
      _shells = List.unmodifiable(shells);
      for (final entry in _hosts.entries) {
        _initializeRecord(entry.key, entry.value);
        _ensureNotDisposed();
        _bindRecord(entry.key, entry.value);
      }
      _ensureNotDisposed();
      _initialized = true;
    } catch (error, stackTrace) {
      try {
        _dispose();
      } catch (_) {
        // Preserve the initialization failure after best-effort ownership cleanup.
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _initializing = false;
    }
  }

  /// Executes one request on its resolved Host Adapter.
  @override
  Future<Object?> navigate(CCNavigationRequest request) {
    final adapter = _adapterForRequest(request);
    _hostByNavigationId[request.navigationId] = request.hostId;
    return adapter.navigate(request);
  }

  @override
  /// Queries only the selected child's declarative reconstruction capability.
  bool supportsParentStack(CCNavigationRequest request) {
    final adapter = _adapterForRequest(request);
    return adapter is CCNavigationParentStackAdapter &&
        (adapter as CCNavigationParentStackAdapter).supportsParentStack(
          request,
        );
  }

  /// Forwards explicit acceptance only when the resolved child can prove it.
  ///
  /// Returning null preserves every Host and leaves legacy navigation intact.
  @override
  CCNavigationDispatch? dispatchNavigation(CCNavigationRequest request) {
    final adapter = _adapterForRequest(request);
    if (adapter is! CCNavigationDispatchAdapter) return null;
    _hostByNavigationId[request.navigationId] = request.hostId;
    try {
      final receipt = (adapter as CCNavigationDispatchAdapter)
          .dispatchNavigation(request);
      if (receipt == null) _hostByNavigationId.remove(request.navigationId);
      return receipt;
    } catch (_) {
      _hostByNavigationId.remove(request.navigationId);
      rethrow;
    }
  }

  /// Asks the active Host to coordinate a conditional Pop.
  @override
  Future<bool> maybePop({Object? result}) async =>
      (await maybePopOutcome(result: result)).handled;

  /// Returns a Pop result belonging to the Host selected before waiting.
  ///
  /// Focus changes and Host removal cannot relabel a completed child outcome.
  /// The child's actual Outlet wins over the pre-dispatch fallback target.
  @override
  Future<CCPopOutcome> maybePopOutcome({Object? result}) {
    final adapter = _activeAdapter;
    final hostId = _activeHostId;
    final namespace = _hosts[hostId]!.eventNamespace;
    final outlet = activePopTarget.navigatorOutlet;
    return adapter is CCNavigationPopCoordinator
        ? (adapter as CCNavigationPopCoordinator)
              .maybePopOutcome(result: result)
              .then(
                (outcome) =>
                    _outcomeForHost(hostId, namespace, outcome, outlet),
              )
        : adapter
              .maybePop(result: result)
              .then(
                (handled) => CCPopOutcome(
                  handled: handled,
                  hostId: hostId,
                  navigatorOutlet: outlet,
                ),
              );
  }

  @override
  /// Coordinates a Pop in the explicitly selected Host and Outlet.
  Future<CCPopOutcome> maybePopOutcomeAt({
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) {
    _ensureAvailable();
    final record = _hosts[hostId];
    final adapter = record?.adapter;
    final namespace = record?.eventNamespace;
    if (adapter is CCNavigationScopedPopCoordinator) {
      return (adapter as CCNavigationScopedPopCoordinator)
          .maybePopOutcomeAt(
            hostId: hostId,
            navigatorOutlet: navigatorOutlet,
            result: result,
          )
          .then(
            (outcome) =>
                _outcomeForHost(hostId, namespace!, outcome, navigatorOutlet),
          );
    }
    return Future<CCPopOutcome>.value(
      CCPopOutcome(
        handled: false,
        hostId: hostId,
        navigatorOutlet: navigatorOutlet,
      ),
    );
  }

  /// Pops the current entry from the active Host.
  @override
  void pop({Object? result}) => _activeAdapter.pop(result: result);

  /// Pops the active Host and preserves backend ownership information.
  @override
  CCPopOutcome popOutcome({Object? result}) {
    final adapter = _activeAdapter;
    final hostId = _activeHostId;
    final record = _hosts[hostId]!;
    final outlet = activePopTarget.navigatorOutlet;
    if (adapter is CCNavigationPopCoordinator) {
      final outcome = (adapter as CCNavigationPopCoordinator).popOutcome(
        result: result,
      );
      return _outcomeForHost(hostId, record.eventNamespace, outcome, outlet);
    }
    adapter.pop(result: result);
    return CCPopOutcome(handled: true, hostId: hostId, navigatorOutlet: outlet);
  }

  @override
  /// Executes a business Pop in the explicitly selected Host and Outlet.
  CCPopOutcome popOutcomeAt({
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) {
    _ensureAvailable();
    final record = _hosts[hostId];
    final adapter = record?.adapter;
    if (adapter is CCNavigationScopedPopCoordinator) {
      final outcome = (adapter as CCNavigationScopedPopCoordinator)
          .popOutcomeAt(
            hostId: hostId,
            navigatorOutlet: navigatorOutlet,
            result: result,
          );
      return _outcomeForHost(
        hostId,
        record!.eventNamespace,
        outcome,
        navigatorOutlet,
      );
    }
    return CCPopOutcome(
      handled: false,
      hostId: hostId,
      navigatorOutlet: navigatorOutlet,
    );
  }

  /// Routes an exact close to its owning Host without changing active Host.
  @override
  Future<CCRouteCloseOutcome> closeNavigation({
    required String navigationId,
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) async {
    _ensureAvailable();
    final adapter = _hosts[hostId]?.adapter;
    if (adapter == null)
      return const CCRouteCloseOutcome(CCRouteCloseStatus.notFound);
    if (adapter is! CCNavigationTargetedCloseAdapter) {
      return const CCRouteCloseOutcome(CCRouteCloseStatus.unsupported);
    }
    return (adapter as CCNavigationTargetedCloseAdapter).closeNavigation(
      navigationId: navigationId,
      hostId: hostId,
      navigatorOutlet: navigatorOutlet,
      result: result,
    );
  }

  /// Whether the active Host backend can currently pop.
  @override
  bool canPop() => _activeAdapter.canPop();

  @override
  /// Reports Pop capability for the explicitly selected Host and Outlet.
  bool canPopAt({required String hostId, required String navigatorOutlet}) {
    _ensureAvailable();
    final adapter = _hosts[hostId]?.adapter;
    return adapter is CCNavigationScopedPopCoordinator &&
        (adapter as CCNavigationScopedPopCoordinator).canPopAt(
          hostId: hostId,
          navigatorOutlet: navigatorOutlet,
        );
  }

  /// Reads initial stacks from every snapshot-capable Host.
  @override
  List<CCInitialBackendEntrySnapshot> readInitialBackendEntries() {
    _ensureAvailable();
    final result = <CCInitialBackendEntrySnapshot>[];
    for (final entry in _hosts.entries) {
      final adapter = entry.value.adapter;
      if (adapter is! CCNavigationBackendSnapshotSource) continue;
      final snapshots = (adapter as CCNavigationBackendSnapshotSource)
          .readInitialBackendEntries();
      result.addAll(
        snapshots.map(
          (snapshot) => _snapshotForHost(entry.key, entry.value, snapshot),
        ),
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
    for (final entry in _hosts.entries) {
      _bindChildPopGuards(entry.value, hostId: entry.key);
    }
  }

  /// Propagates exact-target Runtime policy to current and future children.
  @override
  void bindScopedPopGuardEvaluator(CCScopedPopGuardEvaluator? evaluator) {
    _scopedPopGuardEvaluator = evaluator;
    for (final entry in _hosts.entries) {
      _bindChildPopGuards(entry.value, hostId: entry.key);
    }
  }

  /// Preserves precise targets; legacy single-Navigator children use their Host.
  void _bindChildPopGuards(
    _CCNavigationHostAdapterRecord record, {
    String? hostId,
    bool clear = false,
  }) {
    final adapter = record.adapter;
    final scoped = clear ? null : _scopedPopGuardEvaluator;
    final legacy = clear ? null : _popGuardEvaluator;
    if (adapter is CCNavigationScopedPopGuardBinding) {
      (adapter as CCNavigationScopedPopGuardBinding)
          .bindScopedPopGuardEvaluator(
            scoped != null
                ? (trigger, {required target}) => scoped(
                    trigger,
                    target: _targetForHost(hostId!, record, target),
                  )
                : (legacy == null
                      ? null
                      : (trigger, {required target}) => legacy(trigger)),
          );
    } else if (adapter is CCNavigationPopGuardBinding) {
      (adapter as CCNavigationPopGuardBinding).bindPopGuardEvaluator(
        scoped == null
            ? legacy
            : (trigger) {
                final target = adapter is CCNavigationPopTargetSource
                    ? (adapter as CCNavigationPopTargetSource).activePopTarget
                    : null;
                return scoped(
                  trigger,
                  target: _targetForHost(
                    hostId!,
                    record,
                    target ??
                        CCNavigationPopTarget(
                          hostId: hostId,
                          navigatorOutlet: 'root',
                        ),
                  ),
                );
              },
      );
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
    final records = {
      ..._hosts.values,
      ..._pendingHosts.values,
      ..._retiringHosts.values,
    }.toList();
    _hosts.clear();
    _pendingHosts.clear();
    _retiringHosts.clear();
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final record in records) {
      try {
        _unbindRecord(record);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    _hostByNavigationId.clear();
    _backendListeners.clear();
    _predictiveBackListeners.clear();
    _popGuardEvaluator = null;
    _scopedPopGuardEvaluator = null;
    _routes = const [];
    _shells = const [];
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

  /// Ownership reserved until initialization and every binding has completed.
  ///
  /// Removed before unregister callbacks so a replacement can use the same
  /// address without the old transaction's rollback erasing it.
  final Map<String, _CCNavigationHostAdapterRecord> _pendingHosts = {};

  /// Prevents a new lifetime from receiving the old Host's in-progress detach.
  ///
  /// Released before unsubscription/disposal hooks, which may then install a
  /// replacement without any later Host-wide mutation from the retired record.
  final Map<String, _CCNavigationHostAdapterRecord> _retiringHosts = {};

  /// Prevents recursive initialization from configuring or rebinding children.
  bool _initializing = false;

  /// Owning Host indexed by Runtime navigation identity.
  final Map<String, String> _hostByNavigationId = {};

  /// Runtime listeners receiving merged backend events.
  final Set<CCNavigationBackendEventListener> _backendListeners = {};

  /// Runtime listeners receiving merged predictive-back phases.
  final Set<CCPredictiveBackEventListener> _predictiveBackListeners = {};

  /// Allocates aggregate identities without retaining retired Adapter objects.
  static int _nextAdapterId = 0;

  /// Process-local namespace shared by this aggregate's registration identities.
  final String _adapterId = 'multi-${++_nextAdapterId}';

  /// Monotonic registration ordinal, independent of logical Host reuse.
  int _nextRegistrationId = 0;

  /// Route table cached for dynamically registered Hosts.
  List<CCNavigationRoute> _routes = const [];

  /// Shell table cached for dynamically registered Hosts.
  List<CCNavigationShell> _shells = const [];

  /// Pop policy propagated to compatible child Adapters.
  CCPopGuardEvaluator? _popGuardEvaluator;

  /// Exact-target policy retained only while the Runtime is bound.
  CCScopedPopGuardEvaluator? _scopedPopGuardEvaluator;

  /// Host selected for placement-default requests and active Pop commands.
  String _activeHostId;

  /// Whether all initial child Adapters accepted their route tables.
  bool _initialized = false;

  /// Whether adapter ownership has permanently ended.
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
    if (adapter == null || _pendingHosts.containsKey(request.hostId)) {
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

  /// Creates an isolated event lifetime without retaining historical Host IDs.
  _CCNavigationHostAdapterRecord _createRecord(CCNavigationAdapter adapter) =>
      _CCNavigationHostAdapterRecord(
        adapter,
        '$_adapterId-${++_nextRegistrationId}',
      );

  /// Connects child backend and predictive sources to merged listeners.
  void _bindRecord(String hostId, _CCNavigationHostAdapterRecord record) {
    final adapter = record.adapter;
    if (adapter is CCNavigationBackendEventSource) {
      record.backendRemover = (adapter as CCNavigationBackendEventSource)
          .addBackendEventListener((event) {
            if (_disposed || !identical(_hosts[hostId], record)) return;
            final normalized = _eventForHost(hostId, record, event);
            if ((normalized.kind == CCNavigationBackendEventKind.pop ||
                    normalized.kind == CCNavigationBackendEventKind.remove) &&
                normalized.navigationId != null) {
              _hostByNavigationId.remove(normalized.navigationId);
            }
            _publishBackendEvent(normalized);
          });
      _ensureRegisteredRecord(hostId, record);
    }
    final predictiveSource = adapter is CCNavigationPredictiveBackSourceProvider
        ? (adapter as CCNavigationPredictiveBackSourceProvider)
              .predictiveBackSource
        : adapter is CCNavigationPredictiveBackSource
        ? adapter as CCNavigationPredictiveBackSource
        : null;
    _ensureRegisteredRecord(hostId, record);
    if (predictiveSource != null) {
      record.predictiveRemover = predictiveSource.addPredictiveBackListener((
        event,
      ) {
        if (_disposed || !identical(_hosts[hostId], record)) return;
        final normalized = _predictiveEventForHost(hostId, record, event);
        for (final listener in _predictiveBackListeners.toList()) {
          try {
            listener(normalized);
          } catch (_) {
            // One Host observer must not hide a phase from other observers.
          }
        }
      });
      _ensureRegisteredRecord(hostId, record);
    }
    _bindChildPopGuards(record, hostId: hostId);
    _ensureRegisteredRecord(hostId, record);
  }

  /// Rejects continuation after an external binding callback retires its owner.
  void _ensureRegisteredRecord(
    String hostId,
    _CCNavigationHostAdapterRecord record,
  ) {
    _ensureNotDisposed();
    if (!identical(_hosts[hostId], record)) {
      throw CCNavigationAdapterError(
        'Navigation Host "$hostId" was removed during registration.',
      );
    }
  }

  /// Disconnects listener bridges without disposing the child Adapter.
  void _unbindRecord(_CCNavigationHostAdapterRecord record) {
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      _bindChildPopGuards(record, clear: true);
    } catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }
    final backendRemover = record.backendRemover;
    record.backendRemover = null;
    try {
      backendRemover?.call();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
    final predictiveRemover = record.predictiveRemover;
    record.predictiveRemover = null;
    try {
      predictiveRemover?.call();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

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
        'The multi-Host navigation adapter is not initialized.',
      );
    }
  }

  /// Rejects operations after final ownership teardown.
  void _ensureNotDisposed() {
    if (_disposed) {
      throw const CCNavigationAdapterError(
        'The multi-Host navigation adapter has been disposed.',
      );
    }
  }
}

/// Internal ownership record for one child Host Adapter.
final class _CCNavigationHostAdapterRecord {
  /// Creates a record before listener bridges are attached.
  _CCNavigationHostAdapterRecord(this.adapter, this.eventNamespace);

  /// Adapter exclusively owned by the multi-Host parent adapter.
  final CCNavigationAdapter adapter;

  /// Unique registration prefix for child Entry and operation identities.
  final String eventNamespace;

  /// Merged sequence owned only by this registration, including its final detach.
  int eventSequence = 0;

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
