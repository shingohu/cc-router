import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart'
    show CCFlutterPage, CCFlutterPredictiveBackHandler;
import 'package:flutter/widgets.dart';

/// Creates a GoRouter-compatible Page for a normal CCRouter presentation.
///
/// Existing `GoRoute.pageBuilder` integrations retain this entry point while
/// route construction is shared with other Flutter backends.
/// Hosts with custom or attached GoRouters opt in to default Android Material
/// gesture observation by supplying their Adapter's predictive-back bridge as
/// [predictiveBackHandler]. Null preserves the original construction path.
Page<Object?> ccGoRouterPage({
  required Widget child,
  required CCPagePresentation presentation,
  LocalKey? key,
  String? name,
  Object? arguments,
  String? restorationId,
  CCFlutterPredictiveBackHandler? predictiveBackHandler,
}) => CCGoRouterPage(
  child: child,
  presentation: presentation,
  key: key,
  name: name,
  arguments: arguments,
  restorationId: restorationId,
  predictiveBackHandler: predictiveBackHandler,
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
    super.predictiveBackHandler,
  });
}
