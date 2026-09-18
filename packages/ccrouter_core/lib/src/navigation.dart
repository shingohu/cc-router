part of 'runtime.dart';

/// Adds adapter-neutral navigation execution to [CCRouterRuntime].
///
/// Framework hosts use these methods behind `CCRouter.navigator`. Low-level Core
/// tests may call them directly; application business code must not retain or
/// invoke a Runtime instance.
extension CCRouterRuntimeNavigation on CCRouterRuntime {
  /// Pushes a typed [intent] and completes with its eventual Pop result.
  Future<R?> pushRoute<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
  }) => _navigateForResult(CCNavigationOperation.push, intent, source);

  /// Replaces the current route and completes with the new route's Pop result.
  Future<R?> replaceRoute<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
  }) => _navigateForResult(CCNavigationOperation.replace, intent, source);

  /// Asks the backend to handle a Pop and reports whether it was handled.
  ///
  /// Use this for system back and gesture handling when the active page may
  /// veto the Pop. It is distinct from [canPopRoute], which only reports stack
  /// capability and cannot account for a backend Pop guard. A successful
  /// backend Pop may consume a foreign Route or LocalHistoryEntry, so Runtime
  /// does not remove a managed Route Entry by stack position. Result-bearing
  /// managed entries close when their Adapter Future completes; complete
  /// identity synchronization is provided by the future Pop coordinator.
  Future<bool> maybePopRoute<R>({R? result}) async {
    final outcome = await maybePopOutcomeRoute(result: result);
    return outcome.handled;
  }

  /// Coordinates a backend Pop and preserves ownership information.
  ///
  /// Use this when system back, a gesture, or a form guard must distinguish a
  /// Managed Route from a foreign Popup or LocalHistoryEntry. Legacy adapters
  /// that expose only the Boolean Pop API are converted to an outcome with
  /// [CCPopRemovedOwner.none]. [trigger] is attached by Runtime so all Pop
  /// sources share one ownership and lifecycle pipeline.
  Future<CCPopOutcome> maybePopOutcomeRoute<R>({
    R? result,
    CCPopTrigger trigger = CCPopTrigger.system,
  }) async {
    _ensureInitialized();
    try {
      final adapter = _requiredNavigationAdapter;
      if (adapter is CCNavigationPopCoordinator) {
        final coordinator = adapter as CCNavigationPopCoordinator;
        final outcome = (await coordinator.maybePopOutcome(
          result: result,
        )).copyWith(trigger: trigger);
        _applyManagedPopOutcome(outcome);
        return outcome;
      }
      final handled = await adapter.maybePop(result: result);
      return CCPopOutcome(handled: handled, trigger: trigger);
    } on CCRouterError {
      rethrow;
    } catch (error) {
      throw CCNavigationAdapterError(
        'Navigation adapter maybePop failed: ${error.runtimeType}.',
      );
    }
  }

  /// Closes a RouteEntry only after the Adapter explicitly confirms ownership.
  void _applyManagedPopOutcome(CCPopOutcome outcome) {
    if (outcome.removedOwner != CCPopRemovedOwner.managed) return;
    final backendEntryId = outcome.removedBackendEntryId;
    if (backendEntryId != null) {
      final backendEntry = _backendEntries[backendEntryId];
      final routeEntryId = backendEntry?.routeEntryId;
      if (routeEntryId != null) {
        for (final entry in _routeEntries.toList()) {
          if (entry.id == routeEntryId) {
            _removeRouteEntry(entry, reason: 'maybePop');
            return;
          }
        }
      }
    }
    // Adapters without a backend ledger may still explicitly guarantee that
    // the active entry was managed. In that narrow case, only the top entry
    // can be reconciled; foreign/opaque outcomes never reach this fallback.
    _removeTopRouteEntry(reason: 'maybePop', preserveRoot: true);
  }

  /// Pops the current route and pushes [intent] as one stack operation.
  ///
  /// [popResult] completes the removed route's pending result. The returned
  /// Future completes with the new route's typed Pop result.
  Future<R?> popAndPushRoute<R>(
    CCRouteIntent<R> intent, {
    Object? popResult,
    CCNavigationSource? source,
  }) async {
    _ensureInitialized();
    _ensureAdapterCapability(
      (capabilities) => capabilities.supportsAtomicPopAndPush,
      'supportsAtomicPopAndPush',
    );
    final prepared = _routeRegistry.prepareIntent(intent);
    final result = await _dispatchNavigationWithAction(
      CCNavigationOperation.popAndPush,
      prepared,
      CCNavigationOrigin.internal,
      source,
      action: (request) =>
          _requiredNavigationAdapter.popAndPush(request, popResult: popResult),
    );
    try {
      return result as R?;
    } on TypeError {
      throw CCRouteResultTypeError(prepared.routeId);
    }
  }

  /// Pops entries until the current entry satisfies [predicate].
  Future<void> popUntilRoute(CCNavigationStackPredicate predicate) async {
    _ensureInitialized();
    try {
      await _requiredNavigationAdapter.popUntil(predicate);
      _popUntilRouteEntries(predicate);
    } on CCRouterError {
      rethrow;
    } catch (error) {
      throw CCNavigationAdapterError(
        'Navigation adapter popUntil failed: ${error.runtimeType}.',
      );
    }
  }

  /// Pushes [intent] and removes previous entries until [predicate] matches.
  Future<R?> pushAndRemoveUntilRoute<R>(
    CCRouteIntent<R> intent,
    CCNavigationStackPredicate predicate, {
    CCNavigationSource? source,
  }) async {
    _ensureInitialized();
    _ensureAdapterCapability(
      (capabilities) => capabilities.supportsPushAndRemoveUntil,
      'supportsPushAndRemoveUntil',
    );
    final prepared = _routeRegistry.prepareIntent(intent);
    final result = await _dispatchNavigationWithAction(
      CCNavigationOperation.pushAndRemoveUntil,
      prepared,
      CCNavigationOrigin.internal,
      source,
      action: (request) =>
          _requiredNavigationAdapter.pushAndRemoveUntil(request, predicate),
      commitEntry: (created) =>
          _commitPushAndRemoveRouteEntry(created, predicate),
    );
    try {
      return result as R?;
    } on TypeError {
      throw CCRouteResultTypeError(prepared.routeId);
    }
  }

  /// Changes the current location to the route targeted by [intent].
  Future<void> goRoute<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
  }) => _navigateWithoutResult(CCNavigationOperation.go, intent, source);

  /// Resets navigation state to the route targeted by [intent].
  Future<void> resetRoute<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
  }) => _navigateWithoutResult(CCNavigationOperation.reset, intent, source);

  /// Resolves and opens a dynamic [uri] under the trusted ingress [origin].
  ///
  /// Framework hosts use an external Origin for platform links, notifications,
  /// or scanned input. Ordinary application calls use
  /// [CCNavigationOrigin.internal].
  Future<void> openRoute(
    Uri uri, {
    CCNavigationOrigin origin = CCNavigationOrigin.internal,
    CCNavigationSource? source,
  }) async {
    _ensureInitialized();
    final prepared = _routeRegistry.prepareUri(uri, origin);
    await _dispatchNavigation(
      CCNavigationOperation.open,
      prepared,
      origin,
      source,
    );
  }

  /// Pops the active adapter route with an optional typed [result].
  void popRoute<R>({R? result}) {
    _ensureInitialized();
    try {
      final adapter = _requiredNavigationAdapter;
      if (adapter is CCNavigationPopCoordinator) {
        final coordinator = adapter as CCNavigationPopCoordinator;
        final outcome = coordinator
            .popOutcome(result: result)
            .copyWith(trigger: CCPopTrigger.business);
        _applyManagedPopOutcome(outcome);
        return;
      }
      // Older adapters do not expose ownership-aware direct Pop results. Keep
      // their historical behavior while newer adapters use the coordinator
      // above to isolate foreign and opaque backend entries.
      adapter.pop(result: result);
      _removeTopRouteEntry(reason: 'pop', preserveRoot: true);
    } on CCRouterError {
      rethrow;
    } catch (error) {
      throw CCNavigationAdapterError(
        'Navigation adapter Pop failed: ${error.runtimeType}.',
      );
    }
  }

  /// Whether the active adapter can currently remove one route.
  bool canPopRoute() {
    _ensureInitialized();
    try {
      return _requiredNavigationAdapter.canPop();
    } on CCRouterError {
      rethrow;
    } catch (error) {
      throw CCNavigationAdapterError(
        'Navigation adapter canPop failed: ${error.runtimeType}.',
      );
    }
  }

  /// Executes a result-bearing typed navigation operation.
  Future<R?> _navigateForResult<R>(
    CCNavigationOperation operation,
    CCRouteIntent<R> intent,
    CCNavigationSource? source,
  ) async {
    _ensureInitialized();
    final prepared = _routeRegistry.prepareIntent(intent);
    final result = await _dispatchNavigation(
      operation,
      prepared,
      CCNavigationOrigin.internal,
      source,
    );
    try {
      return result as R?;
    } on TypeError {
      throw CCRouteResultTypeError(prepared.routeId);
    }
  }

  /// Executes a typed navigation operation that has no business result.
  Future<void> _navigateWithoutResult<R>(
    CCNavigationOperation operation,
    CCRouteIntent<R> intent,
    CCNavigationSource? source,
  ) async {
    _ensureInitialized();
    final prepared = _routeRegistry.prepareIntent(intent);
    await _dispatchNavigation(
      operation,
      prepared,
      CCNavigationOrigin.internal,
      source,
    );
  }

  /// Builds and delivers one validated request to the configured adapter.
  Future<Object?> _dispatchNavigation(
    CCNavigationOperation operation,
    _PreparedRoute prepared,
    CCNavigationOrigin origin,
    CCNavigationSource? source,
  ) => _dispatchNavigationWithAction(
    operation,
    prepared,
    origin,
    source,
    action: (request) => _requiredNavigationAdapter.navigate(request),
  );

  /// Runs the common interception pipeline before one Adapter operation.
  ///
  /// [action] receives the final request after all redirects have been
  /// resolved. Keeping this pipeline shared ensures composite operations such
  /// as PopAndPush and PushAndRemoveUntil enforce the same access policies as
  /// ordinary Push and Replace navigation.
  Future<Object?> _dispatchNavigationWithAction(
    CCNavigationOperation operation,
    _PreparedRoute prepared,
    CCNavigationOrigin origin,
    CCNavigationSource? source, {
    required Future<Object?> Function(CCNavigationRequest request) action,
    void Function(_RouteEntryRecord entry)? commitEntry,
  }) async {
    final navigationId = '$_runtimeId-navigation-${++_navigationSequence}';
    final cancellation = CCCancellationToken();
    var current = prepared;
    var redirectDepth = 0;
    while (true) {
      final request = _buildNavigationRequest(
        operation,
        current,
        origin,
        source,
        navigationId: navigationId,
      );
      _emitAspectFound(request);
      if (!_hasInterceptors(request.routeId)) {
        final entry = _createRouteEntry(request);
        return _dispatchRequest(
          request,
          () => action(request),
          entry: entry,
          commitEntry: commitEntry,
        );
      }
      var adapterDispatchStarted = false;
      try {
        final decision = await _runInterceptors(
          request,
          cancellation: cancellation,
          redirectDepth: redirectDepth,
        );
        switch (decision) {
          case CCNavigationProceed():
            adapterDispatchStarted = true;
            final entry = _createRouteEntry(request);
            return await _dispatchRequest(
              request,
              () => action(request),
              entry: entry,
              commitEntry: commitEntry,
            );
          case CCNavigationCancel(:final code):
            throw CCRouteCancelledError(code);
          case CCNavigationRedirect(:final intent, :final uri):
            if (redirectDepth >= CCRouterRuntime.maxNavigationRedirects) {
              throw CCRouteRedirectLoopError(request.routeId);
            }
            if (intent != null) {
              current = _routeRegistry.prepareIntent(intent, origin: origin);
            } else {
              current = _routeRegistry.prepareUri(uri!, origin);
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
        throw CCNavigationAdapterError(
          'Navigation interceptor failed: ${error.runtimeType}.',
        );
      }
    }
  }

  /// Runs global interceptors followed by the selected route interceptors.
  Future<CCNavigationInterception> _runInterceptors(
    CCNavigationRequest request, {
    required CCCancellationToken cancellation,
    required int redirectDepth,
  }) async {
    final context = CCNavigationInterceptorContext(
      request: request,
      cancellation: cancellation,
      redirectDepth: redirectDepth,
    );
    final aspectDecision = await _runAspectBefore(
      request,
      cancellation: cancellation,
      redirectDepth: redirectDepth,
    );
    if (aspectDecision is! CCNavigationProceed) return aspectDecision;
    for (final registration in _globalInterceptors) {
      final decision = await registration.interceptor.intercept(context);
      if (decision is! CCNavigationProceed) return decision;
    }
    final route = _routeRegistry.routeDefinition(request.routeId);
    for (final id in route.interceptorIds) {
      final registration = _routeInterceptors[id]!;
      final decision = await registration.interceptor.intercept(context);
      if (decision is! CCNavigationProceed) return decision;
    }
    return const CCNavigationProceed();
  }

  /// Returns whether this request needs the asynchronous interception pass.
  bool _hasInterceptors(String routeId) {
    if (_globalInterceptors.isNotEmpty || _hasNavigationAspects) return true;
    return _routeRegistry.routeDefinition(routeId).interceptorIds.isNotEmpty;
  }

  /// Creates the immutable request delivered to one Adapter operation.
  CCNavigationRequest _buildNavigationRequest(
    CCNavigationOperation operation,
    _PreparedRoute prepared,
    CCNavigationOrigin origin,
    CCNavigationSource? source, {
    String? navigationId,
  }) => CCNavigationRequest(
    navigationId:
        navigationId ?? '$_runtimeId-navigation-${++_navigationSequence}',
    operation: operation,
    routeId: prepared.routeId,
    uri: prepared.uri,
    arguments: prepared.arguments,
    extra: prepared.extra,
    presentation: prepared.presentation,
    placement: prepared.placement,
    origin: origin,
    ownerComponentId: prepared.ownerComponentId,
    source: source,
  );

  /// Normalizes Adapter failures while preserving framework errors.
  Future<Object?> _dispatchRequest(
    CCNavigationRequest request,
    Future<Object?> Function() action, {
    _RouteEntryRecord? entry,
    void Function(_RouteEntryRecord entry)? commitEntry,
  }) async {
    _emitNavigationEvent(request, CCNavigationLifecyclePhase.requested);
    var committed = false;
    try {
      final pending = action();
      if (entry != null) {
        (commitEntry ?? _commitRouteEntry)(entry);
        committed = true;
      }
      final result = await pending;
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
      if (entry != null && !committed) {
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
      if (entry != null && !committed) {
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

  /// Rejects an operation when an optional capability-aware Adapter declares
  /// that its backend cannot preserve the requested contract.
  ///
  /// Adapters without capability metadata remain backward compatible and are
  /// responsible for reporting their own unsupported-operation errors.
  void _ensureAdapterCapability(
    bool Function(CCNavigationAdapterCapabilities capabilities) selector,
    String capabilityName,
  ) {
    final adapter = _requiredNavigationAdapter;
    final capabilitySource = adapter is CCNavigationAdapterCapabilitySource
        ? adapter as CCNavigationAdapterCapabilitySource
        : null;
    if (capabilitySource != null && !selector(capabilitySource.capabilities)) {
      throw CCNavigationAdapterError(
        'Navigation adapter does not support $capabilityName.',
      );
    }
  }
}
