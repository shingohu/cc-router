part of 'facade.dart';

/// Controlled external navigation ingress for application hosts.
///
/// Platform integrations, notification handlers, and QR scanners use the
/// matching fixed entry point instead of constructing a [CCNavigationOrigin].
/// Each method preserves the external origin through Runtime route resolution
/// and therefore enforces [CCDeepLinkPolicy]. Business page-to-page navigation
/// must continue using [CCRouter.navigator.open], which remains internal.
abstract final class CCDeepLinkIngress {
  /// Opens a URI received from a Universal Link, App Link, custom scheme, or
  /// platform initial location.
  static Future<void> fromPlatform(Uri uri, {CCNavigationSource? source}) =>
      CCRouter._runtime.openRoute(
        uri,
        origin: CCNavigationOrigin.externalPlatform,
        source: source,
      );

  /// Opens a URI extracted from an external notification payload.
  static Future<void> fromNotification(Uri uri, {CCNavigationSource? source}) =>
      CCRouter._runtime.openRoute(
        uri,
        origin: CCNavigationOrigin.externalNotification,
        source: source,
      );

  /// Opens a URI obtained from a QR code or equivalent untrusted scan input.
  static Future<void> fromQrCode(Uri uri, {CCNavigationSource? source}) =>
      CCRouter._runtime.openRoute(
        uri,
        origin: CCNavigationOrigin.externalQrCode,
        source: source,
      );
}
