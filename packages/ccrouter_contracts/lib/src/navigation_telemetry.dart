/// Anonymous identifiers attached to sanitized navigation observations.
///
/// Hosts use this context to correlate navigation events with an analytics
/// visitor or application run without exposing an account ID, route payload,
/// device secret, or arbitrary business object. UV aggregation remains the
/// responsibility of the external analytics system.
final class CCNavigationTelemetryContext {
  /// Creates one immutable anonymous telemetry snapshot.
  ///
  /// Identifiers must be opaque values generated for analytics use. Do not pass
  /// an account ID, email, phone number, authentication token, or device ID.
  const CCNavigationTelemetryContext({
    required this.anonymousVisitorId,
    this.applicationSessionId,
  });

  /// Stable pseudonymous visitor identity used for external UV aggregation.
  final String anonymousVisitorId;

  /// Optional identity for one application process or analytics session.
  final String? applicationSessionId;
}

/// Host SPI that snapshots anonymous context at navigation start.
///
/// Application composition code may implement this interface to connect an
/// analytics identity provider. The callback must be synchronous, inexpensive,
/// and side-effect free. Business pages should not call it directly.
abstract interface class CCNavigationTelemetryContextProvider {
  /// Returns the current anonymous context, or null when tracking is disabled.
  CCNavigationTelemetryContext? currentContext();
}
