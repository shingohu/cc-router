import 'package:go_router/go_router.dart';

/// Associates one CCRouter route contract with an application-owned [GoRoute].
///
/// The binding carries only the stable CCRouter [routeId] and the concrete
/// GoRouter route. The application or component composition root remains the
/// owner of the [GoRoute] tree and must include [goRoute] when constructing its
/// [GoRouter]. A binding does not register or mutate a router by itself.
final class CCGoRouterRouteBinding {
  /// Creates a binding for [routeId] and an application-owned [goRoute].
  CCGoRouterRouteBinding({required this.routeId, required this.goRoute});

  /// Stable CCRouter route ID declared by the component contract.
  final String routeId;

  /// Concrete GoRouter route that renders the destination.
  final GoRoute goRoute;
}
