import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

part 'flutter_predictive_back.dart';

/// Creates Flutter Routes and Pages from backend-neutral presentation data.
///
/// Host backends use this factory; business code uses generated navigation
/// Intents instead of constructing Flutter Routes or Pages directly.
abstract final class CCFlutterRouteFactory {
  /// Creates a Page for a declarative Navigator with stable [key] identity.
  ///
  /// [predictiveBackHandler] is optional Host SPI for default Android Material
  /// Pages only. Null preserves original Route construction and handling.
  static Page<T> createPage<T>({
    required Widget child,
    required CCRoutePresentation presentation,
    LocalKey? key,
    String? name,
    Object? arguments,
    String? restorationId,
    CCFlutterPredictiveBackHandler? predictiveBackHandler,
  }) => switch (presentation) {
    final CCPagePresentation value => CCFlutterPage<T>(
      child: child,
      presentation: value,
      key: key,
      name: name,
      arguments: arguments,
      restorationId: restorationId,
      predictiveBackHandler: predictiveBackHandler,
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
  /// A non-null [predictiveBackHandler] opts default Android Material Routes
  /// into observation and commit-time local gate checks; other presentations
  /// retain their original constructors and handling.
  static Route<T> createRoute<T>({
    required BuildContext context,
    required Widget child,
    required CCRoutePresentation presentation,
    RouteSettings? settings,
    CCFlutterPredictiveBackHandler? predictiveBackHandler,
  }) => switch (presentation) {
    final CCPagePresentation value => _pageRoute<T>(
      context,
      child,
      value,
      settings,
      predictiveBackHandler,
    ),
    final CCModalBottomSheetPresentation value => ModalBottomSheetRoute<T>(
      builder: (_) => child,
      backgroundColor: value.transparent ? Colors.transparent : null,
      elevation: value.transparent ? 0 : null,
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

  /// 根据宿主选择 Material/Cupertino 路由，或使用显式页面转场。
  ///
  /// MaterialApp 自动提供 CupertinoTheme，不能以该 Theme 判断宿主类型；
  /// Material 路由自身会按主题平台适配 iOS 返回手势和 Android 系统返回。
  static Route<T> _pageRoute<T>(
    BuildContext context,
    Widget child,
    CCPagePresentation presentation,
    RouteSettings? settings,
    CCFlutterPredictiveBackHandler? predictiveBackHandler,
  ) {
    final useCupertino = switch (presentation.routeType) {
      CCPageRouteType.cupertino => true,
      CCPageRouteType.material => false,
      CCPageRouteType.platformDefault => _usesCupertinoRouteFamily(context),
    };
    if (presentation.transition == CCPageTransitionType.platformDefault &&
        presentation.opaque) {
      if (useCupertino) {
        return CupertinoPageRoute<T>(
          settings: settings,
          fullscreenDialog: presentation.fullscreenDialog,
          builder: (_) => child,
        );
      }
      if (predictiveBackHandler != null &&
          Theme.of(context).platform == TargetPlatform.android) {
        return _CCPredictiveMaterialPageRoute<T>(
          settings: settings,
          fullscreenDialog: presentation.fullscreenDialog,
          builder: (_) => child,
          handler: predictiveBackHandler,
        );
      }
      return MaterialPageRoute<T>(
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
      CCDialogRouteType.platformDefault => _usesCupertinoRouteFamily(context),
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

  /// Resolves the nearest known App family before consulting custom-host theme.
  ///
  /// MaterialApp installs an inherited Cupertino theme for widget compatibility,
  /// so a known Material host must win before that theme is considered. When no
  /// known App exists, an explicit inherited Cupertino theme preserves the
  /// platform policy of custom Hosts built directly from WidgetsApp or Navigator.
  static bool _usesCupertinoRouteFamily(BuildContext context) {
    bool? useCupertino;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is MaterialApp) {
        useCupertino = false;
        return false;
      }
      if (widget is CupertinoApp) {
        useCupertino = true;
        return false;
      }
      return true;
    });
    return useCupertino ??
        context.dependOnInheritedWidgetOfExactType<InheritedCupertinoTheme>() !=
            null;
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
    this.predictiveBackHandler,
  });

  /// Widget displayed by the Route.
  final Widget child;

  /// Material, Cupertino, opacity and transition options.
  final CCPagePresentation presentation;

  /// Optional Host-only observer for default Android Material route gestures.
  ///
  /// Null preserves the original Route construction and Flutter behavior.
  /// Custom transitions, Cupertino routes and modal pages do not use it.
  final CCFlutterPredictiveBackHandler? predictiveBackHandler;

  @override
  /// Creates a Route retaining this Page as its settings.
  Route<T> createRoute(BuildContext context) =>
      CCFlutterRouteFactory.createRoute<T>(
        context: context,
        child: child,
        presentation: presentation,
        settings: this,
        predictiveBackHandler: predictiveBackHandler,
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

  /// Sheet dismissal, surface, and layout options.
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
