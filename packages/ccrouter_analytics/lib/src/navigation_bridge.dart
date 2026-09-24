import 'package:ccrouter_contracts/ccrouter_contracts.dart';

import 'analytics.dart';

/// Bridges CCRouter navigation lifecycle observations into page analytics.
///
/// The bridge treats managed Route arrival and re-show as page views. A hide
/// is one page leave because it represents the route no longer being current;
/// final removal does not create a duplicate leave event. Foreign routes and
/// overlays are never converted into CCRouter page views by this bridge.
final class CCRouterNavigationAnalytics {
  /// Creates a navigation bridge that writes events to [dispatcher].
  const CCRouterNavigationAnalytics({
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

  /// Creates a `CCNavigationAspect` for `CCRouter.initialize`.
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
    final telemetry = request.telemetryContext;
    final prefix = type == CCAnalyticsEventType.pageView
        ? pageViewEventPrefix
        : pageLeaveEventPrefix;
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
        properties: CCAnalyticsProperties.from([
          CCAnalyticsProperty('operation', request.operation.name),
          CCAnalyticsProperty('phase', event.phase.name),
        ]),
      ),
    );
  }
}
