import 'package:demo_analytics/demo_analytics.dart';
import 'package:flutter/widgets.dart';

/// Provides an inherited analytics dispatcher and stable context to a subtree.
///
/// A root Scope normally receives the application-owned Dispatcher. Nested
/// Scopes may omit [dispatcher] and add only page or feature context. The
/// Scope never closes or otherwise owns the Dispatcher; the Composition Root
/// remains responsible for its lifecycle. It also does not inspect Routes,
/// Widgets, pointer events, or foreign overlays.
final class AppAnalyticsScope extends StatefulWidget {
  /// Creates an analytics Scope around [child].
  const AppAnalyticsScope({
    required this.child,
    this.dispatcher,
    this.context = const AppAnalyticsContext(),
    this.enabled = true,
    super.key,
  });

  /// Dispatcher inherited from this Scope or the nearest parent Scope.
  final AppAnalyticsEventDispatcher? dispatcher;

  /// Stable context fields added to the nearest parent context.
  final AppAnalyticsContext context;

  /// Local enablement combined with every enabled parent Scope.
  final bool enabled;

  /// Subtree receiving the inherited analytics data.
  final Widget child;

  /// Returns a tracker for the nearest Scope and an optional local context.
  ///
  /// Throws [FlutterError] when no Scope with a Dispatcher is an ancestor.
  /// The returned tracker is a value object and does not retain [context].
  static AppAnalyticsTracker trackerOf(
    BuildContext context, {
    AppAnalyticsContext analyticsContext = const AppAnalyticsContext(),
  }) {
    final tracker = maybeTrackerOf(context, analyticsContext: analyticsContext);
    if (tracker == null) {
      throw FlutterError(
        'AppAnalyticsScope.trackerOf() requires an ancestor '
        'AppAnalyticsScope with a dispatcher.',
      );
    }
    return tracker;
  }

  /// Returns a tracker when a configured Scope is available, otherwise null.
  ///
  /// A disabled Scope still returns a disabled tracker so a feature can keep
  /// one callback path without changing its business behavior.
  static AppAnalyticsTracker? maybeTrackerOf(
    BuildContext context, {
    AppAnalyticsContext analyticsContext = const AppAnalyticsContext(),
  }) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_AppAnalyticsInherited>()
        ?.data;
    final dispatcher = inherited?.dispatcher;
    if (dispatcher == null) return null;
    return AppAnalyticsTracker(
      dispatcher: dispatcher,
      context: inherited!.context.merge(analyticsContext),
      enabled: inherited.enabled,
    );
  }

  @override
  State<AppAnalyticsScope> createState() => _AppAnalyticsScopeState();
}

/// Holds the immutable value inherited by one Scope subtree.
final class _AppAnalyticsScopeData {
  const _AppAnalyticsScopeData({
    required this.dispatcher,
    required this.context,
    required this.enabled,
  });

  final AppAnalyticsEventDispatcher? dispatcher;
  final AppAnalyticsContext context;
  final bool enabled;

  bool sameAs(_AppAnalyticsScopeData other) =>
      dispatcher == other.dispatcher &&
      enabled == other.enabled &&
      _sameContext(context, other.context);
}

/// Inherited implementation kept private so the public API remains a Scope.
final class _AppAnalyticsInherited extends InheritedWidget {
  const _AppAnalyticsInherited({required this.data, required super.child});

  final _AppAnalyticsScopeData data;

  @override
  bool updateShouldNotify(_AppAnalyticsInherited oldWidget) =>
      !data.sameAs(oldWidget.data);
}

final class _AppAnalyticsScopeState extends State<AppAnalyticsScope> {
  _AppAnalyticsScopeData? _parent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _parent = context
        .dependOnInheritedWidgetOfExactType<_AppAnalyticsInherited>()
        ?.data;
  }

  @override
  Widget build(BuildContext context) {
    final parent = _parent;
    final data = _AppAnalyticsScopeData(
      dispatcher: widget.dispatcher ?? parent?.dispatcher,
      context: (parent?.context ?? const AppAnalyticsContext()).merge(
        widget.context,
      ),
      enabled: (parent?.enabled ?? true) && widget.enabled,
    );
    return _AppAnalyticsInherited(data: data, child: widget.child);
  }
}

bool _sameContext(AppAnalyticsContext first, AppAnalyticsContext second) =>
    first.navigationId == second.navigationId &&
    first.traceId == second.traceId &&
    first.routeId == second.routeId &&
    first.componentId == second.componentId &&
    first.hostId == second.hostId &&
    first.outlet == second.outlet &&
    first.source == second.source &&
    first.anonymousVisitorId == second.anonymousVisitorId &&
    first.applicationSessionId == second.applicationSessionId;
