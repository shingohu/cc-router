import 'route.dart';
import 'route_pattern.dart';
import 'route_placement.dart';
import 'route_presentation.dart';

/// Compile-time identity and dependency contract shared by routes and Runtime.
///
/// Define one const value in each component and reuse it from every [CCRoute]
/// plus `CCComponentManifest.fromDescriptor`. This keeps build-time ownership
/// and Runtime dependency ordering aligned.
final class CCComponentDescriptor {
  /// Creates one stable component contract declaration.
  const CCComponentDescriptor({
    required this.id,
    required this.version,
    this.dependencies = const [],
    this.optionalDependencies = const [],
  });

  /// Globally unique component identifier used by route ownership metadata.
  final String id;

  /// Semantic contract version displayed in generated route documentation.
  final String version;

  /// Component IDs that must be installed before this component.
  final List<String> dependencies;

  /// Component IDs ordered first only when present in the application.
  final List<String> optionalDependencies;
}

/// Marks the registrar that publishes one [descriptor] to generated metadata.
///
/// Use exactly once per component package. This also describes components that
/// own no routes, so workspace visibility checks can resolve every consumer.
final class CCComponent {
  /// Associates a registrar declaration with its shared component descriptor.
  const CCComponent(this.descriptor);

  /// Single source of component identity, version and dependency information.
  final CCComponentDescriptor descriptor;
}

/// Declares a destination whose typed contract is generated at build time.
///
/// Component authors annotate a concrete page with an unnamed constructor,
/// then include its `.ccroute.g.dart` file using `part`. The generator creates
/// arguments, an Intent factory, a codec, a definition and a page factory. It
/// never navigates or selects a backend. [R] is the page's return type; use
/// `void` for destinations without a business result.
final class CCRoute<R> {
  /// Creates route metadata with exactly one of [pattern] or [patterns].
  ///
  /// The generator rejects missing or simultaneous declarations and resolves
  /// the one effective primary before emitting the Runtime definition.
  const CCRoute({
    required this.component,
    required this.id,
    this.pattern,
    this.patterns = const [],
    this.visibility = CCRouteVisibility.component,
    this.visibleTo = const {},
    this.deepLink = CCDeepLinkPolicy.disabled,
    this.presentation = const CCPagePresentation(),
    this.placement = const CCRoutePlacement.root(),
    this.interceptors = const [],
    this.description,
  });

  /// Component that owns registration, visibility and generated documentation.
  final CCComponentDescriptor component;

  /// Stable route identity shared by tracing, registration and typed Intents.
  final String id;

  /// Single canonical pattern for the common one-address route declaration.
  ///
  /// Use this instead of [patterns] when the destination has no aliases. The
  /// generator promotes a reversible Path or URI pattern to primary, so callers
  /// do not need to set `primary: true`. It is a build error to set both fields
  /// or to provide a match-only regular expression here.
  final CCRoutePattern? pattern;

  /// Canonical pattern and aliases for destinations with multiple addresses.
  ///
  /// Use this instead of [pattern] when compatibility paths, full URLs, custom
  /// schemes, or regular-expression aliases resolve to one route. If exactly
  /// one entry is reversible, the generator promotes it to primary. Multiple
  /// reversible entries require exactly one explicit primary declaration.
  final List<CCRoutePattern> patterns;

  /// Whether the generated contract is library-private or explicitly exported.
  ///
  /// Component-only routes generate private declarations in the page library.
  /// Exported declarations require a deliberate component barrel export;
  /// cross-package dependency and allowlist checks are a separate build stage.
  final CCRouteVisibility visibility;

  /// Consumers permitted by the workspace component aggregation validator.
  ///
  /// Preserved in the definition, not interpreted as Runtime authorization.
  final Set<String> visibleTo;

  /// Whether a controlled external ingress may resolve this destination.
  final CCDeepLinkPolicy deepLink;

  /// Adapter-neutral page, dialog or modal-sheet presentation metadata.
  final CCRoutePresentation presentation;

  /// Explicit host, parent, shell and outlet placement metadata.
  final CCRoutePlacement placement;

  /// Registered route-level interceptor identities in execution order.
  final List<String> interceptors;

  /// Route purpose included in generated JSON and Markdown documentation.
  final String? description;
}

/// Marks a constructor parameter as a single URI query value.
///
/// Use for optional filters or a required query value. Scalars support String,
/// int, double, bool and enums. Missing optional values use the constructor
/// default or null; repeated scalar values and invalid values are rejected.
final class CCQueryParam {
  /// Uses the constructor parameter's name unless [name] supplies a wire name.
  const CCQueryParam({this.name});

  /// URI query key, independent of the generated Dart parameter name.
  final String? name;
}

/// Marks the one in-memory constructor parameter carried outside the URI.
///
/// Use for optional snapshots or complex application objects. A required Extra
/// cannot be combined with enabled deep links, and wrong Extra types produce
/// a parameter error. Extra is not serialized or suitable for restoration.
final class CCExtraParam {
  /// Declares a typed, process-local Extra value.
  const CCExtraParam();
}
