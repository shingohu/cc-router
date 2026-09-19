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

  /// Removes exactly the managed Entry identified by [handle].
  ///
  /// Obtain [handle] from `CCRouter.activeRouteEntries`. Stale, foreign, and
  /// cross-Runtime handles fail with [CCNavigationAdapterError].
  Future<void> removeRoute(CCRouteEntryHandle handle);

  /// Removes managed Entries below [handle], retaining the target Entry.
  ///
  /// Foreign and opaque backend Entries remain untouched. The configured
  /// Adapter must explicitly support exact identity removal.
  Future<void> removeRouteBelow(CCRouteEntryHandle handle);

  /// Replaces the managed Entry immediately below [handle] with [intent].
  ///
  /// The Future completes when the Adapter accepts the operation. The anchor
  /// remains active, and the replacement later follows ordinary Pop lifecycle.
  Future<void> replaceRouteBelow<R>(
    CCRouteEntryHandle handle,
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
  });

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

  /// Pushes a dynamic internal [uri] after Pattern matching and Codec decoding.
  ///
  /// Use this for application-controlled runtime locations. Platform links,
  /// notification URIs, and scanned values must enter through the future
  /// trusted `CCRouterApp` Deep Link ingress so external policy is enforced.
  /// The Future completes after backend acceptance and does not expose the
  /// destination's Pop result; use [push] with a generated Intent for that.
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

  /// Coordinates a Pop through the Runtime-owned Adapter.
  @override
  Future<CCPopOutcome> maybePopOutcome<R>({
    R? result,
    CCPopTrigger trigger = CCPopTrigger.system,
  }) =>
      CCRouter._runtime.maybePopOutcomeRoute(result: result, trigger: trigger);

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

  /// Removes one exact managed Entry through the Runtime-owned Adapter.
  @override
  Future<void> removeRoute(CCRouteEntryHandle handle) =>
      CCRouter._runtime.removeRoute(handle);

  /// Removes managed Entries below one exact Entry through the Runtime-owned
  /// Adapter.
  @override
  Future<void> removeRouteBelow(CCRouteEntryHandle handle) =>
      CCRouter._runtime.removeRouteBelow(handle);

  /// Replaces one exact Entry below an anchor through the Runtime-owned
  /// Adapter.
  @override
  Future<void> replaceRouteBelow<R>(
    CCRouteEntryHandle handle,
    CCRouteIntent<R> intent, {
    CCNavigationSource? source,
  }) => CCRouter._runtime.replaceRouteBelow(handle, intent, source: source);

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
