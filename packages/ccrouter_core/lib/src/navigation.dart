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
      final guarded = _guardedPopOutcome(trigger);
      if (guarded != null) return guarded;
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
      return CCPopOutcome(
        handled: handled,
        trigger: trigger,
        hostId: _activeRouteEntryHostId,
      );
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
    if (backendEntryId == null) {
      _recordUncorrelatedManagedPop(outcome);
      return;
    }
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
  /// [CCNavigationOrigin.internal]. [mode] independently selects whether the
  /// resolved destination is pushed above the current page or becomes the
  /// Host's declarative location. The returned Future represents backend
  /// acceptance, not the destination's eventual Pop result.
  Future<void> openRoute(
    Uri uri, {
    CCNavigationOrigin origin = CCNavigationOrigin.internal,
    CCDeepLinkOpenMode mode = CCDeepLinkOpenMode.push,
    CCNavigationSource? source,
  }) async {
    _ensureInitialized();
    await _executeNavigationWithFailurePolicy(
      operation: CCNavigationOperation.open,
      origin: origin,
      openMode: mode,
      source: source,
      routeIdHint: null,
      prepare: () => _routeRegistry.prepareUri(uri, origin),
      action: (request) => _requiredNavigationAdapter.navigate(request),
    );
  }

  /// Pops the active adapter route with an optional typed [result].
  void popRoute<R>({R? result}) {
    _ensureInitialized();
    try {
      final guarded = _guardedPopOutcome(CCPopTrigger.business);
      if (guarded != null) {
        throw CCPopGuardDeniedError(guarded.guardDeniedCode!);
      }
      final adapter = _requiredNavigationAdapter;
      if (adapter is CCNavigationPopCoordinator) {
        final coordinator = adapter as CCNavigationPopCoordinator;
        final outcome = coordinator
            .popOutcome(result: result)
            .copyWith(trigger: CCPopTrigger.business);
        _applyManagedPopOutcome(outcome);
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
    final result = await _executeNavigationWithFailurePolicy(
      operation: operation,
      origin: CCNavigationOrigin.internal,
      openMode: null,
      source: source,
      routeIdHint: intent.routeId,
      prepare: () => _routeRegistry.prepareIntent(intent),
      action: (request) => _requiredNavigationAdapter.navigate(request),
    );
    try {
      return result as R?;
    } on TypeError {
      throw CCRouteResultTypeError(intent.routeId);
    }
  }

  /// Executes a typed navigation operation that has no business result.
  Future<void> _navigateWithoutResult<R>(
    CCNavigationOperation operation,
    CCRouteIntent<R> intent,
    CCNavigationSource? source,
  ) async {
    _ensureInitialized();
    await _executeNavigationWithFailurePolicy(
      operation: operation,
      origin: CCNavigationOrigin.internal,
      openMode: null,
      source: source,
      routeIdHint: intent.routeId,
      prepare: () => _routeRegistry.prepareIntent(intent),
      action: (request) => _requiredNavigationAdapter.navigate(request),
    );
  }

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
    CCDeepLinkOpenMode? openMode,
    CCNavigationSource? source, {
    String? navigationId,
    required Future<Object?> Function(CCNavigationRequest request) action,
    void Function(_RouteEntryRecord entry)? commitEntry,
  }) {
    if (_navigationCallbackActive ||
        identical(
          Zone.current[CCRouterRuntime._navigationCallbackZoneKey],
          this,
        )) {
      return Future<Object?>.error(const CCNavigationReentrancyError());
    }
    final key = _navigationConcurrencyKey(operation, prepared, openMode);
    final existing = _inFlightNavigation[key];
    switch (navigationConcurrencyPolicy) {
      case CCNavigationConcurrencyPolicy.allow:
        break;
      case CCNavigationConcurrencyPolicy.rejectDuplicate:
        if (existing != null) {
          throw CCNavigationDuplicateError(prepared.routeId);
        }
      case CCNavigationConcurrencyPolicy.singleFlight:
        if (existing != null) return existing;
    }
    final pending = _dispatchNavigationUncoordinated(
      operation,
      prepared,
      origin,
      openMode,
      source,
      navigationId: navigationId,
      action: action,
      commitEntry: commitEntry,
    );
    if (navigationConcurrencyPolicy != CCNavigationConcurrencyPolicy.allow) {
      _inFlightNavigation[key] = pending;
      void clear() {
        if (identical(_inFlightNavigation[key], pending)) {
          _inFlightNavigation.remove(key);
        }
      }

      unawaited(pending.then<void>((_) => clear(), onError: (_, _) => clear()));
    }
    return pending;
  }

  /// Runs one navigation after the concurrency gate has admitted it.
  Future<Object?> _dispatchNavigationUncoordinated(
    CCNavigationOperation operation,
    _PreparedRoute prepared,
    CCNavigationOrigin origin,
    CCDeepLinkOpenMode? openMode,
    CCNavigationSource? source, {
    String? navigationId,
    required Future<Object?> Function(CCNavigationRequest request) action,
    void Function(_RouteEntryRecord entry)? commitEntry,
  }) async {
    final effectiveNavigationId =
        navigationId ?? '$_runtimeId-navigation-${++_navigationSequence}';
    final cancellation = CCCancellationToken();
    var current = prepared;
    var redirectDepth = 0;
    while (true) {
      final request = _buildNavigationRequest(
        operation,
        current,
        origin,
        openMode,
        source,
        navigationId: effectiveNavigationId,
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
        final interceptClock = Stopwatch()..start();
        late final CCNavigationInterception decision;
        try {
          decision = await _runInterceptors(
            request,
            cancellation: cancellation,
            redirectDepth: redirectDepth,
          );
        } finally {
          interceptClock.stop();
          _recordAspectIntercept(request.navigationId, interceptClock.elapsed);
        }
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
            );
          case CCNavigationCancel(:final code):
            throw CCRouteCancelledError(code);
          case CCNavigationRedirect(:final intent, :final uri):
            if (redirectDepth >= CCRouterRuntime.maxNavigationRedirects) {
              throw CCRouteRedirectLoopError(request.routeId);
            }
            final redirectResolveClock = Stopwatch()..start();
            try {
              if (intent != null) {
                current = _routeRegistry.prepareIntent(intent, origin: origin);
              } else {
                current = _routeRegistry.prepareUri(uri!, origin);
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
    for (final registration in _globalInterceptors) {
      final decision = await _invokeNavigationInterceptor(
        id: registration.id,
        interceptor: registration.interceptor,
        timeout: registration.timeout,
        request: request,
        cancellation: cancellation,
        redirectDepth: redirectDepth,
      );
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
        redirectDepth: redirectDepth,
      );
      if (decision is! CCNavigationProceed) return decision;
    }
    return const CCNavigationProceed();
  }

  /// Executes one interceptor with a fresh deadline and sanitized failures.
  Future<CCNavigationInterception> _invokeNavigationInterceptor({
    required String id,
    required CCNavigationInterceptor interceptor,
    required Duration? timeout,
    required CCNavigationRequest request,
    required CCCancellationToken cancellation,
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
      var pending = Future<CCNavigationInterception>.sync(
        () => interceptor.intercept(context),
      );
      if (timeout != null) {
        pending = pending.timeout(
          timeout,
          onTimeout: () {
            cancellation.cancel();
            throw CCNavigationInterceptorTimeoutError(id);
          },
        );
      }
      return await pending;
    } on CCNavigationInterceptorTimeoutError {
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

  /// Resolves the route's default Host through the active Adapter binding.
  ///
  /// Explicit non-default placement remains unchanged so a single-Host
  /// Adapter can reject requests intended for another Host.
  String _resolveNavigationHostId(CCRoutePlacement placement) {
    if (placement.hostId != 'default') return placement.hostId;
    final adapter = _navigationAdapter;
    if (adapter is CCNavigationAdapterHostBinding) {
      final binding = adapter as CCNavigationAdapterHostBinding;
      if (binding.hostId.isNotEmpty) return binding.hostId;
    }
    return placement.hostId;
  }

  /// Creates the immutable request delivered to one Adapter operation.
  CCNavigationRequest _buildNavigationRequest(
    CCNavigationOperation operation,
    _PreparedRoute prepared,
    CCNavigationOrigin origin,
    CCDeepLinkOpenMode? openMode,
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
    openMode: openMode,
    ownerComponentId: prepared.ownerComponentId,
    hostId: _resolveNavigationHostId(prepared.placement),
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
    try {
      final dispatchClock = Stopwatch()..start();
      late final Future<Object?> pending;
      try {
        pending = action();
      } finally {
        dispatchClock.stop();
        _recordAspectDispatch(request.navigationId, dispatchClock.elapsed);
      }
      if (entry != null) {
        (commitEntry ?? _commitRouteEntry)(entry);
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
