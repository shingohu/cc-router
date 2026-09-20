part of 'runtime.dart';

/// Internal mutable Route Entry owned by one Runtime and one Route Scope.
final class _RouteEntryRecord {
  /// Creates an entry in the `created` state.
  _RouteEntryRecord({
    required this.id,
    required this.request,
    required this.address,
  }) : scope = CCScope('route-$id');

  /// Stable identity for this concrete route opening.
  final String id;

  /// Immutable request that created this entry.
  final CCNavigationRequest request;

  /// Sanitized address metadata copied into retained public snapshots.
  final CCRouteAddressSummary address;

  /// Scope owning services and cancellation tied to this route opening.
  final CCScope scope;

  /// Mutable lifecycle state retained only by Runtime.
  CCRouteEntryLifecycleState state = CCRouteEntryLifecycleState.created;

  /// Converts the internal record into an immutable public snapshot.
  CCRouteEntrySnapshot get snapshot => CCRouteEntrySnapshot(
    routeEntryId: id,
    navigationId: request.navigationId,
    routeId: request.routeId,
    ownerComponentId: request.ownerComponentId,
    hostId: request.hostId,
    address: address,
    placement: request.placement,
    origin: request.origin,
    lifecycleState: state,
  );
}

/// Exposes Route Entry snapshots and lifecycle transitions from Runtime.
extension CCRouterRuntimeRouteEntries on CCRouterRuntime {
  /// Returns active Route Entries in current navigation order.
  ///
  /// The returned values are immutable snapshots; Route Scopes and backend
  /// navigation objects remain Runtime-owned.
  List<CCRouteEntrySnapshot> get activeRouteEntries =>
      List.unmodifiable(_routeEntries.map((entry) => entry.snapshot));

  /// Returns a bounded immutable snapshot of Route Entry lifecycle events.
  List<CCRouteEntryLifecycleEvent> get recentRouteEntryEvents =>
      List.unmodifiable(_routeEntryEvents);

  /// Subscribes to Route Entry lifecycle transitions.
  ///
  /// Listener failures are isolated from navigation. The returned callback
  /// removes the listener.
  void Function() addRouteEntryListener(
    CCRouteEntryLifecycleListener listener,
  ) {
    _ensureInitialized();
    _routeEntryListeners.add(listener);
    return () => _routeEntryListeners.remove(listener);
  }

  /// Allocates one Entry and its Route Scope before Adapter execution.
  _RouteEntryRecord _createRouteEntry(CCNavigationRequest request) {
    final entry = _RouteEntryRecord(
      id: '$_runtimeId-entry-${++_routeEntrySequence}',
      request: request,
      address: _addressSummaryFor(routeId: request.routeId, uri: request.uri),
    );
    _emitRouteEntryTransition(entry, CCRouteEntryLifecycleState.resolving);
    return entry;
  }

  /// Commits an accepted Entry into Runtime's navigation order.
  void _commitRouteEntry(_RouteEntryRecord entry) {
    switch (entry.request.operation) {
      case CCNavigationOperation.replace:
        _removeTopRouteEntry(
          reason: 'replace',
          revealPrevious: false,
          hostId: entry.request.hostId,
          navigatorOutlet: entry.request.placement.navigatorOutlet,
        );
      case CCNavigationOperation.go:
        _prepareDeclarativeRouteEntry(entry, reason: 'go');
      case CCNavigationOperation.reset:
        _removeAllRouteEntries(reason: 'reset', hostId: entry.request.hostId);
      case CCNavigationOperation.push:
      case CCNavigationOperation.open:
        if (entry.request.operation == CCNavigationOperation.open &&
            entry.request.openMode == CCDeepLinkOpenMode.go) {
          _prepareDeclarativeRouteEntry(entry, reason: 'openGo');
        }
        break;
    }
    _routeEntries.add(entry);
    _emitRouteEntryTransition(entry, CCRouteEntryLifecycleState.pushed);
    _associateCommittedBackendEntry(entry);
    if (!_usesBackendVisibilityConfirmationFor(entry.request.hostId)) {
      _hidePreviousRouteEntry(entry);
      _setRouteEntryVisible(entry, reason: 'runtimeCommit');
    }
  }

  /// Concrete active Host exposed by a Host-bound Adapter, when available.
  String? get _activeRouteEntryHostId {
    final adapter = _navigationAdapter;
    return adapter is CCNavigationAdapterHostBinding
        ? (adapter as CCNavigationAdapterHostBinding).hostId
        : null;
  }

  /// Hides the preceding top Entry when a new Entry becomes visible.
  void _hidePreviousRouteEntry(_RouteEntryRecord entry) {
    final index = _routeEntries.indexOf(entry);
    if (index <= 0) return;
    for (
      var candidateIndex = index - 1;
      candidateIndex >= 0;
      candidateIndex--
    ) {
      final previous = _routeEntries[candidateIndex];
      if (!_sameRouteEntryPartition(previous, entry)) continue;
      _setRouteEntryHidden(previous, reason: 'covered');
      return;
    }
  }

  /// Applies one confirmed current Entry within a Host and Navigator Outlet.
  void _synchronizeRouteEntryVisibility({
    required String hostId,
    required String navigatorOutlet,
    required String? visibleRouteEntryId,
    required String reason,
  }) {
    _RouteEntryRecord? visibleEntry;
    for (final entry in _routeEntries) {
      if (entry.request.hostId != hostId ||
          entry.request.placement.navigatorOutlet != navigatorOutlet) {
        continue;
      }
      if (entry.id == visibleRouteEntryId) {
        visibleEntry = entry;
      } else {
        _setRouteEntryHidden(entry, reason: reason);
      }
    }
    if (visibleEntry != null) {
      _setRouteEntryVisible(visibleEntry, reason: reason);
    }
  }

  /// Marks one retained Entry visible and emits one idempotent transition.
  void _setRouteEntryVisible(
    _RouteEntryRecord entry, {
    required String reason,
  }) {
    if (entry.state == CCRouteEntryLifecycleState.visible ||
        entry.state == CCRouteEntryLifecycleState.removed ||
        entry.state == CCRouteEntryLifecycleState.disposed ||
        !_routeEntries.contains(entry)) {
      return;
    }
    _emitRouteVisibility(
      entry,
      CCRouteVisibilityPhase.willShow,
      reason: reason,
    );
    _emitRouteEntryTransition(entry, CCRouteEntryLifecycleState.visible);
    _emitRouteVisibility(entry, CCRouteVisibilityPhase.didShow, reason: reason);
  }

  /// Marks one retained Entry hidden without closing its Route Scope.
  void _setRouteEntryHidden(_RouteEntryRecord entry, {required String reason}) {
    if (entry.state == CCRouteEntryLifecycleState.hidden ||
        entry.state == CCRouteEntryLifecycleState.removed ||
        entry.state == CCRouteEntryLifecycleState.disposed ||
        !_routeEntries.contains(entry)) {
      return;
    }
    if (entry.state == CCRouteEntryLifecycleState.visible) {
      _emitRouteVisibility(
        entry,
        CCRouteVisibilityPhase.willHide,
        reason: reason,
      );
      _emitRouteEntryTransition(entry, CCRouteEntryLifecycleState.hidden);
      _emitRouteVisibility(
        entry,
        CCRouteVisibilityPhase.didHide,
        reason: reason,
      );
      return;
    }
    _emitRouteEntryTransition(entry, CCRouteEntryLifecycleState.hidden);
  }

  /// Whether two managed Entries belong to the same backend stack partition.
  bool _sameRouteEntryPartition(
    _RouteEntryRecord first,
    _RouteEntryRecord second,
  ) =>
      first.request.hostId == second.request.hostId &&
      first.request.placement.navigatorOutlet ==
          second.request.placement.navigatorOutlet;

  /// Prepares a declarative location change without treating it as a reset.
  ///
  /// Identity-aware backends report the concrete Entries removed by their
  /// rebuilt page tree, so Runtime keeps every Scope until those events arrive.
  /// Simpler adapters cannot report that diff; for them the documented fallback
  /// replaces only the target Host and Outlet partition and never destroys an
  /// inactive Shell branch or another pane.
  void _prepareDeclarativeRouteEntry(
    _RouteEntryRecord entry, {
    required String reason,
  }) {
    if (_usesManagedRemovalConfirmationFor(entry.request.hostId)) return;
    _removeRouteEntriesInPartition(
      reason: reason,
      hostId: entry.request.hostId,
      navigatorOutlet: entry.request.placement.navigatorOutlet,
    );
  }

  /// Marks one Entry as removed and closes its Route Scope asynchronously.
  void _removeRouteEntry(
    _RouteEntryRecord entry, {
    required String reason,
    bool revealPrevious = true,
  }) {
    if (entry.state == CCRouteEntryLifecycleState.disposed ||
        entry.state == CCRouteEntryLifecycleState.removed) {
      return;
    }
    _routeEntries.remove(entry);
    final adapter = _navigationAdapter;
    if (adapter is CCNavigationManagedEntryReleaseSink) {
      (adapter as CCNavigationManagedEntryReleaseSink).releaseManagedNavigation(
        entry.request.navigationId,
      );
    }
    final wasVisible = entry.state == CCRouteEntryLifecycleState.visible;
    if (wasVisible) {
      _emitRouteVisibility(
        entry,
        CCRouteVisibilityPhase.willHide,
        reason: reason,
      );
    }
    if (entry.state != CCRouteEntryLifecycleState.popping) {
      _emitRouteEntryTransition(entry, CCRouteEntryLifecycleState.popping);
    }
    if (wasVisible) {
      _emitRouteVisibility(
        entry,
        CCRouteVisibilityPhase.didHide,
        reason: reason,
      );
    }
    _emitRouteEntryTransition(entry, CCRouteEntryLifecycleState.removed);
    if (revealPrevious &&
        !_usesBackendVisibilityConfirmationFor(entry.request.hostId)) {
      for (final previous in _routeEntries.reversed) {
        if (_sameRouteEntryPartition(previous, entry)) {
          _setRouteEntryVisible(previous, reason: reason);
          break;
        }
      }
    }
    final close = _closeRouteEntry(entry, reason);
    _routeEntryCloseFutures.add(close);
    // Retain only pending closes. Runtime shutdown snapshots this collection
    // before awaiting it, while completed entries do not consume memory for
    // the lifetime of a long-running host.
    unawaited(
      close.then(
        (_) => _routeEntryCloseFutures.remove(close),
        onError: (Object _, StackTrace __) {
          _routeEntryCloseFutures.remove(close);
        },
      ),
    );
    unawaited(close);
  }

  /// Closes one Route Scope without blocking the Adapter transition.
  Future<void> _closeRouteEntry(_RouteEntryRecord entry, String reason) async {
    await entry.scope.close();
    if (entry.state == CCRouteEntryLifecycleState.removed) {
      _emitRouteEntryTransition(
        entry,
        CCRouteEntryLifecycleState.disposed,
        reason: reason,
      );
    }
  }

  /// Removes the current top Entry, preserving the root when requested.
  void _removeTopRouteEntry({
    required String reason,
    bool preserveRoot = false,
    bool revealPrevious = true,
    String? hostId,
    String? navigatorOutlet,
  }) {
    _RouteEntryRecord? target;
    var matchingCount = 0;
    for (final entry in _routeEntries.reversed) {
      if ((hostId == null || entry.request.hostId == hostId) &&
          (navigatorOutlet == null ||
              entry.request.placement.navigatorOutlet == navigatorOutlet)) {
        matchingCount++;
        target ??= entry;
      }
    }
    if (target == null || preserveRoot && matchingCount == 1) return;
    _removeRouteEntry(target, reason: reason, revealPrevious: revealPrevious);
  }

  /// Removes retained Entries, optionally isolated to one Host.
  void _removeAllRouteEntries({required String reason, String? hostId}) {
    for (final entry in _routeEntries.toList().reversed) {
      if (hostId != null && entry.request.hostId != hostId) continue;
      _removeRouteEntry(entry, reason: reason, revealPrevious: false);
    }
  }

  /// Removes retained Entries from one exact Host and Navigator Outlet.
  ///
  /// This fallback is used only by adapters that cannot report an identity-
  /// based declarative stack diff. It deliberately preserves sibling Outlets.
  void _removeRouteEntriesInPartition({
    required String reason,
    required String hostId,
    required String navigatorOutlet,
  }) {
    for (final entry in _routeEntries.toList().reversed) {
      if (entry.request.hostId != hostId ||
          entry.request.placement.navigatorOutlet != navigatorOutlet) {
        continue;
      }
      _removeRouteEntry(entry, reason: reason, revealPrevious: false);
    }
  }

  /// Completes the pending result lifecycle for an Entry.
  void _completeRouteEntry(_RouteEntryRecord entry, {String reason = 'pop'}) {
    _removeRouteEntry(entry, reason: reason);
  }

  /// Records and publishes one Entry transition with bounded retention.
  void _emitRouteEntryTransition(
    _RouteEntryRecord entry,
    CCRouteEntryLifecycleState state, {
    String? reason,
  }) {
    final previousState = entry.state;
    entry.state = state;
    final event = CCRouteEntryLifecycleEvent(
      entry: entry.snapshot,
      previousState: previousState,
      timestamp: DateTime.now(),
      reason: reason,
    );
    if (navigationDiagnosticCapacity > 0) {
      if (_routeEntryEvents.length == navigationDiagnosticCapacity) {
        _routeEntryEvents.removeFirst();
      }
      _routeEntryEvents.add(event);
    }
    _emitAspectEntryState(entry, state);
    for (final listener in _routeEntryListeners.toList()) {
      _notifyNavigationObserver(
        () => listener(event),
        failureLabel: 'Route Entry listener',
      );
    }
  }
}
