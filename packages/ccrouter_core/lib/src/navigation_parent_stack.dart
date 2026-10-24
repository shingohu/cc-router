part of 'runtime.dart';

/// Validates structural ancestors before any declarative Backend mutation.
extension _CCRouterRuntimeParentStack on CCRouterRuntime {
  /// Resolves independent ancestor arguments and identities for a leaf request.
  ///
  /// Reconstruction is restricted to declarative operations. Ordinary pushes
  /// preserve their existing stack; no retained Entry or Extra is cloned.
  List<CCNavigationRequest> _prepareParentStack(
    CCNavigationRequest request,
    _PreparedRoute leaf,
  ) {
    final declarative =
        request.operation == CCNavigationOperation.go ||
        request.operation == CCNavigationOperation.reset ||
        (request.operation == CCNavigationOperation.open &&
            request.openMode == CCDeepLinkOpenMode.go);
    final adapter = _requiredNavigationAdapter;
    if (!declarative ||
        adapter is! CCNavigationParentStackAdapter ||
        !(adapter as CCNavigationParentStackAdapter).supportsParentStack(
          request,
        )) {
      return const [];
    }
    final parents = <_PreparedRoute>[];
    final visited = {leaf.routeId};
    var child = leaf;
    while (child.placement.parentRouteId != null) {
      child = _routeRegistry.prepareParent(child);
      if (!visited.add(child.routeId)) {
        throw CCRouteRegistrationError(
          'Cyclic reconstructed parent route "${child.routeId}".',
        );
      }
      parents.add(child);
    }
    return [
      for (final parent in parents.reversed)
        _buildNavigationRequest(
          CCNavigationOperation.open,
          parent,
          request.origin,
          CCDeepLinkOpenMode.push,
          request.source,
          navigationId: '$_runtimeId-navigation-${++_navigationSequence}',
        ),
    ];
  }

  /// Commits reconstructed ancestors after the leaf's removal strategy ran.
  ///
  /// Backend acceptance already succeeded. Parent Entries precede the leaf,
  /// remain hidden until confirmed top, and own independent cancellable Scopes.
  void _commitParentStack(
    _RouteEntryRecord leaf,
    List<CCNavigationRequest> parents,
  ) {
    for (final request in parents) {
      final parent = _createRouteEntry(request);
      _routeEntries.insert(_routeEntries.indexOf(leaf), parent);
      _emitRouteEntryTransition(parent, CCRouteEntryLifecycleState.pushed);
      _associateCommittedBackendEntry(parent);
    }
  }
}
