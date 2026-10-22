import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter/widgets.dart';

import 'predictive_back_coordinator.dart';

/// Stable reason why the Managed predictive-back bridge used Flutter fallback.
enum CCManagedPredictiveBackFallbackReason {
  /// The platform reported a button/system-back event.
  buttonEvent,

  /// No eligible Managed Route is currently registered.
  noEligibleRoute,

  /// The Route context or transition could not be inspected.
  routeUnavailable,

  /// The Host theme does not use a supported predictive transition.
  unsupportedTransition,

  /// The candidate Route is not current.
  routeNotCurrent,

  /// A local Flutter route gate disabled the gesture.
  routeBlocked,

  /// The candidate Route belongs to a different Outlet.
  inactiveOutlet,

  /// The candidate Route has no live Managed Entry.
  unknownManagedEntry,
}

/// Sanitized diagnostic for one declined Managed predictive-back start.
final class CCManagedPredictiveBackFallbackEvent {
  /// Creates an immutable fallback event.
  const CCManagedPredictiveBackFallbackEvent({
    required this.reason,
    required this.hostId,
    required this.navigatorOutlet,
    required this.timestamp,
  });

  /// Stable fallback category.
  final CCManagedPredictiveBackFallbackReason reason;

  /// Host that declined the gesture.
  final String hostId;

  /// Outlet evaluated at gesture start.
  final String navigatorOutlet;

  /// Time of the declined start.
  final DateTime timestamp;
}

/// Managed Backend facade over the shared predictive-back coordinator.
///
/// The backend supplies Store identity callbacks while
/// [CCPredictiveBackCoordinator] owns Route, gesture, observer, listener and
/// terminal Timer state. Callback references are cleared before terminal-only
/// observation so a retired Host cannot be retained by the binding.
final class CCManagedPredictiveBackBridge extends CCPredictiveBackCoordinator {
  /// Creates a bridge for one Managed Host.
  CCManagedPredictiveBackBridge({
    required this.hostId,
    required String Function() activeOutlet,
    required NavigatorState? Function(String outlet) navigatorForOutlet,
    required String? Function(Route<dynamic> route) backendEntryIdForRoute,
    required bool Function(String backendEntryId) hasLiveEntry,
    required void Function(CCManagedPredictiveBackFallbackReason reason)
    recordFallback,
  }) : _activeOutlet = activeOutlet,
       _navigatorForOutlet = navigatorForOutlet,
       _backendEntryIdForRoute = backendEntryIdForRoute,
       _hasLiveEntry = hasLiveEntry,
       _recordFallback = recordFallback;

  /// Stable Host identity exposed in diagnostics.
  final String hostId;

  /// Backend callback resolving the currently focused Outlet.
  String Function()? _activeOutlet;

  /// Backend callback resolving an Outlet's Navigator.
  NavigatorState? Function(String outlet)? _navigatorForOutlet;

  /// Backend callback resolving exact Route identity.
  String? Function(Route<dynamic> route)? _backendEntryIdForRoute;

  /// Backend callback checking whether an Entry remains live.
  bool Function(String backendEntryId)? _hasLiveEntry;

  /// Backend callback storing a bounded fallback diagnostic.
  void Function(CCManagedPredictiveBackFallbackReason reason)? _recordFallback;

  /// Outlet currently selected by the Managed Store.
  @override
  String get activePredictiveBackOutlet => _activeOutlet!.call();

  /// Resolves the Navigator currently rendering [outlet].
  @override
  NavigatorState? navigatorForPredictiveBackOutlet(String outlet) =>
      _navigatorForOutlet!.call(outlet);

  /// Resolves exact Store identity for [route].
  @override
  CCPredictiveBackRouteIdentity? resolvePredictiveBackRoute(
    Route<dynamic> route,
  ) {
    final backendEntryId = _backendEntryIdForRoute!.call(route);
    if (backendEntryId == null) return null;
    return CCPredictiveBackRouteIdentity(
      backendEntryId: backendEntryId,
      navigatorOutlet: activePredictiveBackOutlet,
    );
  }

  /// Whether the Managed Store still contains [backendEntryId].
  @override
  bool hasLivePredictiveBackEntry(String backendEntryId) =>
      _hasLiveEntry!.call(backendEntryId);

  /// Maps the backend-neutral fallback reason to the Managed diagnostic API.
  @override
  void recordPredictiveBackFallback(CCPredictiveBackFallbackReason reason) {
    _recordFallback?.call(_managedFallbackReason(reason));
  }

  /// Clears every callback that could otherwise retain the Managed Adapter.
  @override
  void releasePredictiveBackBackendReferences() {
    _activeOutlet = null;
    _navigatorForOutlet = null;
    _backendEntryIdForRoute = null;
    _hasLiveEntry = null;
    _recordFallback = null;
  }

  /// Attaches the platform observer as part of Backend construction.
  void attach() => attachPredictiveBackCoordinator();

  /// Binds Runtime PopGuard evaluation to this Host lifecycle.
  void bindPopGuardEvaluator(CCPopGuardEvaluator? evaluator) =>
      bindPredictiveBackPopGuardEvaluator(evaluator);

  /// Invalidates previews when another Outlet becomes active.
  void invalidateInactiveOutlets() => invalidateInactivePredictiveBackOutlets();

  /// Invalidates previews newly covered by an ancestor Navigator Route.
  void observeNavigatorTopChange() => invalidateCoveredPredictiveBackRoutes();

  /// Confirms commits and invalidates previews from Store events.
  void observeBackendEvent(CCNavigationBackendEvent event) =>
      observePredictiveBackBackendEvent(event);

  /// Releases observer, Timer, Routes, listeners and backend callbacks.
  void dispose() => disposePredictiveBackCoordinator();
}

/// Converts a shared fallback reason without relying on enum ordinal order.
CCManagedPredictiveBackFallbackReason _managedFallbackReason(
  CCPredictiveBackFallbackReason reason,
) => switch (reason) {
  CCPredictiveBackFallbackReason.buttonEvent =>
    CCManagedPredictiveBackFallbackReason.buttonEvent,
  CCPredictiveBackFallbackReason.noEligibleRoute =>
    CCManagedPredictiveBackFallbackReason.noEligibleRoute,
  CCPredictiveBackFallbackReason.routeUnavailable =>
    CCManagedPredictiveBackFallbackReason.routeUnavailable,
  CCPredictiveBackFallbackReason.unsupportedTransition =>
    CCManagedPredictiveBackFallbackReason.unsupportedTransition,
  CCPredictiveBackFallbackReason.routeNotCurrent =>
    CCManagedPredictiveBackFallbackReason.routeNotCurrent,
  CCPredictiveBackFallbackReason.routeBlocked =>
    CCManagedPredictiveBackFallbackReason.routeBlocked,
  CCPredictiveBackFallbackReason.inactiveOutlet =>
    CCManagedPredictiveBackFallbackReason.inactiveOutlet,
  CCPredictiveBackFallbackReason.unknownManagedEntry =>
    CCManagedPredictiveBackFallbackReason.unknownManagedEntry,
};
