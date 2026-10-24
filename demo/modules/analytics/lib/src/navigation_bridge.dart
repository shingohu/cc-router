import 'package:ccrouter_contracts/ccrouter_contracts.dart';

import 'analytics.dart';

/// Application-owned anonymous identity; CCRouter never receives this value.
final class AppAnalyticsIdentity {
  const AppAnalyticsIdentity({
    required this.anonymousVisitorId,
    this.applicationSessionId,
  });

  final String anonymousVisitorId;
  final String? applicationSessionId;

  bool get _isValid =>
      _validIdentity(anonymousVisitorId) &&
      (applicationSessionId == null || _validIdentity(applicationSessionId!));
}

bool _validIdentity(String value) =>
    value.length <= 64 &&
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(value);

/// Bridges CCRouter navigation lifecycle observations into page analytics.
///
/// The bridge treats managed Route arrival and re-show as page views. A hide
/// is one page leave because it represents the route no longer being current;
/// final removal does not create a duplicate leave event. Foreign routes and
/// overlays are never converted into page views by this application bridge.
/// These are Demo statistics rules, not CCRouter framework PV guarantees.
final class AppNavigationAnalyticsBridge {
  /// Creates a navigation bridge that writes events to [dispatcher].
  AppNavigationAnalyticsBridge({
    required this.dispatcher,
    AppAnalyticsIdentity? Function()? identityProvider,
    this.pageViewEventPrefix = 'page.view',
    this.pageLeaveEventPrefix = 'page.leave',
  }) : _identityProvider = identityProvider;

  /// Bounded event dispatcher owned by the application Host.
  final AppAnalyticsEventDispatcher dispatcher;

  /// Read at the first delivered Found (or visible-entry fallback) observation.
  /// Observations are asynchronous: this is not the identity at invocation time.
  /// Invalid values and provider failures are dropped without affecting routing.
  AppAnalyticsIdentity? Function()? _identityProvider;

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
    if (_disposed || _foreground) return;
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
    if (_disposed || !_foreground) return;
    _foreground = false;
    for (final visit in _visits.values) {
      visit.addForegroundUntil(timestamp);
    }
  }

  /// Releases open visit state when the owning Host no longer uses this bridge.
  ///
  /// The bridge never owns the Dispatcher and therefore does not close it.
  void dispose() {
    _disposed = true;
    resetTracking();
    _identityProvider = null;
  }

  /// Clears application identity and dwell state on Consent/account changes.
  /// The Host calls this before updating its tracking policy or identity owner.
  void resetTracking() {
    _trackingRevision++;
    _visits.clear();
    _identities.clear();
  }

  /// Bounded application snapshots, exposed for lifecycle verification.
  int get retainedIdentityCount => _identities.length;

  bool get _trackingAllowed =>
      !_disposed &&
      dispatcher.policy.enabled &&
      dispatcher.policy.consentGranted;

  void _onFound(CCNavigationAspectEvent event) {
    if (!_trackingAllowed) return;
    _captureIdentity(event.request.navigationId);
  }

  bool _captureIdentity(String navigationId) {
    if (_identities.containsKey(navigationId)) return true;
    final revision = _trackingRevision;
    if (_identities.length >= _maxOpenVisits) {
      final oldest = _identities.keys.first;
      _identities.remove(oldest);
      _visits.remove(oldest);
    }
    AppAnalyticsIdentity? identity;
    try {
      final candidate = _identityProvider?.call();
      if (candidate?._isValid ?? false) identity = candidate;
    } on Object {
      // Product tracking cannot affect navigation or expose provider errors.
    }
    if (!_trackingAllowed || revision != _trackingRevision) return false;
    _identities[navigationId] = identity;
    return true;
  }

  void _onAfter(CCNavigationAspectEvent event) {
    if (event.outcome != CCNavigationAspectOutcome.succeeded) {
      _onTerminal(event);
    }
  }

  /// Creates a `CCNavigationAspect` for `CCRouterHost.initialize`.
  ///
  /// The returned aspect is observation-only. It cannot cancel, redirect, or
  /// otherwise change navigation behavior.
  CCNavigationAspect createAspect({String id = 'demo.analytics.navigation'}) {
    return CCNavigationAspect(
      id: id,
      onFound: _onFound,
      onArrival: _onNavigation,
      onShow: _onNavigation,
      onHide: _onNavigation,
      onRemoved: _onTerminal,
      onDisposed: _onTerminal,
      onLost: _onTerminal,
      onAfter: _onAfter,
    );
  }

  /// Converts one managed navigation lifecycle observation into an event.
  void _onNavigation(CCNavigationAspectEvent event) {
    if (_disposed) return;
    final type = switch (event.phase) {
      CCNavigationAspectPhase.arrival ||
      CCNavigationAspectPhase.show => AppAnalyticsEventType.pageView,
      CCNavigationAspectPhase.hide => AppAnalyticsEventType.pageLeave,
      _ => null,
    };
    if (type == null) return;
    final request = event.request;
    // Consent is checked before retaining a visit. A route shown before
    // consent and hidden after consent does not leak a pre-consent duration.
    if (!_trackingAllowed) {
      resetTracking();
      return;
    }
    if (type == AppAnalyticsEventType.pageView &&
        !_captureIdentity(request.navigationId)) {
      return;
    }
    final identity = _identities[request.navigationId];
    final prefix = type == AppAnalyticsEventType.pageView
        ? pageViewEventPrefix
        : pageLeaveEventPrefix;
    final visit = type == AppAnalyticsEventType.pageView
        ? _startVisit(request, event.timestamp)
        : _visits.remove(request.navigationId);
    final properties = <AppAnalyticsProperty>[
      AppAnalyticsProperty('operation', request.operation.name),
      AppAnalyticsProperty('phase', event.phase.name),
    ];
    if (visit != null) {
      properties.add(AppAnalyticsProperty('visit_id', visit.id));
      if (type == AppAnalyticsEventType.pageLeave) {
        properties.add(
          AppAnalyticsProperty('dwell_ms', visit.dwellUntil(event.timestamp)),
        );
        properties.add(
          AppAnalyticsProperty(
            'foreground_dwell_ms',
            visit.foregroundDwellUntil(event.timestamp),
          ),
        );
      }
    }
    dispatcher.dispatch(
      AppAnalyticsEvent(
        eventId: '$prefix.${request.routeId}',
        type: type,
        occurredAt: event.timestamp,
        navigationId: request.navigationId,
        routeId: request.routeId,
        componentId: request.ownerComponentId,
        hostId: request.resolvedHostId,
        outlet: request.navigatorOutlet,
        source: request.source?.id,
        anonymousVisitorId: identity?.anonymousVisitorId,
        applicationSessionId: identity?.applicationSessionId,
        properties: AppAnalyticsProperties.from(properties),
      ),
    );
  }

  /// Removes state when a managed Entry leaves or is disposed without a hide.
  void _onTerminal(CCNavigationAspectEvent event) {
    _visits.remove(event.request.navigationId);
    _identities.remove(event.request.navigationId);
  }

  _AppAnalyticsPageVisit _startVisit(
    CCNavigationAspectRequest request,
    DateTime startedAt,
  ) {
    final existing = _visits[request.navigationId];
    if (existing != null) return existing;
    if (_visits.length >= _maxOpenVisits) {
      _visits.remove(_visits.keys.first);
    }
    final visit = _AppAnalyticsPageVisit(
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
  final Map<String, _AppAnalyticsPageVisit> _visits = {};

  /// Product data stays outside Runtime and ends with its managed Entry.
  final Map<String, AppAnalyticsIdentity?> _identities = {};

  bool _disposed = false;

  /// Fences synchronous provider callbacks that retire the current attribution.
  int _trackingRevision = 0;

  /// Whether effective foreground time is currently accumulating.
  bool _foreground = true;
}

/// Mutable state for one visible managed navigation visit.
final class _AppAnalyticsPageVisit {
  _AppAnalyticsPageVisit({
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
