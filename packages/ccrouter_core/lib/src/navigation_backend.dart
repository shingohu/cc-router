part of 'runtime.dart';

/// Runtime-owned structural record for one observed backend Entry.
///
/// This record is library-private because only Runtime may reconcile ownership,
/// lifecycle, and identity. It stores a sanitized address summary rather than
/// the concrete Adapter location; business diagnostics receive a separate
/// immutable [CCBackendEntrySnapshot].
final class _BackendEntryRecord {
  /// Creates one retained backend Entry record.
  const _BackendEntryRecord({
    required this.backendEntryId,
    required this.owner,
    required this.lifecycleState,
    required this.navigatorOutlet,
    required this.address,
    this.visibilityState = CCBackendEntryVisibilityState.unknown,
    this.routeEntryId,
    this.navigationId,
    this.routeId,
    this.hostId,
    this.lastSequence,
  });

  /// Stable identity assigned by the navigation adapter.
  final String backendEntryId;

  /// Ownership classification protecting managed Route Entries.
  final CCBackendEntryOwner owner;

  /// CCRouter RouteEntry identity when [owner] is managed.
  final String? routeEntryId;

  /// Runtime navigation identity correlated with this backend Entry.
  final String? navigationId;

  /// Stable route contract ID supplied by the backend, when known.
  final String? routeId;

  /// Navigation Host containing this entry, when known.
  final String? hostId;

  /// Navigator Outlet containing this backend entry.
  final String navigatorOutlet;

  /// Confirmed current or hidden state within [navigatorOutlet].
  final CCBackendEntryVisibilityState visibilityState;

  /// Sanitized declaration and parameter-presence metadata.
  final CCRouteAddressSummary address;

  /// Current state in Runtime's backend ledger.
  final CCBackendEntryLifecycleState lifecycleState;

  /// Last adapter sequence observed for this entry.
  final int? lastSequence;
}

/// Exposes backend Navigator observations collected by Runtime.
extension CCRouterRuntimeNavigationBackend on CCRouterRuntime {
  /// Whether one Host reports exact managed removals after backend mutations.
  ///
  /// Runtime uses this to preserve Route Scopes during declarative `go`
  /// transitions until the backend identifies the entries that truly left its
  /// page tree. A false result selects the documented partition-local fallback.
  bool _usesManagedRemovalConfirmationFor(String hostId) {
    final adapter = _navigationAdapter;
    if (adapter is CCNavigationHostCapabilitySource) {
      return (adapter as CCNavigationHostCapabilitySource)
              .capabilitiesForHost(hostId)
              ?.supportsManagedPopObservation ==
          true;
    }
    return adapter is CCNavigationAdapterCapabilitySource &&
        (adapter as CCNavigationAdapterCapabilitySource)
            .capabilities
            .supportsManagedPopObservation;
  }

  /// Whether the active Adapter confirms managed visibility from backend tops.
  bool _usesBackendVisibilityConfirmationFor(String hostId) {
    final adapter = _navigationAdapter;
    if (adapter is CCNavigationHostCapabilitySource) {
      return (adapter as CCNavigationHostCapabilitySource)
              .capabilitiesForHost(hostId)
              ?.supportsBackendVisibilityObservation ==
          true;
    }
    return adapter is CCNavigationAdapterCapabilitySource &&
        (adapter as CCNavigationAdapterCapabilitySource)
            .capabilities
            .supportsBackendVisibilityObservation;
  }

  /// Returns the backend Entry ledger, including removed entries retained for
  /// bounded diagnostics until Runtime disposal.
  List<CCBackendEntrySnapshot> get backendEntries =>
      List.unmodifiable(_backendEntries.values.map(_backendEntrySnapshot));

  /// Returns backend Entries that are currently active in an observed stack.
  ///
  /// This snapshot is diagnostic only. It never grants callers permission to
  /// pop or mutate a backend route.
  List<CCBackendEntrySnapshot> get activeBackendEntries => List.unmodifiable(
    _backendEntries.values
        .where(
          (entry) =>
              entry.lifecycleState == CCBackendEntryLifecycleState.active,
        )
        .map(_backendEntrySnapshot),
  );

  /// Returns active backend Entries confirmed as current in their Outlets.
  ///
  /// Use this for diagnostics across root, Shell, and nested Navigators. An
  /// empty result can mean that the Adapter does not support visibility
  /// confirmation; it must not be interpreted as an empty navigation stack.
  List<CCBackendEntrySnapshot> get visibleBackendEntries => List.unmodifiable(
    _backendEntries.values
        .where(
          (entry) =>
              entry.lifecycleState == CCBackendEntryLifecycleState.active &&
              entry.visibilityState == CCBackendEntryVisibilityState.visible,
        )
        .map(_backendEntrySnapshot),
  );

  /// Returns Host IDs whose backend event sequence contains a detected gap.
  ///
  /// A desynchronized Host continues to accept exact identity events, but
  /// Runtime never reconstructs missing foreign or managed transitions by
  /// position. A fresh Runtime/backend snapshot is required to clear this
  /// diagnostic state.
  Set<String> get desynchronizedBackendHosts =>
      Set.unmodifiable(_desynchronizedBackendHosts);

  /// Returns backend entries filtered by optional Host and Navigator Outlet.
  ///
  /// Use this for multi-Host, foldable-pane, Shell-branch, or embedded
  /// Navigator diagnostics. A null filter is a wildcard; filtering never
  /// changes ownership or grants permission to mutate an entry.
  List<CCBackendEntrySnapshot> backendEntriesFor({
    String? hostId,
    String? navigatorOutlet,
    bool activeOnly = false,
  }) => List.unmodifiable(
    _backendEntries.values
        .where(
          (entry) =>
              (!activeOnly ||
                  entry.lifecycleState ==
                      CCBackendEntryLifecycleState.active) &&
              (hostId == null || entry.hostId == hostId) &&
              (navigatorOutlet == null ||
                  entry.navigatorOutlet == navigatorOutlet),
        )
        .map(_backendEntrySnapshot),
  );

  /// Returns a bounded immutable snapshot of backend stack events.
  ///
  /// Use this to correlate system back, gestures, or backend-owned stack
  /// changes with Runtime request telemetry. Events may omit route metadata
  /// when the application changed its backend stack independently.
  List<CCNavigationBackendDiagnosticEvent> get recentBackendNavigationEvents =>
      List.unmodifiable(_backendNavigationEvents);

  /// Subscribes to backend Navigator observations from the configured adapter.
  ///
  /// Events are delivered by the bounded FIFO observer queue. The returned
  /// callback removes the listener and cancels its queued deliveries. This
  /// capability is optional; adapters without backend observation support
  /// simply produce no events.
  void Function() addBackendNavigationListener(
    CCNavigationBackendDiagnosticListener listener,
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
    final predictiveSource = adapter is CCNavigationPredictiveBackSourceProvider
        ? (adapter as CCNavigationPredictiveBackSourceProvider)
              .predictiveBackSource
        : adapter is CCNavigationPredictiveBackSource
        ? adapter as CCNavigationPredictiveBackSource
        : null;
    if (predictiveSource != null) {
      _predictiveBackRemover = predictiveSource.addPredictiveBackListener(
        _recordPredictiveBackEvent,
      );
    }
  }

  /// Applies only a committed ownership-aware predictive Pop.
  void _recordPredictiveBackEvent(CCPredictiveBackEvent event) {
    if (event.phase != CCPredictiveBackPhase.committed) return;
    final outcome = event.outcome?.copyWith(
      trigger: CCPopTrigger.predictiveBack,
    );
    if (outcome == null ||
        outcome.removedOwner != CCPopRemovedOwner.managed ||
        outcome.removedBackendEntryId == null) {
      return;
    }
    final backendEntry = _backendEntries[outcome.removedBackendEntryId];
    final routeEntryId = backendEntry?.routeEntryId;
    if (backendEntry?.owner != CCBackendEntryOwner.managed ||
        routeEntryId == null) {
      return;
    }
    _applyManagedPopOutcome(outcome);
  }

  /// Imports an optional initial backend stack into the diagnostic ledger.
  ///
  /// Snapshot entries are deliberately not emitted as transition events: they
  /// predate Runtime observation and therefore cannot represent a new Push.
  /// Invalid identities fail initialization rather than entering a ledger
  /// that could later be mistaken for a correlated managed transition.
  void _readInitialBackendSnapshot() {
    final adapter = _navigationAdapter;
    final source = adapter is CCNavigationBackendSnapshotSource
        ? adapter as CCNavigationBackendSnapshotSource
        : null;
    if (source == null) return;
    final snapshots = source.readInitialBackendSnapshot();
    for (final snapshot in snapshots) {
      if (snapshot.backendEntryId.isEmpty || snapshot.navigatorOutlet.isEmpty) {
        throw const CCNavigationAdapterError(
          'Initial backend snapshot contains an invalid entry identity.',
        );
      }
      _backendEntries[snapshot.backendEntryId] = _BackendEntryRecord(
        backendEntryId: snapshot.backendEntryId,
        owner: snapshot.owner,
        routeEntryId: snapshot.routeEntryId,
        routeId: snapshot.routeId,
        hostId: snapshot.hostId,
        navigatorOutlet: snapshot.navigatorOutlet,
        address: _addressSummaryFor(
          routeId: snapshot.routeId,
          location: snapshot.location,
        ),
        lifecycleState: CCBackendEntryLifecycleState.active,
        visibilityState: snapshot.visibilityState,
        lastSequence: snapshot.sequence,
      );
    }
  }

  /// Stores and publishes one adapter-observed backend event.
  ///
  /// Backend observations are diagnostic until an adapter can correlate them
  /// with a concrete Runtime Route Entry. Identity-capable adapters may mark
  /// an externally popped Managed entry; only those events can close the exact
  /// RouteEntry. An event without managed identity may represent a Dialog,
  /// PopupRoute, LocalHistoryEntry, or application-owned Navigator route and
  /// must never remove a managed Route Entry by position.
  void _recordBackendNavigationEvent(CCNavigationBackendEvent event) {
    if (!_reconcileBackendEntry(event)) return;
    _applyObservedHostLifecycle(event);
    _applyObservedManagedPop(event);
    _applyObservedBackendTop(event);
    final diagnosticEvent = _backendDiagnosticEvent(event);
    if (navigationDiagnosticCapacity > 0) {
      if (_backendNavigationEvents.length == navigationDiagnosticCapacity) {
        _backendNavigationEvents.removeFirst();
      }
      _backendNavigationEvents.add(diagnosticEvent);
    }
    _enqueueNavigationObserverBatch(
      _backendNavigationListeners,
      (listener) => listener(diagnosticEvent),
      isActive: _backendNavigationListeners.contains,
      failureLabel: 'Backend navigation listener',
      critical: switch (event.kind) {
        CCNavigationBackendEventKind.pop ||
        CCNavigationBackendEventKind.remove ||
        CCNavigationBackendEventKind.hostDetached => true,
        _ => false,
      },
    );
    _emitDiagnostic(
      category: CCDiagnosticCategory.backend,
      level: CCDiagnosticLevel.debug,
      occurredAt: diagnosticEvent.timestamp,
      operation: diagnosticEvent.kind.name,
      status: 'observed',
      duration: Duration.zero,
      navigationId: diagnosticEvent.navigationId,
      routeId: diagnosticEvent.routeId,
      hostId: diagnosticEvent.hostId,
      outlet: diagnosticEvent.navigatorOutlet,
    );
  }

  /// Tears down one detached Host without guessing cross-window migration.
  void _applyObservedHostLifecycle(CCNavigationBackendEvent event) {
    if (event.kind != CCNavigationBackendEventKind.hostDetached) return;
    final hostId = event.hostId ?? event.placement.hostId;
    _removeAllRouteEntries(reason: 'hostDetached', hostId: hostId);
    for (final ledgerEntry in _backendEntries.entries.toList()) {
      final entry = ledgerEntry.value;
      if (entry.hostId == hostId &&
          entry.lifecycleState == CCBackendEntryLifecycleState.active) {
        _backendEntries[ledgerEntry.key] = _copyBackendEntry(
          entry,
          lifecycleState: CCBackendEntryLifecycleState.removed,
          visibilityState: CCBackendEntryVisibilityState.hidden,
          lastSequence: event.sequence ?? entry.lastSequence,
        );
      }
    }
    _trimRemovedBackendEntries();
    _backendSequencesByHost.remove(hostId);
    _desynchronizedBackendHosts.remove(hostId);
  }

  /// Closes a Managed RouteEntry only for an identity-capable adapter event.
  void _applyObservedManagedPop(CCNavigationBackendEvent event) {
    if (event.kind != CCNavigationBackendEventKind.pop &&
        event.kind != CCNavigationBackendEventKind.remove) {
      return;
    }
    final adapter = _navigationAdapter;
    final capabilities = adapter is CCNavigationAdapterCapabilitySource
        ? (adapter as CCNavigationAdapterCapabilitySource).capabilities
        : null;
    if (capabilities?.supportsManagedPopObservation != true ||
        event.owner != CCBackendEntryOwner.managed ||
        event.backendEntryId == null) {
      return;
    }
    final backendEntry = _backendEntries[event.backendEntryId];
    final routeEntryId = backendEntry?.routeEntryId;
    if (backendEntry?.owner != CCBackendEntryOwner.managed ||
        routeEntryId == null) {
      return;
    }
    for (final entry in _routeEntries.toList()) {
      if (entry.id == routeEntryId) {
        _removeRouteEntry(entry, reason: 'backendPop');
        return;
      }
    }
  }

  /// Reconciles one identity-bearing event and rejects duplicates or stale data.
  bool _reconcileBackendEntry(CCNavigationBackendEvent event) {
    final operationId = event.backendOperationId;
    if (operationId != null) {
      if (_processedBackendOperations.contains(operationId)) return false;
      final capacity = max(navigationDiagnosticCapacity, 64);
      while (_processedBackendOperations.length >= capacity) {
        _processedBackendOperations.remove(_processedBackendOperations.first);
      }
      _processedBackendOperations.add(operationId);
    }
    if (!_acceptBackendSequence(event)) return false;
    final backendEntryId = event.backendEntryId;
    if (backendEntryId == null || backendEntryId.isEmpty) return true;

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
    if (event.kind == CCNavigationBackendEventKind.replace &&
        previous != null &&
        previous != backendEntryId) {
      final previousEntry = _backendEntries[previous];
      if (previousEntry != null) {
        _backendEntries[previous] = _copyBackendEntry(
          previousEntry,
          lifecycleState: CCBackendEntryLifecycleState.removed,
          lastSequence: event.sequence ?? previousEntry.lastSequence,
        );
      }
    }

    final isRemoved =
        event.kind == CCNavigationBackendEventKind.pop ||
        event.kind == CCNavigationBackendEventKind.remove;
    _backendEntries[backendEntryId] = _BackendEntryRecord(
      backendEntryId: backendEntryId,
      owner: owner,
      routeEntryId: routeEntry?.id ?? existing?.routeEntryId,
      navigationId: navigationId ?? existing?.navigationId,
      routeId: event.routeId ?? existing?.routeId,
      hostId: event.hostId ?? existing?.hostId,
      navigatorOutlet: event.navigatorOutlet ?? event.placement.navigatorOutlet,
      address: event.uri != null || event.location != null
          ? _addressSummaryFor(
              routeId: event.routeId ?? existing?.routeId,
              uri: event.uri,
              location: event.location,
            )
          : existing?.address ?? _addressSummaryFor(routeId: event.routeId),
      lifecycleState: isRemoved
          ? CCBackendEntryLifecycleState.removed
          : CCBackendEntryLifecycleState.active,
      visibilityState: isRemoved
          ? CCBackendEntryVisibilityState.hidden
          : existing?.visibilityState ?? CCBackendEntryVisibilityState.unknown,
      lastSequence: event.sequence ?? existing?.lastSequence,
    );
    _trimRemovedBackendEntries();
    return true;
  }

  /// Bounds removed diagnostic history without evicting live backend Entries.
  ///
  /// Active entries are structural state required for ownership and exact
  /// visibility correlation, so they may exceed [navigationDiagnosticCapacity].
  /// A zero capacity keeps active state while retaining no removed history.
  void _trimRemovedBackendEntries() {
    var removedCount = _backendEntries.values
        .where(
          (entry) =>
              entry.lifecycleState == CCBackendEntryLifecycleState.removed,
        )
        .length;
    if (removedCount <= navigationDiagnosticCapacity) return;
    for (final entry in _backendEntries.entries.toList()) {
      if (entry.value.lifecycleState != CCBackendEntryLifecycleState.removed) {
        continue;
      }
      _backendEntries.remove(entry.key);
      removedCount--;
      if (removedCount <= navigationDiagnosticCapacity) return;
    }
  }

  /// Accepts a monotonic Host event or records a non-recoverable sequence gap.
  bool _acceptBackendSequence(CCNavigationBackendEvent event) {
    final sequence = event.sequence;
    if (sequence == null) return true;
    final hostId = event.hostId ?? event.placement.hostId;
    final previous = _backendSequencesByHost[hostId];
    if (previous != null && sequence <= previous) return false;
    if (previous != null && sequence > previous + 1) {
      _desynchronizedBackendHosts.add(hostId);
      for (final ledgerEntry in _backendEntries.entries.toList()) {
        final entry = ledgerEntry.value;
        if (entry.hostId == hostId &&
            entry.lifecycleState == CCBackendEntryLifecycleState.active) {
          _backendEntries[ledgerEntry.key] = _copyBackendEntry(
            entry,
            visibilityState: CCBackendEntryVisibilityState.unknown,
          );
        }
      }
    }
    _backendSequencesByHost[hostId] = sequence;
    return true;
  }

  /// Applies one confirmed backend top without inferring structural removal.
  void _applyObservedBackendTop(CCNavigationBackendEvent event) {
    if (event.kind == CCNavigationBackendEventKind.outletsChanged) {
      _applyActiveOutlets(
        hostId: event.hostId ?? event.placement.hostId,
        shellId: event.placement.shellId,
        activeOutlets: event.activeNavigatorOutlets,
        reason: 'adaptiveOutletsChanged',
      );
      return;
    }
    if (event.kind == CCNavigationBackendEventKind.outletActivated) {
      _applyActivatedOutlet(event);
      return;
    }
    if (event.kind != CCNavigationBackendEventKind.topChanged) return;
    final eventHostId = event.hostId ?? event.placement.hostId;
    if (!_usesBackendVisibilityConfirmationFor(eventHostId)) return;
    final backendEntryId = event.backendEntryId;
    if (backendEntryId == null) return;
    final current = _backendEntries[backendEntryId];
    if (current == null ||
        current.lifecycleState != CCBackendEntryLifecycleState.active) {
      return;
    }
    final hostId = current.hostId ?? event.hostId ?? event.placement.hostId;
    final outlet = current.navigatorOutlet;
    for (final ledgerEntry in _backendEntries.entries.toList()) {
      final entry = ledgerEntry.value;
      if (entry.lifecycleState != CCBackendEntryLifecycleState.active ||
          (entry.hostId ?? hostId) != hostId ||
          entry.navigatorOutlet != outlet) {
        continue;
      }
      final visibility = entry.backendEntryId == backendEntryId
          ? CCBackendEntryVisibilityState.visible
          : CCBackendEntryVisibilityState.hidden;
      if (entry.visibilityState != visibility) {
        _backendEntries[ledgerEntry.key] = _copyBackendEntry(
          entry,
          visibilityState: visibility,
          lastSequence: event.sequence ?? entry.lastSequence,
        );
      }
    }
    _synchronizeRouteEntryVisibility(
      hostId: hostId,
      navigatorOutlet: outlet,
      visibleRouteEntryId: current.routeEntryId,
      reason: 'backendTopChanged',
    );
  }

  /// Switches visible managed state between persistent Stateful Shell branches.
  void _applyActivatedOutlet(CCNavigationBackendEvent event) {
    final shellId = event.placement.shellId;
    if (shellId == null) return;
    final hostId = event.hostId ?? event.placement.hostId;
    final activeOutlet =
        event.navigatorOutlet ?? event.placement.navigatorOutlet;
    _applyActiveOutlets(
      hostId: hostId,
      shellId: shellId,
      activeOutlets: [activeOutlet],
      reason: 'outletActivated',
    );
  }

  /// Reconciles one Host's visible Outlets without changing stack ownership.
  void _applyActiveOutlets({
    required String hostId,
    required String? shellId,
    required Iterable<String> activeOutlets,
    required String reason,
  }) {
    final active = activeOutlets.toSet();
    for (final entry in _routeEntries) {
      if (entry.request.hostId == hostId &&
          (shellId == null || entry.request.placement.shellId == shellId) &&
          !active.contains(entry.request.placement.navigatorOutlet)) {
        _setRouteEntryHidden(entry, reason: reason);
      }
    }

    for (final activeOutlet in active) {
      _BackendEntryRecord? current;
      for (final entry in _backendEntries.values) {
        if (entry.lifecycleState != CCBackendEntryLifecycleState.active ||
            entry.visibilityState != CCBackendEntryVisibilityState.visible ||
            (entry.hostId ?? hostId) != hostId ||
            entry.navigatorOutlet != activeOutlet) {
          continue;
        }
        if (current == null ||
            (entry.lastSequence ?? -1) >= (current.lastSequence ?? -1)) {
          current = entry;
        }
      }
      String? visibleRouteEntryId = current?.routeEntryId;
      if (current == null) {
        for (final entry in _routeEntries.reversed) {
          if (entry.request.hostId == hostId &&
              entry.request.placement.navigatorOutlet == activeOutlet &&
              (shellId == null || entry.request.placement.shellId == shellId)) {
            visibleRouteEntryId = entry.id;
            break;
          }
        }
      }
      _synchronizeRouteEntryVisibility(
        hostId: hostId,
        navigatorOutlet: activeOutlet,
        visibleRouteEntryId: visibleRouteEntryId,
        reason: reason,
      );
    }
  }

  /// Associates a committed Runtime Entry with callbacks received synchronously.
  void _associateCommittedBackendEntry(_RouteEntryRecord routeEntry) {
    for (final ledgerEntry in _backendEntries.entries.toList()) {
      final entry = ledgerEntry.value;
      if (entry.navigationId != routeEntry.request.navigationId) continue;
      final associated = _copyBackendEntry(
        entry,
        owner: CCBackendEntryOwner.managed,
        routeEntryId: routeEntry.id,
        routeId: routeEntry.request.routeId,
      );
      _backendEntries[ledgerEntry.key] = associated;
      switch (associated.visibilityState) {
        case CCBackendEntryVisibilityState.visible:
          _synchronizeRouteEntryVisibility(
            hostId: associated.hostId ?? routeEntry.request.hostId,
            navigatorOutlet: associated.navigatorOutlet,
            visibleRouteEntryId: routeEntry.id,
            reason: 'backendTopConfirmed',
          );
        case CCBackendEntryVisibilityState.hidden:
          _setRouteEntryHidden(routeEntry, reason: 'backendTopConfirmed');
        case CCBackendEntryVisibilityState.unknown:
          break;
      }
    }
  }

  /// Copies an immutable backend ledger Entry with selected state changes.
  _BackendEntryRecord _copyBackendEntry(
    _BackendEntryRecord entry, {
    CCBackendEntryOwner? owner,
    String? routeEntryId,
    String? routeId,
    CCBackendEntryLifecycleState? lifecycleState,
    CCBackendEntryVisibilityState? visibilityState,
    int? lastSequence,
  }) => _BackendEntryRecord(
    backendEntryId: entry.backendEntryId,
    owner: owner ?? entry.owner,
    routeEntryId: routeEntryId ?? entry.routeEntryId,
    navigationId: entry.navigationId,
    routeId: routeId ?? entry.routeId,
    hostId: entry.hostId,
    navigatorOutlet: entry.navigatorOutlet,
    address: entry.address,
    lifecycleState: lifecycleState ?? entry.lifecycleState,
    visibilityState: visibilityState ?? entry.visibilityState,
    lastSequence: lastSequence ?? entry.lastSequence,
  );
}
