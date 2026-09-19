part of 'runtime.dart';

/// Navigation entry retained by [CCMemoryNavigationAdapter].
final class _CCMemoryNavigationEntry {
  /// Creates an entry with an optional result completion channel.
  _CCMemoryNavigationEntry(this.request, {this.result});

  /// Validated request represented by this stack entry.
  final CCNavigationRequest request;

  /// Stable backend identity derived from the Runtime navigation identity.
  String get backendEntryId => 'memory-${request.navigationId}';

  /// Result completed when a Push or Replace entry is popped or discarded.
  final Completer<Object?>? result;

  /// Exposes only stable identity to stack predicates.
  CCNavigationEntry get snapshot => CCNavigationEntry(
    navigationId: request.navigationId,
    routeId: request.routeId,
    uri: request.uri,
  );
}

/// Deterministic in-memory adapter for Core and facade navigation tests.
///
/// This adapter models stack operations and typed Pop results without Flutter.
/// Use it for framework or component-contract tests; production applications
/// should provide a platform navigation adapter such as the future GoRouter
/// integration.
@visibleForTesting
final class CCMemoryNavigationAdapter
    implements
        CCNavigationAdapter,
        CCNavigationPopCoordinator,
        CCNavigationExactEntryRemoval,
        CCNavigationExactEntryReplacement,
        CCNavigationAdapterCapabilitySource,
        CCNavigationBackendSnapshotSource {
  /// Creates an uninitialized empty navigation stack.
  CCMemoryNavigationAdapter();

  /// Pure-Dart backend capabilities exposed for test-host diagnostics.
  @override
  CCNavigationAdapterCapabilities get capabilities =>
      const CCNavigationAdapterCapabilities(
        supportsAtomicPopAndPush: true,
        supportsPushAndRemoveUntil: true,
        supportsNestedNavigators: true,
        supportsStatefulShell: true,
        supportsExactEntryRemoval: true,
        supportsExactEntryReplacement: true,
      );

  /// Returns the current in-memory entries as an initialization snapshot.
  @override
  List<CCNavigationBackendEntrySnapshot> readInitialBackendSnapshot() {
    _ensureAvailable();
    return List.unmodifiable(
      _entries.map(
        (entry) => CCNavigationBackendEntrySnapshot(
          backendEntryId: entry.backendEntryId,
          owner: CCBackendEntryOwner.managed,
          hostId: entry.request.hostId,
          routeId: entry.request.routeId,
          navigatorOutlet: entry.request.placement.navigatorOutlet,
          location: entry.request.uri.toString(),
        ),
      ),
    );
  }

  /// Route descriptions supplied during initialization.
  List<CCNavigationRoute> _routes = const [];

  /// Shell descriptions supplied during initialization.
  List<CCNavigationShell> _shells = const [];

  /// Mutable stack entries retained by this test adapter.
  final List<_CCMemoryNavigationEntry> _entries = [];

  /// Whether initialization completed and navigation is accepted.
  bool _initialized = false;

  /// Whether disposal permanently closed this adapter.
  bool _disposed = false;

  /// Whether this adapter currently accepts navigation requests.
  bool get isInitialized => _initialized && !_disposed;

  /// Immutable route descriptions received from the Runtime.
  List<CCNavigationRoute> get routes => _routes;

  /// Immutable Shell descriptions received from the Runtime.
  List<CCNavigationShell> get shells => _shells;

  /// Immutable request snapshot in current stack order.
  List<CCNavigationRequest> get stack =>
      List.unmodifiable(_entries.map((entry) => entry.request));

  /// Immutable route-entry snapshots used to inspect the current stack.
  List<CCNavigationEntry> get entries =>
      List.unmodifiable(_entries.map((entry) => entry.snapshot));

  /// Most recently retained request, or null when the stack is empty.
  CCNavigationRequest? get currentRequest =>
      _entries.isEmpty ? null : _entries.last.request;

  /// Initializes this adapter once with installed route metadata.
  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) {
    if (_disposed) {
      throw const CCNavigationAdapterError(
        'The memory navigation adapter has been disposed.',
      );
    }
    if (_initialized) {
      throw const CCNavigationAdapterError(
        'The memory navigation adapter is already initialized.',
      );
    }
    _routes = List.unmodifiable(routes);
    _shells = List.unmodifiable(shells);
    _initialized = true;
  }

  /// Applies [request] to the in-memory stack.
  @override
  Future<Object?> navigate(CCNavigationRequest request) {
    _ensureAvailable();
    _ensureRoute(request);
    switch (request.operation) {
      case CCNavigationOperation.push:
        return _addResultEntry(request);
      case CCNavigationOperation.replace:
        _removeCurrent();
        return _addResultEntry(request);
      case CCNavigationOperation.go:
      case CCNavigationOperation.reset:
        _clearEntries();
        _entries.add(_CCMemoryNavigationEntry(request));
        return Future<Object?>.value();
      case CCNavigationOperation.open:
        _entries.add(_CCMemoryNavigationEntry(request));
        return Future<Object?>.value();
      case CCNavigationOperation.popAndPush:
      case CCNavigationOperation.pushAndRemoveUntil:
      case CCNavigationOperation.replaceBelow:
        throw const CCNavigationAdapterError(
          'Composite navigation must use its dedicated Adapter operation.',
        );
    }
  }

  /// Pops the current entry when the in-memory stack permits it.
  @override
  Future<bool> maybePop({Object? result}) async {
    final outcome = await maybePopOutcome(result: result);
    return outcome.handled;
  }

  /// Pops the current entry and reports its managed ownership.
  @override
  Future<CCPopOutcome> maybePopOutcome({Object? result}) async {
    _ensureAvailable();
    if (!canPop()) return const CCPopOutcome(handled: false);
    _removeCurrent(result: result);
    return const CCPopOutcome(
      handled: true,
      removedOwner: CCPopRemovedOwner.managed,
    );
  }

  /// Pops the current entry and pushes [request] as one operation.
  ///
  /// The removed entry completes with [popResult], while the returned Future
  /// belongs exclusively to the newly pushed entry.
  @override
  Future<Object?> popAndPush(CCNavigationRequest request, {Object? popResult}) {
    _ensureAvailable();
    _ensureRoute(request);
    _removeCurrent(result: popResult);
    return _addResultEntry(request);
  }

  /// Pops entries until [predicate] matches the current entry.
  @override
  Future<void> popUntil(CCNavigationStackPredicate predicate) async {
    _ensureAvailable();
    while (_entries.length > 1 && !predicate(_entries.last.snapshot)) {
      _removeCurrent();
    }
  }

  /// Pushes [request] and removes previous entries until [predicate] matches.
  ///
  /// Removed entries complete with `null`; only the newly pushed entry owns
  /// the returned result Future.
  @override
  Future<Object?> pushAndRemoveUntil(
    CCNavigationRequest request,
    CCNavigationStackPredicate predicate,
  ) {
    _ensureAvailable();
    _ensureRoute(request);
    final future = _addResultEntry(request);
    while (_entries.length > 1 &&
        !predicate(_entries[_entries.length - 2].snapshot)) {
      _removeAt(_entries.length - 2);
    }
    return future;
  }

  /// Removes exactly one managed entry by its Runtime navigation identity.
  @override
  Future<void> removeManagedEntry({
    required String navigationId,
    String? backendEntryId,
  }) async {
    _ensureAvailable();
    final index = _indexForIdentity(navigationId, backendEntryId);
    _removeAt(index);
  }

  /// Removes all managed entries below the exact target entry.
  @override
  Future<void> removeManagedEntriesBelow({
    required String navigationId,
    String? backendEntryId,
  }) async {
    _ensureAvailable();
    final targetIndex = _indexForIdentity(navigationId, backendEntryId);
    for (var index = targetIndex - 1; index >= 0; index--) {
      _removeAt(index);
    }
  }

  /// Replaces the managed entry directly below an exact anchor identity.
  @override
  Future<void> replaceManagedEntryBelow({
    required String anchorNavigationId,
    String? anchorBackendEntryId,
    required CCNavigationRequest request,
  }) async {
    _ensureAvailable();
    _ensureRoute(request);
    final anchorIndex = _indexForIdentity(
      anchorNavigationId,
      anchorBackendEntryId,
    );
    if (anchorIndex < 1) {
      throw const CCNavigationAdapterError(
        'The exact backend Entry has no entry below it to replace.',
      );
    }
    _removeAt(anchorIndex - 1);
    _entries.insert(anchorIndex - 1, _CCMemoryNavigationEntry(request));
  }

  /// Pops a removable entry and completes its pending result.
  @override
  void pop({Object? result}) {
    final outcome = popOutcome(result: result);
    if (!outcome.handled) {
      throw const CCNavigationAdapterError(
        'The memory navigation stack cannot pop its current root.',
      );
    }
  }

  /// Pops the current managed entry and reports its ownership synchronously.
  @override
  CCPopOutcome popOutcome({Object? result}) {
    _ensureAvailable();
    if (!canPop()) {
      return const CCPopOutcome(handled: false);
    }
    _removeCurrent(result: result);
    return const CCPopOutcome(
      handled: true,
      removedOwner: CCPopRemovedOwner.managed,
    );
  }

  /// Whether a non-root or result-bearing entry can be removed.
  @override
  bool canPop() {
    _ensureAvailable();
    return _entries.length > 1 ||
        _entries.isNotEmpty && _entries.last.result != null;
  }

  /// Completes outstanding results with null and clears all retained state.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _initialized = false;
    _clearEntries();
    _routes = const [];
    _shells = const [];
  }

  /// Adds a result-bearing entry and returns its completion Future.
  Future<Object?> _addResultEntry(CCNavigationRequest request) {
    final result = Completer<Object?>();
    _entries.add(_CCMemoryNavigationEntry(request, result: result));
    return result.future;
  }

  /// Removes the current entry and cancels its pending result with null.
  void _removeCurrent({Object? result}) {
    if (_entries.isEmpty) return;
    final removed = _entries.removeLast();
    removed.result?.complete(result);
  }

  /// Removes one entry at [index] and completes its pending result.
  void _removeAt(int index) {
    final removed = _entries.removeAt(index);
    removed.result?.complete();
  }

  /// Resolves one exact backend identity or reports that it is unavailable.
  int _indexForIdentity(String navigationId, String? backendEntryId) {
    final index = _entries.indexWhere(
      (entry) =>
          entry.request.navigationId == navigationId &&
          (backendEntryId == null || entry.backendEntryId == backendEntryId),
    );
    if (index == -1) {
      throw const CCNavigationAdapterError(
        'The requested managed backend Entry is no longer active.',
      );
    }
    return index;
  }

  /// Clears all entries while safely completing pending result Futures.
  void _clearEntries() {
    for (final entry in _entries.reversed) {
      entry.result?.complete();
    }
    _entries.clear();
  }

  /// Rejects operations before initialization or after disposal.
  void _ensureAvailable() {
    if (!isInitialized) {
      throw const CCNavigationAdapterError(
        'The memory navigation adapter is not active.',
      );
    }
  }

  /// Verifies that [request] targets a route supplied during initialization.
  void _ensureRoute(CCNavigationRequest request) {
    if (!_routes.any((route) => route.routeId == request.routeId)) {
      throw CCNavigationAdapterError(
        'Route "${request.routeId}" was not supplied to the adapter.',
      );
    }
  }
}
