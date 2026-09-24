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
  ///
  /// Use lowercase alphanumeric segments separated by `.`, `_`, or `-`, with
  /// at most 128 characters. The generator and Runtime reject other forms so
  /// Package indexes and diagnostics use one portable identity syntax.
  final String id;

  /// SemVer 2.0 contract version displayed in generated route documentation.
  ///
  /// Use this to communicate component-contract compatibility; build metadata
  /// is allowed, while numeric pre-release identifiers cannot contain leading
  /// zeroes.
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
/// then run the CCRouter generator. It emits the Package-private contract and
/// registration bridge as an independent library under
/// `lib/src/ccrouter_generated/`; the page library does not declare a generated
/// `part`. This is the component-internal route form. Use [CCRouteContract] plus
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
    this.popGuards = const [],
    this.description,
  });

  /// Component that owns registration and generated documentation.
  final CCComponentDescriptor component;

  /// Stable route identity shared by tracing, registration and typed Intents.
  ///
  /// IDs start with lowercase and use case-sensitive alphanumeric segments
  /// separated by `.`, `_`, or `-`. They should normally start with the owning
  /// component ID, though the generator does not force that convention.
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
  ///
  /// IDs use the stable segment syntax and cannot repeat because a
  /// duplicate would execute the same policy twice for one request.
  final List<String> interceptors;

  /// Registered route-local Pop guard identities in execution order.
  ///
  /// Use synchronous guards for managed-route exit rules. The generator emits
  /// these IDs into the route definition and Runtime validates component
  /// ownership before navigation starts. IDs use the stable segment
  /// syntax and cannot repeat.
  final List<String> popGuards;

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
    this.popGuards = const [],
    this.description,
  });

  /// Component that owns the contract and its eventual page implementation.
  final CCComponentDescriptor component;

  /// Stable identity retained when an internal route is promoted.
  ///
  /// It uses the same bounded stable segment syntax as [CCRoute.id].
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
  ///
  /// IDs must be unique within this ordered list and use the stable
  /// segment syntax.
  final List<String> interceptors;

  /// Route-local Pop guard identities applied to the managed implementation.
  ///
  /// IDs must be unique within this ordered list and use the stable
  /// segment syntax.
  final List<String> popGuards;

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

/// Marks a constructor parameter as one typed URI Query value.
///
/// Use scalars for ordinary filters and `List<T>` or `Set<T>` when one key may
/// repeat, such as `?tag=a&tag=b`. Generated conversion supports String, int,
/// double, bool, and enum values. Missing optional values use the constructor
/// default or null. Empty collections are rejected because a URI cannot
/// distinguish them from an absent key. Complex shareable values require an
/// explicit [codec]; process-local or secret objects belong in [CCExtraParam].
final class CCQueryParam {
  /// Uses the constructor parameter's name unless [name] supplies a wire name.
  const CCQueryParam({this.name, this.codec});

  /// URI query key, independent of the generated Dart parameter name.
  final String? name;

  /// Optional const-constructible [CCRouteQueryCodec] implementation type.
  ///
  /// Supply this only for a complex value with a stable URI representation,
  /// for example `codec: OrderFilterQueryCodec`. Scalar and collection Query
  /// parameters use generated conversion and must leave this null.
  final Type? codec;
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
