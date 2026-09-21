import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart'
    show CCFlutterBottomSheetPage, CCFlutterDialogPage;
import 'package:flutter/widgets.dart';

/// Creates a GoRouter-compatible Page for a modal bottom sheet.
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

/// Creates a GoRouter-compatible Page for a Material or Cupertino dialog.
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

/// Compatibility bottom-sheet Page retaining the existing GoRouter type.
final class CCGoRouterBottomSheetPage<T> extends CCFlutterBottomSheetPage<T> {
  /// Creates a GoRouter sheet with the existing constructor and settings.
  const CCGoRouterBottomSheetPage({
    required super.child,
    required super.presentation,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });
}

/// Compatibility dialog Page retaining the existing GoRouter type.
final class CCGoRouterDialogPage<T> extends CCFlutterDialogPage<T> {
  /// Creates a GoRouter dialog with the existing constructor and settings.
  const CCGoRouterDialogPage({
    required super.child,
    required super.presentation,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });
}
