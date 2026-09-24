import 'dart:async';
import 'dart:math' as math;

import 'package:ccrouter_analytics/ccrouter_analytics.dart';
import 'package:flutter/widgets.dart';

/// Emits one exposure event after an explicitly wrapped target stays visible.
///
/// Visibility is an approximation based on the target's global paint bounds
/// and the current Flutter view. It is intended for stable cards, banners, and
/// list items, not for security decisions or pixel-perfect ad measurement.
/// The widget does not inspect text, install global pointer listeners, or
/// retain a [BuildContext] after disposal.
final class CCAnalyticsExposureTarget extends StatefulWidget {
  /// Creates an exposure target around [child].
  CCAnalyticsExposureTarget({
    required this.child,
    required this.tracker,
    required this.eventId,
    this.minimumVisibleFraction = 0.5,
    this.minimumVisibleDuration = const Duration(milliseconds: 500),
    this.once = true,
    this.baseProperties = const CCAnalyticsProperties.empty(),
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
  final CCAnalyticsTracker tracker;

  /// Stable event ID emitted after the dwell threshold is reached.
  final String eventId;

  /// Minimum fraction of the target area that must intersect the view.
  final double minimumVisibleFraction;

  /// Minimum continuous duration for which the target must be eligible.
  final Duration minimumVisibleDuration;

  /// Whether to emit at most one event for the lifetime of this target.
  final bool once;

  /// Stable primitive properties copied onto the exposure event.
  final CCAnalyticsProperties baseProperties;

  @override
  State<CCAnalyticsExposureTarget> createState() =>
      _CCAnalyticsExposureTargetState();
}

/// Owns the short-lived exposure timer and visibility episode state.
final class _CCAnalyticsExposureTargetState
    extends State<CCAnalyticsExposureTarget>
    with WidgetsBindingObserver {
  Timer? _timer;
  BuildContext? _targetContext;
  bool _evaluationScheduled = false;
  bool _hasReported = false;
  bool _reportedForVisibility = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleEvaluation();
  }

  @override
  void didUpdateWidget(covariant CCAnalyticsExposureTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId ||
        oldWidget.tracker != widget.tracker ||
        oldWidget.minimumVisibleFraction != widget.minimumVisibleFraction ||
        oldWidget.minimumVisibleDuration != widget.minimumVisibleDuration ||
        oldWidget.once != widget.once) {
      _cancelEpisode();
      _hasReported = false;
      _reportedForVisibility = false;
      _scheduleEvaluation();
    }
  }

  @override
  Widget build(BuildContext context) {
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
    _targetContext = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleEvaluation();
      return;
    }
    _cancelEpisode();
    _reportedForVisibility = false;
  }

  /// Defers measurement until layout has produced current paint bounds.
  void _scheduleEvaluation() {
    if (_evaluationScheduled) return;
    _evaluationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _evaluationScheduled = false;
      if (mounted) _evaluateVisibility();
    });
  }

  /// Starts, completes, or cancels the current continuous visibility episode.
  void _evaluateVisibility() {
    final fraction = _visibleFraction();
    final eligible = fraction >= widget.minimumVisibleFraction;
    if (!eligible) {
      _cancelEpisode();
      _reportedForVisibility = false;
      return;
    }
    if ((widget.once && _hasReported) || _reportedForVisibility) return;
    if (widget.minimumVisibleDuration <= Duration.zero) {
      _report(fraction);
      return;
    }
    _timer ??= Timer(widget.minimumVisibleDuration, () {
      _timer = null;
      if (!mounted) return;
      final currentFraction = _visibleFraction();
      if (currentFraction >= widget.minimumVisibleFraction) {
        _report(currentFraction);
      } else {
        _cancelEpisode();
      }
    });
  }

  /// Measures the target's area fraction intersecting the current view.
  double _visibleFraction() {
    final targetContext = _targetContext;
    final renderObject = targetContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return 0;
    final size = renderObject.size;
    final area = size.width * size.height;
    if (area <= 0 || !renderObject.attached) return 0;
    final origin = renderObject.localToGlobal(Offset.zero);
    final target = Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height);
    final viewSize =
        MediaQuery.maybeSizeOf(context) ??
        View.of(context).physicalSize / View.of(context).devicePixelRatio;
    final left = math.max(target.left, 0);
    final top = math.max(target.top, 0);
    final right = math.min(target.right, viewSize.width);
    final bottom = math.min(target.bottom, viewSize.height);
    if (right <= left || bottom <= top) return 0;
    return ((right - left) * (bottom - top) / area).clamp(0, 1);
  }

  /// Emits one sanitized exposure event with the measured fraction.
  void _report(double fraction) {
    widget.tracker.exposure(
      eventId: widget.eventId,
      properties: CCAnalyticsProperties.from([
        ...widget.baseProperties.values.entries.map(
          (entry) => CCAnalyticsProperty(entry.key, entry.value),
        ),
        CCAnalyticsProperty('visible_fraction', fraction),
      ]),
    );
    _reportedForVisibility = true;
    _hasReported = true;
  }

  /// Cancels the current dwell timer and clears its episode state.
  void _cancelEpisode() {
    _timer?.cancel();
    _timer = null;
  }
}
