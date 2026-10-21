part of 'adapter.dart';

/// Implements the optional exact-entry capability without positional removal.
extension _CCGoRouterTargetedClose on CCGoRouterAdapter {
  /// Commits a safe imperative match diff before completing its result.
  Future<CCRouteCloseOutcome> _closeExactNavigation({
    required String navigationId,
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) async {
    _ensureAvailable();
    _CCGoRouterEntry? entry;
    for (final candidate in _entries) {
      if (candidate.request.navigationId == navigationId &&
          candidate.request.hostId == hostId &&
          candidate.request.placement.navigatorOutlet == navigatorOutlet) {
        entry = candidate;
        break;
      }
    }
    if (entry == null) {
      return const CCRouteCloseOutcome(CCRouteCloseStatus.notFound);
    }
    final delegate = _router.routerDelegate;
    final before = delegate.currentConfiguration;
    final target = _findExactImperativeMatch(before.matches, navigationId);
    if (target == null) {
      final operation = entry.request.operation;
      final declarative =
          operation == CCNavigationOperation.go ||
          operation == CCNavigationOperation.reset ||
          entry.request.openMode == CCDeepLinkOpenMode.go;
      return CCRouteCloseOutcome(
        declarative || entry.request.placement.shellId != null
            ? CCRouteCloseStatus.unsupported
            : CCRouteCloseStatus.notFound,
      );
    }
    final route = entry.route?.target;
    final navigator = route?.navigator;
    final settings = route?.settings;
    final matches = _withoutExactImperativeMatch(before.matches, target);
    if (_containsExternalExit(before.matches) ||
        matches == null ||
        matches.isEmpty ||
        route == null ||
        !route.isActive ||
        navigator == null ||
        !identical(navigator, _navigatorForOutlet(navigatorOutlet)) ||
        settings is! Page ||
        settings.key != target.pageKey) {
      return const CCRouteCloseOutcome(CCRouteCloseStatus.unsupported);
    }
    final after = RouteMatchList(
      matches: matches,
      uri: before.uri,
      pathParameters: before.pathParameters,
      extra: before.extra,
      error: before.error,
    );
    if (after.isEmpty) {
      return const CCRouteCloseOutcome(CCRouteCloseStatus.unsupported);
    }
    // No external onExit is present, so GoRouter's SynchronousFuture pipeline
    // commits this diff before yielding. Managed PopGuards already ran in Core.
    // RouteMatchList.remove cannot be used: it truncates covering siblings.
    var declarationCommitted = false;
    try {
      final committed = delegate.setNewRoutePath(after);
      if (!identical(delegate.currentConfiguration, after)) {
        await committed;
      }
      if (!identical(delegate.currentConfiguration, after)) {
        throw const CCNavigationAdapterError(
          'GoRouter did not commit targeted close.',
        );
      }
      declarationCommitted = true;
      // Remove the rendered Route before the next pages rebuild. Otherwise
      // Flutter would also complete foreign pageless Popups attached to that
      // Page. Completing exact channels first prevents observer removal from
      // supplying a null result on the normal path.
      if (!target.completer.isCompleted) target.complete(result);
      entry.completeResult(result);
      navigator.removeRoute<Object?>(route, result);
      _removeTrackedEntry(entry);
      return const CCRouteCloseOutcome(CCRouteCloseStatus.closed);
    } catch (error, stackTrace) {
      // setNewRoutePath can notify synchronously, and a future GoRouter version
      // may commit before a later rendering operation fails. Once the
      // declaration is committed, leave no result channel waiting forever: the
      // Runtime will observe its null completion and close the Route Scope.
      if (declarationCommitted ||
          identical(delegate.currentConfiguration, after)) {
        _completeFailedClose(entry, target);
      }
      if (error is CCRouterError) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      throw CCNavigationAdapterError(
        'GoRouter targeted close failed: ${error.runtimeType}.',
      );
    }
  }

  /// Reconciles an entry after GoRouter committed the declaration but the
  /// rendered Route operation failed. A null result denotes external removal
  /// and lets Runtime complete its ordinary Push lifecycle cleanup.
  void _completeFailedClose(
    _CCGoRouterEntry entry,
    ImperativeRouteMatch target,
  ) {
    if (!target.completer.isCompleted) target.complete(null);
    entry.completeResult(null);
    _removeTrackedEntry(entry);
  }

  /// Finds the exact push/replace identity, descending only structural Shells.
  ImperativeRouteMatch? _findExactImperativeMatch(
    List<RouteMatchBase> matches,
    String navigationId,
  ) {
    for (final match in matches) {
      if (match is ImperativeRouteMatch &&
          CCRouterHostBinding.navigationIdForPayload(match.matches.extra) ==
              navigationId) {
        return match;
      }
      if (match is ShellRouteMatch) {
        final nested = _findExactImperativeMatch(match.matches, navigationId);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  /// Rejects callback-bearing trees to prevent unrelated asynchronous exit work.
  bool _containsExternalExit(List<RouteMatchBase> matches) {
    for (final match in matches) {
      if (match is RouteMatch && match.route.onExit != null) return true;
      if (match is ShellRouteMatch && _containsExternalExit(match.matches))
        return true;
      if (match is ImperativeRouteMatch &&
          _containsExternalExit(match.matches.matches))
        return true;
    }
    return false;
  }

  /// Copies structural ancestors, refusing to remove an entire Shell.
  List<RouteMatchBase>? _withoutExactImperativeMatch(
    List<RouteMatchBase> matches,
    ImperativeRouteMatch target,
  ) {
    var changed = false;
    final retained = <RouteMatchBase>[];
    for (final match in matches) {
      if (identical(match, target)) {
        changed = true;
        continue;
      }
      if (match is ShellRouteMatch) {
        final children = _withoutExactImperativeMatch(match.matches, target);
        if (children == null || children.isEmpty) return null;
        if (!identical(children, match.matches)) {
          changed = true;
          retained.add(
            ShellRouteMatch(
              matches: children,
              route: match.route,
              matchedLocation: match.matchedLocation,
              pageKey: match.pageKey,
              navigatorKey: match.navigatorKey,
            ),
          );
          continue;
        }
      }
      retained.add(match);
    }
    return changed ? retained : matches;
  }
}
