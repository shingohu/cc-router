part of 'runtime.dart';

/// Per-ingress scalar identity capture, never an Entry or Scope owner.
final class _NavigationAcceptanceCapture {
  /// Invocation identity assigned before route resolution or concurrency sharing.
  late final String navigationId;

  /// Last committed destination; recovery replaces a failed attempt's identity.
  CCDeepLinkAcceptanceReceipt? receipt;

  /// Copies only immutable identities from a concrete committed Entry.
  void recordEntry(_RouteEntryRecord entry) => record(
    CCDeepLinkAcceptanceReceipt(
      navigationId: entry.request.navigationId,
      entryNavigationId: entry.request.navigationId,
      routeEntryId: entry.id,
      routeId: entry.request.routeId,
    ),
  );

  /// Preserves this caller's ID while associating a shared producer's Entry.
  void record(CCDeepLinkAcceptanceReceipt accepted) {
    receipt = CCDeepLinkAcceptanceReceipt(
      navigationId: navigationId,
      entryNavigationId: accepted.entryNavigationId,
      routeEntryId: accepted.routeEntryId,
      routeId: accepted.routeId,
    );
  }
}

/// Existing cross-Zone result channel plus optional payload-free Entry identity.
///
/// Removed at the same terminal/Host boundary as the original single-flight
/// record. No caller callback, Entry, Scope, or Runtime is retained here.
final class _NavigationFlight {
  /// Keeps typed Pop/acceptance results on their original shared channel.
  final _SharedResult<Object?> result = _SharedResult<Object?>();

  /// Producer's committed identity, available only for external Open operations.
  CCDeepLinkAcceptanceReceipt? acceptance;

  /// Copies committed identity without extending the Entry's lifetime.
  void recordEntry(_RouteEntryRecord entry) {
    acceptance = CCDeepLinkAcceptanceReceipt(
      navigationId: entry.request.navigationId,
      entryNavigationId: entry.request.navigationId,
      routeEntryId: entry.id,
      routeId: entry.request.routeId,
    );
  }
}
