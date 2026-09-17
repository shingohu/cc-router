import 'route_pattern.dart';
import 'route_presentation.dart';

/// Controls which generated consumers may reference a route contract.
///
/// Use component visibility for implementation-only pages and exported
/// visibility for stable cross-component navigation contracts. This is an
/// API-generation boundary, not a security authorization mechanism.
enum CCRouteVisibility {
  /// Keeps the route available only to its owning component.
  ///
  /// Use for workflow steps and implementation pages with no external caller.
  component,

  /// Allows the generator to export the route to explicitly listed consumers.
  ///
  /// Use for stable entry points intentionally consumed by other components.
  exported,
}

/// Controls whether a route may be entered from an external URI.
///
/// External entry includes Universal Links, App Links, custom schemes, QR
/// codes, notification links, and links opened by another application. This
/// policy only decides whether the route may enter the deep-link pipeline; it
/// does not grant component visibility or bypass authentication, authorization,
/// host allowlists, parameter validation, or route interceptors.
enum CCDeepLinkPolicy {
  /// Rejects platform and browser deep-link entry for the route.
  ///
  /// This is the default and is appropriate for internal workflow pages,
  /// payment confirmation, debug tools, and pages that require in-memory
  /// [CCEncodedRouteArguments.extra] data.
  disabled,

  /// Allows external entry after application-level validation.
  ///
  /// Use this for shareable detail pages, campaign pages, notification targets,
  /// and other routes intentionally reachable from a URI. The application must
  /// still validate the URI scheme and host and run route-level access checks.
  enabled,
}

/// Encoded route values exchanged at the controlled codec boundary.
///
/// Generated codecs and navigation adapters use this boundary to exchange URI
/// values and optional in-memory Extra data. Business code should use generated
/// argument types instead of constructing this object directly.
final class CCEncodedRouteArguments {
  /// Creates immutable Path, Query, and in-memory Extra arguments.
  CCEncodedRouteArguments({
    Map<String, String> path = const {},
    Map<String, List<String>> query = const {},
    this.extra,
  }) : path = Map.unmodifiable(path),
       query = Map.unmodifiable(
         query.map(
           (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
         ),
       );

  /// String values encoded into named Path parameters.
  final Map<String, String> path;

  /// String values encoded into Query parameters.
  final Map<String, List<String>> query;

  /// In-memory value that is never serialized into a URI.
  final Object? extra;
}

/// Converts one generated argument type to and from route boundary values.
///
/// Generated route code implements this interface for automatic Path, Query,
/// and Extra injection. Custom codecs are appropriate only for explicitly
/// supported value types that the standard generator cannot encode.
abstract interface class CCRouteCodec<A> {
  /// Decodes validated Path, Query, and Extra values into [A].
  A decode(CCEncodedRouteArguments input);

  /// Encodes [arguments] into validated Path, Query, and Extra values.
  CCEncodedRouteArguments encode(A arguments);
}

/// Immutable definition registered by one component's generated Registrar.
///
/// Component registrars use definitions to install routes in the Runtime.
/// Business callers should navigate with [CCRouteIntent] rather than depending
/// on definitions or their codec details.
final class CCRouteDefinition<A, R> {
  /// Creates a route definition with a stable ID and one primary pattern.
  CCRouteDefinition({
    required this.routeId,
    required List<CCRoutePattern> patterns,
    required this.codec,
    this.visibility = CCRouteVisibility.component,
    Set<String> visibleTo = const {},
    this.deepLink = CCDeepLinkPolicy.disabled,
    this.presentation = const CCPagePresentation(),
    this.description,
  }) : patterns = List.unmodifiable(patterns),
       visibleTo = Set.unmodifiable(visibleTo);

  /// Stable identity used for tracing, registration, and generated contracts.
  final String routeId;

  /// Canonical address pattern followed by compatible matching aliases.
  ///
  /// Use path patterns for normal application locations, URI patterns for
  /// explicit external authorities, and regular expressions only for
  /// non-reversible compatibility input.
  final List<CCRoutePattern> patterns;

  /// Typed argument codec generated for this route.
  final CCRouteCodec<A> codec;

  /// Component-only or explicitly exported visibility policy.
  final CCRouteVisibility visibility;

  /// Component IDs for which generators may expose this exported contract.
  ///
  /// An empty set leaves the exported contract unrestricted by a component
  /// allowlist. Use that form sparingly for intentionally application-wide APIs.
  ///
  /// Build tooling and CI validate this allowlist and component dependencies.
  /// Runtime navigation does not treat it as caller identity or authorization.
  final Set<String> visibleTo;

  /// Whether external URI entry is permitted for this route.
  final CCDeepLinkPolicy deepLink;

  /// Adapter-neutral instructions for presenting this route.
  ///
  /// Page presentation is the default for ordinary destinations. Route owners
  /// use modal bottom-sheet or dialog presentations for focused overlay
  /// workflows; callers cannot change presentation behavior for an individual
  /// navigation.
  final CCRoutePresentation presentation;

  /// Optional human-readable documentation description.
  final String? description;
}

/// Typed navigation intent created by generated route APIs.
///
/// Business code passes an intent to `CCRouter.navigator` for push, replace, or
/// go operations. Intent implementations construct data only and must not call
/// a navigation adapter directly.
abstract interface class CCRouteIntent<R> {
  /// Stable route ID targeted by this intent.
  String get routeId;

  /// Type-erased generated argument object consumed by the route codec.
  Object get arguments;
}

/// Location resolved from a URI or internal path before adapter navigation.
///
/// The Runtime and navigation adapters use this value after deterministic
/// Pattern matching. Business code normally receives generated arguments
/// instead.
final class CCRouteLocation {
  /// Creates an immutable route location with decoded string parameters.
  CCRouteLocation({
    required this.routeId,
    required this.path,
    required Map<String, String> pathParameters,
    required Map<String, List<String>> queryParameters,
  }) : pathParameters = Map.unmodifiable(pathParameters),
       queryParameters = Map.unmodifiable(
         queryParameters.map(
           (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
         ),
       );

  /// Stable route ID selected by the matcher.
  final String routeId;

  /// Normalized path that matched the route.
  final String path;

  /// Named values captured from a path template or full regular expression.
  final Map<String, String> pathParameters;

  /// Query values captured from the URI, preserving repeated values.
  final Map<String, List<String>> queryParameters;
}
