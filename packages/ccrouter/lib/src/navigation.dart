part of 'facade.dart';

/// Unified business-facing navigation operations.
///
/// Generated route APIs create typed [CCRouteIntent] values; business code
/// passes them here instead of invoking an adapter or Flutter Navigator
/// directly. Dynamic locations use [open] and still pass through Runtime route
/// matching, policy checks, and Codec decoding.
abstract interface class CCNavigator {
  /// Pushes [intent] and completes with the route's typed Pop result.
  Future<R?> push<R>(CCRouteIntent<R> intent, {CCNavigationSource? source});

  /// Replaces the current route and completes with its typed Pop result.
  Future<R?> replace<R>(CCRouteIntent<R> intent, {CCNavigationSource? source});

  /// Attempts to pop the current route and reports whether it was removed.
  ///
  /// Use this for system back and gesture handling when the active page may
  /// veto the Pop. It is distinct from [canPop], which cannot account for a
  /// backend Pop guard.
  Future<bool> maybePop<R>({R? result});

  /// Pops the current route and pushes [intent] as one stack operation.
  ///
  /// [popResult] completes the removed route's pending result. The returned
  /// Future completes with the new route's typed Pop result.
  Future<R?> popAndPush<R>(
    CCRouteIntent<R> intent, {
    Object? popResult,
    CCNavigationSource? source,
  });

  /// Pops entries until the current entry satisfies [predicate].
  Future<void> popUntil(CCNavigationStackPredicate predicate);

  /// Pushes [intent] and removes previous entries until [predicate] matches.
  Future<R?> pushAndRemoveUntil<R>(
    CCRouteIntent<R> intent,
    CCNavigationStackPredicate predicate, {
    CCNavigationSource? source,
  });

  /// Changes the current location to [intent] without a typed result.
  Future<void> go<R>(CCRouteIntent<R> intent, {CCNavigationSource? source});

  /// Resets navigation state to [intent] as the new root location.
  Future<void> reset<R>(CCRouteIntent<R> intent, {CCNavigationSource? source});

  /// Opens a dynamic internal [uri] after Pattern matching and Codec decoding.
  ///
  /// Use this for application-controlled runtime locations. Platform links,
  /// notification URIs, and scanned values must enter through the future
  /// trusted `CCRouterApp` Deep Link ingress so external policy is enforced.
  Future<void> open(Uri uri, {CCNavigationSource? source});

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
  Future<R?> push<R>(CCRouteIntent<R> intent, {CCNavigationSource? source}) =>
      CCRouter._runtime.pushRoute(intent, source: source);

  /// Replaces through the Runtime owned by [CCRouter].
  @override
  Future<R?> replace<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
  }) => CCRouter._runtime.replaceRoute(intent, source: source);

  /// Attempts to pop through the Runtime owned by [CCRouter].
  @override
  Future<bool> maybePop<R>({R? result}) =>
      CCRouter._runtime.maybePopRoute(result: result);

  /// Pops and pushes through the Runtime owned by [CCRouter].
  @override
  Future<R?> popAndPush<R>(
    CCRouteIntent<R> intent, {
    Object? popResult,
    CCNavigationSource? source,
  }) => CCRouter._runtime.popAndPushRoute(
    intent,
    popResult: popResult,
    source: source,
  );

  /// Pops through the Runtime until [predicate] matches.
  @override
  Future<void> popUntil(CCNavigationStackPredicate predicate) =>
      CCRouter._runtime.popUntilRoute(predicate);

  /// Pushes and removes entries through the Runtime owned by [CCRouter].
  @override
  Future<R?> pushAndRemoveUntil<R>(
    CCRouteIntent<R> intent,
    CCNavigationStackPredicate predicate, {
    CCNavigationSource? source,
  }) => CCRouter._runtime.pushAndRemoveUntilRoute(
    intent,
    predicate,
    source: source,
  );

  /// Changes location through the Runtime owned by [CCRouter].
  @override
  Future<void> go<R>(CCRouteIntent<R> intent, {CCNavigationSource? source}) =>
      CCRouter._runtime.goRoute(intent, source: source);

  /// Resets navigation state through the Runtime owned by [CCRouter].
  @override
  Future<void> reset<R>(
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
  }) => CCRouter._runtime.resetRoute(intent, source: source);

  /// Opens one dynamic application-controlled URI through the Runtime.
  @override
  Future<void> open(Uri uri, {CCNavigationSource? source}) => CCRouter._runtime
      .openRoute(uri, origin: CCNavigationOrigin.internal, source: source);

  /// Pops through the Runtime owned by [CCRouter].
  @override
  void pop<R>({R? result}) => CCRouter._runtime.popRoute(result: result);

  /// Reads Pop capability from the configured Runtime adapter.
  @override
  bool canPop() => CCRouter._runtime.canPopRoute();
}
