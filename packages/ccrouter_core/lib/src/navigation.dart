part of 'runtime.dart';

/// Adds adapter-neutral navigation execution to [CCRouterRuntime].
///
/// Framework hosts use these methods behind `CCRouter.navigator`. Low-level Core
/// tests may call them directly; application business code must not retain or
/// invoke a Runtime instance.
extension CCRouterRuntimeNavigation on CCRouterRuntime {
  /// Pushes a typed [intent] and completes with its eventual Pop result.
  ///
  /// A Host-only Flutter facade may pass [placementOverride] after resolving a
  /// call-site Outlet. The route's explicit non-root placement always wins;
  /// Core never reads a Flutter `BuildContext`. A supplied Host ID is concrete,
  /// including `default`; omit the override to follow the active Adapter Host.
  Future<R?> pushRoute<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
    CCRoutePlacement? placementOverride,
  }) => _navigateForResult(
    CCNavigationOperation.push,
    intent,
    source,
    placementOverride,
  );

  /// Replaces the current route and completes with the new route's Pop result.
  ///
  /// [placementOverride] is an optional Host-layer placement for a route that
  /// uses the default root placement. It is ignored for explicit route
  /// placement and has no effect on the result contract.
  Future<R?> replaceRoute<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
    CCRoutePlacement? placementOverride,
  }) => _navigateForResult(
    CCNavigationOperation.replace,
    intent,
    source,
    placementOverride,
  );

  /// Asks the backend to handle a Pop and reports whether it was handled.
  ///
  /// Use this for system back and gesture handling when the active page may
  /// veto the Pop. It is distinct from [canPopRoute], which only reports stack
  /// capability and cannot account for a backend Pop guard. A successful
  /// backend Pop may consume a foreign Route or LocalHistoryEntry, so Runtime
  /// does not remove a managed Route Entry by stack position. Result-bearing
  /// managed entries close when their Adapter Future completes; complete
  /// identity synchronization is provided by the future Pop coordinator.
  Future<bool> maybePopRoute<R>({
    R? result,
    CCRoutePlacement? placementOverride,
  }) async {
    final outcome = await maybePopOutcomeRoute(
      result: result,
      placementOverride: placementOverride,
    );
    return outcome.handled;
  }

  /// Coordinates a backend Pop and preserves ownership information.
  ///
  /// Use this when system back, a gesture, or a form guard must distinguish a
  /// Managed Route from a foreign Popup or LocalHistoryEntry. Legacy adapters
  /// that expose only the Boolean Pop API are converted to an outcome with
  /// [CCPopRemovedEntryOwner.none]. [trigger] is attached by Runtime so all Pop
  /// sources share one ownership and lifecycle pipeline.
  /// Host or Runtime retirement consumes the request without removing an Entry;
  /// it never waits for an unfinished external Adapter Future or retries Back
  /// against a replacement Host. Registration is captured before synchronous
  /// Guard evaluation. The producer runs in the Runtime's Host Zone.
  Future<CCPopOutcome> maybePopOutcomeRoute<R>({
    R? result,
    CCPopTrigger trigger = CCPopTrigger.system,
    CCRoutePlacement? placementOverride,
  }) async {
    _ensureNavigationCanStart();
    _ensureInitialized();
    try {
      final target = _popTargetForPlacement(placementOverride);
      final hostId = target?.hostId ?? _activeRouteEntryHostId ?? 'default';
      final registration = _popRegistrationForHost(hostId);
      final retired = CCPopOutcome(
        handled: true,
        hostId: hostId,
        navigatorOutlet: target?.navigatorOutlet,
      );
      final guarded = _guardedPopOutcome(trigger, target: target);
      if (guarded != null) return guarded;
      // A synchronous Guard may indirectly retire its Host. Its allow decision
      // authorizes only the original registration, never a same-ID replacement.
      if (_disposed || registration.isCancelled) return retired;
      final adapter = _requiredNavigationAdapter;
      if (target != null && adapter is CCNavigationScopedPopCoordinator) {
        final outcome = (await _awaitNavigationBackend(
          () => (adapter as CCNavigationScopedPopCoordinator).maybePopOutcomeAt(
            hostId: target.hostId,
            navigatorOutlet: target.navigatorOutlet,
            result: result,
          ),
          registration: registration,
          retired: retired,
        )).copyWith(trigger: trigger);
        _applyManagedPopOutcome(outcome, registration: registration);
        return outcome;
      }
      if (adapter is CCNavigationPopCoordinator) {
        final coordinator = adapter as CCNavigationPopCoordinator;
        final outcome = (await _awaitNavigationBackend(
          () => coordinator.maybePopOutcome(result: result),
          registration: registration,
          retired: retired,
        )).copyWith(trigger: trigger);
        _applyManagedPopOutcome(outcome, registration: registration);
        return outcome;
      }
      final handled = await _awaitNavigationBackend(
        () => adapter.maybePop(result: result),
        registration: registration,
        retired: true,
      );
      return CCPopOutcome(
        handled: handled,
        trigger: trigger,
        hostId: hostId,
        navigatorOutlet: target?.navigatorOutlet,
      );
    } on CCRouterError {
      rethrow;
    } catch (error) {
      throw CCNavigationAdapterError(
        'Navigation adapter maybePop failed: ${error.runtimeType}.',
      );
    }
  }

  /// Establishes the exact Host lifetime before entering child Pop SPI.
  ///
  /// A detached registration remains cancelled when its logical ID is reused.
  /// Initial and foreign stacks need this identity even without prior navigation.
  CCCancellationToken _popRegistrationForHost(String hostId) {
    _ensureNavigationAlive();
    return _navigationHostRegistration(hostId);
  }

  /// Applies an ownership-confirmed Pop only within its original live lifetime.
  ///
  /// A late receipt after Host detach or shutdown may still report its original
  /// outcome, but cannot mutate replacement state or desynchronization metadata.
  void _applyManagedPopOutcome(
    CCPopOutcome outcome, {
    CCCancellationToken? registration,
  }) {
    if (_disposed || registration?.isCancelled == true) return;
    if (outcome.removedEntryOwner != CCPopRemovedEntryOwner.managed) return;
    final backendEntryId = outcome.removedBackendEntryId;
    if (backendEntryId == null) {
      _recordUncorrelatedManagedPop(outcome);
      return;
    }
    final backendEntry = _backendEntries[backendEntryId];
    if (backendEntry != null &&
        (backendEntry.owner != CCBackendEntryOwner.managed ||
            (outcome.hostId != null &&
                backendEntry.hostId != null &&
                outcome.hostId != backendEntry.hostId) ||
            (outcome.navigatorOutlet != null &&
                outcome.navigatorOutlet != backendEntry.navigatorOutlet))) {
      _recordUncorrelatedManagedPop(outcome);
      return;
    }
    final routeEntryId = backendEntry?.routeEntryId;
    if (routeEntryId != null) {
      for (final entry in _routeEntries.toList()) {
        if (entry.id == routeEntryId) {
          _removeRouteEntry(entry, reason: 'maybePop');
          return;
        }
      }
    }
    if (_usesManagedRemovalConfirmationFor(
      outcome.hostId ?? _activeRouteEntryHostId ?? 'default',
    )) {
      _recordUncorrelatedManagedPop(outcome);
    }
  }

  /// Records an identity contract violation without guessing a RouteEntry.
  ///
  /// A managed outcome without an associated ledger Entry may have consumed a
  /// foreign route, a sibling Outlet, or an already removed page. Marking the
  /// Host desynchronized keeps the failure observable while preserving every
  /// managed Scope until a later exact event or result Future resolves it.
  void _recordUncorrelatedManagedPop(CCPopOutcome outcome) {
    final hostId = outcome.hostId ?? _activeRouteEntryHostId;
    if (hostId != null) _desynchronizedBackendHosts.add(hostId);
  }

  /// Changes the current location to the route targeted by [intent].
  ///
  /// [placementOverride] is supplied only by a Host integration after strict
  /// call-site resolution; it never changes an explicit route placement.
  Future<void> goRoute<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
    CCRoutePlacement? placementOverride,
  }) => _navigateWithoutResult(
    CCNavigationOperation.go,
    intent,
    source,
    placementOverride,
  );

  /// Resets navigation state to the route targeted by [intent].
  ///
  /// [placementOverride] is supplied only by a Host integration after strict
  /// call-site resolution; it never changes an explicit route placement.
  Future<void> resetRoute<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
    CCRoutePlacement? placementOverride,
  }) => _navigateWithoutResult(
    CCNavigationOperation.reset,
    intent,
    source,
    placementOverride,
  );

  /// Resolves and opens a dynamic [uri] under the trusted ingress [origin].
  ///
  /// Framework hosts use an external Origin for platform links, notifications,
  /// or scanned input. Ordinary application calls use
  /// [CCNavigationOrigin.internal]. [mode] independently selects whether the
  /// resolved destination is pushed above the current page or becomes the
  /// Host's declarative location. The returned Future represents backend
  /// acceptance, not the destination's eventual Pop result.
  ///
  /// [placementOverride] is an optional Host-layer placement for a route that
  /// uses the default root placement. It does not weaken external ingress
  /// policy or change an explicit route placement.
  /// Host Router bindings may supply [requestCancellation] to supersede a
  /// platform location. Ordinary business navigation leaves this unset.
  Future<void> openRoute(
    Uri uri, {
    CCNavigationOrigin origin = CCNavigationOrigin.internal,
    CCDeepLinkOpenMode mode = CCDeepLinkOpenMode.push,
    CCNavigationSource? source,
    CCRoutePlacement? placementOverride,
    CCCancellationToken? requestCancellation,
  }) async {
    _ensureInitialized();
    await _executeNavigationWithFailurePolicy(
      operation: CCNavigationOperation.open,
      origin: origin,
      openMode: mode,
      source: source,
      routeIdHint: null,
      placementOverride: placementOverride,
      requestCancellation: requestCancellation,
      prepare: () => _routeRegistry.prepareUri(
        uri,
        origin,
        placementOverride: placementOverride,
      ),
      action: (request) => _requiredNavigationAdapter.navigate(request),
    );
  }

  /// Pops the active adapter route with an optional typed [result].
  ///
  /// Guard evaluation cannot transfer this request to a replacement Host:
  /// retirement of the captured registration consumes the original Pop.
  void popRoute<R>({R? result, CCRoutePlacement? placementOverride}) {
    _ensureNavigationCanStart();
    _ensureInitialized();
    try {
      final target = _popTargetForPlacement(placementOverride);
      final registration = _popRegistrationForHost(
        target?.hostId ?? _activeRouteEntryHostId ?? 'default',
      );
      final guarded = _guardedPopOutcome(CCPopTrigger.business, target: target);
      if (guarded != null) {
        throw CCPopGuardDeniedError(guarded.guardDeniedCode!);
      }
      if (_disposed || registration.isCancelled) return;
      final adapter = _requiredNavigationAdapter;
      if (target != null && adapter is CCNavigationScopedPopCoordinator) {
        final outcome = (adapter as CCNavigationScopedPopCoordinator)
            .popOutcomeAt(
              hostId: target.hostId,
              navigatorOutlet: target.navigatorOutlet,
              result: result,
            )
            .copyWith(trigger: CCPopTrigger.business);
        _applyManagedPopOutcome(outcome, registration: registration);
        return;
      }
      if (adapter is CCNavigationPopCoordinator) {
        final coordinator = adapter as CCNavigationPopCoordinator;
        final outcome = coordinator
            .popOutcome(result: result)
            .copyWith(trigger: CCPopTrigger.business);
        _applyManagedPopOutcome(outcome, registration: registration);
        return;
      }
      // Legacy adapters cannot prove which backend Entry they removed. Their
      // result-bearing navigation Future may still close the matching Runtime
      // Entry, but Runtime never mutates managed state by stack position.
      adapter.pop(result: result);
    } on CCRouterError {
      rethrow;
    } catch (error) {
      throw CCNavigationAdapterError(
        'Navigation adapter Pop failed: ${error.runtimeType}.',
      );
    }
  }

  /// Closes one Runtime-issued entry without disturbing covering pages.
  ///
  /// Managed guards evaluate the selected entry with a business trigger. A
  /// malformed result throws before removal; stale/foreign handles and adapters
  /// without the optional capability return explicit outcomes. Ordinary Pop
  /// semantics remain independent of this operation.
  /// Losing the original Entry, Host or Runtime ends a pending external wait
  /// with `notFound`. Already completing exact receipts retain their outcome;
  /// outgoing animation lifetime cannot extend this wait. Adapter work runs in
  /// the Runtime's Host Zone and late completion cannot revive the Entry.
  Future<CCRouteCloseOutcome> closeRoute<R>(
    CCRouteEntryHandle handle, {
    R? result,
  }) async {
    _ensureNavigationCanStart();
    _ensureInitialized();
    _RouteEntryRecord? entry;
    for (final candidate in _routeEntries) {
      if (identical(candidate.handle, handle)) {
        entry = candidate;
        break;
      }
    }
    if (entry == null) {
      return const CCRouteCloseOutcome(CCRouteCloseStatus.notFound);
    }
    entry.validateResult?.call(result);
    final decision = _evaluatePopGuardsForEntry(entry, CCPopTrigger.business);
    if (decision is CCPopDeny) {
      return CCRouteCloseOutcome(
        CCRouteCloseStatus.guardDenied,
        guardDeniedCode: decision.code,
      );
    }
    if (!_routeEntries.contains(entry) || _disposed) {
      return const CCRouteCloseOutcome(CCRouteCloseStatus.notFound);
    }
    final adapter = _requiredNavigationAdapter;
    if (adapter is! CCNavigationTargetedCloseAdapter) {
      return const CCRouteCloseOutcome(CCRouteCloseStatus.unsupported);
    }
    try {
      final request = entry.request;
      final registration = _popRegistrationForHost(request.hostId);
      final outcome = await _awaitNavigationBackend(
        () => (adapter as CCNavigationTargetedCloseAdapter).closeNavigation(
          navigationId: request.navigationId,
          hostId: request.hostId,
          navigatorOutlet: request.placement.navigatorOutlet,
          result: result,
        ),
        registration: registration,
        entryRemoval: entry.removal,
        retired: const CCRouteCloseOutcome(CCRouteCloseStatus.notFound),
      );
      if (outcome.status == CCRouteCloseStatus.closed) {
        _removeRouteEntry(entry, reason: 'targetedClose');
      }
      return outcome;
    } on CCRouterError {
      rethrow;
    } catch (error) {
      throw CCNavigationAdapterError(
        'Navigation adapter targeted close failed: ${error.runtimeType}.',
      );
    }
  }

  /// Whether the active adapter can currently remove one route.
  bool canPopRoute({CCRoutePlacement? placementOverride}) {
    _ensureInitialized();
    try {
      final target = _popTargetForPlacement(placementOverride);
      final adapter = _requiredNavigationAdapter;
      if (target != null && adapter is CCNavigationScopedPopCoordinator) {
        return (adapter as CCNavigationScopedPopCoordinator).canPopAt(
          hostId: target.hostId,
          navigatorOutlet: target.navigatorOutlet,
        );
      }
      return adapter.canPop();
    } on CCRouterError {
      rethrow;
    } catch (error) {
      throw CCNavigationAdapterError(
        'Navigation adapter canPop failed: ${error.runtimeType}.',
      );
    }
  }

  /// Converts an optional Host placement into a stable Pop target.
  CCNavigationPopTarget? _popTargetForPlacement(CCRoutePlacement? placement) {
    if (placement == null) return null;
    final adapter = _requiredNavigationAdapter;
    if (adapter is CCNavigationScopedPopTargetSource) {
      final target = (adapter as CCNavigationScopedPopTargetSource).popTargetAt(
        hostId: placement.hostId,
        navigatorOutlet: placement.navigatorOutlet,
      );
      if (target != null) return target;
    }
    return CCNavigationPopTarget(
      hostId: placement.hostId,
      navigatorOutlet: placement.navigatorOutlet,
    );
  }

  /// Executes a result-bearing typed navigation operation.
  Future<R?> _navigateForResult<R>(
    CCNavigationOperation operation,
    CCRouteIntent<R> intent,
    CCNavigationSource? source,
    CCRoutePlacement? placementOverride,
  ) async {
    _ensureInitialized();
    final result = await _executeNavigationWithFailurePolicy(
      operation: operation,
      origin: CCNavigationOrigin.internal,
      openMode: null,
      source: source,
      routeIdHint: intent.routeId,
      placementOverride: placementOverride,
      prepare: () => _routeRegistry.prepareIntent(
        intent,
        placementOverride: placementOverride,
      ),
      action: (request) => _requiredNavigationAdapter.navigate(request),
      validateResult: (result) {
        try {
          result as R?;
        } on TypeError {
          throw CCRouteResultTypeError(intent.routeId);
        }
      },
    );
    return result as R?;
  }

  /// Executes a typed navigation operation that has no business result.
  Future<void> _navigateWithoutResult<R>(
    CCNavigationOperation operation,
    CCRouteIntent<R> intent,
    CCNavigationSource? source,
    CCRoutePlacement? placementOverride,
  ) async {
    _ensureInitialized();
    await _executeNavigationWithFailurePolicy(
      operation: operation,
      origin: CCNavigationOrigin.internal,
      openMode: null,
      source: source,
      routeIdHint: intent.routeId,
      placementOverride: placementOverride,
      prepare: () => _routeRegistry.prepareIntent(
        intent,
        placementOverride: placementOverride,
      ),
      action: (request) => _requiredNavigationAdapter.navigate(request),
    );
  }

  /// Runs the common interception pipeline before one Adapter operation.
  ///
  /// [action] receives the final request after all redirects have been
  /// resolved. Keeping this pipeline shared ensures Push, Replace, Go, Reset,
  /// and dynamic Open apply the same concurrency and access-policy boundaries.
  /// [onInterceptorRedirect] marks a redirect before its replacement target
  /// is resolved, so Failure Policy diagnostics can retain the correct attempt
  /// category without exposing redirect payloads.
  /// [coordinateConcurrency] is false only for framework reconciliation whose
  /// exact source identity cannot share another request's result.
  Future<Object?> _dispatchNavigationWithAction(
    CCNavigationOperation operation,
    _PreparedRoute prepared,
    CCNavigationOrigin origin,
    CCDeepLinkOpenMode? openMode,
    CCNavigationSource? source, {
    String? navigationId,
    CCRoutePlacement? placementOverride,
    required Future<Object?> Function(CCNavigationRequest request) action,
    void Function(_RouteEntryRecord entry)? commitEntry,
    void Function(_RouteEntryRecord entry)? onEntryCommitted,
    void Function(Object? result)? validateResult,
    bool coordinateConcurrency = true,
    CCCancellationToken? requestCancellation,
    void Function(String routeId)? onAttempt,
    void Function()? onInterceptorRedirect,
  }) {
    if (!coordinateConcurrency ||
        prepared.extra != null ||
        requestCancellation != null) {
      return _dispatchNavigationUncoordinated(
        operation,
        prepared,
        origin,
        openMode,
        source,
        navigationId: navigationId,
        placementOverride: placementOverride,
        action: action,
        commitEntry: commitEntry,
        onEntryCommitted: onEntryCommitted,
        validateResult: validateResult,
        requestCancellation: requestCancellation,
        onAttempt: onAttempt,
        onInterceptorRedirect: onInterceptorRedirect,
      );
    }
    final key = _navigationConcurrencyKey(
      operation,
      prepared,
      origin,
      openMode,
    );
    final existing = _inFlightNavigation[key];
    switch (navigationConcurrencyPolicy) {
      case CCNavigationConcurrencyPolicy.allow:
        break;
      case CCNavigationConcurrencyPolicy.rejectDuplicate:
        if (existing != null) {
          final request = _buildNavigationRequest(
            operation,
            prepared,
            origin,
            openMode,
            source,
            navigationId: navigationId,
          );
          final error = CCNavigationDuplicateError(prepared.routeId);
          _emitAspectFound(request);
          _emitShortCircuitedNavigationFailure(request, error);
          throw error;
        }
      case CCNavigationConcurrencyPolicy.singleFlight:
        if (existing != null) {
          final request = _buildNavigationRequest(
            operation,
            prepared,
            origin,
            openMode,
            source,
            navigationId: navigationId,
          );
          _emitAspectFound(request);
          return _observeSharedNavigation(request, existing);
        }
    }
    final shared =
        navigationConcurrencyPolicy == CCNavigationConcurrencyPolicy.allow
        ? null
        : _SharedResult<Object?>();
    if (shared != null) _inFlightNavigation[key] = shared;
    final pending = _dispatchNavigationUncoordinated(
      operation,
      prepared,
      origin,
      openMode,
      source,
      navigationId: navigationId,
      placementOverride: placementOverride,
      action: action,
      commitEntry: commitEntry,
      onEntryCommitted: onEntryCommitted,
      validateResult: validateResult,
      onAttempt: onAttempt,
      onInterceptorRedirect: onInterceptorRedirect,
    );
    if (shared != null) {
      void Function()? removeOwnershipCancellation;
      void clear() {
        if (identical(_inFlightNavigation[key], shared)) {
          _inFlightNavigation.remove(key);
        }
        removeOwnershipCancellation?.call();
        removeOwnershipCancellation = null;
      }

      // Redirects may have visited a different Host from the initial key.
      // Clear on any captured registration's detach before admitting retries.
      removeOwnershipCancellation = _navigationOperation?.cancellation
          .addListener(clear);
      // Register in the producer's Zone and retire admission before either the
      // original caller or shared waiters can immediately attempt another call.
      unawaited(pending.then<void>((_) => clear(), onError: (_, _) => clear()));
      shared.follow(pending);
    }
    return pending;
  }

  /// Publishes the terminal state of a request rejected before interception.
  void _emitShortCircuitedNavigationFailure(
    CCNavigationRequest request,
    CCRouterError error,
  ) {
    final errorType = error.runtimeType.toString();
    _emitAspectLost(
      request,
      outcome: CCNavigationAspectOutcome.failed,
      errorType: errorType,
    );
    _emitAspectAfter(
      request,
      outcome: CCNavigationAspectOutcome.failed,
      errorType: errorType,
    );
    _emitNavigationEvent(request, CCNavigationLifecyclePhase.requested);
    _emitNavigationEvent(
      request,
      CCNavigationLifecyclePhase.failed,
      errorType: errorType,
    );
  }

  /// Mirrors one admitted request's result into a distinct shared observation.
  ///
  /// The shared request has its own navigation identity but does not allocate a
  /// Route Entry or emit Arrival. Its terminal result follows the first request
  /// while preserving the original error object and stack trace for callers.
  Future<Object?> _observeSharedNavigation(
    CCNavigationRequest request,
    _SharedResult<Object?> shared,
  ) async {
    _emitNavigationEvent(request, CCNavigationLifecyclePhase.requested);
    try {
      final result = await shared.wait();
      _emitAspectAfter(request, outcome: CCNavigationAspectOutcome.succeeded);
      _emitNavigationEvent(request, CCNavigationLifecyclePhase.completed);
      return result;
    } catch (error, stackTrace) {
      final errorType = error.runtimeType.toString();
      final outcome = error is CCRouteCancelledError
          ? CCNavigationAspectOutcome.cancelled
          : CCNavigationAspectOutcome.failed;
      _emitAspectLost(request, outcome: outcome, errorType: errorType);
      _emitAspectAfter(request, outcome: outcome, errorType: errorType);
      _emitNavigationEvent(
        request,
        CCNavigationLifecyclePhase.failed,
        errorType: errorType,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Runs one navigation after the concurrency gate has admitted it.
  ///
  /// [onInterceptorRedirect] is an internal diagnostic hook only; it never
  /// changes the selected navigation operation or adapter behavior.
  /// Default-Host redirects remain in the initially selected concrete Host;
  /// explicitly placed destinations may still select another Host.
  Future<Object?> _dispatchNavigationUncoordinated(
    CCNavigationOperation operation,
    _PreparedRoute prepared,
    CCNavigationOrigin origin,
    CCDeepLinkOpenMode? openMode,
    CCNavigationSource? source, {
    String? navigationId,
    CCRoutePlacement? placementOverride,
    required Future<Object?> Function(CCNavigationRequest request) action,
    void Function(_RouteEntryRecord entry)? commitEntry,
    void Function(_RouteEntryRecord entry)? onEntryCommitted,
    void Function(Object? result)? validateResult,
    CCCancellationToken? requestCancellation,
    void Function(String routeId)? onAttempt,
    void Function()? onInterceptorRedirect,
  }) async {
    final effectiveNavigationId =
        navigationId ?? '$_runtimeId-navigation-${++_navigationSequence}';
    final cancellation = CCCancellationToken();
    final navigationHostId = _resolveNavigationHostId(prepared.placement);
    var current = prepared;
    var redirectDepth = 0;
    while (true) {
      current = _bindPreparedNavigationHost(current, navigationHostId);
      _bindNavigationHost(_resolveNavigationHostId(current.placement));
      var request = _buildNavigationRequest(
        operation,
        current,
        origin,
        openMode,
        source,
        navigationId: effectiveNavigationId,
      );
      onAttempt?.call(request.routeId);
      _emitAspectFound(request);
      var adapterDispatchStarted = false;
      try {
        _ensureNavigationAlive(cancellation);
        _ensureNavigationRequestAlive(requestCancellation);
        final parents = _prepareParentStack(request, current);
        if (parents.isNotEmpty) {
          request = _buildNavigationRequest(
            operation,
            current,
            origin,
            openMode,
            source,
            navigationId: effectiveNavigationId,
            parentStack: parents,
          );
        }
        if (![
          ...parents,
          request,
        ].any((item) => _hasInterceptors(item.routeId))) {
          adapterDispatchStarted = true;
          final entry = _createRouteEntry(request);
          return _dispatchRequest(
            request,
            () => action(request),
            requestCancellation: requestCancellation,
            entry: entry,
            commitEntry: commitEntry,
            onEntryCommitted: onEntryCommitted,
            validateResult: validateResult,
          );
        }
        final interceptClock = Stopwatch()..start();
        late CCNavigationInterceptorDecision decision;
        try {
          decision = const CCNavigationProceed();
          for (final candidate in [...parents, request]) {
            if (!_hasInterceptors(candidate.routeId)) continue;
            decision = await _runInterceptors(
              candidate,
              cancellation: cancellation,
              requestCancellation: requestCancellation,
              redirectDepth: redirectDepth,
            );
            _ensureNavigationAlive(cancellation);
            _ensureNavigationRequestAlive(requestCancellation);
            if (decision is! CCNavigationProceed) break;
          }
        } finally {
          interceptClock.stop();
          _recordAspectIntercept(request.navigationId, interceptClock.elapsed);
        }
        _ensureNavigationAlive(cancellation);
        _ensureNavigationRequestAlive(requestCancellation);
        switch (decision) {
          case CCNavigationProceed():
            adapterDispatchStarted = true;
            final entry = _createRouteEntry(request);
            return await _dispatchRequest(
              request,
              () => action(request),
              requestCancellation: requestCancellation,
              entry: entry,
              commitEntry: commitEntry,
              onEntryCommitted: onEntryCommitted,
              validateResult: validateResult,
            );
          case CCNavigationDefer(:final code, :final timeout):
            return _deferNavigation(
              request,
              operation: operation,
              prepared: current,
              origin: origin,
              openMode: openMode,
              source: source,
              code: code,
              timeout: timeout,
              action: action,
              commitEntry: commitEntry,
              onEntryCommitted: onEntryCommitted,
              placementOverride: placementOverride,
              validateResult: validateResult,
              requestCancellation: requestCancellation,
            );
          case CCNavigationCancel(:final code):
            throw CCRouteCancelledError(code);
          case CCNavigationRedirect(:final intent, :final uri):
            onInterceptorRedirect?.call();
            if (redirectDepth >= CCRouterRuntime.maxNavigationRedirects) {
              throw CCRouteRedirectLoopError(request.routeId);
            }
            final redirectResolveClock = Stopwatch()..start();
            try {
              if (intent != null) {
                onAttempt?.call(intent.routeId);
                current = _routeRegistry.prepareIntent(
                  intent,
                  origin: origin,
                  placementOverride: placementOverride,
                );
              } else {
                current = _routeRegistry.prepareUri(
                  uri!,
                  origin,
                  placementOverride: placementOverride,
                );
              }
            } finally {
              redirectResolveClock.stop();
              _recordAspectResolve(
                request.navigationId,
                redirectResolveClock.elapsed,
              );
            }
            redirectDepth++;
        }
      } on CCRouterError catch (error) {
        if (!adapterDispatchStarted) {
          final outcome = error is CCRouteCancelledError
              ? CCNavigationAspectOutcome.cancelled
              : CCNavigationAspectOutcome.failed;
          _emitAspectLost(
            request,
            outcome: outcome,
            errorType: error.runtimeType.toString(),
          );
          _emitAspectAfter(
            request,
            outcome: outcome,
            errorType: error.runtimeType.toString(),
          );
          _emitNavigationEvent(request, CCNavigationLifecyclePhase.requested);
          _emitNavigationEvent(
            request,
            CCNavigationLifecyclePhase.failed,
            errorType: error.runtimeType.toString(),
          );
        }
        rethrow;
      } catch (error) {
        if (!adapterDispatchStarted) {
          _emitAspectLost(
            request,
            outcome: CCNavigationAspectOutcome.failed,
            errorType: error.runtimeType.toString(),
          );
          _emitAspectAfter(
            request,
            outcome: CCNavigationAspectOutcome.failed,
            errorType: error.runtimeType.toString(),
          );
          _emitNavigationEvent(request, CCNavigationLifecyclePhase.requested);
          _emitNavigationEvent(
            request,
            CCNavigationLifecyclePhase.failed,
            errorType: error.runtimeType.toString(),
          );
        }
        if (error is _RouteRevalidationRequestError) rethrow;
        throw CCNavigationAdapterError(
          'Navigation interceptor failed: ${error.runtimeType}.',
        );
      }
    }
  }

  /// Runs global interceptors followed by the selected route interceptors.
  Future<CCNavigationInterceptorDecision> _runInterceptors(
    CCNavigationRequest request, {
    required CCCancellationToken cancellation,
    CCCancellationToken? requestCancellation,
    required int redirectDepth,
  }) async {
    for (final registration in _globalInterceptors) {
      final decision = await _invokeNavigationInterceptor(
        id: registration.id,
        interceptor: registration.interceptor,
        timeout: registration.timeout,
        request: request,
        cancellation: cancellation,
        requestCancellation: requestCancellation,
        redirectDepth: redirectDepth,
      );
      _ensureNavigationAlive(cancellation);
      _ensureNavigationRequestAlive(requestCancellation);
      if (decision is! CCNavigationProceed) return decision;
    }
    final route = _routeRegistry.routeDefinition(request.routeId);
    for (final id in route.interceptorIds) {
      final registration = _routeInterceptors[id]!;
      final decision = await _invokeNavigationInterceptor(
        id: id,
        interceptor: registration.interceptor,
        timeout: registration.timeout,
        request: request,
        cancellation: cancellation,
        requestCancellation: requestCancellation,
        redirectDepth: redirectDepth,
      );
      _ensureNavigationAlive(cancellation);
      _ensureNavigationRequestAlive(requestCancellation);
      if (decision is! CCNavigationProceed) return decision;
    }
    return const CCNavigationProceed();
  }

  /// Executes one interceptor with a fresh deadline and sanitized failures.
  Future<CCNavigationInterceptorDecision> _invokeNavigationInterceptor({
    required String id,
    required CCNavigationInterceptor interceptor,
    required Duration? timeout,
    required CCNavigationRequest request,
    required CCCancellationToken cancellation,
    CCCancellationToken? requestCancellation,
    required int redirectDepth,
  }) async {
    final deadline = timeout == null ? null : DateTime.now().add(timeout);
    final context = CCNavigationInterceptorContext(
      request: request,
      cancellation: cancellation,
      redirectDepth: redirectDepth,
      deadline: deadline,
    );
    try {
      return await _awaitNavigationDecision(
        () => interceptor.intercept(context),
        cancellation: cancellation,
        requestCancellation: requestCancellation,
        timeout: timeout,
        timeoutError: CCNavigationInterceptorTimeoutError(id),
      );
    } on CCNavigationInterceptorTimeoutError {
      rethrow;
    } on CCRouteCancelledError {
      rethrow;
    } catch (error) {
      throw CCNavigationInterceptorError(id, error.runtimeType.toString());
    }
  }

  /// Returns whether this request needs the asynchronous interception pass.
  bool _hasInterceptors(String routeId) {
    if (_globalInterceptors.isNotEmpty) return true;
    return _routeRegistry.routeDefinition(routeId).interceptorIds.isNotEmpty;
  }

  /// Resolves default placement through the operation snapshot, then Adapter.
  ///
  /// Explicit non-default placement remains unchanged so a single-Host
  /// Adapter can reject requests intended for another Host. A captured real
  /// Host named `default` must not be interpreted as the declaration sentinel.
  String _resolveNavigationHostId(CCRoutePlacement placement) {
    if (placement.hostId != 'default') return placement.hostId;
    final captured = _navigationOperation?.defaultHostId;
    if (captured != null) return captured;
    final adapter = _navigationAdapter;
    if (adapter is CCNavigationAdapterHostBinding) {
      final binding = adapter as CCNavigationAdapterHostBinding;
      if (binding.hostId.isNotEmpty) return binding.hostId;
    }
    return placement.hostId;
  }

  /// Copies placement topology while selecting one operation-owned Host.
  ///
  /// Passing this as the call-site default lets the registry preserve explicit
  /// destination Hosts independently of Parent, Shell and Outlet resolution.
  CCRoutePlacement _navigationPlacementForHost(
    CCRoutePlacement? placement,
    String hostId,
  ) => CCRoutePlacement(
    hostId: hostId,
    parentRouteId: placement?.parentRouteId,
    shellId: placement?.shellId,
    navigatorOutlet: placement?.navigatorOutlet ?? 'root',
  );

  /// Binds only a prepared route's default Host without changing its topology.
  ///
  /// The operation owns [hostId] across asynchronous policy and recovery. A
  /// destination's explicit Host still wins; Parent, Shell, Outlet, arguments
  /// and Extra remain exactly as resolved by the registry.
  _PreparedRoute _bindPreparedNavigationHost(
    _PreparedRoute prepared,
    String hostId,
  ) {
    final placement = prepared.placement;
    if (placement.hostId != 'default' || placement.hostId == hostId) {
      return prepared;
    }
    return _PreparedRoute(
      routeId: prepared.routeId,
      ownerComponentId: prepared.ownerComponentId,
      uri: prepared.uri,
      pathParameters: prepared.pathParameters,
      arguments: prepared.arguments,
      extra: prepared.extra,
      presentation: prepared.presentation,
      placement: _navigationPlacementForHost(placement, hostId),
      interceptorIds: prepared.interceptorIds,
      popGuardIds: prepared.popGuardIds,
      typed: prepared.typed,
    );
  }

  /// Creates the immutable request delivered to one Adapter operation.
  CCNavigationRequest _buildNavigationRequest(
    CCNavigationOperation operation,
    _PreparedRoute prepared,
    CCNavigationOrigin origin,
    CCDeepLinkOpenMode? openMode,
    CCNavigationSource? source, {
    String? navigationId,
    List<CCNavigationRequest> parentStack = const [],
  }) => CCNavigationRequest(
    navigationId:
        navigationId ?? '$_runtimeId-navigation-${++_navigationSequence}',
    operation: operation,
    routeId: prepared.routeId,
    uri: prepared.uri,
    pathParameters: prepared.pathParameters,
    arguments: prepared.arguments,
    extra: prepared.extra,
    presentation: prepared.presentation,
    placement: prepared.placement,
    origin: origin,
    openMode: openMode,
    ownerComponentId: prepared.ownerComponentId,
    hostId: _resolveNavigationHostId(prepared.placement),
    source: source,
    parentStack: parentStack,
  );

  /// Normalizes Adapter failures and fences synchronous external reentrancy.
  ///
  /// An Adapter can detach its Host or end Runtime during its synchronous
  /// acceptance callback. Such a return cannot commit an Entry for the retired
  /// lifetime; its eventual Future is consumed without waiting for cleanup.
  Future<Object?> _dispatchRequest(
    CCNavigationRequest request,
    Future<Object?> Function() action, {
    CCCancellationToken? requestCancellation,
    _RouteEntryRecord? entry,
    void Function(_RouteEntryRecord entry)? commitEntry,
    void Function(_RouteEntryRecord entry)? onEntryCommitted,
    void Function(Object? result)? validateResult,
  }) async {
    _emitNavigationEvent(request, CCNavigationLifecyclePhase.requested);
    try {
      final dispatchClock = Stopwatch()..start();
      entry?.validateResult = validateResult;
      late final Future<Object?> pending;
      try {
        pending = action();
      } finally {
        dispatchClock.stop();
        _recordAspectDispatch(request.navigationId, dispatchClock.elapsed);
      }
      try {
        _ensureNavigationRequestAlive(requestCancellation);
        if (entry != null) {
          if (commitEntry == null) {
            _commitRouteEntry(entry, requestCancellation: requestCancellation);
          } else {
            commitEntry(entry);
          }
          _ensureNavigationRequestAlive(requestCancellation);
          _commitParentStack(entry, request.parentStack);
          onEntryCommitted?.call(entry);
        }
      } catch (_) {
        // Rejection must not strand a late Adapter error or wait for a result
        // that only ends after Backend disposal. Backend work owns its cleanup.
        unawaited(
          pending.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
        );
        rethrow;
      }
      final result = await pending;
      validateResult?.call(result);
      if (entry != null &&
          request.operation != CCNavigationOperation.go &&
          request.operation != CCNavigationOperation.reset &&
          request.operation != CCNavigationOperation.open) {
        _completeRouteEntry(entry);
      }
      if (entry != null) {
        _emitAspectAfter(request, outcome: CCNavigationAspectOutcome.succeeded);
      }
      _emitNavigationEvent(request, CCNavigationLifecyclePhase.completed);
      return result;
    } on CCRouterError catch (error) {
      // Adapter Futures represent both immediate acceptance and eventual
      // route results. If either phase fails, the newly allocated entry must
      // be discarded so its Scope and pending lifecycle cannot leak. An
      // adapter that mutates an existing backend stack before reporting an
      // error must provide its own atomic rollback or capability boundary;
      // Runtime never guesses how to recreate an older entry.
      if (entry != null) {
        _removeRouteEntry(entry, reason: 'failed');
      }
      final outcome = error is CCRouteCancelledError
          ? CCNavigationAspectOutcome.cancelled
          : CCNavigationAspectOutcome.failed;
      if (entry != null) {
        _emitAspectLost(
          request,
          outcome: outcome,
          errorType: error.runtimeType.toString(),
        );
        _emitAspectAfter(
          request,
          outcome: outcome,
          errorType: error.runtimeType.toString(),
        );
      }
      _emitNavigationEvent(
        request,
        CCNavigationLifecyclePhase.failed,
        errorType: error.runtimeType.toString(),
      );
      rethrow;
    } catch (error) {
      if (entry != null) {
        _removeRouteEntry(entry, reason: 'failed');
      }
      if (entry != null) {
        _emitAspectLost(
          request,
          outcome: CCNavigationAspectOutcome.failed,
          errorType: error.runtimeType.toString(),
        );
        _emitAspectAfter(
          request,
          outcome: CCNavigationAspectOutcome.failed,
          errorType: error.runtimeType.toString(),
        );
      }
      _emitNavigationEvent(
        request,
        CCNavigationLifecyclePhase.failed,
        errorType: error.runtimeType.toString(),
      );
      if (error is _RouteRevalidationRequestError) rethrow;
      throw CCNavigationAdapterError(
        'Navigation adapter failed: ${error.runtimeType}.',
      );
    }
  }

  /// Returns the configured adapter or reports a host configuration failure.
  CCNavigationAdapter get _requiredNavigationAdapter {
    final adapter = _navigationAdapter;
    if (adapter == null) {
      throw const CCNavigationAdapterError(
        'No navigation adapter is configured for this Runtime.',
      );
    }
    return adapter;
  }
}
