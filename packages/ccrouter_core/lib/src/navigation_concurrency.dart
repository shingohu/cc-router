part of 'runtime.dart';

/// Structured identity used by Runtime's overlapping-navigation gate.
///
/// The key deliberately contains route placement and normalized URI so two
/// Shell outlets or two parameterized destinations cannot suppress one
/// another accidentally. Host identity is reserved for multi-window hosts and
/// is empty until an adapter supplies one.
final class _NavigationConcurrencyKey {
  /// Creates a key from the immutable target metadata.
  const _NavigationConcurrencyKey({
    required this.hostId,
    required this.navigatorOutlet,
    required this.operation,
    required this.routeId,
    required this.normalizedUri,
  });

  /// Backend Host identity, empty for the default Host.
  final String hostId;

  /// Navigator outlet selected by the route placement.
  final String navigatorOutlet;

  /// Stack operation being coordinated.
  final CCNavigationOperation operation;

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
      other.routeId == routeId &&
      other.normalizedUri == normalizedUri;

  @override
  int get hashCode =>
      Object.hash(hostId, navigatorOutlet, operation, routeId, normalizedUri);
}

/// Adds concurrency coordination to Runtime navigation dispatch.
extension CCRouterRuntimeNavigationConcurrency on CCRouterRuntime {
  /// Returns the structured key for a prepared navigation target.
  _NavigationConcurrencyKey _navigationConcurrencyKey(
    CCNavigationOperation operation,
    _PreparedRoute prepared,
  ) => _NavigationConcurrencyKey(
    hostId: '',
    navigatorOutlet: prepared.placement.navigatorOutlet,
    operation: operation,
    routeId: prepared.routeId,
    normalizedUri: prepared.uri,
  );
}
