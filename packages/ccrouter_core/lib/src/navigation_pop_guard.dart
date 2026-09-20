part of 'runtime.dart';

/// Evaluates synchronous Pop policy for managed route entries.
extension CCRouterRuntimePopGuard on CCRouterRuntime {
  /// Runs global guards followed by guards declared by the active route.
  ///
  /// Foreign, opaque, and unidentifiable backend entries bypass managed guards
  /// so third-party UI can consume back without consulting or mutating the
  /// underlying CCRouter page. Guard failures fail closed with a stable code.
  CCPopGuardDecision _evaluatePopGuardsForActiveEntry(CCPopTrigger trigger) {
    if (!_initialized || _disposed) return const CCPopAllow();
    final target = _activePopTarget;
    final entry = _managedPopTarget(target);
    if (entry == null) return const CCPopAllow();
    final context = CCPopGuardContext(entry: entry.snapshot, trigger: trigger);
    for (final registration in _globalPopGuards) {
      final decision = _evaluatePopGuard(
        id: registration.id,
        guard: registration.guard,
        context: context,
      );
      if (decision is CCPopDeny) return decision;
    }
    final definition = _routeRegistry.retainedRouteDefinition(
      entry.request.routeId,
    );
    for (final id in definition.popGuardIds) {
      final registration = _routePopGuards[id];
      if (registration == null) {
        return const CCPopDeny(code: 'pop_guard_unavailable');
      }
      final decision = _evaluatePopGuard(
        id: id,
        guard: registration.guard,
        context: context,
      );
      if (decision is CCPopDeny) return decision;
    }
    return const CCPopAllow();
  }

  /// Resolves the managed Entry that an identified backend Pop would remove.
  ///
  /// When a backend ledger exists, its newest active Entry is authoritative.
  /// A foreign or opaque top therefore returns null and protects the managed
  /// stack from inferred positional changes. Adapters without a ledger use the
  /// Runtime top Entry as their documented compatibility behavior.
  _RouteEntryRecord? _managedPopTarget(CCNavigationPopTarget? target) {
    CCBackendEntry? topBackendEntry;
    for (final backendEntry in _backendEntries.values) {
      if (backendEntry.lifecycleState != CCBackendEntryLifecycleState.active) {
        continue;
      }
      if (target != null &&
          ((backendEntry.hostId ?? target.hostId) != target.hostId ||
              backendEntry.navigatorOutlet != target.navigatorOutlet)) {
        continue;
      }
      if (target?.backendEntryId != null &&
          backendEntry.backendEntryId != target!.backendEntryId) {
        continue;
      }
      final currentSequence = topBackendEntry?.lastSequence ?? -1;
      final candidateSequence = backendEntry.lastSequence ?? -1;
      if (topBackendEntry == null || candidateSequence >= currentSequence) {
        topBackendEntry = backendEntry;
      }
    }
    if (topBackendEntry != null) {
      if (topBackendEntry.owner != CCBackendEntryOwner.managed) return null;
      final routeEntryId = topBackendEntry.routeEntryId;
      if (routeEntryId == null) return null;
      for (final entry in _routeEntries) {
        if (entry.id == routeEntryId) return entry;
      }
      return null;
    }
    final activeHostId = target?.hostId ?? _activeRouteEntryHostId;
    for (final entry in _routeEntries.reversed) {
      if ((activeHostId == null || entry.request.hostId == activeHostId) &&
          (target == null ||
              entry.request.placement.navigatorOutlet ==
                  target.navigatorOutlet)) {
        return entry;
      }
    }
    return null;
  }

  /// Isolates one guard failure and converts it into a fail-closed decision.
  CCPopGuardDecision _evaluatePopGuard({
    required String id,
    required CCPopGuard guard,
    required CCPopGuardContext context,
  }) {
    try {
      _navigationCallbackActive = true;
      return guard.evaluate(context);
    } catch (error) {
      if (traceCapacity > 0) {
        if (_subscriberErrors.length == traceCapacity) {
          _subscriberErrors.removeAt(0);
        }
        _subscriberErrors.add(
          CCInvocationError('Pop guard "$id" failed: ${error.runtimeType}.'),
        );
      }
      return const CCPopDeny(code: 'pop_guard_failed');
    } finally {
      _navigationCallbackActive = false;
    }
  }

  /// Converts a denied guard decision into an ownership-safe Pop outcome.
  CCPopOutcome? _guardedPopOutcome(CCPopTrigger trigger) {
    final decision = _evaluatePopGuardsForActiveEntry(trigger);
    if (decision is! CCPopDeny) return null;
    return CCPopOutcome(
      handled: true,
      trigger: trigger,
      guardDeniedCode: decision.code,
      hostId: _activePopTarget?.hostId ?? _activeRouteEntryHostId,
      navigatorOutlet: _activePopTarget?.navigatorOutlet,
    );
  }

  /// Returns the Adapter-declared Pop partition when available.
  CCNavigationPopTarget? get _activePopTarget {
    final adapter = _navigationAdapter;
    return adapter is CCNavigationPopTargetSource
        ? (adapter as CCNavigationPopTargetSource).activePopTarget
        : null;
  }
}
