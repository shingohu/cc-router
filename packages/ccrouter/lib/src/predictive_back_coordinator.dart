import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;

import 'flutter_route_factory.dart';

/// Backend-neutral reason why automatic predictive back used Flutter fallback.
enum CCPredictiveBackFallbackReason {
  /// The platform reported a button or non-interactive system-back event.
  buttonEvent,

  /// No predictive-enabled Route is currently registered.
  noEligibleRoute,

  /// A registered Route could not provide usable Flutter state.
  routeUnavailable,

  /// The current Theme does not use a supported stock predictive transition.
  unsupportedTransition,

  /// The candidate Route is no longer current in its Navigator.
  routeNotCurrent,

  /// Flutter disabled the gesture through a local route gate.
  routeBlocked,

  /// The candidate Route is outside the active backend Outlet.
  inactiveOutlet,

  /// The candidate Route has no matching live managed backend Entry.
  unknownManagedEntry,
}

/// Immutable backend identity captured for one predictive-back Route.
final class CCPredictiveBackRouteIdentity {
  /// Creates an identity without retaining backend entries or request payloads.
  const CCPredictiveBackRouteIdentity({
    required this.backendEntryId,
    required this.navigatorOutlet,
  });

  /// Exact backend Entry correlated with the Flutter Route.
  final String backendEntryId;

  /// Navigator partition that owns the Entry.
  final String navigatorOutlet;
}

/// Backend-neutral predictive-back state machine for Host integrations.
///
/// The coordinator owns Flutter Route registration, gesture sequencing,
/// listener delivery, the binding observer and terminal cleanup Timer. Concrete
/// backends provide only current Entry identity, active Outlet selection and
/// sanitized fallback storage. Flutter remains the sole animation and Pop
/// driver; a committed phase is published only after a matching backend event.
///
/// This is Host/Adapter SPI. Feature code must not construct or retain it.
abstract base class CCPredictiveBackCoordinator
    with WidgetsBindingObserver
    implements
        CCNavigationPredictiveBackSource,
        CCFlutterPredictiveBackHandler {
  /// Creates an unattached coordinator owned by one navigation Adapter.
  CCPredictiveBackCoordinator();

  /// Outlet currently eligible for context-free platform Back.
  @protected
  String get activePredictiveBackOutlet;

  /// Resolves the Navigator currently rendering [outlet].
  @protected
  NavigatorState? navigatorForPredictiveBackOutlet(String outlet);

  /// Resolves a live backend identity for [route], without retaining payloads.
  @protected
  CCPredictiveBackRouteIdentity? resolvePredictiveBackRoute(
    Route<dynamic> route,
  );

  /// Whether [backendEntryId] still belongs to the active backend ledger.
  @protected
  bool hasLivePredictiveBackEntry(String backendEntryId);

  /// Stores one bounded, sanitized fallback reason in the concrete backend.
  @protected
  void recordPredictiveBackFallback(CCPredictiveBackFallbackReason reason);

  /// Releases concrete backend references before terminal-only observation.
  ///
  /// A disposed coordinator may remain binding-owned for at most thirty seconds
  /// while consuming an outstanding terminal platform callback. Implementations
  /// must clear Adapter and callback references here.
  @protected
  void releasePredictiveBackBackendReferences();

  /// Registered Runtime listeners receiving normalized predictive phases.
  final Set<CCPredictiveBackEventListener> _listeners = {};

  /// Navigator-owned Routes currently connected to this coordinator.
  final Set<Route<dynamic>> _routes = {};

  /// Gesture identities retained until their unique terminal transition.
  final Map<Route<dynamic>, _CCPredictiveBackGesture> _gestures = {};

  /// Runtime-owned synchronous guard evaluator while the Adapter is active.
  CCPopGuardEvaluator? _popGuardEvaluator;

  /// Bounds terminal-only binding observation after Adapter teardown.
  Timer? _terminalCleanup;

  /// Whether the coordinator has permanently stopped accepting new work.
  bool _disposed = false;

  /// Whether Flutter still owes a terminal callback for an accepted start.
  bool _claimsPlatformGesture = false;

  /// Whether this coordinator is registered with the Flutter binding.
  bool _platformObserverAttached = false;

  /// Last automatic removal, used to suppress duplicate manual reporting.
  String? _lastAutomaticCommit;

  /// Closed coordinators relinquish new gestures on surviving Routes.
  @override
  bool get isActive => !_disposed;

  /// Installs the binding observer as part of Adapter construction.
  @protected
  void attachPredictiveBackCoordinator() {
    if (_disposed || _platformObserverAttached) return;
    WidgetsBinding.instance.addObserver(this);
    _platformObserverAttached = true;
  }

  /// Synchronously rolls back a partially constructed Adapter.
  @protected
  void rollbackPredictiveBackCoordinator() {
    if (_platformObserverAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _platformObserverAttached = false;
    }
    _disposed = true;
    _terminalCleanup?.cancel();
    _terminalCleanup = null;
    _popGuardEvaluator = null;
    _listeners.clear();
    _gestures.clear();
    _routes.clear();
    _lastAutomaticCommit = null;
    releasePredictiveBackBackendReferences();
  }

  /// Installs or clears the Runtime PopGuard evaluator for this Host.
  @protected
  void bindPredictiveBackPopGuardEvaluator(CCPopGuardEvaluator? evaluator) {
    if (_disposed && evaluator != null) return;
    _popGuardEvaluator = evaluator;
  }

  /// Claims only a current, identity-known Route using a supported transition.
  @override
  bool handleStartBackGesture(PredictiveBackEvent event) {
    if (_disposed) {
      _endPlatformGesture();
      return false;
    }
    _claimsPlatformGesture = false;
    try {
      return _tryStartPlatformGesture(event);
    } catch (_) {
      recordPredictiveBackFallback(
        CCPredictiveBackFallbackReason.routeUnavailable,
      );
      return false;
    }
  }

  /// Evaluates one platform start while the public callback stays fail-open.
  bool _tryStartPlatformGesture(PredictiveBackEvent event) {
    if (event.isButtonEvent) {
      recordPredictiveBackFallback(CCPredictiveBackFallbackReason.buttonEvent);
      return false;
    }
    var fallback = CCPredictiveBackFallbackReason.noEligibleRoute;
    for (final route in _routes) {
      if (route is! PageRoute<dynamic>) continue;
      final context = route.subtreeContext;
      if (context == null) {
        fallback = CCPredictiveBackFallbackReason.routeUnavailable;
        continue;
      }
      PageTransitionsBuilder? transition;
      try {
        final theme = Theme.of(context);
        if (theme.platform == TargetPlatform.android) {
          transition = theme.pageTransitionsTheme.builders[theme.platform];
        }
      } catch (_) {
        fallback = CCPredictiveBackFallbackReason.routeUnavailable;
        continue;
      }
      if (transition.runtimeType != PredictiveBackPageTransitionsBuilder &&
          transition.runtimeType !=
              PredictiveBackFullscreenPageTransitionsBuilder) {
        fallback = CCPredictiveBackFallbackReason.unsupportedTransition;
        continue;
      }
      if (!route.isCurrent) {
        fallback = CCPredictiveBackFallbackReason.routeNotCurrent;
        continue;
      }
      bool enabled;
      try {
        enabled = route.popGestureEnabled;
      } catch (_) {
        fallback = CCPredictiveBackFallbackReason.routeUnavailable;
        continue;
      }
      if (!enabled) {
        fallback = CCPredictiveBackFallbackReason.routeBlocked;
        continue;
      }
      final activeOutlet = activePredictiveBackOutlet;
      if (!identical(
        route.navigator,
        navigatorForPredictiveBackOutlet(activeOutlet),
      )) {
        fallback = CCPredictiveBackFallbackReason.inactiveOutlet;
        continue;
      }
      final identity = resolvePredictiveBackRoute(route);
      if (identity != null &&
          identity.navigatorOutlet == activeOutlet &&
          hasLivePredictiveBackEntry(identity.backendEntryId)) {
        _claimsPlatformGesture = true;
        return true;
      }
      fallback = CCPredictiveBackFallbackReason.unknownManagedEntry;
    }
    recordPredictiveBackFallback(fallback);
    return false;
  }

  /// Consumes a late platform commit without performing navigation.
  @override
  void handleCommitBackGesture() => _endPlatformGesture();

  /// Releases terminal-only observation after platform cancellation.
  @override
  void handleCancelBackGesture() => _endPlatformGesture();

  /// Ends a platform claim and releases a retired binding observer.
  void _endPlatformGesture() {
    _claimsPlatformGesture = false;
    _terminalCleanup?.cancel();
    _terminalCleanup = null;
    if (_disposed) _detachPlatformObserver();
  }

  /// Defers removal because Flutter may be iterating gesture observers.
  void _detachPlatformObserver() {
    if (!_platformObserverAttached) return;
    _platformObserverAttached = false;
    scheduleMicrotask(() => WidgetsBinding.instance.removeObserver(this));
  }

  /// Registers a Route for exactly its Navigator-owned lifetime.
  @override
  void onAttach(Route<dynamic> route) {
    if (!_disposed) _routes.add(route);
  }

  /// Captures exact backend and Outlet identity at gesture start.
  @override
  void onStart(Route<dynamic> route) {
    if (_disposed) return;
    final identity = resolvePredictiveBackRoute(route);
    if (identity == null ||
        !hasLivePredictiveBackEntry(identity.backendEntryId)) {
      return;
    }
    for (final previous in _gestures.values.toList()) {
      if (previous.navigatorOutlet == identity.navigatorOutlet) {
        _cancelGesture(previous);
      }
    }
    _gestures[route] = _CCPredictiveBackGesture(identity);
    _emit(const _CCPredictiveBackReport.started());
  }

  /// Reports progress only while the original backend identity remains valid.
  @override
  void onUpdate(Route<dynamic> route, double progress) {
    final gesture = _gestures[route];
    if (gesture == null || gesture.ended || _disposed) return;
    if (!canCommit(route)) {
      _cancelGesture(gesture);
      return;
    }
    _validateProgress(progress);
    _emit(_CCPredictiveBackReport.updated(progress));
  }

  /// Ends one captured sequence without mutating navigation state.
  @override
  void onCancel(Route<dynamic> route) {
    final gesture = _gestures.remove(route);
    if (gesture != null) _cancelGesture(gesture);
  }

  /// Rejects stale identities, hidden Outlets and disposed backend owners.
  @override
  bool canCommit(Route<dynamic> route) {
    if (_disposed) return false;
    final gesture = _gestures[route];
    if (gesture == null) return true;
    final identity = resolvePredictiveBackRoute(route);
    return !gesture.ended &&
        route.isCurrent &&
        activePredictiveBackOutlet == gesture.navigatorOutlet &&
        identical(
          route.navigator,
          navigatorForPredictiveBackOutlet(gesture.navigatorOutlet),
        ) &&
        identity?.backendEntryId == gesture.backendEntryId &&
        identity?.navigatorOutlet == gesture.navigatorOutlet &&
        hasLivePredictiveBackEntry(gesture.backendEntryId);
  }

  /// Records that Flutter is about to perform its sole Navigator Pop.
  @override
  void onCommit(Route<dynamic> route) {
    final gesture = _gestures[route];
    if (gesture != null && !gesture.ended) gesture.commitRequested = true;
  }

  /// Releases Route and gesture references during Navigator teardown.
  @override
  void onDispose(Route<dynamic> route) {
    _routes.remove(route);
    onCancel(route);
  }

  /// Cancels previews no longer belonging to the active Outlet.
  @protected
  void invalidateInactivePredictiveBackOutlets() {
    if (_disposed) return;
    for (final gesture in _gestures.values.toList()) {
      if (!gesture.commitRequested &&
          gesture.navigatorOutlet != activePredictiveBackOutlet) {
        _cancelGesture(gesture);
      }
    }
  }

  /// Reconciles one backend event with the exact pending gesture identity.
  ///
  /// [observedRoute] is supplied by observer-driven backends such as GoRouter.
  /// Store-driven Managed backends omit it and reconcile by immutable Entry ID.
  @protected
  void observePredictiveBackBackendEvent(
    CCNavigationBackendEvent event, {
    Route<dynamic>? observedRoute,
  }) {
    if (_disposed) return;
    for (final item in _gestures.entries.toList()) {
      final route = item.key;
      final gesture = item.value;
      if (gesture.ended) continue;
      if (observedRoute == null) {
        if (_isCommittedRemoval(gesture, event)) {
          _commitGesture(route, gesture, event);
        } else if (!gesture.commitRequested &&
            event.navigatorOutlet == gesture.navigatorOutlet) {
          _cancelGesture(gesture);
        }
        continue;
      }
      if (gesture.navigatorOutlet != event.navigatorOutlet) {
        if (!gesture.commitRequested && _hasCoveredAncestor(route)) {
          _cancelGesture(gesture);
        }
        continue;
      }
      if (_isCommittedRemoval(gesture, event) &&
          identical(route, observedRoute)) {
        _commitGesture(route, gesture, event);
      } else if (event.kind != CCNavigationBackendEventKind.topChanged ||
          (!gesture.commitRequested && !identical(route, observedRoute))) {
        _cancelGesture(gesture);
      }
    }
  }

  /// Whether [event] proves removal of the originally captured Entry.
  bool _isCommittedRemoval(
    _CCPredictiveBackGesture gesture,
    CCNavigationBackendEvent event,
  ) =>
      event.kind == CCNavigationBackendEventKind.pop &&
      gesture.commitRequested &&
      event.backendEntryId == gesture.backendEntryId &&
      event.owner == CCBackendEntryOwner.managed;

  /// Publishes a unique committed phase after exact backend proof.
  void _commitGesture(
    Route<dynamic> route,
    _CCPredictiveBackGesture gesture,
    CCNavigationBackendEvent event,
  ) {
    gesture.ended = true;
    _gestures.remove(route);
    _lastAutomaticCommit = gesture.backendEntryId;
    _emit(
      _CCPredictiveBackReport.committed(
        CCPopOutcome(
          handled: true,
          removedBackendEntryId: gesture.backendEntryId,
          removedEntryOwner: CCPopRemovedEntryOwner.managed,
          trigger: CCPopTrigger.predictiveBack,
          hostId: event.hostId,
          navigatorOutlet: gesture.navigatorOutlet,
        ),
      ),
    );
  }

  /// Detects a Popup or Route covering a nested Navigator candidate.
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

  /// Evaluates the Runtime PopGuard without opening an async UI decision.
  CCPopGuardDecision evaluateStart() =>
      _popGuardEvaluator?.call(CCPopTrigger.predictiveBack) ??
      const CCPopAllow();

  /// Subscribes to predictive phases until the returned callback is invoked.
  @override
  void Function() addPredictiveBackListener(
    CCPredictiveBackEventListener listener,
  ) {
    if (_disposed) return () {};
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Reports a manual start only when no automatic Route owns a sequence.
  void started() {
    if (!_automaticallyTracking) {
      _emit(const _CCPredictiveBackReport.started());
    }
  }

  /// Reports normalized progress for a manual Host integration.
  void updated(double progress) {
    _validateProgress(progress);
    if (!_automaticallyTracking) {
      _emit(_CCPredictiveBackReport.updated(progress));
    }
  }

  /// Reports manual cancellation without completing a result or Scope.
  void cancelled([double progress = 0]) {
    _validateProgress(progress);
    if (!_automaticallyTracking) {
      _emit(_CCPredictiveBackReport.cancelled(progress));
    }
  }

  /// Reports a manual commit after a backend already removed its Route.
  void committed(CCPopOutcome outcome) {
    if (_automaticallyTracking ||
        (outcome.removedBackendEntryId != null &&
            outcome.removedBackendEntryId == _lastAutomaticCommit)) {
      return;
    }
    _emit(_CCPredictiveBackReport.committed(outcome));
  }

  /// Publishes one cancellation while preserving a late-commit tombstone.
  void _cancelGesture(_CCPredictiveBackGesture gesture) {
    if (gesture.ended) return;
    gesture.ended = true;
    _emit(const _CCPredictiveBackReport.cancelled(0));
  }

  /// Whether automatic observation currently owns a live sequence.
  bool get _automaticallyTracking =>
      _gestures.values.any((gesture) => !gesture.ended);

  /// Rejects non-finite or out-of-range platform progress.
  void _validateProgress(double progress) {
    if (!progress.isFinite || progress < 0 || progress > 1) {
      throw ArgumentError.value(
        progress,
        'progress',
        'Must be between 0 and 1.',
      );
    }
  }

  /// Publishes one phase while isolating diagnostic listener failures.
  void _emit(_CCPredictiveBackReport report) {
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
        // Host diagnostics cannot interrupt Flutter's gesture callback.
      }
    }
  }

  /// Permanently releases backend, Runtime, Route and gesture ownership.
  @protected
  void disposePredictiveBackCoordinator() {
    if (_disposed) return;
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
    _lastAutomaticCommit = null;
    releasePredictiveBackBackendReferences();
  }
}

/// Coordinator-owned snapshot for one accepted gesture sequence.
final class _CCPredictiveBackGesture {
  /// Captures immutable backend and Outlet identity.
  _CCPredictiveBackGesture(CCPredictiveBackRouteIdentity identity)
    : backendEntryId = identity.backendEntryId,
      navigatorOutlet = identity.navigatorOutlet;

  /// Exact managed backend Entry previewed at gesture start.
  final String backendEntryId;

  /// Navigator partition whose changes invalidate the preview.
  final String navigatorOutlet;

  /// Whether Flutter requested its sole Pop and now awaits backend proof.
  bool commitRequested = false;

  /// Whether the unique terminal phase has already been emitted.
  bool ended = false;
}

/// Internal normalized payload used to construct predictive events.
final class _CCPredictiveBackReport {
  /// Creates a gesture-start report.
  const _CCPredictiveBackReport.started()
    : phase = CCPredictiveBackPhase.started,
      progress = 0,
      outcome = null;

  /// Creates a progress report.
  const _CCPredictiveBackReport.updated(this.progress)
    : phase = CCPredictiveBackPhase.updated,
      outcome = null;

  /// Creates a cancellation report.
  const _CCPredictiveBackReport.cancelled(this.progress)
    : phase = CCPredictiveBackPhase.cancelled,
      outcome = null;

  /// Creates a backend-confirmed commit report.
  const _CCPredictiveBackReport.committed(this.outcome)
    : phase = CCPredictiveBackPhase.committed,
      progress = 1;

  /// Normalized gesture phase.
  final CCPredictiveBackPhase phase;

  /// Normalized progress in the range 0 through 1.
  final double progress;

  /// Backend Pop result attached only to a committed phase.
  final CCPopOutcome? outcome;
}
