import 'package:ccrouter_contracts/ccrouter_contracts.dart';

import 'analytics.dart';

/// Bridges CCRouter navigation lifecycle observations into page analytics.
///
/// The bridge treats managed Route arrival and re-show as page views. A hide
/// is one page leave because it represents the route no longer being current;
/// final removal does not create a duplicate leave event. Foreign routes and
/// overlays are never converted into CCRouter page views by this bridge.
final class CCNavigationAnalyticsBridge {
  /// Creates a navigation bridge that writes events to [dispatcher].
  CCNavigationAnalyticsBridge({
    required this.dispatcher,
    this.pageViewEventPrefix = 'page.view',
    this.pageLeaveEventPrefix = 'page.leave',
  });

  /// Bounded event dispatcher owned by the application Host.
  final CCAnalyticsEventDispatcher dispatcher;

  /// Event ID prefix used for page-view events.
  final String pageViewEventPrefix;

  /// Event ID prefix used for page-leave events.
  final String pageLeaveEventPrefix;

  /// Records that the application entered its foreground at [timestamp].
  ///
  /// Call this from the Host's application lifecycle observer. Active page
  /// visits resume their foreground dwell clock; it does not create a new
  /// PageShow event.
  void onForeground(DateTime timestamp) {
    if (_foreground) return;
    _foreground = true;
    for (final visit in _visits.values) {
      visit.foregroundStartedAt = timestamp;
    }
  }

  /// Records that the application left its foreground at [timestamp].
  ///
  /// Active visits retain total current time but stop accumulating effective
  /// foreground dwell until [onForeground] is called again.
  void onBackground(DateTime timestamp) {
    if (!_foreground) return;
    _foreground = false;
    for (final visit in _visits.values) {
      visit.addForegroundUntil(timestamp);
    }
  }

  /// Releases open visit state when the owning Host no longer uses this bridge.
  ///
  /// The bridge never owns the Dispatcher and therefore does not close it.
  void dispose() => _visits.clear();

  /// Creates a `CCNavigationAspect` for `CCRouterHost.initialize`.
  ///
  /// The returned aspect is observation-only. It cannot cancel, redirect, or
  /// otherwise change navigation behavior.
  CCNavigationAspect createAspect({
    String id = 'ccrouter.analytics.navigation',
  }) {
    return CCNavigationAspect(
      id: id,
      onArrival: _onNavigation,
      onShow: _onNavigation,
      onHide: _onNavigation,
      onRemoved: _onTerminal,
      onDisposed: _onTerminal,
    );
  }

  /// Converts one managed navigation lifecycle observation into an event.
  void _onNavigation(CCNavigationAspectEvent event) {
    final type = switch (event.phase) {
      CCNavigationAspectPhase.arrival ||
      CCNavigationAspectPhase.show => CCAnalyticsEventType.pageView,
      CCNavigationAspectPhase.hide => CCAnalyticsEventType.pageLeave,
      _ => null,
    };
    if (type == null) return;
    final request = event.request;
    // Consent is checked before retaining a visit. A route shown before
    // consent and hidden after consent does not leak a pre-consent duration.
    if (!dispatcher.policy.enabled || !dispatcher.policy.consentGranted) {
      if (event.phase == CCNavigationAspectPhase.hide) {
        _visits.remove(request.navigationId);
      }
      return;
    }
    final telemetry = request.telemetryContext;
    final prefix = type == CCAnalyticsEventType.pageView
        ? pageViewEventPrefix
        : pageLeaveEventPrefix;
    final visit = type == CCAnalyticsEventType.pageView
        ? _startVisit(request, event.timestamp)
        : _visits.remove(request.navigationId);
    final properties = <CCAnalyticsProperty>[
      CCAnalyticsProperty('operation', request.operation.name),
      CCAnalyticsProperty('phase', event.phase.name),
    ];
    if (visit != null) {
      properties.add(CCAnalyticsProperty('visit_id', visit.id));
      if (type == CCAnalyticsEventType.pageLeave) {
        properties.add(
          CCAnalyticsProperty('dwell_ms', visit.dwellUntil(event.timestamp)),
        );
        properties.add(
          CCAnalyticsProperty(
            'foreground_dwell_ms',
            visit.foregroundDwellUntil(event.timestamp),
          ),
        );
      }
    }
    dispatcher.dispatch(
      CCAnalyticsEvent(
        eventId: '$prefix.${request.routeId}',
        type: type,
        occurredAt: event.timestamp,
        navigationId: request.navigationId,
        routeId: request.routeId,
        componentId: request.ownerComponentId,
        hostId: request.resolvedHostId,
        outlet: request.navigatorOutlet,
        source: request.source?.id,
        anonymousVisitorId: telemetry?.anonymousVisitorId,
        applicationSessionId: telemetry?.applicationSessionId,
        properties: CCAnalyticsProperties.from(properties),
      ),
    );
  }

  /// Removes state when a managed Entry leaves or is disposed without a hide.
  void _onTerminal(CCNavigationAspectEvent event) {
    _visits.remove(event.request.navigationId);
  }

  _CCAnalyticsPageVisit _startVisit(
    CCNavigationAspectRequest request,
    DateTime startedAt,
  ) {
    final existing = _visits[request.navigationId];
    if (existing != null) return existing;
    if (_visits.length >= _maxOpenVisits) {
      _visits.remove(_visits.keys.first);
    }
    final visit = _CCAnalyticsPageVisit(
      id: '${request.navigationId}.v${++_visitSequence}',
      startedAt: startedAt,
      foregroundStartedAt: _foreground ? startedAt : null,
    );
    _visits[request.navigationId] = visit;
    return visit;
  }

  /// Open visits are short-lived and also capped to protect a faulty Adapter.
  static const int _maxOpenVisits = 1024;

  /// Monotonic bridge-local visit sequence used only for correlation.
  int _visitSequence = 0;

  /// Current visit by Runtime navigation identity.
  final Map<String, _CCAnalyticsPageVisit> _visits = {};

  /// Whether effective foreground time is currently accumulating.
  bool _foreground = true;
}

/// Mutable state for one visible managed navigation visit.
final class _CCAnalyticsPageVisit {
  _CCAnalyticsPageVisit({
    required this.id,
    required this.startedAt,
    required this.foregroundStartedAt,
  });

  final String id;
  final DateTime startedAt;
  DateTime? foregroundStartedAt;
  Duration foregroundElapsed = Duration.zero;

  void addForegroundUntil(DateTime timestamp) {
    final started = foregroundStartedAt;
    if (started == null) return;
    if (timestamp.isAfter(started)) {
      foregroundElapsed += timestamp.difference(started);
    }
    foregroundStartedAt = null;
  }

  int dwellUntil(DateTime timestamp) =>
      _millisecondsSince(startedAt, timestamp);

  int foregroundDwellUntil(DateTime timestamp) {
    final total =
        foregroundElapsed +
        (foregroundStartedAt == null
            ? Duration.zero
            : _safeDifference(foregroundStartedAt!, timestamp));
    return total.inMilliseconds;
  }
}

Duration _safeDifference(DateTime start, DateTime end) =>
    end.isAfter(start) ? end.difference(start) : Duration.zero;

int _millisecondsSince(DateTime start, DateTime end) =>
    _safeDifference(start, end).inMilliseconds;
