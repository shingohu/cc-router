import 'component.dart';

/// Declares a non-generic marker for one statically composed UI capability.
///
/// [P] is an immutable input DTO; [A] is a plain public enum or an immutable
/// output DTO. DTOs are public final Pure Dart classes with const generative
/// constructors and public final stored scalar, plain enum or nested DTO fields.
/// Neither type may contain Flutter objects, functions, collections, streams,
/// asynchronous values or sealed unions. DTO Actions require a Generator that
/// supports UI schema 2; changing an enum to a DTO is a breaking Contract change.
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
  const CCUIFragmentRenderer(this.contract);

  /// Public marker annotated with [CCUIFragmentContract].
  final Type contract;
}
