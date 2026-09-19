part of 'runtime.dart';

/// Mutable timing and attribution retained for one observed navigation.
final class _CCNavigationAspectRecord {
  /// Starts timing with the optional anonymous Host context already captured.
  _CCNavigationAspectRecord({required this.telemetryContext}) {
    clock.start();
  }

  /// Monotonic clock covering the complete observed navigation lifetime.
  final Stopwatch clock = Stopwatch();

  /// Anonymous analytics identity captured at navigation start.
  final CCNavigationTelemetryContext? telemetryContext;

  /// Route identities visited through redirects and failure recovery.
  final List<String> routeChain = [];

  /// First deterministic managed referrer inferred by Runtime.
  String? referrerRouteId;

  /// Cumulative synchronous route resolution duration.
  Duration resolve = Duration.zero;

  /// Cumulative interceptor wait duration.
  Duration intercept = Duration.zero;

  /// Cumulative Adapter entry duration before synchronous acceptance.
  Duration dispatch = Duration.zero;

  /// Elapsed duration when the Entry first became visible.
  Duration? arrival;

  /// Cumulative duration for which the Entry was current in its Outlet.
  Duration stay = Duration.zero;

  /// Clock position at which the current visible interval began.
  Duration? visibleSince;

  /// Whether at least one resolution duration has been captured.
  bool resolved = false;

  /// Whether at least one interceptor duration has been captured.
  bool intercepted = false;

  /// Whether Adapter dispatch duration has been captured.
  bool dispatched = false;

  /// Whether an `after` observation has reached a terminal outcome.
  bool terminal = false;

  /// Whether Runtime allocated a managed Route Entry for this navigation.
  bool hasEntry = false;

  /// Whether the managed Route Entry completed Scope disposal.
  bool disposed = false;
}

/// Executes the Runtime-owned navigation AOP hooks.
extension CCRouterRuntimeNavigationAspects on CCRouterRuntime {
  /// Returns whether any aspect observes navigation.
  bool get _hasNavigationAspects => _navigationAspects.isNotEmpty;

  /// Starts one observation before route resolution begins.
  void _beginNavigationObservation(String navigationId) {
    if (!_hasNavigationAspects ||
        _navigationAspectRecords.containsKey(navigationId)) {
      return;
    }
    _navigationAspectRecords[navigationId] = _CCNavigationAspectRecord(
      telemetryContext: _snapshotTelemetryContext(),
    );
  }

  /// Adds one synchronous route-resolution duration to an observation.
  void _recordAspectResolve(String navigationId, Duration elapsed) {
    final record = _navigationAspectRecords[navigationId];
    if (record == null) return;
    record.resolve += elapsed;
    record.resolved = true;
  }

  /// Adds one interceptor-pipeline duration to an observation.
  void _recordAspectIntercept(String navigationId, Duration elapsed) {
    final record = _navigationAspectRecords[navigationId];
    if (record == null) return;
    record.intercept += elapsed;
    record.intercepted = true;
  }

  /// Adds one Adapter entry duration to an observation.
  void _recordAspectDispatch(String navigationId, Duration elapsed) {
    final record = _navigationAspectRecords[navigationId];
    if (record == null) return;
    record.dispatch += elapsed;
    record.dispatched = true;
  }

  /// Emits a matched-route observation after Runtime resolution.
  void _emitAspectFound(CCNavigationRequest request) {
    if (!_hasNavigationAspects) return;
    final record = _navigationAspectRecords.putIfAbsent(
      request.navigationId,
      () => _CCNavigationAspectRecord(
        telemetryContext: _snapshotTelemetryContext(),
      ),
    );
    record.referrerRouteId ??= _aspectReferrerRouteId(request);
    if (record.routeChain.isEmpty ||
        record.routeChain.last != request.routeId) {
      record.routeChain.add(request.routeId);
    }
    _emitAspectEvent(
      CCNavigationAspectEvent(
        phase: CCNavigationAspectPhase.found,
        request: _aspectRequest(request),
        timestamp: DateTime.now(),
        elapsed: record.clock.elapsed,
        timing: _aspectTiming(request.navigationId),
      ),
    );
  }

  /// Emits one managed Route Entry state observation.
  void _emitAspectEntryState(
    _RouteEntryRecord entry,
    CCRouteEntryLifecycleState state,
  ) {
    final record = _navigationAspectRecords[entry.request.navigationId];
    if (record == null) return;
    record.hasEntry = true;
    final now = record.clock.elapsed;
    late final CCNavigationAspectPhase? phase;
    switch (state) {
      case CCRouteEntryLifecycleState.visible:
        if (record.arrival == null) {
          record.arrival = now;
          phase = CCNavigationAspectPhase.arrival;
        } else {
          phase = CCNavigationAspectPhase.show;
        }
        record.visibleSince = now;
      case CCRouteEntryLifecycleState.hidden:
        _closeAspectVisibleInterval(record, now);
        phase = CCNavigationAspectPhase.hide;
      case CCRouteEntryLifecycleState.removed:
        _closeAspectVisibleInterval(record, now);
        phase = CCNavigationAspectPhase.removed;
      case CCRouteEntryLifecycleState.disposed:
        _closeAspectVisibleInterval(record, now);
        record.disposed = true;
        phase = CCNavigationAspectPhase.disposed;
      case CCRouteEntryLifecycleState.created:
      case CCRouteEntryLifecycleState.resolving:
      case CCRouteEntryLifecycleState.pushed:
      case CCRouteEntryLifecycleState.popping:
        phase = null;
    }
    if (phase == null) return;
    _emitAspectEvent(
      CCNavigationAspectEvent(
        phase: phase,
        request: _aspectRequest(entry.request),
        entry: entry.snapshot,
        timestamp: DateTime.now(),
        elapsed: record.clock.elapsed,
        timing: _aspectTiming(entry.request.navigationId),
      ),
    );
    _releaseAspectRecordIfFinished(entry.request.navigationId);
  }

  /// Emits a failed or cancelled navigation observation.
  void _emitAspectLost(
    CCNavigationRequest request, {
    required CCNavigationAspectOutcome outcome,
    String? errorType,
  }) {
    final timing = _aspectTiming(request.navigationId);
    _emitAspectEvent(
      CCNavigationAspectEvent(
        phase: CCNavigationAspectPhase.lost,
        request: _aspectRequest(request),
        outcome: outcome,
        errorType: errorType,
        timestamp: DateTime.now(),
        elapsed: timing?.total,
        timing: timing,
      ),
    );
  }

  /// Emits the terminal observation for one navigation request.
  void _emitAspectAfter(
    CCNavigationRequest request, {
    required CCNavigationAspectOutcome outcome,
    String? errorType,
  }) {
    final record = _navigationAspectRecords[request.navigationId];
    final timing = _aspectTiming(request.navigationId);
    _emitAspectEvent(
      CCNavigationAspectEvent(
        phase: CCNavigationAspectPhase.after,
        request: _aspectRequest(request),
        outcome: outcome,
        errorType: errorType,
        timestamp: DateTime.now(),
        elapsed: timing?.total,
        timing: timing,
      ),
    );
    if (record != null) record.terminal = true;
    _releaseAspectRecordIfFinished(request.navigationId);
  }

  /// Drops timing for a navigation that failed before a safe request existed.
  void _discardNavigationObservation(String navigationId) {
    _navigationAspectRecords.remove(navigationId)?.clock.stop();
  }

  /// Converts an internal request into the safe aspect snapshot.
  CCNavigationAspectRequest _aspectRequest(CCNavigationRequest request) {
    final record = _navigationAspectRecords[request.navigationId];
    return CCNavigationAspectRequest(
      navigationId: request.navigationId,
      operation: request.operation,
      routeId: request.routeId,
      routePattern: _routeRegistry.routePattern(request.routeId),
      resolvedHostId: request.hostId,
      navigatorOutlet: request.placement.navigatorOutlet,
      ownerComponentId: request.ownerComponentId,
      referrerRouteId: record?.referrerRouteId,
      redirectChain: record?.routeChain ?? const [],
      placement: request.placement,
      origin: request.origin,
      source: request.source,
      presentation: request.presentation,
      telemetryContext: record?.telemetryContext,
    );
  }

  /// Creates one cumulative timing snapshot for [navigationId].
  CCNavigationAspectTiming? _aspectTiming(String navigationId) {
    final record = _navigationAspectRecords[navigationId];
    if (record == null) return null;
    final now = record.clock.elapsed;
    final activeStay = record.visibleSince == null
        ? Duration.zero
        : now - record.visibleSince!;
    return CCNavigationAspectTiming(
      resolve: record.resolved ? record.resolve : null,
      intercept: record.intercepted ? record.intercept : null,
      dispatch: record.dispatched ? record.dispatch : null,
      arrival: record.arrival,
      stay: record.arrival == null ? null : record.stay + activeStay,
      total: now,
    );
  }

  /// Closes the current visible interval, if one is active.
  void _closeAspectVisibleInterval(
    _CCNavigationAspectRecord record,
    Duration now,
  ) {
    final visibleSince = record.visibleSince;
    if (visibleSince == null) return;
    record.stay += now - visibleSince;
    record.visibleSince = null;
  }

  /// Infers a safe managed referrer without reading URI payloads.
  String? _aspectReferrerRouteId(CCNavigationRequest request) {
    _RouteEntryRecord? hostFallback;
    for (final entry in _routeEntries.reversed) {
      if (entry.request.hostId != request.hostId ||
          entry.state != CCRouteEntryLifecycleState.visible) {
        continue;
      }
      hostFallback ??= entry;
      if (entry.request.placement.navigatorOutlet ==
          request.placement.navigatorOutlet) {
        return entry.request.routeId;
      }
    }
    return hostFallback?.request.routeId;
  }

  /// Snapshots and validates Host telemetry while isolating provider failures.
  CCNavigationTelemetryContext? _snapshotTelemetryContext() {
    final provider = telemetryContextProvider;
    if (provider == null) return null;
    try {
      return _validatedTelemetryContext(provider.currentContext());
    } catch (error) {
      _recordNavigationCallbackFailure(
        'Navigation telemetry context failed: ${error.runtimeType}.',
      );
      return null;
    }
  }

  /// Rejects malformed anonymous identifiers without failing navigation.
  CCNavigationTelemetryContext? _validatedTelemetryContext(
    CCNavigationTelemetryContext? context,
  ) {
    if (context == null) return null;
    final visitor = context.anonymousVisitorId;
    final session = context.applicationSessionId;
    final validVisitor =
        visitor.isNotEmpty &&
        visitor == visitor.trim() &&
        visitor.length <= 256;
    final validSession =
        session == null ||
        session.isNotEmpty &&
            session == session.trim() &&
            session.length <= 256;
    if (!validVisitor || !validSession) {
      _recordNavigationCallbackFailure(
        'Navigation telemetry context contained an invalid anonymous ID.',
      );
      return null;
    }
    return context;
  }

  /// Releases one record after both navigation and Entry lifecycles finish.
  void _releaseAspectRecordIfFinished(String navigationId) {
    final record = _navigationAspectRecords[navigationId];
    if (record == null || !record.terminal) return;
    if (record.hasEntry && !record.disposed) return;
    _navigationAspectRecords.remove(navigationId);
    record.clock.stop();
  }

  /// Dispatches an aspect event while isolating callback failures.
  void _emitAspectEvent(CCNavigationAspectEvent event) {
    for (final aspect in _navigationAspects) {
      final observer = switch (event.phase) {
        CCNavigationAspectPhase.found => aspect.onFound,
        CCNavigationAspectPhase.arrival => aspect.onArrival,
        CCNavigationAspectPhase.show => aspect.onShow,
        CCNavigationAspectPhase.hide => aspect.onHide,
        CCNavigationAspectPhase.removed => aspect.onRemoved,
        CCNavigationAspectPhase.disposed => aspect.onDisposed,
        CCNavigationAspectPhase.lost => aspect.onLost,
        CCNavigationAspectPhase.after => aspect.onAfter,
      };
      if (observer == null) continue;
      _navigationCallbackActive = true;
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
      } finally {
        _navigationCallbackActive = false;
      }
    }
  }
}
