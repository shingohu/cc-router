import 'component.dart';

/// Declares a non-generic marker for one statically composed UI capability.
///
/// [P] is an immutable input DTO; [A] is a public enum. Neither may contain
/// Flutter objects, functions, streams, or asynchronous values. This annotation
/// does not create a Route or extend the Service type system.
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
