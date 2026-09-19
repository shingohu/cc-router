part of 'runtime.dart';

/// Applies Host-owned recovery to sanitized navigation failures.
extension CCRouterRuntimeNavigationFailure on CCRouterRuntime {
  /// Maximum number of fallback or redirect decisions in one failure chain.
  static const int _maxNavigationFailureRecoveries = 4;

  /// Returns a bounded snapshot of sanitized navigation failure decisions.
  List<CCNavigationFailureEvent> get recentNavigationFailures =>
      List.unmodifiable(_navigationFailures);

  /// Subscribes to sanitized failure decisions.
  ///
  /// The returned callback removes the listener. Listener failures are
  /// isolated and never alter the selected recovery or original error.
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
    required CCNavigationSource? source,
    required String? routeIdHint,
    required _PreparedRoute Function() prepare,
    required Future<Object?> Function(CCNavigationRequest request) action,
    void Function(_RouteEntryRecord entry)? commitEntry,
  }) async {
    final navigationId = '$_runtimeId-navigation-${++_navigationSequence}';
    _beginNavigationObservation(navigationId);
    var recoveryDepth = 0;
    var currentOperation = operation;
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
                source,
                navigationId: navigationId,
                action: currentAction,
                commitEntry: currentCommitEntry,
              )
            : _dispatchNavigationUncoordinated(
                currentOperation,
                prepared,
                origin,
                source,
                navigationId: navigationId,
                action: currentAction,
                commitEntry: currentCommitEntry,
              ));
        return suppressRecoveryResult ? null : result;
      } catch (error, stackTrace) {
        final policy = navigationFailurePolicy;
        if (policy == null) {
          if (prepared == null) _discardNavigationObservation(navigationId);
          rethrow;
        }
        final context = CCNavigationFailureContext(
          navigationId: navigationId,
          operation: operation,
          routeId:
              prepared?.routeId ??
              currentRouteIdHint ??
              _navigationFailureRouteId(error),
          origin: origin,
          source: source,
          stage: _navigationFailureStage(error),
          errorType: error.runtimeType.toString(),
          recoveryDepth: recoveryDepth,
        );
        late final CCNavigationFailureDecision decision;
        try {
          decision = await runZoned(
            () => Future<CCNavigationFailureDecision>.sync(
              () => policy.onFailure(context),
            ),
            zoneValues: {CCRouterRuntime._navigationCallbackZoneKey: this},
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
        final target = _failureRecoveryTarget(decision);
        _validateFailureRecoveryOperation(target.operation);
        _emitNavigationFailure(context, recovered: true);
        recoveryDepth++;
        currentOperation = target.operation;
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

  /// Normalizes redirect and fallback decisions into one internal target.
  ({CCRouteIntent<Object?>? intent, Uri? uri, CCNavigationOperation operation})
  _failureRecoveryTarget(
    CCNavigationFailureDecision decision,
  ) => switch (decision) {
    CCNavigationFailureRedirect(:final intent, :final uri, :final operation) =>
      (intent: intent, uri: uri, operation: operation),
    CCNavigationFailureFallback(:final intent, :final uri, :final operation) =>
      (intent: intent, uri: uri, operation: operation),
    CCNavigationFailurePropagate() => throw StateError(
      'A propagate decision has no recovery target.',
    ),
  };

  /// Rejects composite or Pop-only operations for failure recovery.
  void _validateFailureRecoveryOperation(CCNavigationOperation operation) {
    switch (operation) {
      case CCNavigationOperation.push:
      case CCNavigationOperation.replace:
      case CCNavigationOperation.go:
      case CCNavigationOperation.reset:
      case CCNavigationOperation.open:
        return;
      case CCNavigationOperation.popAndPush:
      case CCNavigationOperation.pushAndRemoveUntil:
      case CCNavigationOperation.replaceBelow:
        throw const CCNavigationAdapterError(
          'Failure recovery requires a non-composite navigation operation.',
        );
    }
  }

  /// Maps framework errors to one stable failure stage.
  CCNavigationFailureStage _navigationFailureStage(Object error) =>
      switch (error) {
        CCRouteNotFoundError() ||
        CCRouteAmbiguityError() ||
        CCRouteUnavailableError() ||
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
    for (final listener in _navigationFailureListeners.toList()) {
      try {
        listener(event);
      } catch (error) {
        _recordNavigationCallbackFailure(
          'Navigation failure listener failed: ${error.runtimeType}.',
        );
      }
    }
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
