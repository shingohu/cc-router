part of 'runtime.dart';

/// Structured identity used by Runtime's overlapping-navigation gate.
///
/// The key deliberately contains route placement and normalized URI so two
/// Shell outlets or two parameterized destinations cannot suppress one
/// another accidentally. Host identity isolates independently owned navigation
/// backends and is empty until an adapter supplies one.
final class _NavigationConcurrencyKey {
  /// Creates a key from the immutable target metadata.
  const _NavigationConcurrencyKey({
    required this.hostId,
    required this.navigatorOutlet,
    required this.operation,
    required this.openMode,
    required this.routeId,
    required this.normalizedUri,
  });

  /// Backend Host identity, empty for the default Host.
  final String hostId;

  /// Navigator outlet selected by the route placement.
  final String navigatorOutlet;

  /// Stack operation being coordinated.
  final CCNavigationOperation operation;

  /// Dynamic Open stack behavior, or null for typed operations.
  ///
  /// Keeping this in the key prevents simultaneous Push and Go ingress for the
  /// same URI from sharing a single-flight result with different stack effects.
  final CCDeepLinkOpenMode? openMode;

  /// Stable route identity.
  final String routeId;

  /// Canonical URI containing path and query parameters.
  final Uri normalizedUri;

  @override
  bool operator ==(Object other) =>
      other is _NavigationConcurrencyKey &&
      other.hostId == hostId &&
      other.navigatorOutlet == navigatorOutlet &&
      other.operation == operation &&
      other.openMode == openMode &&
      other.routeId == routeId &&
      other.normalizedUri == normalizedUri;

  @override
  int get hashCode => Object.hash(
    hostId,
    navigatorOutlet,
    operation,
    openMode,
    routeId,
    normalizedUri,
  );
}

/// Adds concurrency coordination to Runtime navigation dispatch.
extension CCRouterRuntimeNavigationConcurrency on CCRouterRuntime {
  /// Returns the structured key for a prepared navigation target.
  _NavigationConcurrencyKey _navigationConcurrencyKey(
    CCNavigationOperation operation,
    _PreparedRoute prepared,
    CCDeepLinkOpenMode? openMode,
  ) => _NavigationConcurrencyKey(
    hostId: _resolveNavigationHostId(prepared.placement),
    navigatorOutlet: prepared.placement.navigatorOutlet,
    operation: operation,
    openMode: openMode,
    routeId: prepared.routeId,
    normalizedUri: prepared.uri,
  );
}
