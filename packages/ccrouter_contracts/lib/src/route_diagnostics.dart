/// Sanitized description of a route address retained for diagnostics.
///
/// The summary deliberately excludes the concrete URI, path values, query
/// values, fragment text, and backend location. Use it for bounded histories,
/// telemetry, and developer diagnostics where retaining a navigable address
/// would expose user identifiers, tokens, or third-party URLs.
final class CCRouteAddressSummary {
  /// Creates an immutable address summary without concrete parameter values.
  const CCRouteAddressSummary({
    required this.routePattern,
    required this.hasPathParameters,
    required this.hasQueryParameters,
    required this.hasFragment,
  });

  /// Canonical registered route pattern, or null for an unknown backend route.
  ///
  /// This is declaration metadata such as `/orders/:id`; it never contains a
  /// concrete parameter value from the navigation request.
  final String? routePattern;

  /// Whether the canonical pattern contains named or wildcard Path values.
  final bool hasPathParameters;

  /// Whether the concrete address contained one or more Query parameters.
  ///
  /// Parameter names and values are intentionally not retained.
  final bool hasQueryParameters;

  /// Whether the concrete address contained a Fragment.
  ///
  /// The Fragment text is intentionally not retained.
  final bool hasFragment;
}
