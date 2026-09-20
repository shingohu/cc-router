/// One exact external URI authority accepted by the application Host.
///
/// Use a rule for Universal Links, App Links, or custom-scheme links that the
/// Host intentionally owns. Scheme and Host comparisons are case-insensitive,
/// while [port] distinguishes non-default endpoints. Wildcards are rejected so
/// a component cannot silently broaden the application's trust boundary.
final class CCDeepLinkAuthorityRule {
  /// Creates and normalizes one exact Scheme, Host, and optional Port rule.
  ///
  /// Configuration errors throw [ArgumentError] during application startup.
  /// Omit [port] to accept the Scheme's default effective Port, including an
  /// explicitly written default Port such as `:443` for HTTPS.
  factory CCDeepLinkAuthorityRule({
    required String scheme,
    required String host,
    int? port,
  }) {
    final normalizedScheme = scheme.trim().toLowerCase();
    if (!_schemeExpression.hasMatch(normalizedScheme)) {
      throw ArgumentError.value(scheme, 'scheme', 'Invalid URI scheme.');
    }
    final normalizedHost = host.trim().toLowerCase();
    if (normalizedHost.isEmpty || normalizedHost.contains('*')) {
      throw ArgumentError.value(
        host,
        'host',
        'Expected one exact non-wildcard Host.',
      );
    }
    if (port != null && (port < 1 || port > 65535)) {
      throw ArgumentError.value(port, 'port', 'Expected a valid TCP port.');
    }
    late final Uri authority;
    try {
      authority = Uri(
        scheme: normalizedScheme,
        host: normalizedHost,
        port: port,
      );
    } on ArgumentError {
      throw ArgumentError.value(host, 'host', 'Invalid URI Host.');
    }
    if (authority.host.isEmpty || authority.userInfo.isNotEmpty) {
      throw ArgumentError.value(host, 'host', 'Invalid URI Host.');
    }
    return CCDeepLinkAuthorityRule._(
      scheme: normalizedScheme,
      host: authority.host.toLowerCase(),
      port: port,
    );
  }

  /// Stores one validated and normalized authority rule.
  const CCDeepLinkAuthorityRule._({
    required this.scheme,
    required this.host,
    required this.port,
  });

  /// URI Scheme accepted by this rule in normalized lowercase form.
  final String scheme;

  /// URI Host accepted by this rule in normalized lowercase form.
  final String host;

  /// Explicit non-default Port, or null when the Scheme default is required.
  final int? port;

  /// URI Scheme grammar used to reject malformed Host configuration early.
  static final RegExp _schemeExpression = RegExp(
    r'^[a-z][a-z0-9+.-]*$',
    caseSensitive: false,
  );
}

/// Application Host trust policy for externally supplied route locations.
///
/// The policy is evaluated before route matching for platform links,
/// notifications, and QR-code input. It complements route-level
/// `CCDeepLinkPolicy` and authentication interceptors; it does not replace
/// either layer. Components must not construct or expand this Host-owned
/// policy.
final class CCDeepLinkIngressPolicy {
  /// Creates an immutable allowlist from exact authority rules.
  ///
  /// Set [allowRelativePaths] only when the Host has already authenticated or
  /// normalized path-only notification or QR payloads. Relative input still
  /// requires the matched route to enable external entry.
  factory CCDeepLinkIngressPolicy({
    Iterable<CCDeepLinkAuthorityRule> allowedAuthorities = const [],
    bool allowRelativePaths = false,
  }) => CCDeepLinkIngressPolicy._(
    List<CCDeepLinkAuthorityRule>.unmodifiable(allowedAuthorities),
    allowRelativePaths,
  );

  /// Stores immutable Host policy data.
  const CCDeepLinkIngressPolicy._(
    this.allowedAuthorities,
    this.allowRelativePaths,
  );

  /// Secure default that rejects every external absolute URI and relative Path.
  ///
  /// Applications that do not consume Deep Links require no additional setup.
  static const CCDeepLinkIngressPolicy denyAll = CCDeepLinkIngressPolicy._(
    <CCDeepLinkAuthorityRule>[],
    false,
  );

  /// Exact external Scheme, Host, and Port combinations owned by the Host.
  final List<CCDeepLinkAuthorityRule> allowedAuthorities;

  /// Whether an external absolute Path without an authority may be resolved.
  ///
  /// Enable this for trusted Host mappers that convert notification, QR, or Web
  /// URLs into paths such as `/orders/42`; never use it as a substitute for
  /// validating an absolute URI's authority.
  final bool allowRelativePaths;
}
