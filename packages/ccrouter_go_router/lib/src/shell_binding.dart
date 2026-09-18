import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Associates one CCRouter Shell ID with an application-owned GoRouter Shell.
///
/// For [ShellRoute], provide one Outlet key matching [ShellRoute.navigatorKey].
/// For [StatefulShellRoute], provide one key for every branch, preserving the
/// branch Navigator identity across tab or parallel-stack switches. The
/// binding does not register or mutate the application-owned GoRouter.
final class CCGoRouterShellBinding {
  /// Creates a Shell binding with named application-owned Outlet keys.
  CCGoRouterShellBinding({
    required this.shellId,
    required this.route,
    required Map<String, GlobalKey<NavigatorState>> outlets,
  }) : outlets = Map.unmodifiable(outlets);

  /// Stable Shell ID used by [CCRoutePlacement.shellId].
  final String shellId;

  /// Application-owned ShellRoute or StatefulShellRoute.
  final RouteBase route;

  /// Navigator keys indexed by CCRouter Outlet name.
  final Map<String, GlobalKey<NavigatorState>> outlets;
}
