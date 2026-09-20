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
        CCNavigationAdapterCapabilitySource,
        CCNavigationBackendSnapshotSource {
  /// Creates an uninitialized empty navigation stack.
  CCMemoryNavigationAdapter();

  /// Pure-Dart backend capabilities exposed for test-host diagnostics.
  @override
  CCNavigationAdapterCapabilities get capabilities =>
      const CCNavigationAdapterCapabilities(
        supportsNestedNavigators: true,
        supportsStatefulShell: true,
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
        if (request.openMode == CCDeepLinkOpenMode.go) _clearEntries();
        _entries.add(_CCMemoryNavigationEntry(request));
        return Future<Object?>.value();
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
