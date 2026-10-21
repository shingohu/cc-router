import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;

import 'flutter_route_factory.dart';

/// Stable reason why the Managed predictive-back bridge used Flutter fallback.
enum CCManagedPredictiveBackFallbackReason {
  /// The platform reported a button/system-back event.
  buttonEvent,

  /// No eligible Managed Route is currently registered.
  noEligibleRoute,

  /// The Route context or transition could not be inspected.
  routeUnavailable,

  /// The Host theme does not use a supported predictive transition.
  unsupportedTransition,

  /// The candidate Route is not current.
  routeNotCurrent,

  /// A local Flutter route gate disabled the gesture.
  routeBlocked,

  /// The candidate Route belongs to a different Outlet.
  inactiveOutlet,

  /// The candidate Route has no live Managed Entry.
  unknownManagedEntry,
}

/// Sanitized diagnostic for one declined Managed predictive-back start.
final class CCManagedPredictiveBackFallbackEvent {
  /// Creates an immutable fallback event.
  const CCManagedPredictiveBackFallbackEvent({
    required this.reason,
    required this.hostId,
    required this.navigatorOutlet,
    required this.timestamp,
  });

  /// Stable fallback category.
  final CCManagedPredictiveBackFallbackReason reason;

  /// Host that declined the gesture.
  final String hostId;

  /// Outlet evaluated at gesture start.
  final String navigatorOutlet;

  /// Time of the declined start.
  final DateTime timestamp;
}

/// Predictive-back bridge shared by a Managed Host's Route Pages.
///
/// The bridge is callback-driven so it owns no adapter, BuildContext, or Route
/// ledger. Flutter still owns the transition and performs the sole Pop; this
/// object only correlates the exact backend Entry and reports its lifecycle.
final class CCManagedPredictiveBackBridge
    with WidgetsBindingObserver
    implements
        CCNavigationPredictiveBackSource,
        CCFlutterPredictiveBackHandler {
  /// Creates a bridge for one Managed Host.
  CCManagedPredictiveBackBridge({
    required this.hostId,
    required String Function() activeOutlet,
    required NavigatorState? Function(String outlet) navigatorForOutlet,
    required String? Function(Route<dynamic> route) backendEntryIdForRoute,
    required bool Function(String backendEntryId) hasLiveEntry,
    required void Function(CCManagedPredictiveBackFallbackReason reason)
    recordFallback,
  }) : _activeOutlet = activeOutlet,
       _navigatorForOutlet = navigatorForOutlet,
       _backendEntryIdForRoute = backendEntryIdForRoute,
       _hasLiveEntry = hasLiveEntry,
       _recordFallback = recordFallback;

  /// Stable Host identity exposed in diagnostics.
  final String hostId;
  final String Function() _activeOutlet;
  final NavigatorState? Function(String outlet) _navigatorForOutlet;
  final String? Function(Route<dynamic> route) _backendEntryIdForRoute;
  final bool Function(String backendEntryId) _hasLiveEntry;
  final void Function(CCManagedPredictiveBackFallbackReason reason)
  _recordFallback;
  final Set<CCPredictiveBackEventListener> _listeners = {};
  final Set<Route<dynamic>> _routes = {};
  final Map<Route<dynamic>, _ManagedPredictiveGesture> _gestures = {};
  CCPopGuardEvaluator? _popGuardEvaluator;
  Timer? _terminalCleanup;
  bool _disposed = false;
  bool _claimsPlatformGesture = false;
  bool _platformObserverAttached = false;
  String? _lastAutomaticCommit;

  /// Whether the bridge accepts new gestures.
  @override
  bool get isActive => !_disposed;

  /// Attaches the platform observer. Constructor failures remain atomic.
  void attach() {
    if (_disposed || _platformObserverAttached) return;
    WidgetsBinding.instance.addObserver(this);
    _platformObserverAttached = true;
  }

  /// Binds Runtime PopGuard evaluation to this Host lifecycle.
  void bindPopGuardEvaluator(CCPopGuardEvaluator? evaluator) {
    if (!_disposed || evaluator == null) _popGuardEvaluator = evaluator;
  }

  @override
  /// Claims only current, identity-known predictive gestures.
  bool handleStartBackGesture(PredictiveBackEvent event) {
    if (_disposed) {
      _endPlatformGesture();
      return false;
    }
    _claimsPlatformGesture = false;
    if (event.isButtonEvent) {
      _recordFallback(CCManagedPredictiveBackFallbackReason.buttonEvent);
      return false;
    }
    var fallback = CCManagedPredictiveBackFallbackReason.noEligibleRoute;
    for (final route in _routes) {
      if (route is! PageRoute<dynamic>) continue;
      final context = route.subtreeContext;
      if (context == null) {
        fallback = CCManagedPredictiveBackFallbackReason.routeUnavailable;
        continue;
      }
      PageTransitionsBuilder? transition;
      try {
        final theme = Theme.of(context);
        if (theme.platform == TargetPlatform.android) {
          transition = theme.pageTransitionsTheme.builders[theme.platform];
        }
      } catch (_) {
        fallback = CCManagedPredictiveBackFallbackReason.routeUnavailable;
        continue;
      }
      if (transition.runtimeType != PredictiveBackPageTransitionsBuilder &&
          transition.runtimeType !=
              PredictiveBackFullscreenPageTransitionsBuilder) {
        fallback = CCManagedPredictiveBackFallbackReason.unsupportedTransition;
        continue;
      }
      if (!route.isCurrent) {
        fallback = CCManagedPredictiveBackFallbackReason.routeNotCurrent;
        continue;
      }
      bool enabled;
      try {
        enabled = route.popGestureEnabled;
      } catch (_) {
        fallback = CCManagedPredictiveBackFallbackReason.routeUnavailable;
        continue;
      }
      if (!enabled) {
        fallback = CCManagedPredictiveBackFallbackReason.routeBlocked;
        continue;
      }
      if (!identical(route.navigator, _navigatorForOutlet(_activeOutlet()))) {
        fallback = CCManagedPredictiveBackFallbackReason.inactiveOutlet;
        continue;
      }
      final id = _backendEntryIdForRoute(route);
      if (id != null && _hasLiveEntry(id)) {
        _claimsPlatformGesture = true;
        return true;
      }
      fallback = CCManagedPredictiveBackFallbackReason.unknownManagedEntry;
    }
    _recordFallback(fallback);
    return false;
  }

  @override
  /// Consumes a late platform commit after Host teardown.
  void handleCommitBackGesture() => _endPlatformGesture();

  @override
  /// Releases terminal-only observation on platform cancellation.
  void handleCancelBackGesture() => _endPlatformGesture();

  void _endPlatformGesture() {
    _claimsPlatformGesture = false;
    _terminalCleanup?.cancel();
    _terminalCleanup = null;
    if (_disposed) _detachObserver();
  }

  void _detachObserver() {
    if (!_platformObserverAttached) return;
    _platformObserverAttached = false;
    scheduleMicrotask(() => WidgetsBinding.instance.removeObserver(this));
  }

  @override
  /// Registers a Route while Flutter owns its lifetime.
  void onAttach(Route<dynamic> route) {
    if (!_disposed) _routes.add(route);
  }

  @override
  /// Captures the exact Entry at gesture start.
  void onStart(Route<dynamic> route) {
    if (_disposed) return;
    final id = _backendEntryIdForRoute(route);
    if (id == null || !_hasLiveEntry(id)) return;
    final outlet = _activeOutlet();
    for (final previous in _gestures.values.toList()) {
      if (previous.outlet == outlet) _cancelGesture(previous);
    }
    _gestures[route] = _ManagedPredictiveGesture(id, outlet);
    _emit(const _ManagedPredictiveReport.started());
  }

  @override
  /// Reports progress only while identity and Outlet remain valid.
  void onUpdate(Route<dynamic> route, double progress) {
    final gesture = _gestures[route];
    if (gesture == null || gesture.ended || _disposed) return;
    if (!canCommit(route)) {
      _cancelGesture(gesture);
      return;
    }
    _validateProgress(progress);
    _emit(_ManagedPredictiveReport.updated(progress));
  }

  @override
  /// Cancels one preview without mutating navigation state.
  void onCancel(Route<dynamic> route) {
    final gesture = _gestures.remove(route);
    if (gesture != null) _cancelGesture(gesture);
  }

  @override
  /// Verifies exact backend identity before Flutter commits its Pop.
  bool canCommit(Route<dynamic> route) {
    final gesture = _gestures[route];
    if (_disposed) return false;
    if (gesture == null) return true;
    return !gesture.ended &&
        route.isCurrent &&
        _activeOutlet() == gesture.outlet &&
        identical(route.navigator, _navigatorForOutlet(gesture.outlet)) &&
        _backendEntryIdForRoute(route) == gesture.backendEntryId &&
        _hasLiveEntry(gesture.backendEntryId);
  }

  @override
  /// Records that Flutter is about to perform its sole Pop.
  void onCommit(Route<dynamic> route) {
    final gesture = _gestures[route];
    if (gesture != null && !gesture.ended) gesture.commitRequested = true;
  }

  @override
  /// Releases Route and gesture references during Navigator teardown.
  void onDispose(Route<dynamic> route) {
    _routes.remove(route);
    onCancel(route);
  }

  /// Invalidates previews when another Outlet becomes active.
  void invalidateInactiveOutlets() {
    for (final gesture in _gestures.values.toList()) {
      if (!gesture.commitRequested && gesture.outlet != _activeOutlet()) {
        _cancelGesture(gesture);
      }
    }
  }

  /// Confirms a committed Pop after the exact backend removal event.
  void observeBackendEvent(CCNavigationBackendEvent event) {
    if (_disposed) return;
    for (final item in _gestures.entries.toList()) {
      final gesture = item.value;
      if (gesture.ended) continue;
      if (event.kind == CCNavigationBackendEventKind.pop &&
          gesture.backendEntryId == event.backendEntryId &&
          gesture.commitRequested &&
          event.owner == CCBackendEntryOwner.managed) {
        gesture.ended = true;
        _gestures.remove(item.key);
        _lastAutomaticCommit = gesture.backendEntryId;
        _emit(
          _ManagedPredictiveReport.committed(
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
      } else if (!gesture.commitRequested &&
          event.navigatorOutlet == gesture.outlet) {
        _cancelGesture(gesture);
      }
    }
  }

  /// Evaluates a synchronous Runtime PopGuard, if one is bound.
  CCPopGuardDecision evaluateStart() =>
      _popGuardEvaluator?.call(CCPopTrigger.predictiveBack) ??
      const CCPopAllow();

  @override
  /// Subscribes to predictive phases until the returned callback is called.
  void Function() addPredictiveBackListener(
    CCPredictiveBackEventListener listener,
  ) {
    if (_disposed) return () {};
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Reports a manually integrated start when no automatic Route is involved.
  void started() {
    if (!_automaticallyTracking)
      _emit(const _ManagedPredictiveReport.started());
  }

  /// Reports manually integrated progress.
  void updated(double progress) {
    _validateProgress(progress);
    if (!_automaticallyTracking)
      _emit(_ManagedPredictiveReport.updated(progress));
  }

  /// Reports manually integrated cancellation.
  void cancelled([double progress = 0]) {
    _validateProgress(progress);
    if (!_automaticallyTracking) {
      _emit(_ManagedPredictiveReport.cancelled(progress));
    }
  }

  /// Reports manually integrated commit after backend removal.
  void committed(CCPopOutcome outcome) {
    if (_automaticallyTracking ||
        (outcome.removedBackendEntryId != null &&
            outcome.removedBackendEntryId == _lastAutomaticCommit)) {
      return;
    }
    _emit(_ManagedPredictiveReport.committed(outcome));
  }

  void _cancelGesture(_ManagedPredictiveGesture gesture) {
    if (gesture.ended) return;
    gesture.ended = true;
    _emit(const _ManagedPredictiveReport.cancelled(0));
  }

  bool get _automaticallyTracking =>
      _gestures.values.any((gesture) => !gesture.ended);

  void _validateProgress(double progress) {
    if (!progress.isFinite || progress < 0 || progress > 1) {
      throw ArgumentError.value(
        progress,
        'progress',
        'Must be between 0 and 1.',
      );
    }
  }

  void _emit(_ManagedPredictiveReport report) {
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
        // Diagnostics must not interrupt Flutter's platform callback.
      }
    }
  }

  /// Permanently releases observer, timers, routes and Runtime listeners.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_claimsPlatformGesture) {
      _terminalCleanup = Timer(
        const Duration(seconds: 30),
        _endPlatformGesture,
      );
    } else {
      _detachObserver();
    }
    _popGuardEvaluator = null;
    _listeners.clear();
    _gestures.clear();
    _routes.clear();
    _lastAutomaticCommit = null;
  }
}

final class _ManagedPredictiveGesture {
  _ManagedPredictiveGesture(this.backendEntryId, this.outlet);
  final String backendEntryId;
  final String outlet;
  bool commitRequested = false;
  bool ended = false;
}

final class _ManagedPredictiveReport {
  const _ManagedPredictiveReport.started()
    : phase = CCPredictiveBackPhase.started,
      progress = 0,
      outcome = null;
  const _ManagedPredictiveReport.updated(this.progress)
    : phase = CCPredictiveBackPhase.updated,
      outcome = null;
  const _ManagedPredictiveReport.cancelled(this.progress)
    : phase = CCPredictiveBackPhase.cancelled,
      outcome = null;
  const _ManagedPredictiveReport.committed(this.outcome)
    : phase = CCPredictiveBackPhase.committed,
      progress = 1;
  final CCPredictiveBackPhase phase;
  final double progress;
  final CCPopOutcome? outcome;
}
