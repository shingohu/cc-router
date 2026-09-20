part of 'runtime.dart';

/// Builds sanitized navigation diagnostics without retaining concrete values.
extension _CCRouterRuntimeNavigationDiagnostics on CCRouterRuntime {
  /// Summarizes one operational route address for retained diagnostics.
  ///
  /// The returned value includes only declaration metadata and presence bits;
  /// it never copies Path, Query, Fragment, or backend location values.
  CCRouteAddressSummary _addressSummaryFor({
    String? routeId,
    Uri? uri,
    String? location,
  }) {
    final routePattern = _routeRegistry.routePatternOrNull(routeId);
    final patternUri = routePattern == null ? null : Uri.tryParse(routePattern);
    final concreteUri =
        uri ?? (location == null ? null : Uri.tryParse(location));
    return CCRouteAddressSummary(
      routePattern: routePattern,
      hasPathParameters:
          patternUri?.pathSegments.any(
            (segment) => segment.startsWith(':') || segment.startsWith('*'),
          ) ??
          false,
      hasQueryParameters: concreteUri?.hasQuery ?? false,
      hasFragment: concreteUri?.hasFragment ?? false,
    );
  }

  /// Converts one operational backend Entry to a safe retained snapshot.
  CCBackendEntrySnapshot _backendEntrySnapshot(_BackendEntryRecord entry) =>
      CCBackendEntrySnapshot(
        backendEntryId: entry.backendEntryId,
        owner: entry.owner,
        routeEntryId: entry.routeEntryId,
        navigationId: entry.navigationId,
        routeId: entry.routeId,
        hostId: entry.hostId,
        navigatorOutlet: entry.navigatorOutlet,
        visibilityState: entry.visibilityState,
        address: entry.address,
        lifecycleState: entry.lifecycleState,
        lastSequence: entry.lastSequence,
      );

  /// Converts one immediate Adapter event to a safe diagnostic event.
  CCNavigationBackendDiagnosticEvent _backendDiagnosticEvent(
    CCNavigationBackendEvent event,
  ) => CCNavigationBackendDiagnosticEvent(
    kind: event.kind,
    backendEntryId: event.backendEntryId,
    backendOperationId: event.backendOperationId,
    previousBackendEntryId: event.previousBackendEntryId,
    hostId: event.hostId,
    navigatorOutlet: event.navigatorOutlet,
    activeNavigatorOutlets: event.activeNavigatorOutlets,
    sequence: event.sequence,
    owner: event.owner,
    navigationId: event.navigationId,
    routeId: event.routeId,
    address: _addressSummaryFor(
      routeId: event.routeId,
      uri: event.uri,
      location: event.location,
    ),
    placement: event.placement,
    origin: event.origin,
    source: event.source,
    timestamp: event.timestamp,
  );
}
