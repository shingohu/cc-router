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
    required this.version,
  });

  /// Canonical owner declared by the public contracts Package.
  final CCComponentId componentId;

  /// Stable capability identifier within the owner.
  final String id;

  /// SemVer maintained by the owner when public shape or behavior changes.
  final String version;
}

/// Required cross-component UI consumption recorded on a [CCComponent].
final class CCUIFragmentDependency<T extends Object> {
  /// Requires one implementation of [T] in the Host's static assembly.
  const CCUIFragmentDependency({
    required this.versionRange,
    required this.alias,
  });

  /// Accepted owner contract SemVer range.
  final String versionRange;

  /// Explicit Dart method name on the consumer's generated Fragments Client.
  final String alias;
}

/// Binds a public synchronous top-level Renderer function to a marker type.
final class CCUIFragmentRenderer {
  /// Marks a function whose typed render input matches [contract].
  /// Declare one Renderer annotation per function; duplicate bindings are rejected.
  const CCUIFragmentRenderer(this.contract);

  /// Public marker annotated with [CCUIFragmentContract].
  final Type contract;
}
