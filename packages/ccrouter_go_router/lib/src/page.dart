import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Creates a GoRouter page for a normal CCRouter page presentation.
///
/// Use this from a bound `GoRoute.pageBuilder` when the route contract needs a
/// transparent page, an explicit transition, or `fullscreenDialog` semantics.
/// A page with [CCPageTransitionType.slideFromBottom] remains a full-screen
/// Navigator page; it is not converted into a modal bottom sheet.
Page<Object?> ccGoRouterPage({
  required Widget child,
  required CCPagePresentation presentation,
  LocalKey? key,
  String? name,
  Object? arguments,
  String? restorationId,
}) => CCGoRouterPage(
  child: child,
  presentation: presentation,
  key: key,
  name: name,
  arguments: arguments,
  restorationId: restorationId,
);

/// A GoRouter [Page] backed by a normal page route.
///
/// The page chooses Material or Cupertino defaults when the contract leaves
/// [CCPagePresentation.routeType] as [CCPageRouteType.platformDefault].
/// Explicit transitions and transparent pages use [PageRouteBuilder] so that
/// the resulting route keeps this page as its [Route.settings]. This is
/// required by page-based Navigators and prevents route/page identity drift.
final class CCGoRouterPage<T> extends Page<T> {
  /// Creates a normal page with adapter-neutral [presentation] options.
  const CCGoRouterPage({
    required this.child,
    required this.presentation,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// Widget displayed by this page.
  final Widget child;

  /// Page behavior declared by the CCRouter route contract.
  final CCPagePresentation presentation;

  @override
  Route<T> createRoute(BuildContext context) {
    final useCupertino = switch (presentation.routeType) {
      CCPageRouteType.cupertino => true,
      CCPageRouteType.material => false,
      CCPageRouteType.platformDefault =>
        context.findAncestorWidgetOfExactType<CupertinoApp>() != null ||
            context
                    .dependOnInheritedWidgetOfExactType<
                      InheritedCupertinoTheme
                    >() !=
                null,
    };

    final useNativePage =
        presentation.transition == CCPageTransitionType.platformDefault &&
        presentation.opaque;
    if (useNativePage) {
      if (useCupertino) {
        return CupertinoPageRoute<T>(
          settings: this,
          fullscreenDialog: presentation.fullscreenDialog,
          builder: (_) => child,
        );
      }
      return MaterialPageRoute<T>(
        settings: this,
        fullscreenDialog: presentation.fullscreenDialog,
        builder: (_) => child,
      );
    }

    return PageRouteBuilder<T>(
      settings: this,
      pageBuilder: (_, _, _) => child,
      opaque: presentation.opaque,
      fullscreenDialog: presentation.fullscreenDialog,
      transitionDuration: _transitionDuration(presentation.transition),
      reverseTransitionDuration: _transitionDuration(presentation.transition),
      transitionsBuilder: _transitionsBuilder(presentation.transition),
    );
  }

  /// Returns zero duration for page modes that intentionally do not animate.
  static Duration _transitionDuration(CCPageTransitionType transition) =>
      transition == CCPageTransitionType.none ||
          transition == CCPageTransitionType.platformDefault
      ? Duration.zero
      : const Duration(milliseconds: 300);

  /// Selects a transition builder without leaking Flutter types into the
  /// route contract package.
  static Widget Function(
    BuildContext,
    Animation<double>,
    Animation<double>,
    Widget,
  )
  _transitionsBuilder(CCPageTransitionType transition) {
    switch (transition) {
      case CCPageTransitionType.platformDefault:
      case CCPageTransitionType.none:
        return (_, _, _, child) => child;
      case CCPageTransitionType.fade:
        return (_, animation, _, child) => FadeTransition(
          opacity: animation.drive(CurveTween(curve: Curves.easeInOut)),
          child: child,
        );
      case CCPageTransitionType.scale:
        return (_, animation, _, child) => ScaleTransition(
          scale: animation
              .drive(CurveTween(curve: Curves.easeOutCubic))
              .drive(Tween<double>(begin: 0.94, end: 1)),
          child: FadeTransition(opacity: animation, child: child),
        );
      case CCPageTransitionType.slideFromRight:
        return (_, animation, _, child) => SlideTransition(
          position: animation
              .drive(CurveTween(curve: Curves.easeOutCubic))
              .drive(
                Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero),
              ),
          child: child,
        );
      case CCPageTransitionType.slideFromBottom:
        return (_, animation, _, child) => SlideTransition(
          position: animation
              .drive(CurveTween(curve: Curves.easeOutCubic))
              .drive(
                Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero),
              ),
          child: child,
        );
    }
  }
}
