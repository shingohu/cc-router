part of 'adapter.dart';

/// Host-only bridge for platform predictive-back gesture phases.
///
/// Create it by passing `enablePredictiveBack: true` to
/// [CCGoRouterAdapter]. The bridge reports observations only; the platform
/// host remains responsible for driving the actual Navigator gesture and must
/// provide a [CCPopOutcome] only after a committed backend Pop.
final class CCGoRouterPredictiveBackBridge
    implements CCNavigationPredictiveBackSource {
  /// Creates an adapter-owned bridge with no public constructor.
  CCGoRouterPredictiveBackBridge._();

  /// Runtime listeners receiving platform predictive-back phases.
  final Set<CCPredictiveBackEventListener> _listeners = {};

  /// Runtime-owned synchronous guard evaluator, while the Adapter is active.
  CCPopGuardEvaluator? _popGuardEvaluator;

  /// Whether the owning Adapter has been disposed.
  bool _disposed = false;

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
  void started() => _emit(const _PredictiveBackReport.started());

  /// Reports interactive gesture progress in the range 0..1.
  void updated(double progress) {
    _validateProgress(progress);
    _emit(_PredictiveBackReport.updated(progress));
  }

  /// Reports that the platform cancelled and restored the gesture.
  void cancelled([double progress = 0]) {
    _validateProgress(progress);
    _emit(_PredictiveBackReport.cancelled(progress));
  }

  /// Reports a committed Pop after the backend removed its route.
  void committed(CCPopOutcome outcome) {
    _emit(_PredictiveBackReport.committed(outcome));
  }

  /// Installs or clears the Runtime evaluator owned by the Adapter lifecycle.
  void _bindPopGuardEvaluator(CCPopGuardEvaluator? evaluator) {
    if (_disposed && evaluator != null) return;
    _popGuardEvaluator = evaluator;
  }

  /// Rejects platform progress values outside the normalized gesture range.
  void _validateProgress(double progress) {
    if (progress < 0 || progress > 1) {
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
    _popGuardEvaluator = null;
    _listeners.clear();
  }
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
