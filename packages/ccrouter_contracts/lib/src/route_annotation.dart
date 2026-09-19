import 'route.dart';
import 'route_pattern.dart';
import 'route_placement.dart';
import 'route_presentation.dart';

/// Compile-time identity and dependency contract shared by routes and Runtime.
///
/// Define one const value in each component and reuse it from every [CCRoute]
/// plus the Registrar's [CCComponent] annotation. The generator derives the
/// Runtime Manifest from that annotation so build-time ownership and Runtime
/// dependency ordering cannot drift.
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
/// own no routes, so workspace ownership checks and Host assembly can resolve
/// every consumer. Registrar libraries include the generated `.component.g.dart`
/// Part; application code consumes the generated Manifest rather than the
/// private Registrar.
final class CCComponent {
  /// Associates a registrar declaration with its shared component descriptor.
  const CCComponent(this.descriptor);

  /// Single source of component identity, version and dependency information.
  final CCComponentDescriptor descriptor;
}

/// Declares a destination whose typed contract is generated at build time.
///
/// Component authors annotate a concrete page with an unnamed constructor,
/// then include its `.route.g.dart` file using `part`. The generator keeps the
/// complete contract library-private in that Part, making this declaration the
/// component-internal route form. Use [CCRouteContract] plus
/// [CCRouteImplementation] when a route must become a public contract. This
/// annotation neither navigates nor selects a backend. [R] is the page's return
/// type; use `void` when no business result exists.
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
    this.deepLink = CCDeepLinkPolicy.disabled,
    this.presentation = const CCPagePresentation(),
    this.placement = const CCRoutePlacement.root(),
    this.interceptors = const [],
    this.description,
  });

  /// Component that owns registration and generated documentation.
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

/// Declares a Pure Dart route contract independently from its Flutter page.
///
/// Place this annotation on an abstract, non-generic schema class inside a
/// public contract library when a route must be consumed outside its page
/// library. The schema's unnamed constructor defines typed route parameters;
/// the generator emits Arguments, Intent, Definition, and Codec beside that
/// schema. A Flutter component binds the destination separately with
/// [CCRouteImplementation]. Keep the schema in the implementation Package for
/// a Package-public contract, or move it to a dedicated Pure Dart contracts
/// Package for a cross-component contract.
///
/// Keep routes on [CCRoute] while they are component-internal. Promote them to
/// this annotation only when another component needs the contract, preserving
/// the existing route ID, patterns, parameter semantics, and result type.
final class CCRouteContract<R> {
  /// Creates a public Contract-first route declaration.
  ///
  /// Exactly one of [pattern] or [patterns] must be supplied. Contract-first
  /// routes are always public because their purpose is use outside the page
  /// library. Consumers must explicitly depend on and import the Package that
  /// owns the contract.
  const CCRouteContract({
    required this.component,
    required this.id,
    this.pattern,
    this.patterns = const [],
    this.deepLink = CCDeepLinkPolicy.disabled,
    this.presentation = const CCPagePresentation(),
    this.placement = const CCRoutePlacement.root(),
    this.interceptors = const [],
    this.description,
  });

  /// Component that owns the contract and its eventual page implementation.
  final CCComponentDescriptor component;

  /// Stable identity retained when an internal route is promoted.
  final String id;

  /// Single canonical address used by the common one-pattern declaration.
  final CCRoutePattern? pattern;

  /// Canonical address and aliases accepted by the same destination contract.
  final List<CCRoutePattern> patterns;

  /// Whether controlled external ingress may resolve this contract.
  final CCDeepLinkPolicy deepLink;

  /// Adapter-neutral visual presentation requested by the destination.
  final CCRoutePresentation presentation;

  /// Host, Shell, parent, and Navigator Outlet placement metadata.
  final CCRoutePlacement placement;

  /// Route interceptor identities applied after global navigation policies.
  final List<String> interceptors;

  /// Stable purpose included in generated catalogs and review documentation.
  final String? description;
}

/// Binds a concrete Flutter page to one Contract-first route declaration.
///
/// Use this only in the component that implements the route. The generator
/// validates the page's unnamed constructor against the referenced schema and
/// emits registration, description, and page-construction glue without
/// duplicating the public contract. Business callers never use this annotation
/// or import the implementation package.
final class CCRouteImplementation {
  /// Associates a page with the annotated schema [contract].
  ///
  /// The referenced type must carry [CCRouteContract], and workspace assembly
  /// rejects missing or duplicate implementations for the stable route ID.
  const CCRouteImplementation(this.contract);

  /// Abstract Contract-first schema implemented by the annotated page.
  final Type contract;
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
