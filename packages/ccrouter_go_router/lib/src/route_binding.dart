import 'package:go_router/go_router.dart';

/// Declares which Page family an application-owned GoRoute binding returns.
enum CCGoRouterPresentationKind {
  /// A normal full-screen GoRouter page.
  page,

  /// A [CCGoRouterBottomSheetPage] backed by a modal bottom-sheet route.
  bottomSheet,

  /// A [CCGoRouterDialogPage] backed by a dialog route.
  dialog,
}

/// Associates one CCRouter route contract with an application-owned [GoRoute].
///
/// The binding carries only the stable CCRouter [routeId] and the concrete
/// GoRouter route. The application or component composition root remains the
/// owner of the [GoRoute] tree and must include [goRoute] when constructing its
/// [GoRouter]. A binding does not register or mutate a router by itself.
final class CCGoRouterRouteBinding {
  /// Creates a binding for [routeId] and an application-owned [goRoute].
  CCGoRouterRouteBinding({
    required this.routeId,
    required this.goRoute,
    this.presentationKind = CCGoRouterPresentationKind.page,
  });

  /// Stable CCRouter route ID declared by the component contract.
  final String routeId;

  /// Concrete GoRouter route that renders the destination.
  final GoRoute goRoute;

  /// Page family returned by [goRoute]'s `pageBuilder`.
  ///
  /// Set this to [CCGoRouterPresentationKind.bottomSheet] or
  /// [CCGoRouterPresentationKind.dialog] when the route uses one of the
  /// exported modal Page helpers. The Adapter compares this declaration with
  /// the Runtime route contract during initialization.
  final CCGoRouterPresentationKind presentationKind;

  /// Whether this binding supplies a custom GoRouter page constructor.
  ///
  /// Modal BottomSheet and Dialog contracts must use a custom `pageBuilder`
  /// that returns [CCGoRouterBottomSheetPage] or [CCGoRouterDialogPage].
  /// A plain `builder` is intentionally insufficient because GoRouter would
  /// otherwise create an ordinary full-screen page.
  bool get hasCustomPageBuilder => goRoute.pageBuilder != null;
}
