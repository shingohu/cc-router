part of 'adapter.dart';

/// Stable reason the automatic predictive-back bridge used Flutter fallback.
enum CCGoRouterPredictiveBackFallbackReason {
  /// The platform reported a button/system-back event instead of edge progress.
  buttonEvent,

  /// No predictive-enabled Route is currently registered with the bridge.
  noEligibleRoute,

  /// The registered Route could not provide a usable mounted context.
  routeUnavailable,

  /// The Android Theme does not use a supported stock predictive transition.
  unsupportedTransition,

  /// The candidate Route is no longer current in its Navigator.
  routeNotCurrent,

  /// Flutter disabled the gesture through a local route or PopScope gate.
  routeBlocked,

  /// The candidate Route does not belong to the active CCRouter Outlet.
  inactiveOutlet,

  /// The candidate Route has no matching live managed backend Entry.
  unknownManagedEntry,
}

/// Sanitized Host diagnostic for one declined predictive-back start.
final class CCGoRouterPredictiveBackFallbackEvent {
  /// Creates an immutable fallback event without route or business payloads.
  const CCGoRouterPredictiveBackFallbackEvent({
    required this.reason,
    required this.hostId,
    required this.navigatorOutlet,
    required this.timestamp,
  });

  /// Stable fallback category suitable for logs and regression assertions.
  final CCGoRouterPredictiveBackFallbackReason reason;

  /// Stable Host identity of the Adapter that declined the gesture.
  final String hostId;

  /// Active CCRouter Outlet when the gesture start was evaluated.
  final String navigatorOutlet;

  /// Time at which the bridge declined the platform start.
  final DateTime timestamp;
}

/// Host-only bridge for platform predictive-back gesture phases.
///
/// Create it by passing `enablePredictiveBack: true` to
/// [CCGoRouterAdapter]. Managed default Android Material Pages connect through
/// [CCFlutterPredictiveBackHandler]; attached/custom Pages opt in explicitly.
/// Flutter remains the sole animation and Pop driver. Manual reporting is for
/// other platform integrations and must not duplicate automatically wired Routes.
final class CCGoRouterPredictiveBackBridge
    with WidgetsBindingObserver
    implements
        CCNavigationPredictiveBackSource,
        CCFlutterPredictiveBackHandler {
  /// Creates an adapter-owned bridge with no public constructor.
  CCGoRouterPredictiveBackBridge._();

  /// Runtime listeners receiving platform predictive-back phases.
  final Set<CCPredictiveBackEventListener> _listeners = {};

  /// Runtime-owned synchronous guard evaluator, while the Adapter is active.
  CCPopGuardEvaluator? _popGuardEvaluator;

  /// Whether the owning Adapter has been disposed.
  bool _disposed = false;

  @override
  /// Closed bridges relinquish new gestures on surviving attached Routes.
  bool get isActive => !_disposed;

  /// Owning Adapter, cleared with all Route references at permanent disposal.
  CCGoRouterAdapter? _adapter;

  /// Installed opt-in Routes; disposal removes their Navigator-owned identity.
  final Set<Route<dynamic>> _routes = {};

  /// Whether Flutter still owes a terminal callback for an accepted start.
  bool _claimsPlatformGesture = false;

  /// Bounds terminal-only observation after Adapter teardown to thirty seconds.
  ///
  /// No Route, Adapter, Runtime listener or evaluator survives in this period.
  Timer? _terminalCleanup;

  /// Whether this bridge is currently registered with the Flutter binding.
  bool _platformObserverAttached = false;

  /// Installs an opt-in claim observer before Flutter's Route detectors mount.
  void _attach(CCGoRouterAdapter adapter) {
    _adapter = adapter;
    try {
      WidgetsBinding.instance.addObserver(this);
      _platformObserverAttached = true;
    } catch (_) {
      _adapter = null;
      rethrow;
    }
  }

  /// Synchronously releases partial constructor registrations before rethrow.
  void _rollbackAttach() {
    if (_platformObserverAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _platformObserverAttached = false;
    }
    _disposed = true;
    _popGuardEvaluator = null;
    _listeners.clear();
    _gestures.clear();
    _routes.clear();
    _adapter = null;
    _lastAutomaticCommit = null;
  }

  @override
  /// Keeps an accepted gesture consumed if its Route is replaced mid-flight.
  ///
  /// This joins Flutter's detector only for a current, eligible, identity-known
  /// Route. It never drives animation or Pop. Guard, foreign and custom Routes
  /// are declined, preserving the ordinary no-handler system fallback.
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    final adapter = _adapter;
    if (_disposed) {
      _endPlatformGesture();
      return false;
    }
    _claimsPlatformGesture = false;
    if (adapter == null) return false;
    try {
      return _tryStartPlatformGesture(adapter, backEvent);
    } catch (_) {
      adapter._recordPredictiveBackFallback(
        CCGoRouterPredictiveBackFallbackReason.routeUnavailable,
      );
      return false;
    }
  }

  /// Evaluates one platform start while the public callback stays fail-open.
  bool _tryStartPlatformGesture(
    CCGoRouterAdapter adapter,
    PredictiveBackEvent backEvent,
  ) {
    if (backEvent.isButtonEvent) {
      adapter._recordPredictiveBackFallback(
        CCGoRouterPredictiveBackFallbackReason.buttonEvent,
      );
      return false;
    }
    var fallback = CCGoRouterPredictiveBackFallbackReason.noEligibleRoute;
    for (final route in _routes) {
      if (route is! PageRoute<dynamic>) continue;
      final context = route.subtreeContext;
      if (context == null) {
        fallback = CCGoRouterPredictiveBackFallbackReason.routeUnavailable;
        continue;
      }
      PageTransitionsBuilder? transition;
      try {
        final theme = Theme.of(context);
        if (theme.platform == TargetPlatform.android) {
          transition = theme.pageTransitionsTheme.builders[theme.platform];
        }
      } catch (_) {
        fallback = CCGoRouterPredictiveBackFallbackReason.routeUnavailable;
        continue;
      }
      if (transition.runtimeType != PredictiveBackPageTransitionsBuilder &&
          transition.runtimeType !=
              PredictiveBackFullscreenPageTransitionsBuilder) {
        fallback = CCGoRouterPredictiveBackFallbackReason.unsupportedTransition;
        continue;
      }
      if (!route.isCurrent) {
        fallback = CCGoRouterPredictiveBackFallbackReason.routeNotCurrent;
        continue;
      }
      bool popGestureEnabled;
      try {
        popGestureEnabled = route.popGestureEnabled;
      } catch (_) {
        fallback = CCGoRouterPredictiveBackFallbackReason.routeUnavailable;
        continue;
      }
      if (!popGestureEnabled) {
        fallback = CCGoRouterPredictiveBackFallbackReason.routeBlocked;
        continue;
      }
      if (!identical(
        route.navigator,
        adapter._navigatorForOutlet(adapter._activeNavigatorOutlet),
      )) {
        fallback = CCGoRouterPredictiveBackFallbackReason.inactiveOutlet;
        continue;
      }
      final id = adapter._backendRouteIds[route];
      if (id != null &&
          adapter._entries.any((entry) => entry.backendEntryId == id)) {
        _claimsPlatformGesture = true;
        return true;
      }
      fallback = CCGoRouterPredictiveBackFallbackReason.unknownManagedEntry;
    }
    adapter._recordPredictiveBackFallback(fallback);
    return false;
  }

  @override
  /// Consumes an old Host's commit without navigating after its teardown.
  void handleCommitBackGesture() => _endPlatformGesture();

  @override
  /// Releases terminal-only observation when the platform cancels its gesture.
  void handleCancelBackGesture() => _endPlatformGesture();

  /// Ends the platform claim without mutating Flutter's observer iteration.
  void _endPlatformGesture() {
    _claimsPlatformGesture = false;
    _terminalCleanup?.cancel();
    _terminalCleanup = null;
    if (_disposed) _detachPlatformObserver();
  }

  /// Defers removal because Flutter may currently be iterating gesture owners.
  void _detachPlatformObserver() {
    if (!_platformObserverAttached) return;
    _platformObserverAttached = false;
    scheduleMicrotask(() => WidgetsBinding.instance.removeObserver(this));
  }

  @override
  /// Registers a Route only while its Navigator owns its installed lifetime.
  void onAttach(Route<dynamic> route) {
    if (!_disposed) _routes.add(route);
  }

  /// In-flight Route identities, including invalidated gestures awaiting end.
  final Map<Route<dynamic>, _CCPredictiveGesture> _gestures = {};

  /// Last automatic removal, suppressing an accidental duplicate manual report.
  String? _lastAutomaticCommit;

  /// Whether automatic observation currently owns a live gesture sequence.
  bool get _automaticallyTracking =>
      _gestures.values.any((gesture) => !gesture.ended);

  @override
  /// Snapshots managed Entry identity without evaluating or changing policy.
  void onStart(Route<dynamic> route) {
    final adapter = _adapter;
    if (_disposed || adapter == null) return;
    final id = adapter._backendRouteIds[route];
    final entry = adapter._entries.cast<_CCGoRouterEntry?>().firstWhere(
      (entry) => entry?.backendEntryId == id,
      orElse: () => null,
    );
    if (id == null || entry == null) return;
    final outlet = entry.request.placement.navigatorOutlet;
    for (final previous in _gestures.values.toList()) {
      if (previous.outlet == outlet) _cancelGesture(previous);
    }
    _gestures[route] = _CCPredictiveGesture(id, outlet);
    _emit(const _PredictiveBackReport.started());
  }

  @override
  /// Reports progress only while the captured Route is still the active target.
  void onUpdate(Route<dynamic> route, double progress) {
    final gesture = _gestures[route];
    if (gesture == null || gesture.ended || _disposed) return;
    if (!canCommit(route)) {
      _cancelGesture(gesture);
      return;
    }
    _validateProgress(progress);
    _emit(_PredictiveBackReport.updated(progress));
  }

  @override
  /// Ends one captured sequence without publishing a second terminal event.
  void onCancel(Route<dynamic> route) {
    final gesture = _gestures.remove(route);
    if (gesture != null) _cancelGesture(gesture);
  }

  @override
  /// Rejects stale identities, hidden Outlets and permanently closed Adapters.
  bool canCommit(Route<dynamic> route) {
    final adapter = _adapter;
    if (_disposed || adapter == null) return false;
    final gesture = _gestures[route];
    // A Host may use this Page for an untracked initial/foreign destination.
    // Such a Route retains Flutter behavior but has no managed phase reports.
    if (gesture == null) return true;
    return !gesture.ended &&
        route.isCurrent &&
        adapter._activeNavigatorOutlet == gesture.outlet &&
        identical(
          route.navigator,
          adapter._navigatorForOutlet(gesture.outlet),
        ) &&
        adapter._backendRouteIds[route] == gesture.backendEntryId &&
        adapter._entries.any(
          (entry) => entry.backendEntryId == gesture.backendEntryId,
        );
  }

  @override
  /// Waits for the matching Observer Pop instead of reporting success early.
  void onCommit(Route<dynamic> route) {
    final gesture = _gestures[route];
    if (gesture != null && !gesture.ended) gesture.commitRequested = true;
  }

  @override
  /// Releases Route references even when teardown interrupts a gesture.
  void onDispose(Route<dynamic> route) {
    _routes.remove(route);
    onCancel(route);
  }

  /// Invalidates previews when the Router activates another retained Outlet.
  void _invalidateInactiveOutlets() {
    final adapter = _adapter;
    if (_disposed || adapter == null) return;
    for (final gesture in _gestures.values.toList()) {
      if (!gesture.commitRequested &&
          gesture.outlet != adapter._activeNavigatorOutlet) {
        _cancelGesture(gesture);
      }
    }
  }

  /// Confirms a commit only after exact backend removal and ledger delivery.
  void _observeBackendEvent(
    CCNavigationBackendEvent event,
    Route<dynamic> route,
  ) {
    if (_disposed) return;
    for (final item in _gestures.entries.toList()) {
      final gesture = item.value;
      if (gesture.ended) continue;
      if (gesture.outlet != event.navigatorOutlet) {
        if (!gesture.commitRequested && _hasCoveredAncestor(item.key)) {
          _cancelGesture(gesture);
        }
        continue;
      }
      if (event.kind == CCNavigationBackendEventKind.pop &&
          identical(item.key, route) &&
          gesture.commitRequested &&
          event.backendEntryId == gesture.backendEntryId &&
          event.owner == CCBackendEntryOwner.managed) {
        gesture.ended = true;
        _gestures.remove(item.key);
        _lastAutomaticCommit = gesture.backendEntryId;
        _emit(
          _PredictiveBackReport.committed(
            CCPopOutcome(
              handled: true,
              removedBackendEntryId: gesture.backendEntryId,
              removedEntryOwner: CCPopRemovedEntryOwner.managed,
              trigger: CCPopTrigger.predictiveBack,
              hostId: event.hostId,
              navigatorOutlet: gesture.outlet,
            ),
          ),
        );
      } else if (event.kind != CCNavigationBackendEventKind.topChanged ||
          (!gesture.commitRequested && !identical(item.key, route))) {
        _cancelGesture(gesture);
      }
    }
  }

  /// Detects coverage in an ancestor Navigator without retaining its Context.
  /// Observer delivery invalidates the sequence even if the covering Popup
  /// disappears again before the platform sends its terminal callback.
  bool _hasCoveredAncestor(Route<dynamic> route) {
    var navigator = route.navigator;
    while (navigator != null) {
      final ancestor = ModalRoute.of(navigator.context);
      if (ancestor == null) break;
      if (!ancestor.isCurrent) return true;
      navigator = ancestor.navigator;
    }
    return false;
  }

  /// Publishes cancellation once while retaining a tombstone for late commits.
  void _cancelGesture(_CCPredictiveGesture gesture) {
    if (gesture.ended) return;
    gesture.ended = true;
    _emit(const _PredictiveBackReport.cancelled(0));
  }

  /// Evaluates whether a predictive-back gesture may remove the active route.
  ///
  /// The host calls this before allowing the platform gesture to commit. A
  /// denied result means the host must keep the current route and must not call
  /// [committed]. Foreign or opaque top entries are allowed by Runtime without
  /// invoking managed-route guards.
  CCPopGuardDecision evaluateStart() =>
      _popGuardEvaluator?.call(CCPopTrigger.predictiveBack) ??
      const CCPopAllow();

  /// Subscribes to predictive-back phases and returns a removal callback.
  @override
  void Function() addPredictiveBackListener(
    CCPredictiveBackEventListener listener,
  ) {
    if (_disposed) return () {};
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Reports the beginning of one platform back gesture.
  void started() {
    if (!_automaticallyTracking) _emit(const _PredictiveBackReport.started());
  }

  /// Reports interactive gesture progress in the range 0..1.
  void updated(double progress) {
    _validateProgress(progress);
    if (!_automaticallyTracking) _emit(_PredictiveBackReport.updated(progress));
  }

  /// Reports that the platform cancelled and restored the gesture.
  void cancelled([double progress = 0]) {
    _validateProgress(progress);
    if (!_automaticallyTracking)
      _emit(_PredictiveBackReport.cancelled(progress));
  }

  /// Reports a committed Pop after the backend removed its route.
  void committed(CCPopOutcome outcome) {
    if (_automaticallyTracking ||
        (outcome.removedBackendEntryId != null &&
            outcome.removedBackendEntryId == _lastAutomaticCommit)) {
      return;
    }
    _emit(_PredictiveBackReport.committed(outcome));
  }

  /// Installs or clears the Runtime evaluator owned by the Adapter lifecycle.
  void _bindPopGuardEvaluator(CCPopGuardEvaluator? evaluator) {
    if (_disposed && evaluator != null) return;
    _popGuardEvaluator = evaluator;
  }

  /// Rejects platform progress values outside the normalized gesture range.
  void _validateProgress(double progress) {
    if (!progress.isFinite || progress < 0 || progress > 1) {
      throw ArgumentError.value(
        progress,
        'progress',
        'Must be between 0 and 1.',
      );
    }
  }

  /// Publishes one validated phase while isolating listener failures.
  void _emit(_PredictiveBackReport report) {
    if (_disposed) return;
    final event = CCPredictiveBackEvent(
      phase: report.phase,
      progress: report.progress,
      outcome: report.outcome,
      timestamp: DateTime.now(),
    );
    for (final listener in _listeners.toList()) {
      try {
        listener(event);
      } catch (_) {
        // Predictive-back diagnostics must not interrupt platform handling.
      }
    }
  }

  /// Permanently detaches Runtime listeners during Adapter disposal.
  void _dispose() {
    _disposed = true;
    if (_claimsPlatformGesture) {
      _terminalCleanup = Timer(
        const Duration(seconds: 30),
        _endPlatformGesture,
      );
    } else {
      _detachPlatformObserver();
    }
    _popGuardEvaluator = null;
    _listeners.clear();
    _gestures.clear();
    _routes.clear();
    _adapter = null;
    _lastAutomaticCommit = null;
  }
}

/// Adapter-owned identity for one gesture, retained only until Route termination.
final class _CCPredictiveGesture {
  /// Captures immutable backend and Outlet identities at accepted start.
  _CCPredictiveGesture(this.backendEntryId, this.outlet);

  /// Exact managed backend Entry that the gesture originally previewed.
  final String backendEntryId;

  /// Navigator partition whose stack changes invalidate this preview.
  final String outlet;

  /// Whether Flutter has requested its sole Pop and observation awaits proof.
  bool commitRequested = false;

  /// Whether this sequence has emitted its unique terminal event.
  bool ended = false;
}

/// Private payload used to construct one predictive event.
final class _PredictiveBackReport {
  const _PredictiveBackReport.started()
    : phase = CCPredictiveBackPhase.started,
      progress = 0,
      outcome = null;

  const _PredictiveBackReport.updated(this.progress)
    : phase = CCPredictiveBackPhase.updated,
      outcome = null;

  const _PredictiveBackReport.cancelled(this.progress)
    : phase = CCPredictiveBackPhase.cancelled,
      outcome = null;

  const _PredictiveBackReport.committed(this.outcome)
    : phase = CCPredictiveBackPhase.committed,
      progress = 1;

  final CCPredictiveBackPhase phase;
  final double progress;
  final CCPopOutcome? outcome;
}
