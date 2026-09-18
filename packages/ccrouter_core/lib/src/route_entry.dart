part of 'runtime.dart';

/// Internal mutable Route Entry owned by one Runtime and one Route Scope.
final class _RouteEntryRecord {
  /// Creates an entry in the `created` state.
  _RouteEntryRecord({required this.id, required this.request})
    : scope = CCScope('route-$id');

  /// Stable identity for this concrete route opening.
  final String id;

  /// Immutable request that created this entry.
  final CCNavigationRequest request;

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
    normalizedUri: request.uri,
    arguments: request.arguments,
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
    );
    _emitRouteEntryTransition(entry, CCRouteEntryLifecycleState.resolving);
    return entry;
  }

  /// Commits an accepted Entry into Runtime's navigation order.
  void _commitRouteEntry(_RouteEntryRecord entry) {
    switch (entry.request.operation) {
      case CCNavigationOperation.replace:
        _removeTopRouteEntry(reason: 'replace', revealPrevious: false);
      case CCNavigationOperation.go:
      case CCNavigationOperation.reset:
        _removeAllRouteEntries(reason: entry.request.operation.name);
      case CCNavigationOperation.popAndPush:
        _removeTopRouteEntry(reason: 'popAndPush', revealPrevious: false);
      case CCNavigationOperation.pushAndRemoveUntil:
      case CCNavigationOperation.push:
      case CCNavigationOperation.open:
        break;
    }
    _routeEntries.add(entry);
    _emitRouteEntryTransition(entry, CCRouteEntryLifecycleState.pushed);
    _emitRouteEntryTransition(entry, CCRouteEntryLifecycleState.visible);
    _hidePreviousRouteEntry(entry);
  }

  /// Removes entries before [predicate] and commits a new pushed Entry.
  void _commitPushAndRemoveRouteEntry(
    _RouteEntryRecord entry,
    CCNavigationStackPredicate predicate,
  ) {
    _routeEntries.add(entry);
    while (_routeEntries.length > 1 &&
        !predicate(
          _routeEntries[_routeEntries.length - 2].snapshot.navigationEntry,
        )) {
      _removeRouteEntry(
        _routeEntries[_routeEntries.length - 2],
        reason: 'remove',
        revealPrevious: false,
      );
    }
    _emitRouteEntryTransition(entry, CCRouteEntryLifecycleState.pushed);
    _emitRouteEntryTransition(entry, CCRouteEntryLifecycleState.visible);
    _hidePreviousRouteEntry(entry);
  }

  /// Removes tracked entries until [predicate] matches the current Entry.
  void _popUntilRouteEntries(CCNavigationStackPredicate predicate) {
    while (_routeEntries.length > 1 &&
        !predicate(_routeEntries.last.snapshot.navigationEntry)) {
      _removeTopRouteEntry(reason: 'popUntil', preserveRoot: true);
    }
  }

  /// Hides the preceding top Entry when a new Entry becomes visible.
  void _hidePreviousRouteEntry(_RouteEntryRecord entry) {
    final index = _routeEntries.indexOf(entry);
    if (index <= 0) return;
    final previous = _routeEntries[index - 1];
    if (previous.state == CCRouteEntryLifecycleState.visible) {
      _emitRouteEntryTransition(previous, CCRouteEntryLifecycleState.hidden);
    }
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
    if (entry.state != CCRouteEntryLifecycleState.popping) {
      _emitRouteEntryTransition(entry, CCRouteEntryLifecycleState.popping);
    }
    _emitRouteEntryTransition(entry, CCRouteEntryLifecycleState.removed);
    if (revealPrevious && _routeEntries.isNotEmpty) {
      final previous = _routeEntries.last;
      if (previous.state == CCRouteEntryLifecycleState.hidden) {
        _emitRouteEntryTransition(previous, CCRouteEntryLifecycleState.visible);
      }
    }
    final close = _closeRouteEntry(entry, reason);
    _routeEntryCloseFutures.add(close);
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
  }) {
    if (_routeEntries.isEmpty) return;
    if (preserveRoot && _routeEntries.length == 1) return;
    _removeRouteEntry(
      _routeEntries.last,
      reason: reason,
      revealPrevious: revealPrevious,
    );
  }

  /// Removes all currently retained Entries.
  void _removeAllRouteEntries({required String reason}) {
    for (final entry in _routeEntries.toList().reversed) {
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
      state: state,
      timestamp: DateTime.now(),
      reason: reason,
    );
    if (navigationEventCapacity > 0) {
      if (_routeEntryEvents.length == navigationEventCapacity) {
        _routeEntryEvents.removeFirst();
      }
      _routeEntryEvents.add(event);
    }
    for (final listener in _routeEntryListeners.toList()) {
      try {
        listener(event);
      } catch (error) {
        if (traceCapacity > 0) {
          if (_subscriberErrors.length == traceCapacity) {
            _subscriberErrors.removeAt(0);
          }
          _subscriberErrors.add(
            CCInvocationError(
              'Route Entry listener failed: ${error.runtimeType}',
            ),
          );
        }
      }
    }
  }
}
