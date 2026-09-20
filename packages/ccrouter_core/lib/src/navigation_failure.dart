part of 'runtime.dart';

/// Records sanitized navigation failures and applies optional Host recovery.
extension CCRouterRuntimeNavigationFailure on CCRouterRuntime {
  /// Maximum number of fallback or redirect decisions in one failure chain.
  static const int _maxNavigationFailureRecoveries = 4;

  /// Returns a bounded snapshot of sanitized navigation failure outcomes.
  List<CCNavigationFailureEvent> get recentNavigationFailures =>
      List.unmodifiable(_navigationFailures);

  /// Subscribes to sanitized failure outcomes.
  ///
  /// Terminal events are delivered by the bounded FIFO observer queue. The
  /// returned callback removes the listener and cancels its queued deliveries.
  /// Listener failures never alter the selected recovery or original error.
  void Function() addNavigationFailureListener(
    CCNavigationFailureListener listener,
  ) {
    _ensureInitialized();
    _navigationFailureListeners.add(listener);
    return () => _navigationFailureListeners.remove(listener);
  }

  /// Resolves, dispatches, and optionally recovers one target navigation.
  Future<Object?> _executeNavigationWithFailurePolicy({
    required CCNavigationOperation operation,
    required CCNavigationOrigin origin,
    required CCDeepLinkOpenMode? openMode,
    required CCNavigationSource? source,
    required String? routeIdHint,
    required _PreparedRoute Function() prepare,
    required Future<Object?> Function(CCNavigationRequest request) action,
    void Function(_RouteEntryRecord entry)? commitEntry,
  }) async {
    _ensureNavigationCanStart();
    final effectiveSource = _validatedNavigationSource(source);
    final navigationId = '$_runtimeId-navigation-${++_navigationSequence}';
    _beginNavigationObservation(navigationId);
    var recoveryDepth = 0;
    var currentOperation = operation;
    var currentOpenMode = openMode;
    var currentRouteIdHint = routeIdHint;
    var currentPrepare = prepare;
    var currentAction = action;
    var currentCommitEntry = commitEntry;
    var suppressRecoveryResult = false;

    while (true) {
      _PreparedRoute? prepared;
      try {
        final resolveClock = Stopwatch()..start();
        try {
          prepared = currentPrepare();
        } finally {
          resolveClock.stop();
          _recordAspectResolve(navigationId, resolveClock.elapsed);
        }
        final result = await (recoveryDepth == 0
            ? _dispatchNavigationWithAction(
                currentOperation,
                prepared,
                origin,
                currentOpenMode,
                effectiveSource,
                navigationId: navigationId,
                action: currentAction,
                commitEntry: currentCommitEntry,
              )
            : _dispatchNavigationUncoordinated(
                currentOperation,
                prepared,
                origin,
                currentOpenMode,
                effectiveSource,
                navigationId: navigationId,
                action: currentAction,
                commitEntry: currentCommitEntry,
              ));
        return suppressRecoveryResult ? null : result;
      } catch (error, stackTrace) {
        final context = CCNavigationFailureContext(
          navigationId: navigationId,
          operation: operation,
          routeId:
              prepared?.routeId ??
              currentRouteIdHint ??
              _navigationFailureRouteId(error),
          origin: origin,
          openMode: openMode,
          source: effectiveSource,
          stage: _navigationFailureStage(error),
          errorType: error.runtimeType.toString(),
          recoveryDepth: recoveryDepth,
        );
        final policy = navigationFailurePolicy;
        if (policy == null) {
          _emitNavigationFailure(context, recovered: false);
          if (prepared == null) _discardNavigationObservation(navigationId);
          rethrow;
        }
        late final CCNavigationFailureDecision decision;
        try {
          decision = await _runAsyncNavigationDecisionCallback(
            () => policy.onFailure(context),
          );
        } catch (policyError) {
          _recordNavigationCallbackFailure(
            'Navigation failure policy failed: ${policyError.runtimeType}.',
          );
          _emitNavigationFailure(context, recovered: false);
          if (prepared == null) _discardNavigationObservation(navigationId);
          Error.throwWithStackTrace(error, stackTrace);
        }
        if (decision is CCNavigationFailurePropagate) {
          _emitNavigationFailure(context, recovered: false);
          if (prepared == null) _discardNavigationObservation(navigationId);
          rethrow;
        }
        if (recoveryDepth >= _maxNavigationFailureRecoveries) {
          _emitNavigationFailure(context, recovered: false);
          if (prepared == null) _discardNavigationObservation(navigationId);
          throw const CCNavigationFailureRecoveryLoopError();
        }
        final target = _failureRecoveryTarget(
          decision,
          inheritedOperation: currentOperation,
          inheritedOpenMode: currentOpenMode,
        );
        _validateFailureRecoveryOperation(target.operation);
        _emitNavigationFailure(context, recovered: true);
        recoveryDepth++;
        currentOperation = target.operation;
        currentOpenMode = target.openMode;
        currentRouteIdHint = target.intent?.routeId;
        currentPrepare = target.intent == null
            ? () => _routeRegistry.prepareUri(target.uri!, origin)
            : () =>
                  _routeRegistry.prepareIntent(target.intent!, origin: origin);
        currentAction = (request) =>
            _requiredNavigationAdapter.navigate(request);
        currentCommitEntry = null;
        suppressRecoveryResult = decision is CCNavigationFailureFallback;
      }
    }
  }

  /// Removes malformed caller attribution before any observable request data.
  ///
  /// Navigation remains available when attribution is invalid, while a
  /// bounded sanitized diagnostic makes the integration error visible without
  /// retaining the rejected identifier.
  CCNavigationSource? _validatedNavigationSource(CCNavigationSource? source) {
    if (source == null || _isNavigationSourceIdentifier(source.id)) {
      return source;
    }
    _recordNavigationCallbackFailure(
      'Navigation source contained an invalid stable ID.',
    );
    return null;
  }

  /// Normalizes redirect and fallback decisions into one internal target.
  ({
    CCRouteIntent<Object?>? intent,
    Uri? uri,
    CCNavigationOperation operation,
    CCDeepLinkOpenMode? openMode,
  })
  _failureRecoveryTarget(
    CCNavigationFailureDecision decision, {
    required CCNavigationOperation inheritedOperation,
    required CCDeepLinkOpenMode? inheritedOpenMode,
  }) => switch (decision) {
    CCNavigationFailureRedirect(
      :final intent,
      :final uri,
      :final operation,
      :final openMode,
    ) =>
      _resolveFailureRecoveryTarget(
        intent: intent,
        uri: uri,
        operation: operation,
        openMode: openMode,
        inheritedOperation: inheritedOperation,
        inheritedOpenMode: inheritedOpenMode,
      ),
    CCNavigationFailureFallback(
      :final intent,
      :final uri,
      :final operation,
      :final openMode,
    ) =>
      _resolveFailureRecoveryTarget(
        intent: intent,
        uri: uri,
        operation: operation,
        openMode: openMode,
        inheritedOperation: inheritedOperation,
        inheritedOpenMode: inheritedOpenMode,
      ),
    CCNavigationFailurePropagate() => throw StateError(
      'A propagate decision has no recovery target.',
    ),
  };

  /// Resolves inherited versus explicitly overridden recovery stack behavior.
  ({
    CCRouteIntent<Object?>? intent,
    Uri? uri,
    CCNavigationOperation operation,
    CCDeepLinkOpenMode? openMode,
  })
  _resolveFailureRecoveryTarget({
    required CCRouteIntent<Object?>? intent,
    required Uri? uri,
    required CCNavigationOperation? operation,
    required CCDeepLinkOpenMode? openMode,
    required CCNavigationOperation inheritedOperation,
    required CCDeepLinkOpenMode? inheritedOpenMode,
  }) {
    final resolvedOperation = operation ?? inheritedOperation;
    final resolvedOpenMode = resolvedOperation == CCNavigationOperation.open
        ? operation == null
              ? inheritedOpenMode ?? CCDeepLinkOpenMode.push
              : openMode ?? CCDeepLinkOpenMode.push
        : null;
    return (
      intent: intent,
      uri: uri,
      operation: resolvedOperation,
      openMode: resolvedOpenMode,
    );
  }

  /// Validates operations accepted by failure recovery.
  void _validateFailureRecoveryOperation(CCNavigationOperation operation) {
    switch (operation) {
      case CCNavigationOperation.push:
      case CCNavigationOperation.replace:
      case CCNavigationOperation.go:
      case CCNavigationOperation.reset:
      case CCNavigationOperation.open:
        return;
    }
  }

  /// Maps framework errors to one stable failure stage.
  CCNavigationFailureStage _navigationFailureStage(Object error) =>
      switch (error) {
        CCRouteNotFoundError() ||
        CCRouteAmbiguityError() ||
        CCRouteUnavailableError() ||
        CCDeepLinkIngressRejectedError() ||
        CCDeepLinkRejectedError() => CCNavigationFailureStage.resolution,
        CCRouteParameterError() => CCNavigationFailureStage.parameters,
        CCRouteCancelledError() ||
        CCRouteRedirectLoopError() ||
        CCNavigationInterceptorError() ||
        CCNavigationInterceptorTimeoutError() =>
          CCNavigationFailureStage.interception,
        CCNavigationAdapterError() => CCNavigationFailureStage.dispatch,
        CCRouteResultTypeError() => CCNavigationFailureStage.result,
        _ => CCNavigationFailureStage.unknown,
      };

  /// Extracts only stable route identity carried by selected framework errors.
  String? _navigationFailureRouteId(Object error) => switch (error) {
    CCRouteUnavailableError(:final routeId) ||
    CCDeepLinkRejectedError(:final routeId) => routeId,
    _ => null,
  };

  /// Records and publishes one bounded sanitized failure event.
  void _emitNavigationFailure(
    CCNavigationFailureContext context, {
    required bool recovered,
  }) {
    final event = CCNavigationFailureEvent(
      context: context,
      timestamp: DateTime.now(),
      recovered: recovered,
    );
    if (navigationDiagnosticCapacity > 0) {
      if (_navigationFailures.length == navigationDiagnosticCapacity) {
        _navigationFailures.removeFirst();
      }
      _navigationFailures.add(event);
    }
    _enqueueNavigationObserverBatch(
      _navigationFailureListeners,
      (listener) => listener(event),
      isActive: _navigationFailureListeners.contains,
      failureLabel: 'Navigation failure listener',
      critical: true,
    );
  }

  /// Retains a bounded sanitized framework callback failure.
  void _recordNavigationCallbackFailure(String message) {
    if (traceCapacity == 0) return;
    if (_subscriberErrors.length == traceCapacity) {
      _subscriberErrors.removeAt(0);
    }
    _subscriberErrors.add(CCInvocationError(message));
  }
}
