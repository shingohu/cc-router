part of 'facade.dart';

/// Unified business-facing navigation operations.
///
/// Generated route APIs create typed [CCRouteIntent] values; business code
/// passes them here instead of invoking an adapter or Flutter Navigator
/// directly. Dynamic locations use [open] and still pass through Runtime route
/// matching, policy checks, and Codec decoding.
abstract interface class CCNavigator {
  /// Pushes [intent] and completes with the route's typed Pop result.
  ///
  /// When [context] is supplied, the nearest registered Host Outlet is used
  /// only for routes with the default root placement. Resolution is strict and
  /// never falls back to another Host or Outlet.
  Future<R?> push<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
    BuildContext? context,
  });

  /// Replaces the current route and completes with its typed Pop result.
  ///
  /// [context] applies the same optional call-site Outlet resolution as [push].
  Future<R?> replace<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
    BuildContext? context,
  });

  /// Asks the backend to handle a Pop and reports whether it was handled.
  ///
  /// Use this for system back and gesture handling when the active page may
  /// veto the Pop. A `true` result may mean that a LocalHistoryEntry or foreign
  /// PopupRoute consumed the request; it does not prove that a CCRouter Route
  /// Entry was removed. It is distinct from [canPop], which cannot account for
  /// a backend Pop guard.
  Future<bool> maybePop<R>({R? result});

  /// Coordinates a Pop and reports whether a Managed or foreign entry moved.
  ///
  /// Use this when system back, gestures, or modal UI need ownership-aware
  /// diagnostics. [trigger] records whether the request came from system back,
  /// a gesture, or another host integration. For ordinary back handling,
  /// [maybePop] remains sufficient.
  Future<CCPopOutcome> maybePopOutcome<R>({
    R? result,
    CCPopTrigger trigger = CCPopTrigger.system,
  });

  /// Changes the current location to [intent] without a typed result.
  ///
  /// [context] applies the same optional call-site Outlet resolution as [push].
  Future<void> go<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
    BuildContext? context,
  });

  /// Resets navigation state to [intent] as the new root location.
  ///
  /// [context] applies the same optional call-site Outlet resolution as [push].
  Future<void> reset<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
    BuildContext? context,
  });

  /// Pushes a dynamic internal [uri] after Pattern matching and Codec decoding.
  ///
  /// Use this for application-controlled runtime locations. Platform links,
  /// notification URIs, and scanned values must enter through the future
  /// trusted `CCRouterApp` Deep Link ingress so external policy is enforced.
  /// The Future completes after backend acceptance and does not expose the
  /// destination's Pop result; use [push] with a generated Intent for that.
  /// [context] applies the resolved Outlet to the dynamic location.
  Future<void> open(
    Uri uri, {
    CCNavigationSource? source,
    BuildContext? context,
  });

  /// Pops the active route with an optional typed [result].
  void pop<R>({R? result});

  /// Whether the configured adapter can currently pop one route.
  bool canPop();
}

/// Runtime-backed implementation retained privately by [CCRouter].
final class _CCNavigator implements CCNavigator {
  /// Creates the stateless process-local navigation facade.
  const _CCNavigator();

  /// Pushes through the Runtime owned by [CCRouter].
  @override
  Future<R?> push<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
    BuildContext? context,
  }) => CCRouter._runtime.pushRoute(
    intent,
    source: source,
    placementOverride: _resolvePlacement(context),
  );

  /// Replaces through the Runtime owned by [CCRouter].
  @override
  Future<R?> replace<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
    BuildContext? context,
  }) => CCRouter._runtime.replaceRoute(
    intent,
    source: source,
    placementOverride: _resolvePlacement(context),
  );

  /// Attempts to pop through the Runtime owned by [CCRouter].
  @override
  Future<bool> maybePop<R>({R? result}) =>
      CCRouter._runtime.maybePopRoute(result: result);

  /// Coordinates a Pop through the Runtime-owned Adapter.
  @override
  Future<CCPopOutcome> maybePopOutcome<R>({
    R? result,
    CCPopTrigger trigger = CCPopTrigger.system,
  }) =>
      CCRouter._runtime.maybePopOutcomeRoute(result: result, trigger: trigger);

  /// Changes location through the Runtime owned by [CCRouter].
  @override
  Future<void> go<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
    BuildContext? context,
  }) => CCRouter._runtime.goRoute(
    intent,
    source: source,
    placementOverride: _resolvePlacement(context),
  );

  /// Resets navigation state through the Runtime owned by [CCRouter].
  @override
  Future<void> reset<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
    BuildContext? context,
  }) => CCRouter._runtime.resetRoute(
    intent,
    source: source,
    placementOverride: _resolvePlacement(context),
  );

  /// Opens one dynamic application-controlled URI through the Runtime.
  @override
  Future<void> open(
    Uri uri, {
    CCNavigationSource? source,
    BuildContext? context,
  }) => CCRouter._runtime.openRoute(
    uri,
    origin: CCNavigationOrigin.internal,
    mode: CCDeepLinkOpenMode.push,
    source: source,
    placementOverride: _resolvePlacement(context),
  );

  /// Pops through the Runtime owned by [CCRouter].
  @override
  void pop<R>({R? result}) => CCRouter._runtime.popRoute(result: result);

  /// Reads Pop capability from the configured Runtime adapter.
  @override
  bool canPop() => CCRouter._runtime.canPopRoute();

  /// Converts an optional Flutter Context into a strict route placement.
  CCRoutePlacement? _resolvePlacement(BuildContext? context) {
    return _resolveContextPlacement(context);
  }
}
