import 'package:ccrouter_analytics/ccrouter_analytics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Wraps one explicit Scrollable target and emits aggregate scroll events.
///
/// The widget observes only bubbling [ScrollNotification] objects from its
/// child. It never installs a global pointer listener, consumes notifications,
/// creates a [ScrollController], or changes scrolling physics. By default only
/// user-drag sessions are tracked; callers may opt into programmatic sessions
/// with [includeProgrammatic].
final class CCAnalyticsScrollable extends StatefulWidget {
  /// Creates a scroll analytics target around [child].
  const CCAnalyticsScrollable({
    required this.child,
    required this.tracker,
    required this.eventId,
    this.startEventId,
    this.includeProgrammatic = false,
    this.baseProperties = const CCAnalyticsProperties.empty(),
    super.key,
  });

  /// Scrollable subtree whose notifications are observed.
  final Widget child;

  /// Tracker receiving the aggregate events.
  final CCAnalyticsTracker tracker;

  /// Stable event ID for the aggregated scroll-end event.
  final String eventId;

  /// Optional event ID emitted when an eligible scroll session starts.
  final String? startEventId;

  /// Whether programmatic scroll sessions without drag details are tracked.
  final bool includeProgrammatic;

  /// Stable primitive properties copied onto emitted events.
  final CCAnalyticsProperties baseProperties;

  @override
  State<CCAnalyticsScrollable> createState() => _CCAnalyticsScrollableState();
}

/// State that owns one in-progress scroll measurement and no external resource.
final class _CCAnalyticsScrollableState extends State<CCAnalyticsScrollable> {
  double? _startPixels;
  DateTime? _startedAt;
  String _direction = 'idle';

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: widget.child,
      );

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      final isUserSession = notification.dragDetails != null;
      if (!widget.includeProgrammatic && !isUserSession) {
        _reset();
        return false;
      }
      _startPixels = notification.metrics.pixels;
      _startedAt = DateTime.now();
      _direction = 'idle';
      final startEventId = widget.startEventId;
      if (startEventId != null) {
        widget.tracker.track(
          eventId: startEventId,
          type: CCAnalyticsEventType.scroll,
          properties: _properties({'phase': 'start'}),
        );
      }
      return false;
    }
    if (notification is UserScrollNotification) {
      _direction = switch (notification.direction) {
        ScrollDirection.forward => 'forward',
        ScrollDirection.reverse => 'reverse',
        ScrollDirection.idle => 'idle',
      };
      return false;
    }
    if (notification is ScrollEndNotification && _startedAt != null) {
      final startPixels = _startPixels ?? notification.metrics.pixels;
      final distance = (notification.metrics.pixels - startPixels).abs();
      final duration = DateTime.now().difference(_startedAt!);
      widget.tracker.scroll(
        eventId: widget.eventId,
        properties: _properties({
          'phase': 'end',
          'direction': _direction,
          'distance_bucket': _distanceBucket(distance),
          'duration_bucket': _durationBucket(duration),
        }),
      );
      _reset();
    }
    return false;
  }

  CCAnalyticsProperties _properties(Map<String, Object> values) {
    return CCAnalyticsProperties.from([
      ...widget.baseProperties.values.entries.map(
        (entry) => CCAnalyticsProperty(entry.key, entry.value),
      ),
      ...values.entries.map(
        (entry) => CCAnalyticsProperty(entry.key, entry.value),
      ),
    ]);
  }

  void _reset() {
    _startPixels = null;
    _startedAt = null;
    _direction = 'idle';
  }
}

/// Converts a scroll distance into a bounded provider-neutral bucket.
String _distanceBucket(double distance) {
  if (distance <= 0) return '0';
  if (distance < 24) return '1-23';
  if (distance < 120) return '24-119';
  if (distance < 480) return '120-479';
  return '480-plus';
}

/// Converts a session duration into a bounded provider-neutral bucket.
String _durationBucket(Duration duration) {
  if (duration < const Duration(milliseconds: 250)) return '0-249ms';
  if (duration < const Duration(seconds: 1)) return '250-999ms';
  if (duration < const Duration(seconds: 3)) return '1-2s';
  return '3s-plus';
}
