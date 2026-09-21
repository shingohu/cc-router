import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart' show CCFlutterPage;
import 'package:flutter/widgets.dart';

/// Creates a GoRouter-compatible Page for a normal CCRouter presentation.
///
/// Existing `GoRoute.pageBuilder` integrations retain this entry point while
/// route construction is shared with other Flutter backends.
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

/// Compatibility Page retaining the existing GoRouter runtime type.
final class CCGoRouterPage<T> extends CCFlutterPage<T> {
  /// Creates a GoRouter Page with the existing constructor and settings.
  const CCGoRouterPage({
    required super.child,
    required super.presentation,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });
}
