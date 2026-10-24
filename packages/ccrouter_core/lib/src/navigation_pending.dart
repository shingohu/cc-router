part of 'runtime.dart';

/// Internal continuation retained while an interceptor waits for host policy.
final class _PendingNavigationRecord {
  /// Creates a continuation from the already validated navigation payload.
  _PendingNavigationRecord({
    required this.request,
    required this.operation,
    required this.prepared,
    required this.origin,
    required this.openMode,
    required this.source,
    required this.address,
    required this.createdAt,
    required this.completer,
    required this.action,
    required this.commitEntry,
    required this.onEntryCommitted,
    required this.placementOverride,
    required this.validateResult,
    required this.ownership,
    required this.onAttempt,
    this.requestCancellation,
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

  /// Dynamic Open stack behavior retained for deterministic replay.
  final CCDeepLinkOpenMode? openMode;

  /// Product attribution retained for diagnostics.
  final CCNavigationSource? source;

  /// Sanitized address metadata exposed by the public pending snapshot.
  final CCRouteAddressSummary address;

  /// Reason supplied by the interceptor.
  final String code;

  /// Time at which the continuation was created.
  final DateTime createdAt;

  /// Optional expiration time.
  final DateTime? expiresAt;

  /// Completes the original typed navigation Future after resume or cancel.
  final Completer<Object?> completer;

  /// Exact Adapter operation retained for composite navigation semantics.
  final Future<Object?> Function(CCNavigationRequest request) action;

  /// Optional RouteEntry commit strategy retained with the operation.
  final void Function(_RouteEntryRecord entry)? commitEntry;

  /// Optional observer notified only after the resumed Entry is committed.
  final void Function(_RouteEntryRecord entry)? onEntryCommitted;

  /// Call-site placement pinned to the original Host for redirects and replay.
  final CCRoutePlacement placementOverride;

  /// Original result contract used before completing and removing the Entry.
  final void Function(Object? result)? validateResult;

  /// Host ingress lifetime preserved through defer and resume.
  final CCCancellationToken? requestCancellation;

  /// Original operation retained across a replay initiated in another Zone.
  final _NavigationOperationLifetime? ownership;

  /// Updates the original failure boundary when replay redirects elsewhere.
  final void Function(String? routeId, CCRoutePlacement? placement)? onAttempt;

  /// Releases Host cancellation when this continuation leaves the queue.
  void Function()? removeHostCancellationListener;

  /// Releases the ingress listener when this pending record leaves the queue.
  void Function()? removeCancellationListener;

  /// Timer responsible for bounded retention when a timeout was requested.
  Timer? timer;

  /// Converts internal state into a safe public snapshot.
  CCPendingNavigation get snapshot => CCPendingNavigation(
    navigationId: request.navigationId,
    operation: operation,
    routeId: request.routeId,
    address: address,
    origin: origin,
    openMode: openMode,
    source: source,
    createdAt: createdAt,
    expiresAt: expiresAt,
    hostId: request.hostId,
    outlet: request.placement.navigatorOutlet,
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
    required CCDeepLinkOpenMode? openMode,
    required CCNavigationSource? source,
    required String code,
    required Duration? timeout,
    required Future<Object?> Function(CCNavigationRequest request) action,
    required void Function(_RouteEntryRecord entry)? commitEntry,
    required void Function(_RouteEntryRecord entry)? onEntryCommitted,
    required CCRoutePlacement? placementOverride,
    required void Function(Object? result)? validateResult,
    void Function(String? routeId, CCRoutePlacement? placement)? onAttempt,
    CCCancellationToken? requestCancellation,
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
      openMode: openMode,
      source: source,
      address: _addressSummaryFor(routeId: request.routeId, uri: request.uri),
      code: code,
      createdAt: now,
      expiresAt: expiresAt,
      completer: completer,
      action: action,
      commitEntry: commitEntry,
      onEntryCommitted: onEntryCommitted,
      placementOverride: CCRoutePlacement(
        hostId:
            placementOverride == null || placementOverride.hostId == 'default'
            ? request.hostId
            : placementOverride.hostId,
        parentRouteId: placementOverride?.parentRouteId,
        shellId: placementOverride?.shellId,
        navigatorOutlet: placementOverride?.navigatorOutlet ?? 'root',
      ),
      validateResult: validateResult,
      requestCancellation: requestCancellation,
      ownership: _navigationOperation,
      onAttempt: onAttempt,
    );
    _pendingNavigations[request.navigationId] = record;
    _diagnosticRevision++;
    if (timeout != null) {
      record.timer = Timer(timeout, () {
        _cancelPendingNavigationInternal(
          request.navigationId,
          code: 'pending_timeout',
        );
      });
    }
    record.removeCancellationListener = requestCancellation?.addListener(() {
      _cancelPendingNavigationInternal(
        request.navigationId,
        code: 'route_information_superseded',
      );
    });
    record.removeHostCancellationListener = record.ownership?.cancellation
        .addListener(() {
          _cancelPendingNavigationInternal(
            request.navigationId,
            code: 'host_detached',
          );
        });
    return completer.future;
  }

  /// Re-runs the saved navigation through resolution, policy, and Adapter.
  ///
  /// Resuming preserves the original navigation ID and typed payload while
  /// executing the complete interception chain again. A policy that still
  /// returns [CCNavigationDefer] creates a fresh bounded continuation. Typed
  /// requests revalidate through encoding; dynamic URIs match/decode again.
  /// The original concrete Host and call-site Outlet remain pinned across
  /// focus changes, while explicit placement on a redirect target still wins.
  /// Original and restoring callers observe the same result or error in their
  /// own error Zones; a failing original Future is never shared across them.
  Future<Object?> resumePendingNavigation(String navigationId) async {
    _ensureNavigationCanStart();
    _ensureInitialized();
    final record = _pendingNavigations.remove(navigationId);
    if (record == null) throw const CCNavigationPendingNotFoundError();
    _diagnosticRevision++;
    return _inNavigationOwnership(
      record.ownership,
      () => _resumeOwnedPendingNavigation(record),
    );
  }

  /// Replays only while the original registration set remains alive.
  ///
  /// Completes the original caller separately and returns or throws locally.
  /// Returning its Completer Future would lose failures across error Zones.
  Future<Object?> _resumeOwnedPendingNavigation(
    _PendingNavigationRecord record,
  ) async {
    final navigationId = record.request.navigationId;
    record.timer?.cancel();
    record.removeCancellationListener?.call();
    record.removeCancellationListener = null;
    record.removeHostCancellationListener?.call();
    record.removeHostCancellationListener = null;
    var dispatchStarted = false;
    try {
      _ensureNavigationRequestAlive(record.requestCancellation);
      final resolveClock = Stopwatch()..start();
      late final _PreparedRoute resolved;
      try {
        resolved = record.prepared.typed
            ? _routeRegistry.prepareIntent(
                _ResumedRouteIntent(
                  record.request.routeId,
                  record.prepared.arguments,
                ),
                origin: record.origin,
                placementOverride: record.placementOverride,
              )
            : _routeRegistry.prepareUri(
                record.request.uri,
                record.origin,
                placementOverride: record.placementOverride,
              );
      } finally {
        resolveClock.stop();
        _recordAspectResolve(navigationId, resolveClock.elapsed);
      }
      if (resolved.routeId != record.request.routeId) {
        throw CCRouteUnavailableError(record.request.routeId);
      }
      // Even an explicitly declared Shell may have used the active Host alias.
      // Replay must target the original concrete Host after focus changes.
      final replay = _PreparedRoute(
        routeId: resolved.routeId,
        ownerComponentId: resolved.ownerComponentId,
        uri: resolved.uri,
        pathParameters: resolved.pathParameters,
        arguments: resolved.arguments,
        extra: record.prepared.extra,
        presentation: resolved.presentation,
        placement: CCRoutePlacement(
          hostId: record.request.hostId,
          parentRouteId: resolved.placement.parentRouteId,
          shellId: resolved.placement.shellId,
          navigatorOutlet: resolved.placement.navigatorOutlet,
        ),
        interceptorIds: resolved.interceptorIds,
        popGuardIds: resolved.popGuardIds,
        typed: resolved.typed,
      );
      dispatchStarted = true;
      final result = await _dispatchNavigationUncoordinated(
        record.operation,
        replay,
        record.origin,
        record.openMode,
        record.source,
        navigationId: record.request.navigationId,
        action: record.action,
        commitEntry: record.commitEntry,
        onEntryCommitted: record.onEntryCommitted,
        placementOverride: record.placementOverride,
        validateResult: record.validateResult,
        requestCancellation: record.requestCancellation,
        onAttempt: record.onAttempt,
      );
      record.completer.complete(result);
      return result;
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
          error: error,
        );
      }
      _pendingResumeFailures.add(record.request.navigationId);
      record.completer.completeError(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
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
    record.removeCancellationListener?.call();
    record.removeCancellationListener = null;
    record.removeHostCancellationListener?.call();
    record.removeHostCancellationListener = null;
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
      error: error,
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
