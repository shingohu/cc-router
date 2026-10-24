part of 'runtime.dart';

/// Structured identity used by Runtime's overlapping-navigation gate.
///
/// The key deliberately contains route placement and normalized URI so two
/// Shell outlets or two parameterized destinations cannot suppress one
/// another accidentally. Host identity isolates independently owned navigation
/// backends. Exact ingress origin isolates per-source trust policy before
/// interception; telemetry attribution is not a trust boundary. Requests carrying
/// process-local Extra data never create this key because arbitrary objects do
/// not have a stable, type-safe equality contract.
final class _NavigationConcurrencyKey {
  /// Creates a key from the immutable target metadata.
  const _NavigationConcurrencyKey({
    required this.hostId,
    required this.hostRegistration,
    required this.navigatorOutlet,
    required this.operation,
    required this.origin,
    required this.openMode,
    required this.routeId,
    required this.normalizedUri,
  });

  /// Concrete Host identity, or `default` for an Adapter without Host binding.
  final String hostId;

  /// Non-reusable Host lifetime, preventing sharing across unregister/register.
  final CCCancellationToken hostRegistration;

  /// Navigator outlet selected by the route placement.
  final String navigatorOutlet;

  /// Stack operation being coordinated.
  final CCNavigationOperation operation;

  /// Trusted ingress identity whose Interceptor decisions may differ.
  final CCNavigationOrigin origin;

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
      identical(other.hostRegistration, hostRegistration) &&
      other.navigatorOutlet == navigatorOutlet &&
      other.operation == operation &&
      other.origin == origin &&
      other.openMode == openMode &&
      other.routeId == routeId &&
      other.normalizedUri == normalizedUri;

  @override
  int get hashCode => Object.hash(
    hostId,
    hostRegistration,
    navigatorOutlet,
    operation,
    origin,
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
    CCNavigationOrigin origin,
    CCDeepLinkOpenMode? openMode,
  ) => _NavigationConcurrencyKey(
    hostId: _resolveNavigationHostId(prepared.placement),
    hostRegistration: _bindNavigationHost(
      _resolveNavigationHostId(prepared.placement),
    ),
    navigatorOutlet: prepared.placement.navigatorOutlet,
    operation: operation,
    origin: origin,
    openMode: openMode,
    routeId: prepared.routeId,
    normalizedUri: prepared.uri,
  );
}
