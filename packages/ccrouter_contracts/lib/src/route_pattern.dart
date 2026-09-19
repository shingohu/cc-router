/// Base contract for one address pattern accepted by a route definition.
///
/// Route owners combine path, absolute-URI, and full regular-expression
/// patterns when one destination must accept multiple address forms. Exactly
/// one non-match-only pattern in each route is marked [primary] for canonical
/// address generation; every pattern still resolves to the same stable route
/// ID. Regular-expression patterns are the only match-only form; callers can
/// determine reversibility from the concrete pattern type.
sealed class CCRoutePattern {
  /// Creates declarative pattern metadata usable in const route annotations.
  const CCRoutePattern({required this.primary});

  /// Whether this pattern is the canonical address-generation source.
  ///
  /// Exactly one pattern in a route definition must be primary. Use aliases for
  /// compatibility and external entry instead of changing the primary pattern
  /// when a previously published address must remain valid.
  final bool primary;
}

/// Matches a slash-prefixed path template independently of URI authority.
///
/// Use this for normal application routes such as `/orders/:orderId`. Named
/// parameters begin with `:`, while a final `*name` segment captures the
/// remaining path. Parameter constraints restrict individual named segments
/// without turning the complete template into an opaque regular expression.
final class CCPathPattern extends CCRoutePattern {
  /// Creates a path template with optional named-parameter constraints.
  const CCPathPattern(
    this.template, {
    bool primary = false,
    this.constraints = const {},
  }) : super(primary: primary);

  /// Slash-prefixed template such as `/orders/:orderId`.
  final String template;

  /// Regular expressions keyed by named template parameters.
  ///
  /// Use these for segment-level formats such as numeric IDs. Expressions are
  /// automatically full-matched against one decoded path segment. Annotation
  /// and generated code use a const Map; handwritten registration must not
  /// mutate a supplied Map after constructing the pattern.
  final Map<String, String> constraints;
}

/// Matches an absolute URI template by scheme, authority, and path.
///
/// Use this for Universal Links, App Links, and custom schemes such as
/// `https://example.com/orders/:orderId` or `myapp://orders/:orderId`.
/// Scheme and host comparisons are case-insensitive, while path matching keeps
/// its normal case-sensitive semantics. Query values are decoded separately and
/// therefore Query, Fragment, and User Info must not be embedded in [template].
final class CCUriPattern extends CCRoutePattern {
  /// Creates an absolute URI template with optional path-parameter constraints.
  const CCUriPattern(
    this.template, {
    bool primary = false,
    this.constraints = const {},
  }) : super(primary: primary);

  /// Absolute URI template containing a scheme, host, and optional path.
  final String template;

  /// Regular expressions keyed by named parameters in the URI path.
  ///
  /// Constraints apply only to decoded path segments. Scheme, host, and port
  /// remain explicit structural values rather than regular expressions.
  /// Annotation and generated code use a const Map; handwritten registration
  /// must not mutate a supplied Map after constructing the pattern.
  final Map<String, String> constraints;
}

/// Full-matches a path or absolute URI with one regular expression.
///
/// Use this only for compatibility addresses that cannot be represented by a
/// reversible path or URI template. Named capture groups are exposed as Path
/// parameters to the route codec. This pattern is always match-only and cannot
/// be the canonical generation source.
final class CCRegexPattern extends CCRoutePattern {
  /// Creates a match-only full regular-expression pattern.
  const CCRegexPattern(this.expression) : super(primary: false);

  /// Dart regular expression applied to the complete location without Query or
  /// Fragment text.
  ///
  /// The Runtime adds full-match boundaries, so callers should describe the
  /// intended location rather than depending on substring matching.
  final String expression;
}
