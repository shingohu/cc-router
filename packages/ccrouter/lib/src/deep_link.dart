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
/// Each Future completes at the existing backend-acceptance boundary with a
/// payload-free receipt for the actual destination. Redirects and failure
/// recovery report that destination; deferred calls wait for resume. Failure or
/// cancellation still throws. Hosts own business-ID mapping and its cleanup;
/// acceptance does not imply visibility or business success.
///
/// Calls that ignore the receipt may keep their `await` and `try/catch`.
/// Legacy `catchError` handlers returning void/null require conversion with
/// `then<void>((_) {})` before attaching the handler. Merely assigning this
/// Future to `Future<void>`, or returning it from a forwarding function
/// annotated `Future<void>`, preserves its receipt runtime type and can make
/// such handlers throw [ArgumentError] on rejection or cancellation.
abstract final class CCDeepLinkIngress {
  /// Opens a URI received from a Universal Link, App Link, custom scheme, or
  /// platform initial location.
  ///
  /// The Future fails with [CCDeepLinkIngressRejectedError] before matching
  /// when the Host does not own the URI authority.
  static Future<CCDeepLinkAcceptanceReceipt> fromPlatform(
    Uri uri, {
    CCDeepLinkOpenMode mode = CCDeepLinkOpenMode.push,
    CCNavigationSource? source,
  }) => CCRouter._runtime.openRouteWithReceipt(
    uri,
    origin: CCNavigationOrigin.externalPlatform,
    mode: mode,
    source: source,
  );

  /// Opens a URI extracted from an external notification payload.
  ///
  /// Path-only payloads require the Host policy to enable relative Paths; they
  /// still pass route-level Deep Link and interceptor checks.
  static Future<CCDeepLinkAcceptanceReceipt> fromNotification(
    Uri uri, {
    CCDeepLinkOpenMode mode = CCDeepLinkOpenMode.push,
    CCNavigationSource? source,
  }) => CCRouter._runtime.openRouteWithReceipt(
    uri,
    origin: CCNavigationOrigin.externalNotification,
    mode: mode,
    source: source,
  );

  /// Opens a URI obtained from a QR code or equivalent untrusted scan input.
  ///
  /// Treat scan data as untrusted even when it resembles an application Path;
  /// the Host policy remains the first route-resolution boundary.
  static Future<CCDeepLinkAcceptanceReceipt> fromQrCode(
    Uri uri, {
    CCDeepLinkOpenMode mode = CCDeepLinkOpenMode.push,
    CCNavigationSource? source,
  }) => CCRouter._runtime.openRouteWithReceipt(
    uri,
    origin: CCNavigationOrigin.externalQrCode,
    mode: mode,
    source: source,
  );
}
