part of 'runtime.dart';

/// Navigation entry retained by [CCMemoryNavigationAdapter].
final class _CCMemoryNavigationEntry {
  /// Creates an entry with an optional result completion channel.
  _CCMemoryNavigationEntry(this.request, {this.result});

  /// Validated request represented by this stack entry.
  final CCNavigationRequest request;

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
        CCNavigationAdapterCapabilitySource {
  /// Creates an uninitialized empty navigation stack.
  CCMemoryNavigationAdapter();

  /// Pure-Dart backend capabilities exposed for test-host diagnostics.
  @override
  CCNavigationAdapterCapabilities get capabilities =>
      const CCNavigationAdapterCapabilities(
        supportsInitialStackSnapshot: true,
        supportsAtomicPopAndPush: true,
        supportsPushAndRemoveUntil: true,
      );

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
  Future<void> initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) async {
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
      resultAvailable: true,
    );
  }

  /// Pops the current entry and pushes [request] as one operation.
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

  /// Pops a removable entry and completes its pending result.
  @override
  void pop({Object? result}) {
    _ensureAvailable();
    if (!canPop()) {
      throw const CCNavigationAdapterError(
        'The memory navigation stack cannot pop its current root.',
      );
    }
    final entry = _entries.removeLast();
    entry.result?.complete(result);
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
  Future<void> dispose() async {
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
