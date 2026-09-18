part of 'runtime.dart';

/// Executes the Runtime-owned navigation AOP hooks.
extension CCRouterRuntimeNavigationAspects on CCRouterRuntime {
  /// Returns whether any aspect can affect or observe navigation.
  bool get _hasNavigationAspects => _navigationAspects.isNotEmpty;

  /// Runs decision-capable aspect hooks in deterministic ID order.
  Future<CCNavigationInterception> _runAspectBefore(
    CCNavigationRequest request, {
    required CCCancellationToken cancellation,
    required int redirectDepth,
  }) async {
    if (!_hasNavigationAspects) return const CCNavigationProceed();
    final context = CCNavigationAspectContext(
      request: _aspectRequest(request),
      cancellation: cancellation,
      redirectDepth: redirectDepth,
    );
    for (final aspect in _navigationAspects) {
      final before = aspect.before;
      if (before == null) continue;
      final decision = await before(context);
      if (decision is! CCNavigationProceed) return decision;
    }
    return const CCNavigationProceed();
  }

  /// Emits a matched-route observation after Runtime resolution.
  void _emitAspectFound(CCNavigationRequest request) {
    _emitAspectEvent(
      CCNavigationAspectEvent(
        phase: CCNavigationAspectPhase.found,
        request: _aspectRequest(request),
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Emits a managed Route Entry arrival observation.
  void _emitAspectArrival(_RouteEntryRecord entry) {
    _emitAspectEvent(
      CCNavigationAspectEvent(
        phase: CCNavigationAspectPhase.arrival,
        request: _aspectRequest(entry.request),
        entry: entry.snapshot,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Emits a failed or cancelled navigation observation.
  void _emitAspectLost(
    CCNavigationRequest request, {
    required CCNavigationAspectOutcome outcome,
    String? errorType,
  }) {
    _emitAspectEvent(
      CCNavigationAspectEvent(
        phase: CCNavigationAspectPhase.lost,
        request: _aspectRequest(request),
        outcome: outcome,
        errorType: errorType,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Emits the terminal observation for one navigation request.
  void _emitAspectAfter(
    CCNavigationRequest request, {
    required CCNavigationAspectOutcome outcome,
    String? errorType,
  }) {
    _emitAspectEvent(
      CCNavigationAspectEvent(
        phase: CCNavigationAspectPhase.after,
        request: _aspectRequest(request),
        outcome: outcome,
        errorType: errorType,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Converts an internal request into the safe aspect snapshot.
  CCNavigationAspectRequest _aspectRequest(CCNavigationRequest request) =>
      CCNavigationAspectRequest(
        navigationId: request.navigationId,
        operation: request.operation,
        routeId: request.routeId,
        uri: request.uri,
        placement: request.placement,
        origin: request.origin,
        source: request.source,
        presentation: request.presentation,
      );

  /// Dispatches an aspect event while isolating callback failures.
  void _emitAspectEvent(CCNavigationAspectEvent event) {
    for (final aspect in _navigationAspects) {
      final observer = switch (event.phase) {
        CCNavigationAspectPhase.found => aspect.onFound,
        CCNavigationAspectPhase.arrival => aspect.onArrival,
        CCNavigationAspectPhase.lost => aspect.onLost,
        CCNavigationAspectPhase.after => aspect.onAfter,
      };
      if (observer == null) continue;
      try {
        observer(event);
      } catch (error) {
        if (traceCapacity > 0) {
          if (_subscriberErrors.length == traceCapacity) {
            _subscriberErrors.removeAt(0);
          }
          _subscriberErrors.add(
            CCInvocationError('Navigation aspect failed: ${error.runtimeType}'),
          );
        }
      }
    }
  }
}
