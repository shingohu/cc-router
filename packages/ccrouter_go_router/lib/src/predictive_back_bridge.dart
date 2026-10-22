part of 'adapter.dart';

/// Stable reason the automatic predictive-back bridge used Flutter fallback.
enum CCGoRouterPredictiveBackFallbackReason {
  /// The platform reported a button/system-back event instead of edge progress.
  buttonEvent,

  /// No predictive-enabled Route is currently registered with the bridge.
  noEligibleRoute,

  /// The registered Route could not provide a usable mounted context.
  routeUnavailable,

  /// The Android Theme does not use a supported stock predictive transition.
  unsupportedTransition,

  /// The candidate Route is no longer current in its Navigator.
  routeNotCurrent,

  /// Flutter disabled the gesture through a local route or PopScope gate.
  routeBlocked,

  /// The candidate Route does not belong to the active CCRouter Outlet.
  inactiveOutlet,

  /// The candidate Route has no matching live managed backend Entry.
  unknownManagedEntry,
}

/// Sanitized Host diagnostic for one declined predictive-back start.
final class CCGoRouterPredictiveBackFallbackEvent {
  /// Creates an immutable fallback event without route or business payloads.
  const CCGoRouterPredictiveBackFallbackEvent({
    required this.reason,
    required this.hostId,
    required this.navigatorOutlet,
    required this.timestamp,
  });

  /// Stable fallback category suitable for logs and regression assertions.
  final CCGoRouterPredictiveBackFallbackReason reason;

  /// Stable Host identity of the Adapter that declined the gesture.
  final String hostId;

  /// Active CCRouter Outlet when the gesture start was evaluated.
  final String navigatorOutlet;

  /// Time at which the bridge declined the platform start.
  final DateTime timestamp;
}

/// GoRouter facade over the backend-neutral predictive-back coordinator.
///
/// Create it by passing `enablePredictiveBack: true` to [CCGoRouterAdapter].
/// GoRouter contributes only Entry/Outlet resolution and diagnostic storage;
/// [CCPredictiveBackCoordinator] owns Route, gesture, observer, listener and
/// terminal Timer state. Flutter remains the sole animation and Pop driver.
final class CCGoRouterPredictiveBackBridge extends CCPredictiveBackCoordinator {
  /// Creates an Adapter-owned facade with no public constructor.
  CCGoRouterPredictiveBackBridge._();

  /// Owning Adapter, cleared before terminal-only observation begins.
  CCGoRouterAdapter? _adapter;

  /// Outlet currently selected by the GoRouter Adapter.
  @override
  String get activePredictiveBackOutlet => _adapter!._activeNavigatorOutlet;

  /// Resolves the Navigator currently rendering [outlet].
  @override
  NavigatorState? navigatorForPredictiveBackOutlet(String outlet) =>
      _adapter?._navigatorForOutlet(outlet);

  /// Resolves exact GoRouter ledger identity for [route].
  @override
  CCPredictiveBackRouteIdentity? resolvePredictiveBackRoute(
    Route<dynamic> route,
  ) {
    final adapter = _adapter;
    if (adapter == null) return null;
    final backendEntryId = adapter._backendRouteIds[route];
    final entry = adapter._entries.cast<_CCGoRouterEntry?>().firstWhere(
      (candidate) => candidate?.backendEntryId == backendEntryId,
      orElse: () => null,
    );
    if (backendEntryId == null || entry == null) return null;
    return CCPredictiveBackRouteIdentity(
      backendEntryId: backendEntryId,
      navigatorOutlet: entry.request.placement.navigatorOutlet,
    );
  }

  /// Whether the Adapter ledger still contains [backendEntryId].
  @override
  bool hasLivePredictiveBackEntry(String backendEntryId) =>
      _adapter?._entries.any(
        (entry) => entry.backendEntryId == backendEntryId,
      ) ??
      false;

  /// Maps the shared fallback reason to the stable GoRouter diagnostic API.
  @override
  void recordPredictiveBackFallback(CCPredictiveBackFallbackReason reason) {
    _adapter?._recordPredictiveBackFallback(_goRouterFallbackReason(reason));
  }

  /// Clears the Adapter before any terminal-only Timer can retain it.
  @override
  void releasePredictiveBackBackendReferences() {
    _adapter = null;
  }

  /// Installs the binding observer during Adapter construction.
  void _attach(CCGoRouterAdapter adapter) {
    _adapter = adapter;
    try {
      attachPredictiveBackCoordinator();
    } catch (_) {
      _adapter = null;
      rethrow;
    }
  }

  /// Rolls back every partial coordinator registration synchronously.
  void _rollbackAttach() => rollbackPredictiveBackCoordinator();

  /// Installs or clears the Runtime evaluator owned by the Adapter lifecycle.
  void _bindPopGuardEvaluator(CCPopGuardEvaluator? evaluator) =>
      bindPredictiveBackPopGuardEvaluator(evaluator);

  /// Invalidates previews when GoRouter activates another retained Outlet.
  void _invalidateInactiveOutlets() =>
      invalidateInactivePredictiveBackOutlets();

  /// Reconciles one Navigator observation with an exact pending gesture.
  void _observeBackendEvent(
    CCNavigationBackendEvent event,
    Route<dynamic> route,
  ) => observePredictiveBackBackendEvent(event, observedRoute: route);

  /// Permanently releases common and GoRouter-specific ownership.
  void _dispose() => disposePredictiveBackCoordinator();
}

/// Converts a shared fallback reason without relying on enum ordinal order.
CCGoRouterPredictiveBackFallbackReason _goRouterFallbackReason(
  CCPredictiveBackFallbackReason reason,
) => switch (reason) {
  CCPredictiveBackFallbackReason.buttonEvent =>
    CCGoRouterPredictiveBackFallbackReason.buttonEvent,
  CCPredictiveBackFallbackReason.noEligibleRoute =>
    CCGoRouterPredictiveBackFallbackReason.noEligibleRoute,
  CCPredictiveBackFallbackReason.routeUnavailable =>
    CCGoRouterPredictiveBackFallbackReason.routeUnavailable,
  CCPredictiveBackFallbackReason.unsupportedTransition =>
    CCGoRouterPredictiveBackFallbackReason.unsupportedTransition,
  CCPredictiveBackFallbackReason.routeNotCurrent =>
    CCGoRouterPredictiveBackFallbackReason.routeNotCurrent,
  CCPredictiveBackFallbackReason.routeBlocked =>
    CCGoRouterPredictiveBackFallbackReason.routeBlocked,
  CCPredictiveBackFallbackReason.inactiveOutlet =>
    CCGoRouterPredictiveBackFallbackReason.inactiveOutlet,
  CCPredictiveBackFallbackReason.unknownManagedEntry =>
    CCGoRouterPredictiveBackFallbackReason.unknownManagedEntry,
};
