import 'component.dart';

/// Declares a non-generic marker for one statically composed UI capability.
///
/// [P] is an immutable input DTO; [A] is a plain public enum, an immutable
/// output DTO or a restricted sealed union. DTOs are public final Pure Dart
/// classes with const generative constructors and public final stored data.
/// DTOs are terminal even in their defining library/parts: subclasses and
/// implementations could add unmodeled state or override stored-data getters.
/// Action fields can nest sealed unions: each root directly extends Object,
/// with public final direct leaves in the same library (including parts).
/// Base final fields and const `super.field` forwarding are supported; leaves
/// cannot have further subtypes. Props retain the DTO-only boundary.
/// Neither type may contain Flutter objects, functions, collections, streams
/// or asynchronous values. DTO Actions require UI schema 2; union Actions
/// require UI schema 3 / Package Index 5 with compatible tooling. Changing the
/// Action representation or adding/removing variants is a breaking Contract
/// change. Constructors with explicit initializers, redirects or factories
/// are unsupported for union data. Expanded legacy DTO/constant work is bounded
/// at 16,384 visits and 256 levels; union type graphs retain 512 nodes/32 levels.
/// Full validation belongs to the Generator.
/// Output belongs to the mounted consumer callback, without serialization or
/// payload retention in diagnostics. This annotation creates no Route or Scope.
final class CCUIFragmentContract<P extends Object, A extends Object> {
  /// Defines the public identity and semantic version of a Fragment.
  const CCUIFragmentContract({
    required this.componentId,
    required this.id,
    this.alias,
    this.version = '0.1.0',
    this.description = '',
  });

  /// Canonical owner declared by the public contracts Package.
  final CCComponentId componentId;

  /// Stable capability identifier within the owner.
  final String id;

  /// Default generated Client method shared by consuming components.
  ///
  /// A Dependency alias overrides this name for one consumer. When absent,
  /// generation removes a trailing `FragmentContract` from the marker name
  /// and lowercases its first character, without acronym heuristics.
  /// The alias must be a public lower-camel identifier outside Object members.
  final String? alias;

  /// SemVer maintained by the owner when public shape or behavior changes.
  /// Leading or trailing whitespace is rejected, as with other Contracts.
  final String version;

  /// Human-readable usage scenario exported to generated metadata.
  final String description;
}

/// Required cross-component UI consumption recorded on a [CCComponent].
final class CCUIFragmentDependency<T extends Object> {
  /// Requires one implementation of [T] in the Host's static assembly.
  /// Generation records the current Contract's exact version and fingerprint,
  /// matching Service and Command consumer compatibility checks.
  const CCUIFragmentDependency({this.alias});

  /// Overrides the Contract default method for this consuming component.
  ///
  /// When absent, generation uses the Contract alias and then the marker name.
  /// The effective name must be a unique public lower-camel Dart identifier
  /// that is not reserved by Object. It does not identify Widget instances.
  final String? alias;
}

/// Binds a public synchronous top-level Renderer function to a marker type.
final class CCUIFragmentRenderer {
  /// Marks a function whose typed render input matches [contract].
  /// Declare one Renderer annotation per function; duplicate bindings are rejected.
  const CCUIFragmentRenderer(this.contract);

  /// Public marker annotated with [CCUIFragmentContract].
  final Type contract;
}
