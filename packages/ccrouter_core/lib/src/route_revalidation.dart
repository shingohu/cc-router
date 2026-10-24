part of 'runtime.dart';

/// One non-keep decision retained between evaluation and application phases.
final class _PlannedRouteRevalidation {
  /// Creates an identity-fenced plan for [entry].
  const _PlannedRouteRevalidation({
    required this.entry,
    required this.policyId,
    required this.decision,
  });

  /// Exact Runtime-owned Entry captured before policy evaluation.
  final _RouteEntryRecord entry;

  /// First deterministically ordered policy that requested a change.
  final String policyId;

  /// Backend-neutral action selected by the policy.
  final CCRouteRevalidationDecision decision;
}

/// Stops an invalidated final revalidation request before Adapter mutation.
///
/// This internal framework error bypasses navigation Failure Policy so a
/// fallback cannot turn an identity-fenced reconciliation into unrelated
/// navigation. The revalidation caller maps it to `stale` or `unsupported`.
final class _RouteRevalidationRequestError implements Exception {
  /// Creates a sanitized request-fence failure with its report [outcome].
  const _RouteRevalidationRequestError(this.outcome);

  /// Safe terminal result returned to the revalidation caller.
  final CCRouteRevalidationOutcome outcome;
}

/// Adds explicit active-route policy reconciliation to one Runtime.
extension CCRouterRuntimeRouteRevalidation on CCRouterRuntime {
  /// Revalidates every retained managed Entry after application state changes.
  ///
  /// Calls are serialized and each pass captures a fresh Entry snapshot. All
  /// policies finish successfully before the pass mutates any backend state.
  /// Policy callbacks run inside the navigation reentrancy fence. Concurrent
  /// user navigation is tolerated through exact Entry identity checks during
  /// application; stale Entries are reported and never replaced by position.
  Future<CCRouteRevalidationReport> revalidateActiveRoutes({
    required String reason,
  }) {
    _ensureNavigationCanStart();
    _ensureInitialized();
    if (!_isNavigationSourceIdentifier(reason)) {
      throw ArgumentError.value(
        reason,
        'reason',
        'A route revalidation reason must be a stable identifier.',
      );
    }
    final previous = _routeRevalidationTail;
    final operation = previous == null
        ? _performRouteRevalidation(reason: reason)
        : previous.then((_) => _performRouteRevalidation(reason: reason));
    final tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _routeRevalidationTail = tail;
    unawaited(
      tail.then<void>((_) {
        if (identical(_routeRevalidationTail, tail)) {
          _routeRevalidationTail = null;
        }
      }),
    );
    return operation;
  }

  /// Evaluates one complete immutable snapshot before applying any decision.
  Future<CCRouteRevalidationReport> _performRouteRevalidation({
    required String reason,
  }) async {
    _ensureNavigationCanStart();
    _ensureNavigationAlive();
    _ensureInitialized();
    final revision = ++_routeRevalidationRevision;
    final entries = List<_RouteEntryRecord>.of(_routeEntries);
    final plans = <_RouteEntryRecord, _PlannedRouteRevalidation>{};

    for (final entry in entries) {
      for (final registration in _routeRevalidationPolicies) {
        final cancellation = CCCancellationToken();
        final timeout = registration.timeout;
        final deadline = timeout == null ? null : DateTime.now().add(timeout);
        late final CCRouteRevalidationDecision decision;
        try {
          decision = await _awaitNavigationDecision(
            () => registration.policy.evaluate(
              CCRouteRevalidationContext(
                entry: entry.snapshot,
                reason: reason,
                revision: revision,
                cancellation: cancellation,
                deadline: deadline,
              ),
            ),
            cancellation: cancellation,
            timeout: timeout,
            timeoutError: CCRouteRevalidationPolicyTimeoutError(
              registration.id,
            ),
          );
        } on CCRouteRevalidationPolicyTimeoutError {
          rethrow;
        } on CCRouteCancelledError catch (error) {
          if (_disposed) rethrow;
          throw CCRouteRevalidationPolicyError(
            registration.id,
            error.runtimeType.toString(),
          );
        } catch (error) {
          throw CCRouteRevalidationPolicyError(
            registration.id,
            error.runtimeType.toString(),
          );
        }
        if (decision is CCRouteRevalidationKeep) continue;
        plans[entry] = _PlannedRouteRevalidation(
          entry: entry,
          policyId: registration.id,
          decision: decision,
        );
        break;
      }
    }

    _ensureNavigationAlive();
    final outcomes = <_RouteEntryRecord, CCRouteRevalidationEntryResult>{};
    final resetByHost = <String, _PlannedRouteRevalidation>{};
    for (final entry in entries.reversed) {
      final plan = plans[entry];
      if (plan?.decision is CCRouteRevalidationReset) {
        resetByHost.putIfAbsent(entry.request.hostId, () => plan!);
      }
    }

    final resetOwnedHosts = resetByHost.keys.toSet();
    for (final selected in resetByHost.values) {
      final entry = selected.entry;
      if (!_routeEntries.contains(entry)) {
        outcomes[entry] = _routeRevalidationResult(
          entry,
          CCRouteRevalidationOutcome.stale,
          policyId: selected.policyId,
        );
        continue;
      }
      final decision = selected.decision as CCRouteRevalidationReset;
      final outcome = await _resetHostForRevalidation(
        entry,
        decision.intent,
        reason: reason,
      );
      if (outcome != CCRouteRevalidationOutcome.reset) {
        outcomes[entry] = _routeRevalidationResult(
          entry,
          outcome,
          policyId: selected.policyId,
        );
        continue;
      }
      outcomes[entry] = _routeRevalidationResult(
        entry,
        CCRouteRevalidationOutcome.reset,
        policyId: selected.policyId,
      );
    }

    for (final entry in entries.reversed) {
      if (outcomes.containsKey(entry)) continue;
      final plan = plans[entry];
      if (resetOwnedHosts.contains(entry.request.hostId)) {
        outcomes[entry] = _routeRevalidationResult(
          entry,
          CCRouteRevalidationOutcome.superseded,
          policyId: plan?.policyId,
        );
        continue;
      }
      if (plan == null) {
        outcomes[entry] = _routeRevalidationResult(
          entry,
          _routeEntries.contains(entry)
              ? CCRouteRevalidationOutcome.kept
              : CCRouteRevalidationOutcome.stale,
        );
        continue;
      }
      if (!_routeEntries.contains(entry)) {
        outcomes[entry] = _routeRevalidationResult(
          entry,
          CCRouteRevalidationOutcome.stale,
          policyId: plan.policyId,
        );
        continue;
      }
      final outcome = switch (plan.decision) {
        CCRouteRevalidationClose() => await _closeRouteEntryForRevalidation(
          entry,
        ),
        CCRouteRevalidationReplace(:final intent) =>
          await _replaceRouteEntryForRevalidation(
            entry,
            intent,
            reason: reason,
          ),
        CCRouteRevalidationKeep() => CCRouteRevalidationOutcome.kept,
        CCRouteRevalidationReset() => CCRouteRevalidationOutcome.superseded,
      };
      outcomes[entry] = _routeRevalidationResult(
        entry,
        outcome,
        policyId: plan.policyId,
      );
    }

    return CCRouteRevalidationReport(
      reason: reason,
      revision: revision,
      entries: [for (final entry in entries) outcomes[entry]!],
    );
  }

  /// Resets only the Entry's original Host after final-request validation.
  Future<CCRouteRevalidationOutcome> _resetHostForRevalidation(
    _RouteEntryRecord entry,
    CCRouteIntent<Object?> intent, {
    required String reason,
  }) async {
    final placement = _concreteRouteRevalidationPlacement(entry);
    try {
      await _executeNavigationWithFailurePolicy(
        operation: CCNavigationOperation.reset,
        origin: CCNavigationOrigin.internal,
        openMode: null,
        source: CCNavigationSource.system(reason),
        routeIdHint: intent.routeId,
        placementOverride: placement,
        prepare: () =>
            _routeRegistry.prepareIntent(intent, placementOverride: placement),
        action: (request) => _awaitRuntimeWork(
          () => _requiredNavigationAdapter.navigate(request),
        ),
        coordinateConcurrency: false,
        validateRequest: (request) {
          if (!_routeEntries.contains(entry)) {
            throw const _RouteRevalidationRequestError(
              CCRouteRevalidationOutcome.stale,
            );
          }
          if (request.operation != CCNavigationOperation.reset ||
              request.hostId != entry.request.hostId) {
            throw const _RouteRevalidationRequestError(
              CCRouteRevalidationOutcome.unsupported,
            );
          }
        },
      );
      return CCRouteRevalidationOutcome.reset;
    } on _RouteRevalidationRequestError catch (error) {
      return error.outcome;
    }
  }

  /// Removes one exact Entry without applying user-exit PopGuard semantics.
  Future<CCRouteRevalidationOutcome> _closeRouteEntryForRevalidation(
    _RouteEntryRecord entry,
  ) async {
    final adapter = _requiredNavigationAdapter;
    if (adapter is! CCNavigationTargetedCloseAdapter) {
      return CCRouteRevalidationOutcome.unsupported;
    }
    late final CCRouteCloseOutcome outcome;
    try {
      outcome = await _awaitRuntimeWork(
        () => (adapter as CCNavigationTargetedCloseAdapter).closeNavigation(
          navigationId: entry.request.navigationId,
          hostId: entry.request.hostId,
          navigatorOutlet: entry.request.placement.navigatorOutlet,
        ),
      );
    } on CCRouterError {
      rethrow;
    } catch (error) {
      throw CCNavigationAdapterError(
        'Navigation adapter targeted close failed: ${error.runtimeType}.',
      );
    }
    switch (outcome.status) {
      case CCRouteCloseStatus.closed:
        if (_routeEntries.contains(entry)) {
          _removeRouteEntry(entry, reason: 'routeRevalidation');
        }
        return CCRouteRevalidationOutcome.closed;
      case CCRouteCloseStatus.notFound:
        return CCRouteRevalidationOutcome.stale;
      case CCRouteCloseStatus.unsupported:
      case CCRouteCloseStatus.guardDenied:
        return CCRouteRevalidationOutcome.unsupported;
    }
  }

  /// Replaces only a still-topmost Entry and returns after backend acceptance.
  Future<CCRouteRevalidationOutcome> _replaceRouteEntryForRevalidation(
    _RouteEntryRecord entry,
    CCRouteIntent<Object?> intent, {
    required String reason,
  }) async {
    if (!_isTopRouteEntryInPartition(entry)) {
      return CCRouteRevalidationOutcome.unsupported;
    }
    final placement = _concreteRouteRevalidationPlacement(entry);
    try {
      final accepted = Completer<void>();
      final lifecycle = _executeNavigationWithFailurePolicy(
        operation: CCNavigationOperation.replace,
        origin: CCNavigationOrigin.internal,
        openMode: null,
        source: CCNavigationSource.system(reason),
        routeIdHint: intent.routeId,
        placementOverride: placement,
        prepare: () =>
            _routeRegistry.prepareIntent(intent, placementOverride: placement),
        action: _dispatchRevalidationReplacement,
        coordinateConcurrency: false,
        validateRequest: (request) {
          if (!_routeEntries.contains(entry)) {
            throw const _RouteRevalidationRequestError(
              CCRouteRevalidationOutcome.stale,
            );
          }
          if (!_isTopRouteEntryInPartition(entry)) {
            throw const _RouteRevalidationRequestError(
              CCRouteRevalidationOutcome.unsupported,
            );
          }
          if (request.operation != CCNavigationOperation.replace ||
              request.hostId != entry.request.hostId ||
              request.placement.navigatorOutlet !=
                  entry.request.placement.navigatorOutlet) {
            throw const _RouteRevalidationRequestError(
              CCRouteRevalidationOutcome.unsupported,
            );
          }
        },
        onEntryCommitted: (_) {
          if (!accepted.isCompleted) accepted.complete();
        },
      );
      unawaited(
        lifecycle.then<void>(
          (_) {
            if (!accepted.isCompleted) accepted.complete();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!accepted.isCompleted) {
              accepted.completeError(error, stackTrace);
            }
          },
        ),
      );
      await _awaitRuntimeWork(() => accepted.future);
      return CCRouteRevalidationOutcome.replaced;
    } on _RouteRevalidationRequestError catch (error) {
      return error.outcome;
    }
  }

  /// Requires proof of synchronous Backend commit before reporting replacement.
  ///
  /// A legacy result Future cannot distinguish rejection from an open page.
  /// Unsupported adapters are rejected before mutation; no timing-based guess
  /// or second navigation is used. Recovery reuses this same dispatch strategy.
  Future<Object?> _dispatchRevalidationReplacement(
    CCNavigationRequest request,
  ) {
    final adapter = _requiredNavigationAdapter;
    if (adapter is CCNavigationDispatchAdapter) {
      final receipt = (adapter as CCNavigationDispatchAdapter)
          .dispatchNavigation(request);
      if (receipt != null) return _awaitRuntimeWork(() => receipt.result);
    }
    throw const _RouteRevalidationRequestError(
      CCRouteRevalidationOutcome.unsupported,
    );
  }

  /// Whether [entry] remains the latest Entry in its Host and Outlet.
  bool _isTopRouteEntryInPartition(_RouteEntryRecord entry) {
    for (final candidate in _routeEntries.reversed) {
      if (_sameRouteEntryPartition(candidate, entry)) {
        return identical(candidate, entry);
      }
    }
    return false;
  }

  /// Rebuilds an Entry placement with its resolved concrete Host identity.
  ///
  /// Default-placement requests retain `default` in route metadata while the
  /// immutable request stores the Host selected at admission separately. A
  /// revalidation must preserve that admitted Host across focus changes.
  CCRoutePlacement _concreteRouteRevalidationPlacement(
    _RouteEntryRecord entry,
  ) => CCRoutePlacement(
    hostId: entry.request.hostId,
    parentRouteId: entry.request.placement.parentRouteId,
    shellId: entry.request.placement.shellId,
    navigatorOutlet: entry.request.placement.navigatorOutlet,
  );

  /// Builds one payload-free report item from a Runtime-owned Entry.
  CCRouteRevalidationEntryResult _routeRevalidationResult(
    _RouteEntryRecord entry,
    CCRouteRevalidationOutcome outcome, {
    String? policyId,
  }) => CCRouteRevalidationEntryResult(
    routeEntryId: entry.id,
    routeId: entry.request.routeId,
    hostId: entry.request.hostId,
    navigatorOutlet: entry.request.placement.navigatorOutlet,
    outcome: outcome,
    policyId: policyId,
  );
}
