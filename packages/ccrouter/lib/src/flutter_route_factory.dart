import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Creates Flutter Routes and Pages from backend-neutral presentation data.
///
/// Host backends use this factory; business code uses generated navigation
/// Intents instead of constructing Flutter Routes or Pages directly.
abstract final class CCFlutterRouteFactory {
  /// Creates a Page for a declarative Navigator with stable [key] identity.
  static Page<T> createPage<T>({
    required Widget child,
    required CCRoutePresentation presentation,
    LocalKey? key,
    String? name,
    Object? arguments,
    String? restorationId,
  }) => switch (presentation) {
    final CCPagePresentation value => CCFlutterPage<T>(
      child: child,
      presentation: value,
      key: key,
      name: name,
      arguments: arguments,
      restorationId: restorationId,
    ),
    final CCModalBottomSheetPresentation value => CCFlutterBottomSheetPage<T>(
      child: child,
      presentation: value,
      key: key,
      name: name,
      arguments: arguments,
      restorationId: restorationId,
    ),
    final CCDialogPresentation value => CCFlutterDialogPage<T>(
      child: child,
      presentation: value,
      key: key,
      name: name,
      arguments: arguments,
      restorationId: restorationId,
    ),
  };

  /// Creates a Route for an imperative Navigator without allocating a Page.
  ///
  /// For declarative navigation use [createPage]; its Page is passed as Route
  /// settings to preserve page identity. The Navigator owns the returned Route.
  static Route<T> createRoute<T>({
    required BuildContext context,
    required Widget child,
    required CCRoutePresentation presentation,
    RouteSettings? settings,
  }) => switch (presentation) {
    final CCPagePresentation value => _pageRoute<T>(
      context,
      child,
      value,
      settings,
    ),
    final CCModalBottomSheetPresentation value => ModalBottomSheetRoute<T>(
      builder: (_) => child,
      isDismissible: value.isDismissible,
      enableDrag: value.enableDrag,
      isScrollControlled: value.isScrollControlled,
      showDragHandle: value.showDragHandle,
      useSafeArea: value.useSafeArea,
      settings: settings,
    ),
    final CCDialogPresentation value => _dialogRoute<T>(
      context,
      child,
      value,
      settings,
    ),
  };

  /// Chooses native Material/Cupertino behavior or a custom Page transition.
  static Route<T> _pageRoute<T>(
    BuildContext context,
    Widget child,
    CCPagePresentation presentation,
    RouteSettings? settings,
  ) {
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
    if (presentation.transition == CCPageTransitionType.platformDefault &&
        presentation.opaque) {
      return useCupertino
          ? CupertinoPageRoute<T>(
              settings: settings,
              fullscreenDialog: presentation.fullscreenDialog,
              builder: (_) => child,
            )
          : MaterialPageRoute<T>(
              settings: settings,
              fullscreenDialog: presentation.fullscreenDialog,
              builder: (_) => child,
            );
    }
    final duration =
        presentation.transition == CCPageTransitionType.none ||
            presentation.transition == CCPageTransitionType.platformDefault
        ? Duration.zero
        : const Duration(milliseconds: 300);
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (_, _, _) => child,
      opaque: presentation.opaque,
      fullscreenDialog: presentation.fullscreenDialog,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      transitionsBuilder: _transitionsBuilder(presentation.transition),
    );
  }

  /// Uses animation chains without disposable intermediate animations.
  static Widget Function(
    BuildContext,
    Animation<double>,
    Animation<double>,
    Widget,
  )
  _transitionsBuilder(CCPageTransitionType transition) => switch (transition) {
    CCPageTransitionType.platformDefault ||
    CCPageTransitionType.none => (_, _, _, child) => child,
    CCPageTransitionType.fade => (_, animation, _, child) => FadeTransition(
      opacity: animation.drive(CurveTween(curve: Curves.easeInOut)),
      child: child,
    ),
    CCPageTransitionType.scale => (_, animation, _, child) => ScaleTransition(
      scale: animation
          .drive(CurveTween(curve: Curves.easeOutCubic))
          .drive(Tween<double>(begin: 0.94, end: 1)),
      child: FadeTransition(opacity: animation, child: child),
    ),
    CCPageTransitionType.slideFromRight =>
      (_, animation, _, child) => SlideTransition(
        position: animation
            .drive(CurveTween(curve: Curves.easeOutCubic))
            .drive(Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)),
        child: child,
      ),
    CCPageTransitionType.slideFromBottom =>
      (_, animation, _, child) => SlideTransition(
        position: animation
            .drive(CurveTween(curve: Curves.easeOutCubic))
            .drive(Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)),
        child: child,
      ),
  };

  /// Chooses the requested dialog family and safe barrier default.
  static Route<T> _dialogRoute<T>(
    BuildContext context,
    Widget child,
    CCDialogPresentation presentation,
    RouteSettings? settings,
  ) {
    final useCupertino = switch (presentation.routeType) {
      CCDialogRouteType.cupertino => true,
      CCDialogRouteType.material => false,
      CCDialogRouteType.platformDefault =>
        context.dependOnInheritedWidgetOfExactType<InheritedCupertinoTheme>() !=
            null,
    };
    final dismissible = presentation.barrierDismissible ?? !useCupertino;
    return useCupertino
        ? CupertinoDialogRoute<T>(
            context: context,
            builder: (_) => child,
            barrierDismissible: dismissible,
            settings: settings,
          )
        : DialogRoute<T>(
            context: context,
            builder: (_) => child,
            barrierDismissible: dismissible,
            useSafeArea: presentation.useSafeArea,
            settings: settings,
          );
  }
}

/// A normal declarative Flutter Page independent of a Router implementation.
base class CCFlutterPage<T> extends Page<T> {
  /// Creates a Page whose Route is configured by [presentation].
  const CCFlutterPage({
    required this.child,
    required this.presentation,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// Widget displayed by the Route.
  final Widget child;

  /// Material, Cupertino, opacity and transition options.
  final CCPagePresentation presentation;

  @override
  /// Creates a Route retaining this Page as its settings.
  Route<T> createRoute(BuildContext context) =>
      CCFlutterRouteFactory.createRoute<T>(
        context: context,
        child: child,
        presentation: presentation,
        settings: this,
      );
}

/// A declarative Flutter Page backed by a modal bottom-sheet Route.
base class CCFlutterBottomSheetPage<T> extends Page<T> {
  /// Creates a sheet whose dismissal and layout come from [presentation].
  const CCFlutterBottomSheetPage({
    required this.child,
    required this.presentation,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// Widget displayed in the sheet.
  final Widget child;

  /// Sheet dismissal, drag and layout options.
  final CCModalBottomSheetPresentation presentation;

  @override
  /// Creates a sheet Route retaining this Page as its settings.
  Route<T> createRoute(BuildContext context) =>
      CCFlutterRouteFactory.createRoute<T>(
        context: context,
        child: child,
        presentation: presentation,
        settings: this,
      );
}

/// A declarative Flutter Page backed by a Material or Cupertino dialog.
base class CCFlutterDialogPage<T> extends Page<T> {
  /// Creates a dialog whose family and barrier come from [presentation].
  const CCFlutterDialogPage({
    required this.child,
    required this.presentation,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// Widget displayed in the dialog.
  final Widget child;

  /// Dialog family, barrier and safe-area options.
  final CCDialogPresentation presentation;

  @override
  /// Creates a dialog Route retaining this Page as its settings.
  Route<T> createRoute(BuildContext context) =>
      CCFlutterRouteFactory.createRoute<T>(
        context: context,
        child: child,
        presentation: presentation,
        settings: this,
      );
}
