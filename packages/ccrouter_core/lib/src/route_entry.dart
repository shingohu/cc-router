part of 'runtime.dart';

/// Internal mutable Route Entry owned by one Runtime and one Route Scope.
final class _RouteEntryRecord {
  /// Creates an entry in the `created` state.
  _RouteEntryRecord({
    required this.id,
    required this.request,
    required this.address,
  }) : scope = CCScope('route-$id'),
       handle = CCRouteEntryHandle(id);

  /// Payload-free exact identity issued only through the owning Page bridge.
  final CCRouteEntryHandle handle;

  /// Validates a targeted result before any backend mutation.
  void Function(Object? result)? validateResult;

  /// Stable identity for this concrete route opening.
  final String id;

  /// Immutable request that created this entry.
  final CCNavigationRequest request;

  /// Sanitized address metadata copied into retained public snapshots.
  final CCRouteAddressSummary address;

  /// Scope owning services and cancellation tied to this route opening.
  final CCScope scope;

  /// Logical removal signal, independent of the outgoing render Scope lifetime.
  ///
  /// Targeted-close waits end when this exact Entry leaves the active stack;
  /// ordinary Pop animations may keep its Scope alive until rendering exits.
  final CCCancellationToken removal = CCCancellationToken();

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

  /// Returns the Runtime-issued handle for [navigationId], if still retained.
  ///
  /// This is an internal bridge for the Flutter facade. Business code must
  /// capture a handle from its owning Page context instead of resolving one
  /// from a diagnostic snapshot or stack position.
  CCRouteEntryHandle? routeEntryHandleForNavigation(String navigationId) =>
      _routeEntryForNavigation(navigationId)?.handle;

  /// Returns a bounded immutable snapshot of Route Entry lifecycle events.
  List<CCRouteEntryLifecycleEvent> get recentRouteEntryEvents =>
      List.unmodifiable(_routeEntryEvents);

  /// Returns the retained Entry created by [navigationId], if it still exists.
  ///
  /// Route Service resolution uses this exact identity and never substitutes a
  /// visible, top, or same-route Entry when the requested Entry has gone away.
  _RouteEntryRecord? _routeEntryForNavigation(String navigationId) {
    for (final entry in _routeEntries) {
      if (entry.request.navigationId == navigationId) return entry;
    }
    return null;
  }

  /// Resolves services for an active Entry or its bounded outgoing rendering.
  ///
  /// Exiting entries are excluded from navigation, revalidation and diagnostics
  /// of active stacks; only exact Route-bound service access can use them.
  _RouteEntryRecord? _routeServiceEntryForNavigation(String navigationId) =>
      _routeEntryForNavigation(navigationId) ??
      _exitingRouteEntries[navigationId];

  /// Subscribes to Route Entry lifecycle transitions.
  ///
  /// Transitions are delivered by the bounded FIFO observer queue. Listener
  /// failures are isolated from navigation. The returned callback removes the
  /// listener and cancels its queued deliveries.
  /// Cleanup is idempotent and never removes a later re-add of this callback.
  /// Simultaneous duplicate adds still share one subscription.
  void Function() addRouteEntryListener(
    CCRouteEntryLifecycleListener listener,
  ) {
    _ensureInitialized();
    return _subscribeNavigationObserver(_routeEntryListeners, listener);
  }

  /// Allocates Entry-owned signals in Host context before Adapter execution.
  ///
  /// An active Route Scope must not retain its original navigation caller Zone.
  _RouteEntryRecord _createRouteEntry(CCNavigationRequest request) {
    final entry = _hostZone.run(
      () => _RouteEntryRecord(
        id: '$_runtimeId-entry-${++_routeEntrySequence}',
        request: request.parentStack.isEmpty
            ? request
            : request.withParentStack(const []),
        address: _addressSummaryFor(routeId: request.routeId, uri: request.uri),
      ),
    );
    _emitRouteEntryTransition(entry, CCRouteEntryLifecycleState.resolving);
    return entry;
  }

  /// Commits an accepted Entry only while its original lifetime remains live.
  ///
  /// Replacing old Entries can synchronously cancel Scopes and invoke owned
  /// cleanup. Recheck after that work so a detached Host or shutdown cannot
  /// acquire a new Entry after its teardown has already visited this stack.
  void _commitRouteEntry(
    _RouteEntryRecord entry, {
    CCCancellationToken? requestCancellation,
  }) {
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
    _ensureNavigationRequestAlive(requestCancellation);
    _routeEntries.add(entry);
    _emitRouteEntryTransition(entry, CCRouteEntryLifecycleState.pushed);
    _associateCommittedBackendEntry(entry);
    if (!_usesBackendVisibilityConfirmationFor(entry.request.hostId)) {
      _emitNavigationCapabilityFallback(
        entry.request,
        capability: CCNavigationCapabilityType.backendVisibilityObservation,
        behavior:
            CCNavigationCapabilityFallbackBehavior.runtimeCommitVisibility,
      );
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
    final hasPartitionEntries = _routeEntries.any(
      (candidate) => _sameRouteEntryPartition(candidate, entry),
    );
    if (hasPartitionEntries) {
      _emitNavigationCapabilityFallback(
        entry.request,
        capability: CCNavigationCapabilityType.managedPopObservation,
        behavior:
            CCNavigationCapabilityFallbackBehavior.partitionLocalReconciliation,
      );
    }
    _removeRouteEntriesInPartition(
      reason: reason,
      hostId: entry.request.hostId,
      navigatorOutlet: entry.request.placement.navigatorOutlet,
    );
  }

  /// Marks one Entry as removed and closes its Route Scope asynchronously.
  /// Callback failures are rethrown only after state retirement and scheduling
  /// closure; no external release hook may skip the Entry's terminal lifecycle.
  void _removeRouteEntry(
    _RouteEntryRecord entry, {
    required String reason,
    bool revealPrevious = true,
  }) {
    if (entry.state == CCRouteEntryLifecycleState.disposed ||
        entry.state == CCRouteEntryLifecycleState.removed) {
      return;
    }
    // Reserve the close before callbacks can synchronously start shutdown.
    // That shutdown must join this Scope even while removal is still on stack.
    // Observe failures in the producer's Zone and carry them as data. A
    // reentrant shutdown may join from a different Dart error Zone.
    final completion = _SharedResult<void>();
    final close = completion.settled;
    _routeEntryCloseFutures.add(close);
    // Retain only pending closes. Runtime shutdown snapshots this collection
    // before awaiting it, while completed entries do not consume memory for
    // the lifetime of a long-running host.
    unawaited(close.then((_) => _routeEntryCloseFutures.remove(close)));
    Object? firstError;
    StackTrace? firstStack;
    // External cancellation/release hooks may fail. Finish this Entry's state
    // machine and start Scope closure before returning the first failure.
    void attempt(void Function() action) {
      try {
        action();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }

    try {
      if (_routeEntries.remove(entry)) _diagnosticRevision++;
      attempt(entry.removal.cancel);
      final adapter = _navigationAdapter;
      if (adapter is CCNavigationManagedEntryReleaseSink) {
        attempt(
          () => (adapter as CCNavigationManagedEntryReleaseSink)
              .releaseManagedNavigation(entry.request.navigationId),
        );
      }
      final wasVisible = entry.state == CCRouteEntryLifecycleState.visible;
      if (wasVisible) {
        attempt(
          () => _emitRouteVisibility(
            entry,
            CCRouteVisibilityPhase.willHide,
            reason: reason,
          ),
        );
      }
      if (entry.state != CCRouteEntryLifecycleState.popping) {
        attempt(
          () => _emitRouteEntryTransition(
            entry,
            CCRouteEntryLifecycleState.popping,
          ),
        );
      }
      if (wasVisible) {
        attempt(
          () => _emitRouteVisibility(
            entry,
            CCRouteVisibilityPhase.didHide,
            reason: reason,
          ),
        );
      }
      attempt(
        () => _emitRouteEntryTransition(
          entry,
          CCRouteEntryLifecycleState.removed,
        ),
      );
      if (revealPrevious &&
          !_usesBackendVisibilityConfirmationFor(entry.request.hostId)) {
        for (final previous in _routeEntries.reversed) {
          if (_sameRouteEntryPartition(previous, entry)) {
            attempt(() => _setRouteEntryVisible(previous, reason: reason));
            break;
          }
        }
      }
    } finally {
      completion.follow(
        _closeRemovedRouteEntry(entry, reason, firstError, firstStack),
      );
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack!);
    }
  }

  /// Joins Scope cleanup before publishing the first removal failure as data.
  /// Synchronous release failures keep precedence over later Scope failures.
  Future<void> _closeRemovedRouteEntry(
    _RouteEntryRecord entry,
    String reason,
    Object? removalError,
    StackTrace? removalStack,
  ) async {
    try {
      await _closeRouteEntry(entry, reason);
    } catch (_) {
      if (removalError == null) rethrow;
    }
    if (removalError != null) {
      Error.throwWithStackTrace(removalError, removalStack!);
    }
  }

  /// Closes one Route Scope without blocking the Adapter transition.
  /// Publishes disposal even if Scope resource cleanup reports a failure.
  Future<void> _closeRouteEntry(_RouteEntryRecord entry, String reason) async {
    try {
      final exit = _waitForRouteExit(entry, reason);
      if (exit != null) await exit;
    } finally {
      try {
        await entry.scope.close();
      } finally {
        if (entry.state == CCRouteEntryLifecycleState.removed) {
          _emitRouteEntryTransition(
            entry,
            CCRouteEntryLifecycleState.disposed,
            reason: reason,
          );
        }
      }
    }
  }

  /// Waits for rendering with explicit cancellation and no active-stack entry.
  Future<void>? _waitForRouteExit(_RouteEntryRecord entry, String reason) {
    final adapter = _navigationAdapter;
    if (_disposed ||
        reason == 'hostDetached' ||
        adapter is! CCNavigationRouteExitBinding) {
      return null;
    }
    final navigationId = entry.request.navigationId;
    final completed = Completer<void>();
    void Function()? unsubscribe;
    var released = false;
    void release() {
      if (released) return;
      released = true;
      final remove = unsubscribe;
      unsubscribe = null;
      try {
        remove?.call();
      } finally {
        if (identical(_routeExitWaiters[navigationId], release)) {
          _routeExitWaiters.remove(navigationId);
        }
        if (identical(_exitingRouteEntries[navigationId], entry)) {
          _exitingRouteEntries.remove(navigationId);
          _diagnosticRevision++;
        }
        if (!completed.isCompleted) completed.complete();
      }
    }

    // Reserve cancellation before invoking Adapter code. Shutdown/detach may
    // release this provisional wait before the subscription remover is returned.
    _exitingRouteEntries[navigationId] = entry;
    _routeExitWaiters[navigationId] = release;
    _diagnosticRevision++;
    try {
      final remove = (adapter as CCNavigationRouteExitBinding)
          .addRouteExitListener(
            navigationId: navigationId,
            hostId: entry.request.hostId,
            onExited: () {
              if (!completed.isCompleted) completed.complete();
            },
          );
      if (released) {
        remove?.call();
        return null;
      }
      unsubscribe = remove;
      if (remove == null) {
        release();
        return null;
      }
      return completed.future.whenComplete(release);
    } catch (_) {
      release();
      rethrow;
    }
  }

  /// Ends outgoing render waits when their exact Host registration detaches.
  /// Removed Entries are absent from the active stack; their Scopes still need
  /// cancellation even when a custom Adapter never reports an outgoing frame.
  void _releaseRouteExitsForHost(String hostId) {
    for (final entry in _exitingRouteEntries.values.toList()) {
      if (entry.request.hostId != hostId) continue;
      try {
        _routeExitWaiters[entry.request.navigationId]?.call();
      } catch (error) {
        _recordNavigationCallbackFailure(
          'Route exit unsubscription failed: ${error.runtimeType}.',
        );
      }
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
  /// Every matching Entry is retired before the first callback error is rethrown.
  void _removeAllRouteEntries({required String reason, String? hostId}) =>
      _removeMatchingRouteEntries(reason: reason, hostId: hostId);

  /// Removes retained Entries from one exact Host and Navigator Outlet.
  ///
  /// This fallback is used only by adapters that cannot report an identity-
  /// based declarative stack diff. It deliberately preserves sibling Outlets.
  void _removeRouteEntriesInPartition({
    required String reason,
    required String hostId,
    required String navigatorOutlet,
  }) => _removeMatchingRouteEntries(
    reason: reason,
    hostId: hostId,
    navigatorOutlet: navigatorOutlet,
  );

  /// Drains the captured partition despite individual Entry cleanup failures.
  void _removeMatchingRouteEntries({
    required String reason,
    String? hostId,
    String? navigatorOutlet,
  }) {
    Object? firstError;
    StackTrace? firstStack;
    for (final entry in _routeEntries.toList().reversed) {
      if (hostId != null && entry.request.hostId != hostId ||
          navigatorOutlet != null &&
              entry.request.placement.navigatorOutlet != navigatorOutlet) {
        continue;
      }
      try {
        _removeRouteEntry(entry, reason: reason, revealPrevious: false);
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
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
    _routeEntryEventTotal++;
    _retainDiagnostic(_routeEntryEvents, event, navigationDiagnosticCapacity);
    _emitAspectEntryState(entry, state);
    _enqueueRegisteredNavigationObserverBatch(
      _routeEntryListeners,
      (listener) => listener(event),
      failureLabel: 'Route Entry listener',
      critical:
          state == CCRouteEntryLifecycleState.removed ||
          state == CCRouteEntryLifecycleState.disposed,
    );
    _emitDiagnostic(
      category: CCDiagnosticCategory.lifecycle,
      level: state == CCRouteEntryLifecycleState.disposed
          ? CCDiagnosticLevel.info
          : CCDiagnosticLevel.debug,
      occurredAt: event.timestamp,
      operation: 'routeEntry',
      status: state.name,
      duration: Duration.zero,
      navigationId: event.entry.navigationId,
      routeId: event.entry.routeId,
      targetComponentId: event.entry.ownerComponentId,
      hostId: event.entry.hostId,
      outlet: event.entry.placement.navigatorOutlet,
    );
  }
}
