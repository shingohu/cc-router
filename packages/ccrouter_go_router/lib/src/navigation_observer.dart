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
}

/// Immutable lifecycle data emitted by [CCGoRouterNavigationObserver].
final class CCGoRouterNavigationEvent {
  /// Creates an event for one observed Navigator transition.
  const CCGoRouterNavigationEvent({
    required this.kind,
    required this.outlet,
    required this.route,
    this.previousRoute,
    this.result,
  });

  /// Transition kind observed from Flutter's Navigator.
  final CCGoRouterNavigationEventKind kind;

  /// CCRouter Outlet name associated with the observer instance.
  final String outlet;

  /// Route affected by the transition.
  final Route<dynamic> route;

  /// Route that was active before the transition, when Flutter supplies one.
  final Route<dynamic>? previousRoute;

  /// Pop result when the backend observer API provides it; otherwise null.
  final Object? result;

  /// Route settings name, typically the GoRouter location.
  String? get location => route.settings.name;
}

/// NavigatorObserver that turns backend transitions into Outlet-tagged events.
///
/// Add one instance to a `ShellRoute.observers`,
/// `StatefulShellBranch.observers`, or root Navigator observer list. Keep the
/// callback focused on telemetry, lifecycle bridging, or diagnostics; it must
/// not call CCRouter navigation synchronously from inside the callback.
final class CCGoRouterNavigationObserver extends NavigatorObserver {
  /// Creates an observer for [outlet].
  CCGoRouterNavigationObserver({required this.outlet, this.onEvent});

  /// Stable CCRouter Outlet name associated with this Navigator.
  final String outlet;

  /// Optional callback invoked after each backend transition.
  final void Function(CCGoRouterNavigationEvent event)? onEvent;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _emit(
      CCGoRouterNavigationEvent(
        kind: CCGoRouterNavigationEventKind.push,
        outlet: outlet,
        route: route,
        previousRoute: previousRoute,
      ),
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _emit(
      CCGoRouterNavigationEvent(
        kind: CCGoRouterNavigationEventKind.pop,
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
    _emit(
      CCGoRouterNavigationEvent(
        kind: CCGoRouterNavigationEventKind.replace,
        outlet: outlet,
        route: route,
        previousRoute: oldRoute,
      ),
    );
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _emit(
      CCGoRouterNavigationEvent(
        kind: CCGoRouterNavigationEventKind.remove,
        outlet: outlet,
        route: route,
        previousRoute: previousRoute,
      ),
    );
  }

  /// Emits one event after Flutter has updated its Navigator state.
  void _emit(CCGoRouterNavigationEvent event) => onEvent?.call(event);
}
