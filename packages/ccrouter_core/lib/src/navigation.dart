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

  /// Attempts to pop the current route and reports whether it was removed.
  ///
  /// Use this for system back and gesture handling when the active page may
  /// veto the Pop. It is distinct from [canPopRoute], which only reports stack
  /// capability and cannot account for a backend Pop guard.
  Future<bool> maybePopRoute<R>({R? result}) async {
    _ensureInitialized();
    try {
      return await _requiredNavigationAdapter.maybePop(result: result);
    } on CCRouterError {
      rethrow;
    } catch (error) {
      throw CCNavigationAdapterError(
        'Navigation adapter maybePop failed: ${error.runtimeType}.',
      );
    }
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
    final prepared = _routeRegistry.prepareIntent(intent);
    final request = _buildNavigationRequest(
      CCNavigationOperation.popAndPush,
      prepared,
      CCNavigationOrigin.internal,
      source,
    );
    final result = await _dispatchRequest(
      request,
      () =>
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
    final prepared = _routeRegistry.prepareIntent(intent);
    final request = _buildNavigationRequest(
      CCNavigationOperation.pushAndRemoveUntil,
      prepared,
      CCNavigationOrigin.internal,
      source,
    );
    final result = await _dispatchRequest(
      request,
      () => _requiredNavigationAdapter.pushAndRemoveUntil(request, predicate),
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
      _requiredNavigationAdapter.pop(result: result);
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
  ) async {
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
      if (!_hasInterceptors(request.routeId)) {
        return _dispatchRequest(
          request,
          () => _requiredNavigationAdapter.navigate(request),
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
            return await _dispatchRequest(
              request,
              () => _requiredNavigationAdapter.navigate(request),
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
    if (_globalInterceptors.isNotEmpty) return true;
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
    source: source,
  );

  /// Normalizes Adapter failures while preserving framework errors.
  Future<Object?> _dispatchRequest(
    CCNavigationRequest request,
    Future<Object?> Function() action,
  ) async {
    _emitNavigationEvent(request, CCNavigationLifecyclePhase.requested);
    try {
      final result = await action();
      _emitNavigationEvent(request, CCNavigationLifecyclePhase.completed);
      return result;
    } on CCRouterError catch (error) {
      _emitNavigationEvent(
        request,
        CCNavigationLifecyclePhase.failed,
        errorType: error.runtimeType.toString(),
      );
      rethrow;
    } catch (error) {
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
