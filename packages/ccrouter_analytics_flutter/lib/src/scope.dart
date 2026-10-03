import 'package:ccrouter_analytics/ccrouter_analytics.dart';
import 'package:flutter/widgets.dart';

/// Provides an inherited analytics dispatcher and stable context to a subtree.
///
/// A root Scope normally receives the application-owned Dispatcher. Nested
/// Scopes may omit [dispatcher] and add only page or feature context. The
/// Scope never closes or otherwise owns the Dispatcher; the Composition Root
/// remains responsible for its lifecycle. It also does not inspect Routes,
/// Widgets, pointer events, or foreign overlays.
final class CCAnalyticsScope extends StatefulWidget {
  /// Creates an analytics Scope around [child].
  const CCAnalyticsScope({
    required this.child,
    this.dispatcher,
    this.context = const CCAnalyticsContext(),
    this.enabled = true,
    super.key,
  });

  /// Dispatcher inherited from this Scope or the nearest parent Scope.
  final CCAnalyticsEventDispatcher? dispatcher;

  /// Stable context fields added to the nearest parent context.
  final CCAnalyticsContext context;

  /// Local enablement combined with every enabled parent Scope.
  final bool enabled;

  /// Subtree receiving the inherited analytics data.
  final Widget child;

  /// Returns a tracker for the nearest Scope and an optional local context.
  ///
  /// Throws [FlutterError] when no Scope with a Dispatcher is an ancestor.
  /// The returned tracker is a value object and does not retain [context].
  static CCAnalyticsTracker trackerOf(
    BuildContext context, {
    CCAnalyticsContext analyticsContext = const CCAnalyticsContext(),
  }) {
    final tracker = maybeTrackerOf(context, analyticsContext: analyticsContext);
    if (tracker == null) {
      throw FlutterError(
        'CCAnalyticsScope.trackerOf() requires an ancestor '
        'CCAnalyticsScope with a dispatcher.',
      );
    }
    return tracker;
  }

  /// Returns a tracker when a configured Scope is available, otherwise null.
  ///
  /// A disabled Scope still returns a disabled tracker so a feature can keep
  /// one callback path without changing its business behavior.
  static CCAnalyticsTracker? maybeTrackerOf(
    BuildContext context, {
    CCAnalyticsContext analyticsContext = const CCAnalyticsContext(),
  }) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_CCAnalyticsInherited>()
        ?.data;
    final dispatcher = inherited?.dispatcher;
    if (dispatcher == null) return null;
    return CCAnalyticsTracker(
      dispatcher: dispatcher,
      context: inherited!.context.merge(analyticsContext),
      enabled: inherited.enabled,
    );
  }

  @override
  State<CCAnalyticsScope> createState() => _CCAnalyticsScopeState();
}

/// Holds the immutable value inherited by one Scope subtree.
final class _CCAnalyticsScopeData {
  const _CCAnalyticsScopeData({
    required this.dispatcher,
    required this.context,
    required this.enabled,
  });

  final CCAnalyticsEventDispatcher? dispatcher;
  final CCAnalyticsContext context;
  final bool enabled;

  bool sameAs(_CCAnalyticsScopeData other) =>
      dispatcher == other.dispatcher &&
      enabled == other.enabled &&
      _sameContext(context, other.context);
}

/// Inherited implementation kept private so the public API remains a Scope.
final class _CCAnalyticsInherited extends InheritedWidget {
  const _CCAnalyticsInherited({required this.data, required super.child});

  final _CCAnalyticsScopeData data;

  @override
  bool updateShouldNotify(_CCAnalyticsInherited oldWidget) =>
      !data.sameAs(oldWidget.data);
}

final class _CCAnalyticsScopeState extends State<CCAnalyticsScope> {
  _CCAnalyticsScopeData? _parent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _parent = context
        .dependOnInheritedWidgetOfExactType<_CCAnalyticsInherited>()
        ?.data;
  }

  @override
  Widget build(BuildContext context) {
    final parent = _parent;
    final data = _CCAnalyticsScopeData(
      dispatcher: widget.dispatcher ?? parent?.dispatcher,
      context: (parent?.context ?? const CCAnalyticsContext()).merge(
        widget.context,
      ),
      enabled: (parent?.enabled ?? true) && widget.enabled,
    );
    return _CCAnalyticsInherited(data: data, child: widget.child);
  }
}

bool _sameContext(CCAnalyticsContext first, CCAnalyticsContext second) =>
    first.navigationId == second.navigationId &&
    first.traceId == second.traceId &&
    first.routeId == second.routeId &&
    first.componentId == second.componentId &&
    first.hostId == second.hostId &&
    first.outlet == second.outlet &&
    first.source == second.source &&
    first.anonymousVisitorId == second.anonymousVisitorId &&
    first.applicationSessionId == second.applicationSessionId;
