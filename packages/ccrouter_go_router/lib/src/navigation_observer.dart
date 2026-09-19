import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/widgets.dart';

/// Identifies a backend Navigator lifecycle transition.
enum CCGoRouterNavigationEventKind {
  /// A route was pushed onto the observed Navigator.
  push,

  /// A route was popped from the observed Navigator.
  pop,

  /// A route was replaced on the observed Navigator.
  replace,

  /// A route was removed without becoming the active route.
  remove,

  /// Flutter confirmed a different top Route for this Navigator.
  topChanged,
}

/// Immutable lifecycle data emitted by [CCGoRouterNavigationObserver].
final class CCGoRouterNavigationEvent {
  /// Creates an event for one observed Navigator transition.
  const CCGoRouterNavigationEvent({
    required this.kind,
    required this.hostId,
    required this.outlet,
    required this.route,
    this.previousRoute,
  });

  /// Transition kind observed from Flutter's Navigator.
  final CCGoRouterNavigationEventKind kind;

  /// Stable Flutter Host identity associated with the observed Navigator.
  final String hostId;

  /// CCRouter Outlet name associated with the observer instance.
  final String outlet;

  /// Route affected by the transition.
  final Route<dynamic> route;

  /// Route that was active before the transition, when Flutter supplies one.
  final Route<dynamic>? previousRoute;

  /// Route settings name, typically the GoRouter location.
  String? get location => route.settings.name;
}

/// NavigatorObserver that turns backend transitions into Outlet-tagged events.
///
/// Add one instance to a `ShellRoute.observers`,
/// `StatefulShellBranch.observers`, or root Navigator observer list. Keep the
/// callback focused on telemetry, lifecycle bridging, or diagnostics; it must
/// not call CCRouter navigation synchronously from inside the callback.
///
/// GoRouter 17 forwards nested Shell transitions to root observers by default.
/// This observer ignores a forwarded transition when its Route belongs to a
/// different Navigator, preserving the configured [outlet] identity. Install a
/// dedicated observer on every managed Shell Outlet that needs lifecycle
/// tracking.
final class CCGoRouterNavigationObserver extends NavigatorObserver {
  /// Creates an observer for one [hostId] and [outlet] pair.
  ///
  /// Use the same Host identity supplied to `CCGoRouterAdapter`. The default
  /// identity preserves single-window integrations that target the framework's
  /// default Host.
  CCGoRouterNavigationObserver({
    this.hostId = 'default',
    required this.outlet,
    this.onEvent,
  }) {
    if (hostId.isEmpty) {
      throw ArgumentError.value(hostId, 'hostId', 'Host ID cannot be empty.');
    }
    if (outlet.isEmpty) {
      throw ArgumentError.value(
        outlet,
        'outlet',
        'Navigator Outlet cannot be empty.',
      );
    }
  }

  /// Stable Flutter Host identity associated with this Navigator.
  final String hostId;

  /// Stable CCRouter Outlet name associated with this Navigator.
  final String outlet;

  /// Optional callback invoked after each backend transition.
  final void Function(CCGoRouterNavigationEvent event)? onEvent;

  /// Additional listeners used by framework integrations such as the Adapter.
  final Set<void Function(CCGoRouterNavigationEvent event)> _listeners = {};

  @override
  /// Reports the confirmed current Route to CCRouter's Host lifecycle ledger.
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    super.didChangeTop(topRoute, previousTopRoute);
    if (!_observesRoute(topRoute)) return;
    CCPageLifecycleHostBridge.didChangeTop(
      hostId: hostId,
      outlet: outlet,
      topRoute: topRoute,
      previousTopRoute: previousTopRoute,
    );
    _emit(
      CCGoRouterNavigationEvent(
        kind: CCGoRouterNavigationEventKind.topChanged,
        hostId: hostId,
        outlet: outlet,
        route: topRoute,
        previousRoute: previousTopRoute,
      ),
    );
  }

  /// Subscribes to lifecycle events and returns a callback that removes the
  /// subscription. The callback is invoked after [onEvent].
  void Function() addListener(
    void Function(CCGoRouterNavigationEvent event) listener,
  ) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (!_observesRoute(route)) return;
    _emit(
      CCGoRouterNavigationEvent(
        kind: CCGoRouterNavigationEventKind.push,
        hostId: hostId,
        outlet: outlet,
        route: route,
        previousRoute: previousRoute,
      ),
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (!_observesRoute(route)) return;
    _emit(
      CCGoRouterNavigationEvent(
        kind: CCGoRouterNavigationEventKind.pop,
        hostId: hostId,
        outlet: outlet,
        route: route,
        previousRoute: previousRoute,
      ),
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    final route = newRoute ?? oldRoute;
    if (route == null) return;
    if (!_observesRoute(route)) return;
    _emit(
      CCGoRouterNavigationEvent(
        kind: CCGoRouterNavigationEventKind.replace,
        hostId: hostId,
        outlet: outlet,
        route: route,
        previousRoute: oldRoute,
      ),
    );
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (!_observesRoute(route)) return;
    _emit(
      CCGoRouterNavigationEvent(
        kind: CCGoRouterNavigationEventKind.remove,
        hostId: hostId,
        outlet: outlet,
        route: route,
        previousRoute: previousRoute,
      ),
    );
  }

  /// Emits one event after Flutter has updated its Navigator state.
  void _emit(CCGoRouterNavigationEvent event) {
    onEvent?.call(event);
    for (final listener in _listeners.toList()) {
      listener(event);
    }
  }

  /// Returns whether [route] is installed in this observer's Navigator.
  ///
  /// A null Route navigator is accepted for direct observer tests and for
  /// framework callbacks that occur before attachment. A non-null mismatch is
  /// a GoRouter-forwarded nested transition and must retain its real Outlet.
  bool _observesRoute(Route<dynamic> route) {
    final routeNavigator = route.navigator;
    return routeNavigator == null || identical(routeNavigator, navigator);
  }
}
