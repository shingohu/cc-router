/// Tabs encoded by name in the generated route query.
enum GeneratedDetailTab {
  /// Summary tab.
  summary,

  /// Item list tab.
  items,
}

/// In-memory state passed through the route Extra boundary.
final class GeneratedSnapshot {
  /// Creates a snapshot with a stable test label.
  const GeneratedSnapshot(this.label);

  /// Test-only label retained by identity checks.
  final String label;
}

/// Result modes used by generated route import-prefix regression tests.
enum GeneratedRouteMode {
  /// Default mode.
  normal,

  /// Alternate mode.
  alternate,
}

/// In-memory payload used by generated Extra regression tests.
final class GeneratedRoutePayload {
  /// Creates the immutable fixture payload.
  const GeneratedRoutePayload();
}

/// Typed result used to verify imported result contracts.
final class GeneratedRouteResult {
  /// Creates the immutable fixture result.
  const GeneratedRouteResult();
}
