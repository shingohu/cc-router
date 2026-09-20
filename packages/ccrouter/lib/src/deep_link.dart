part of 'facade.dart';

/// Controlled external navigation ingress for application hosts.
///
/// Platform integrations, notification handlers, and QR scanners use the
/// matching fixed entry point instead of constructing a [CCNavigationOrigin].
/// Each method preserves the external origin through Runtime route resolution
/// and therefore enforces the Host's [CCDeepLinkIngressPolicy] before the
/// route's [CCDeepLinkPolicy]. Business page-to-page navigation must continue
/// using [CCRouter.navigator.open], which remains internal.
///
/// Every ingress defaults to [CCDeepLinkOpenMode.push], preserving a fixed root
/// or main-Tab page and its Back path. Hosts may explicitly choose
/// [CCDeepLinkOpenMode.go] when an incoming URI must reconstruct a declarative
/// Shell or Outlet location. Stack behavior never weakens origin validation.
abstract final class CCDeepLinkIngress {
  /// Opens a URI received from a Universal Link, App Link, custom scheme, or
  /// platform initial location.
  ///
  /// The Future fails with [CCDeepLinkIngressRejectedError] before matching
  /// when the Host does not own the URI authority.
  static Future<void> fromPlatform(
    Uri uri, {
    CCDeepLinkOpenMode mode = CCDeepLinkOpenMode.push,
    CCNavigationSource? source,
  }) => CCRouter._runtime.openRoute(
    uri,
    origin: CCNavigationOrigin.externalPlatform,
    mode: mode,
    source: source,
  );

  /// Opens a URI extracted from an external notification payload.
  ///
  /// Path-only payloads require the Host policy to enable relative Paths; they
  /// still pass route-level Deep Link and interceptor checks.
  static Future<void> fromNotification(
    Uri uri, {
    CCDeepLinkOpenMode mode = CCDeepLinkOpenMode.push,
    CCNavigationSource? source,
  }) => CCRouter._runtime.openRoute(
    uri,
    origin: CCNavigationOrigin.externalNotification,
    mode: mode,
    source: source,
  );

  /// Opens a URI obtained from a QR code or equivalent untrusted scan input.
  ///
  /// Treat scan data as untrusted even when it resembles an application Path;
  /// the Host policy remains the first route-resolution boundary.
  static Future<void> fromQrCode(
    Uri uri, {
    CCDeepLinkOpenMode mode = CCDeepLinkOpenMode.push,
    CCNavigationSource? source,
  }) => CCRouter._runtime.openRoute(
    uri,
    origin: CCNavigationOrigin.externalQrCode,
    mode: mode,
    source: source,
  );
}
