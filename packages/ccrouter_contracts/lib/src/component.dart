/// Stable, typed identity shared by a component and its public contracts.
///
/// Declare the canonical constant in a Pure Dart contracts package once a
/// component exposes cross-package routes or services. Before that promotion,
/// an implementation package may own the constant locally. Generated metadata
/// serializes [value], while source declarations retain this type so an
/// unrelated string cannot accidentally become a component owner.
final class CCComponentId {
  /// Creates a compile-time component identity.
  const CCComponentId(this.value);

  /// Lowercase stable identifier serialized into generated metadata.
  final String value;

  /// Compares component identities by their portable serialized value.
  @override
  bool operator ==(Object other) =>
      other is CCComponentId && other.value == value;

  /// Hashes the portable identity used by generation and Runtime diagnostics.
  @override
  int get hashCode => value.hashCode;

  /// Returns the portable identity without adding implementation details.
  @override
  String toString() => value;
}

/// Build-time definition of one component implementation package.
///
/// An implementation package declares exactly one top-level `const` value of
/// this type. The generator discovers that value without an annotation, assigns
/// package-internal routes, services, and contributions to it, then generates
/// the Runtime Registrar and Manifest. Contracts packages declare only
/// [CCComponentId] values and public contracts, never a [CCComponent].
final class CCComponent {
  /// Creates one immutable component definition.
  const CCComponent({
    required this.id,
    required this.version,
    this.dependencies = const [],
    this.optionalDependencies = const [],
  });

  /// Globally unique component identifier used by generated ownership metadata.
  ///
  /// Use lowercase alphanumeric segments separated by `.`, `_`, or `-`, with
  /// at most 128 characters. Generator and Runtime validation rejects other
  /// forms so Package indexes and diagnostics share one portable syntax.
  final CCComponentId id;

  /// SemVer 2.0 contract version displayed in generated documentation.
  ///
  /// Build metadata is allowed, while numeric pre-release identifiers cannot
  /// contain leading zeroes.
  final String version;

  /// Component IDs that must be installed before this component.
  final List<CCComponentId> dependencies;

  /// Component IDs ordered first only when present in the application.
  final List<CCComponentId> optionalDependencies;
}

/// Marks one package-internal capability registration contribution.
///
/// Use this on a public top-level synchronous function accepting exactly one
/// `CCRegistry` when a component capability has no dedicated declaration, for
/// example Command, Event, Shell, policy, or InitTask registration. The
/// generator assigns the function to the package's sole [CCComponent], orders
/// contributions by [id], and invokes them from the private generated
/// Registrar. A contribution must only register declarations; it must not run
/// I/O, navigate, resolve services, or retain the supplied Registry.
final class CCComponentContribution {
  /// Creates a contribution with one stable component-local [id].
  const CCComponentContribution({required this.id});

  /// Stable identifier used for deterministic ordering and duplicate checks.
  final String id;
}
