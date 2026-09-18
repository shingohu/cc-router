import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Creates a GoRouter page that presents [child] as a modal bottom sheet.
///
/// Use this function from a bound `GoRoute.pageBuilder` for a route whose
/// contract uses [CCModalBottomSheetPresentation]. The route remains a real
/// GoRouter entry, so its typed push Future completes with the value supplied
/// to `pop` or by a dismiss gesture.
Page<Object?> ccGoRouterBottomSheetPage({
  required Widget child,
  required CCModalBottomSheetPresentation presentation,
  LocalKey? key,
  String? name,
  Object? arguments,
  String? restorationId,
}) => CCGoRouterBottomSheetPage(
  child: child,
  presentation: presentation,
  key: key,
  name: name,
  arguments: arguments,
  restorationId: restorationId,
);

/// Creates a GoRouter page that presents [child] as a modal dialog.
///
/// The selected dialog family is resolved by the surrounding Flutter app when
/// [CCDialogRouteType.platformDefault] is used. Material and Cupertino can be
/// requested explicitly through the route contract.
Page<Object?> ccGoRouterDialogPage({
  required Widget child,
  required CCDialogPresentation presentation,
  LocalKey? key,
  String? name,
  Object? arguments,
  String? restorationId,
}) => CCGoRouterDialogPage(
  child: child,
  presentation: presentation,
  key: key,
  name: name,
  arguments: arguments,
  restorationId: restorationId,
);

/// A GoRouter [Page] backed by Flutter's modal bottom-sheet route.
final class CCGoRouterBottomSheetPage<T> extends Page<T> {
  /// Creates a bottom-sheet page with adapter-neutral [presentation] options.
  const CCGoRouterBottomSheetPage({
    required this.child,
    required this.presentation,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// Widget displayed inside the sheet.
  final Widget child;

  /// Bottom-sheet behavior declared by the CCRouter route contract.
  final CCModalBottomSheetPresentation presentation;

  @override
  Route<T> createRoute(BuildContext context) => ModalBottomSheetRoute<T>(
    builder: (_) => child,
    isDismissible: presentation.isDismissible,
    enableDrag: presentation.enableDrag,
    isScrollControlled: presentation.isScrollControlled,
    showDragHandle: presentation.showDragHandle,
    useSafeArea: presentation.useSafeArea,
    settings: this,
  );
}

/// A GoRouter [Page] backed by a Material or Cupertino dialog route.
final class CCGoRouterDialogPage<T> extends Page<T> {
  /// Creates a dialog page with adapter-neutral [presentation] options.
  const CCGoRouterDialogPage({
    required this.child,
    required this.presentation,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// Widget displayed inside the dialog.
  final Widget child;

  /// Dialog behavior declared by the CCRouter route contract.
  final CCDialogPresentation presentation;

  @override
  Route<T> createRoute(BuildContext context) {
    final useCupertino = switch (presentation.routeType) {
      CCDialogRouteType.cupertino => true,
      CCDialogRouteType.material => false,
      CCDialogRouteType.platformDefault =>
        context.dependOnInheritedWidgetOfExactType<InheritedCupertinoTheme>() !=
            null,
    };
    final dismissible = presentation.barrierDismissible ?? !useCupertino;
    if (useCupertino) {
      return CupertinoDialogRoute<T>(
        context: context,
        builder: (_) => child,
        barrierDismissible: dismissible,
        settings: this,
      );
    }
    return DialogRoute<T>(
      context: context,
      builder: (_) => child,
      barrierDismissible: dismissible,
      useSafeArea: presentation.useSafeArea,
      settings: this,
    );
  }
}
