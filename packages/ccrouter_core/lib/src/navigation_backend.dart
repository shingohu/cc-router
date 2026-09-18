part of 'runtime.dart';

/// Exposes backend Navigator observations collected by Runtime.
extension CCRouterRuntimeNavigationBackend on CCRouterRuntime {
  /// Returns the backend Entry ledger, including removed entries retained for
  /// bounded diagnostics until Runtime disposal.
  List<CCBackendEntry> get backendEntries =>
      List.unmodifiable(_backendEntries.values);

  /// Returns backend Entries that are currently active in an observed stack.
  ///
  /// This snapshot is diagnostic only. It never grants callers permission to
  /// pop or mutate a backend route.
  List<CCBackendEntry> get activeBackendEntries => List.unmodifiable(
    _backendEntries.values.where(
      (entry) => entry.lifecycleState == CCBackendEntryLifecycleState.active,
    ),
  );

  /// Returns backend entries filtered by optional Host and Navigator Outlet.
  ///
  /// Use this for multi-window, foldable-pane, Shell-branch, or embedded
  /// Navigator diagnostics. A null filter is a wildcard; filtering never
  /// changes ownership or grants permission to mutate an entry.
  List<CCBackendEntry> backendEntriesFor({
    String? hostId,
    String? navigatorOutlet,
    bool activeOnly = false,
  }) => List.unmodifiable(
    _backendEntries.values.where(
      (entry) =>
          (!activeOnly ||
              entry.lifecycleState == CCBackendEntryLifecycleState.active) &&
          (hostId == null || entry.hostId == hostId) &&
          (navigatorOutlet == null || entry.navigatorOutlet == navigatorOutlet),
    ),
  );

  /// Returns a bounded immutable snapshot of backend stack events.
  ///
  /// Use this to correlate system back, gestures, or backend-owned stack
  /// changes with Runtime request telemetry. Events may omit route metadata
  /// when the application changed its backend stack independently.
  List<CCNavigationBackendEvent> get recentBackendNavigationEvents =>
      List.unmodifiable(_backendNavigationEvents);

  /// Subscribes to backend Navigator observations from the configured adapter.
  ///
  /// The returned callback removes the listener. This capability is optional;
  /// adapters without backend observation support simply produce no events.
  void Function() addBackendNavigationListener(
    CCNavigationBackendEventListener listener,
  ) {
    _ensureInitialized();
    _backendNavigationListeners.add(listener);
    return () => _backendNavigationListeners.remove(listener);
  }

  /// Connects an optional adapter backend event source during initialization.
  void _attachBackendNavigationSource() {
    final adapter = _navigationAdapter;
    if (adapter is CCNavigationBackendEventSource) {
      _backendNavigationRemover = (adapter as CCNavigationBackendEventSource)
          .addBackendEventListener(_recordBackendNavigationEvent);
    }
  }

  /// Imports an optional initial backend stack into the diagnostic ledger.
  ///
  /// Snapshot entries are deliberately not emitted as transition events: they
  /// predate Runtime observation and therefore cannot represent a new Push.
  /// Invalid identities fail initialization rather than entering a ledger
  /// that could later be mistaken for a correlated managed transition.
  Future<void> _readInitialBackendSnapshot() async {
    final adapter = _navigationAdapter;
    final source = adapter is CCNavigationBackendSnapshotSource
        ? adapter as CCNavigationBackendSnapshotSource
        : null;
    if (source == null) return;
    final snapshots = await source.readInitialBackendSnapshot();
    for (final snapshot in snapshots) {
      if (snapshot.backendEntryId.isEmpty || snapshot.navigatorOutlet.isEmpty) {
        throw const CCNavigationAdapterError(
          'Initial backend snapshot contains an invalid entry identity.',
        );
      }
      if (_backendEntries.length >= navigationEventCapacity &&
          navigationEventCapacity > 0 &&
          !_backendEntries.containsKey(snapshot.backendEntryId)) {
        _backendEntries.remove(_backendEntries.keys.first);
      }
      _backendEntries[snapshot.backendEntryId] = CCBackendEntry(
        backendEntryId: snapshot.backendEntryId,
        owner: snapshot.owner,
        routeEntryId: snapshot.routeEntryId,
        routeId: snapshot.routeId,
        hostId: snapshot.hostId,
        navigatorOutlet: snapshot.navigatorOutlet,
        location: snapshot.location,
        lifecycleState: CCBackendEntryLifecycleState.active,
        lastSequence: snapshot.sequence,
      );
    }
  }

  /// Stores and publishes one adapter-observed backend event.
  ///
  /// Backend observations are diagnostic until an adapter can correlate them
  /// with a concrete Runtime Route Entry. In particular, an event without
  /// managed identity may represent a Dialog, PopupRoute, LocalHistoryEntry,
  /// or application-owned Navigator route and must never remove a managed
  /// Route Entry by position.
  void _recordBackendNavigationEvent(CCNavigationBackendEvent event) {
    _reconcileBackendEntry(event);
    if (navigationEventCapacity > 0) {
      if (_backendNavigationEvents.length == navigationEventCapacity) {
        _backendNavigationEvents.removeFirst();
      }
      _backendNavigationEvents.add(event);
    }
    for (final listener in _backendNavigationListeners.toList()) {
      try {
        listener(event);
      } catch (error) {
        if (traceCapacity > 0) {
          if (_subscriberErrors.length == traceCapacity) {
            _subscriberErrors.removeAt(0);
          }
          _subscriberErrors.add(
            CCInvocationError(
              'Backend navigation listener failed: ${error.runtimeType}',
            ),
          );
        }
      }
    }
  }

  /// Reconciles one identity-bearing event without changing Route Entries.
  void _reconcileBackendEntry(CCNavigationBackendEvent event) {
    final operationId = event.backendOperationId;
    if (operationId != null) {
      if (_processedBackendOperations.contains(operationId)) return;
      if (navigationEventCapacity > 0) {
        while (_processedBackendOperations.length >= navigationEventCapacity) {
          _processedBackendOperations.remove(_processedBackendOperations.first);
        }
        _processedBackendOperations.add(operationId);
      }
    }
    final backendEntryId = event.backendEntryId;
    if (backendEntryId == null || backendEntryId.isEmpty) return;

    _RouteEntryRecord? routeEntry;
    final navigationId = event.navigationId;
    if (navigationId != null) {
      for (final entry in _routeEntries) {
        if (entry.request.navigationId == navigationId) {
          routeEntry = entry;
          break;
        }
      }
    }
    final existing = _backendEntries[backendEntryId];
    final owner = routeEntry != null
        ? CCBackendEntryOwner.managed
        : existing?.owner == CCBackendEntryOwner.managed
        ? CCBackendEntryOwner.managed
        : event.owner ?? CCBackendEntryOwner.foreign;
    final previous = event.previousBackendEntryId;
    if (previous != null && previous != backendEntryId) {
      final previousEntry = _backendEntries[previous];
      if (previousEntry != null) {
        _backendEntries[previous] = CCBackendEntry(
          backendEntryId: previousEntry.backendEntryId,
          owner: previousEntry.owner,
          routeEntryId: previousEntry.routeEntryId,
          routeId: previousEntry.routeId,
          hostId: previousEntry.hostId,
          navigatorOutlet: previousEntry.navigatorOutlet,
          location: previousEntry.location,
          lifecycleState: CCBackendEntryLifecycleState.removed,
          lastSequence: event.sequence ?? previousEntry.lastSequence,
        );
      }
    }

    final isRemoved =
        event.kind == CCNavigationBackendEventKind.pop ||
        event.kind == CCNavigationBackendEventKind.remove;
    if (existing == null && navigationEventCapacity > 0) {
      while (_backendEntries.length >= navigationEventCapacity) {
        _backendEntries.remove(_backendEntries.keys.first);
      }
    }
    _backendEntries[backendEntryId] = CCBackendEntry(
      backendEntryId: backendEntryId,
      owner: owner,
      routeEntryId: routeEntry?.id ?? existing?.routeEntryId,
      routeId: event.routeId ?? existing?.routeId,
      hostId: event.hostId ?? existing?.hostId,
      navigatorOutlet: event.navigatorOutlet ?? event.placement.navigatorOutlet,
      location: event.location ?? existing?.location,
      lifecycleState: isRemoved
          ? CCBackendEntryLifecycleState.removed
          : CCBackendEntryLifecycleState.active,
      lastSequence: event.sequence ?? existing?.lastSequence,
    );
  }
}
