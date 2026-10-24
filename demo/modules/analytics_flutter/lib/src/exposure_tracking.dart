import 'dart:async';

import 'package:demo_analytics/demo_analytics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Emits one exposure event after an explicitly wrapped target stays visible.
///
/// Visibility is an approximation based on the target's global paint bounds
/// intersected with ancestor paint clips and the current Flutter view. It is
/// intended for stable cards, banners, and list items, not for security
/// decisions or pixel-perfect ad measurement. Arbitrary overlay occlusion and
/// opacity are not detected. Ancestor scrolling and policy changes trigger
/// fresh measurements without requiring the application to rebuild the target.
/// The widget does not inspect text, install global pointer listeners, or
/// retain a [BuildContext] after disposal.
final class AppAnalyticsExposureTarget extends StatefulWidget {
  /// Creates an exposure target around [child].
  AppAnalyticsExposureTarget({
    required this.child,
    required this.tracker,
    required this.eventId,
    this.minimumVisibleFraction = 0.5,
    this.minimumVisibleDuration = const Duration(milliseconds: 500),
    this.once = true,
    this.baseProperties = const AppAnalyticsProperties.empty(),
    super.key,
  }) : assert(
         minimumVisibleFraction >= 0 && minimumVisibleFraction <= 1,
         'minimumVisibleFraction must be between 0 and 1.',
       ) {
    if (minimumVisibleDuration.isNegative) {
      throw ArgumentError.value(
        minimumVisibleDuration,
        'minimumVisibleDuration',
        'Cannot be negative.',
      );
    }
  }

  /// Target whose visible bounds are measured.
  final Widget child;

  /// Tracker receiving the exposure event.
  final AppAnalyticsTracker tracker;

  /// Stable event ID emitted after the dwell threshold is reached.
  final String eventId;

  /// Minimum fraction intersecting the view and ancestor paint clips.
  /// A completely invisible target never qualifies, even with a zero threshold.
  final double minimumVisibleFraction;

  /// Minimum continuous foreground, consent-granted visible duration.
  /// Revocation, backgrounding, and detach discard partial dwell time.
  final Duration minimumVisibleDuration;

  /// Whether to accept at most one event for the lifetime of this target.
  /// Acceptance is admission to the dispatcher, not guaranteed Sink delivery.
  /// Filtered attempts do not consume this allowance, but are not retried until
  /// a new visibility episode or policy change, avoiding per-frame resampling.
  final bool once;

  /// Stable primitive properties copied onto the exposure event.
  final AppAnalyticsProperties baseProperties;

  @override
  State<AppAnalyticsExposureTarget> createState() =>
      _AppAnalyticsExposureTargetState();
}

/// Owns the short-lived exposure timer and visibility episode state.
final class _AppAnalyticsExposureTargetState
    extends State<AppAnalyticsExposureTarget>
    with WidgetsBindingObserver {
  /// One dwell timer per eligible visibility episode.
  Timer? _timer;

  /// Render lookup owned only while this target is attached.
  BuildContext? _targetContext;

  /// Coalesces scroll/layout/policy signals into one measurement per frame.
  bool _evaluationScheduled = false;

  /// True only after the dispatcher accepted a lifetime exposure event.
  bool _hasReported = false;

  /// Rejected samples are attempted only once per episode, never polled.
  bool _attemptedForVisibility = false;

  /// Positions of enclosing scrollables whose motion changes target bounds.
  final Set<ScrollPosition> _positions = {};

  /// Releases the application-owned dispatcher's policy observation.
  void Function()? _removePolicyListener;

  /// Prevents callbacks from measuring a temporarily detached GlobalKey child.
  bool _active = true;

  /// Background frames cannot start a new dwell timer.
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _observePolicy();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindScrollPositions();
    _scheduleEvaluation();
  }

  @override
  void didUpdateWidget(covariant AppAnalyticsExposureTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tracker.dispatcher != widget.tracker.dispatcher) {
      _observePolicy();
    }
    if (oldWidget.eventId != widget.eventId ||
        oldWidget.tracker != widget.tracker ||
        oldWidget.minimumVisibleFraction != widget.minimumVisibleFraction ||
        oldWidget.minimumVisibleDuration != widget.minimumVisibleDuration ||
        oldWidget.once != widget.once) {
      _cancelEpisode();
      _hasReported = false;
      _attemptedForVisibility = false;
      _scheduleEvaluation();
    }
  }

  @override
  Widget build(BuildContext context) {
    _bindScrollPositions();
    _scheduleEvaluation();
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _scheduleEvaluation();
        return false;
      },
      child: Builder(
        builder: (targetContext) {
          _targetContext = targetContext;
          return widget.child;
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelEpisode();
    _unbindScrollPositions();
    _removePolicyListener?.call();
    _removePolicyListener = null;
    _targetContext = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _scheduleEvaluation();
      return;
    }
    _cancelEpisode();
    _attemptedForVisibility = false;
  }

  @override
  void didChangeMetrics() => _scheduleEvaluation();

  @override
  void deactivate() {
    _active = false;
    _cancelEpisode();
    _attemptedForVisibility = false;
    _unbindScrollPositions();
    _removePolicyListener?.call();
    _removePolicyListener = null;
    _targetContext = null;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    _observePolicy();
    _scheduleEvaluation();
  }

  /// Subscribes to privacy transitions without requiring application rebuilds.
  void _observePolicy() {
    _removePolicyListener?.call();
    _removePolicyListener = widget.tracker.dispatcher.addPolicyListener(() {
      _cancelEpisode();
      _attemptedForVisibility = false;
      _scheduleEvaluation();
    });
  }

  /// Binds actual ancestor positions; descendant notifications alone cannot do so.
  void _bindScrollPositions() {
    // Depend on the nearest scrollable in each axis so position replacements
    // invalidate this State, including common vertical/horizontal nesting.
    Scrollable.maybeOf(context, axis: Axis.vertical);
    Scrollable.maybeOf(context, axis: Axis.horizontal);
    final next = <ScrollPosition>{};
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        next.add((element.state as ScrollableState).position);
      }
      return true;
    });
    for (final position in _positions.difference(next)) {
      position.removeListener(_scheduleEvaluation);
    }
    for (final position in next.difference(_positions)) {
      position.addListener(_scheduleEvaluation);
    }
    _positions
      ..clear()
      ..addAll(next);
  }

  /// Detaches every listener without disposing application-owned positions.
  void _unbindScrollPositions() {
    for (final position in _positions) {
      position.removeListener(_scheduleEvaluation);
    }
    _positions.clear();
  }

  /// Defers measurement until layout has produced current paint bounds.
  void _scheduleEvaluation() {
    if (!mounted || !_active || _evaluationScheduled) return;
    _evaluationScheduled = true;
    final target = WeakReference(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = target.target;
      if (state == null) return;
      state._evaluationScheduled = false;
      if (state.mounted && state._active) state._evaluateVisibility();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Starts, completes, or cancels the current continuous visibility episode.
  void _evaluateVisibility() {
    if (!_canMeasure) {
      _cancelEpisode();
      _attemptedForVisibility = false;
      return;
    }
    final fraction = _visibleFraction();
    final eligible = fraction > 0 && fraction >= widget.minimumVisibleFraction;
    if (!eligible) {
      _cancelEpisode();
      _attemptedForVisibility = false;
      return;
    }
    if ((widget.once && _hasReported) || _attemptedForVisibility) return;
    if (widget.minimumVisibleDuration <= Duration.zero) {
      _report(fraction);
      return;
    }
    _timer ??= Timer(widget.minimumVisibleDuration, () {
      _timer = null;
      if (!mounted || !_canMeasure) return;
      final currentFraction = _visibleFraction();
      if (currentFraction > 0 &&
          currentFraction >= widget.minimumVisibleFraction) {
        _report(currentFraction);
      } else {
        _cancelEpisode();
      }
    });
  }

  /// Dwell time excludes denied, closed, inactive, and background periods.
  bool get _canMeasure {
    final dispatcher = widget.tracker.dispatcher;
    return _active &&
        _foreground &&
        !dispatcher.isClosed &&
        dispatcher.policy.enabled &&
        dispatcher.policy.consentGranted;
  }

  /// Measures the target's area fraction intersecting the current view.
  double _visibleFraction() {
    final targetContext = _targetContext;
    final renderObject = targetContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return 0;
    final size = renderObject.size;
    final area = size.width * size.height;
    if (area <= 0 || !renderObject.attached) return 0;
    final target = MatrixUtils.transformRect(
      renderObject.getTransformTo(null),
      Offset.zero & size,
    );
    if (!target.isFinite || target.isEmpty) return 0;
    final viewSize =
        MediaQuery.maybeSizeOf(context) ??
        View.of(context).physicalSize / View.of(context).devicePixelRatio;
    var visible = target.intersect(Offset.zero & viewSize);
    RenderObject child = renderObject;
    while (child.parent != null) {
      final parent = child.parent!;
      if (parent is RenderOffstage && parent.offstage) return 0;
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        visible = visible.intersect(
          MatrixUtils.transformRect(parent.getTransformTo(null), clip),
        );
      }
      child = parent;
    }
    if (!visible.isFinite || visible.isEmpty) return 0;
    return (visible.width * visible.height / (target.width * target.height))
        .clamp(0, 1);
  }

  /// Emits one sanitized exposure event with the measured fraction.
  void _report(double fraction) {
    final accepted = widget.tracker.exposure(
      eventId: widget.eventId,
      properties: AppAnalyticsProperties.from([
        ...widget.baseProperties.values.entries.map(
          (entry) => AppAnalyticsProperty(entry.key, entry.value),
        ),
        AppAnalyticsProperty('visible_fraction', fraction),
      ]),
    );
    _attemptedForVisibility = true;
    if (accepted) _hasReported = true;
  }

  /// Cancels the current dwell timer and clears its episode state.
  void _cancelEpisode() {
    _timer?.cancel();
    _timer = null;
  }
}
