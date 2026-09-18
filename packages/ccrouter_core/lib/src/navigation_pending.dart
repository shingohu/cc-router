part of 'runtime.dart';

/// Internal continuation retained while an interceptor waits for host policy.
final class _PendingNavigationRecord {
  /// Creates a continuation from the already validated navigation payload.
  _PendingNavigationRecord({
    required this.request,
    required this.operation,
    required this.prepared,
    required this.origin,
    required this.source,
    required this.createdAt,
    required this.completer,
    this.code = 'deferred',
    this.expiresAt,
  });

  /// Original request identity used for diagnostics and resume correlation.
  final CCNavigationRequest request;

  /// Operation to replay when the continuation resumes.
  final CCNavigationOperation operation;

  /// Fully decoded target retained inside Runtime.
  final _PreparedRoute prepared;

  /// Trusted origin retained for the second interception pass.
  final CCNavigationOrigin origin;

  /// Product attribution retained for diagnostics.
  final CCNavigationSource? source;

  /// Reason supplied by the interceptor.
  final String code;

  /// Time at which the continuation was created.
  final DateTime createdAt;

  /// Optional expiration time.
  final DateTime? expiresAt;

  /// Completes the original typed navigation Future after resume or cancel.
  final Completer<Object?> completer;

  /// Timer responsible for bounded retention when a timeout was requested.
  Timer? timer;

  /// Converts internal state into a safe public snapshot.
  CCPendingNavigation get snapshot => CCPendingNavigation(
    navigationId: request.navigationId,
    operation: operation,
    routeId: request.routeId,
    uri: request.uri,
    origin: origin,
    source: source,
    createdAt: createdAt,
    expiresAt: expiresAt,
  );
}

/// Exposes generic pending-navigation continuation controls.
extension CCRouterRuntimePendingNavigation on CCRouterRuntime {
  /// Returns pending continuations awaiting an external policy decision.
  ///
  /// Authentication, consent, onboarding, and device-unlock hosts may inspect
  /// this list and choose one ID to resume or cancel. The returned snapshots do
  /// not expose typed arguments, `extra`, Widgets, or backend objects.
  List<CCPendingNavigation> get pendingNavigations => List.unmodifiable(
    _pendingNavigations.values.map((item) => item.snapshot),
  );

  /// Stores one deferred request and returns its original result Future.
  Future<Object?> _deferNavigation(
    CCNavigationRequest request, {
    required CCNavigationOperation operation,
    required _PreparedRoute prepared,
    required CCNavigationOrigin origin,
    required CCNavigationSource? source,
    required String code,
    required Duration? timeout,
  }) {
    final completer = Completer<Object?>();
    if (_disposed) {
      completer.completeError(const CCRouteCancelledError('runtime_disposed'));
      return completer.future;
    }
    final now = DateTime.now();
    final expiresAt = timeout == null ? null : now.add(timeout);
    final record = _PendingNavigationRecord(
      request: request,
      operation: operation,
      prepared: prepared,
      origin: origin,
      source: source,
      code: code,
      createdAt: now,
      expiresAt: expiresAt,
      completer: completer,
    );
    _pendingNavigations[request.navigationId] = record;
    if (timeout != null) {
      record.timer = Timer(timeout, () {
        _cancelPendingNavigationInternal(
          request.navigationId,
          code: 'pending_timeout',
        );
      });
    }
    return completer.future;
  }

  /// Re-runs the saved navigation through resolution, policy, and Adapter.
  ///
  /// Resuming preserves the original navigation ID and typed payload while
  /// executing the complete interception chain again. A policy that still
  /// returns [CCNavigationDefer] creates a fresh bounded continuation.
  Future<Object?> resumePendingNavigation(String navigationId) async {
    _ensureInitialized();
    final record = _pendingNavigations.remove(navigationId);
    if (record == null) throw const CCNavigationPendingNotFoundError();
    record.timer?.cancel();
    var dispatchStarted = false;
    try {
      final resolved = _routeRegistry.prepareUri(
        record.request.uri,
        record.origin,
      );
      if (resolved.routeId != record.request.routeId) {
        throw CCRouteUnavailableError(record.request.routeId);
      }
      final replay = _PreparedRoute(
        routeId: resolved.routeId,
        ownerComponentId: resolved.ownerComponentId,
        uri: resolved.uri,
        arguments: resolved.arguments,
        extra: record.prepared.extra,
        presentation: resolved.presentation,
        placement: resolved.placement,
        interceptorIds: resolved.interceptorIds,
      );
      dispatchStarted = true;
      final result = await _dispatchNavigationUncoordinated(
        record.operation,
        replay,
        record.origin,
        record.source,
        navigationId: record.request.navigationId,
        action: (request) => _requiredNavigationAdapter.navigate(request),
      );
      record.completer.complete(result);
    } catch (error, stackTrace) {
      if (!dispatchStarted) {
        final errorType = error.runtimeType.toString();
        _emitAspectLost(
          record.request,
          outcome: CCNavigationAspectOutcome.failed,
          errorType: errorType,
        );
        _emitAspectAfter(
          record.request,
          outcome: CCNavigationAspectOutcome.failed,
          errorType: errorType,
        );
        _emitNavigationEvent(
          record.request,
          CCNavigationLifecyclePhase.failed,
          errorType: errorType,
        );
      }
      record.completer.completeError(error, stackTrace);
    }
    return record.completer.future;
  }

  /// Cancels a pending continuation and completes its original Future with a
  /// standard navigation cancellation error.
  bool cancelPendingNavigation(
    String navigationId, {
    String code = 'pending_cancelled',
  }) => _cancelPendingNavigationInternal(navigationId, code: code);

  /// Cancels one continuation and publishes its terminal diagnostics.
  bool _cancelPendingNavigationInternal(
    String navigationId, {
    required String code,
  }) {
    final record = _pendingNavigations.remove(navigationId);
    if (record == null) return false;
    record.timer?.cancel();
    final error = CCRouteCancelledError(code);
    if (!record.completer.isCompleted) {
      record.completer.completeError(error);
    }
    _emitAspectLost(
      record.request,
      outcome: CCNavigationAspectOutcome.cancelled,
      errorType: error.runtimeType.toString(),
    );
    _emitAspectAfter(
      record.request,
      outcome: CCNavigationAspectOutcome.cancelled,
      errorType: error.runtimeType.toString(),
    );
    _emitNavigationEvent(
      record.request,
      CCNavigationLifecyclePhase.failed,
      errorType: error.runtimeType.toString(),
    );
    return true;
  }

  /// Cancels every pending continuation during Session or Runtime shutdown.
  void _cancelAllPendingNavigations({required String code}) {
    for (final navigationId in _pendingNavigations.keys.toList()) {
      _cancelPendingNavigationInternal(navigationId, code: code);
    }
  }
}
