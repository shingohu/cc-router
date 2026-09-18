import 'navigation.dart';

/// Public snapshot of a navigation paused by an external application policy.
///
/// The snapshot is safe for authentication or host UI to inspect. Typed
/// arguments and `extra` remain Runtime-owned; resuming always re-runs route
/// resolution, component activation checks, and every interceptor.
final class CCPendingNavigation {
  /// Creates an immutable pending-navigation snapshot.
  const CCPendingNavigation({
    required this.navigationId,
    required this.operation,
    required this.routeId,
    required this.uri,
    required this.origin,
    required this.source,
    required this.createdAt,
    required this.expiresAt,
  });

  /// Stable navigation identity retained across resume.
  final String navigationId;

  /// Stack operation that will be replayed when resumed.
  final CCNavigationOperation operation;

  /// Stable resolved route ID.
  final String routeId;

  /// Normalized URI of the paused target.
  final Uri uri;

  /// Trusted ingress classification retained for policy checks.
  final CCNavigationOrigin origin;

  /// Non-sensitive product attribution retained for telemetry.
  final CCNavigationSource? source;

  /// Time at which Runtime created the pending continuation.
  final DateTime createdAt;

  /// Optional expiry time; null means the continuation has no timer.
  final DateTime? expiresAt;
}
