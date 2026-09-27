import 'component.dart';

/// Stable identity of a service contract across package-boundary promotion.
///
/// Declare a const token in the domain contracts package when a service becomes
/// cross-component. Callers pass it to `CCRouter.service`, while the owning
/// component attaches it to its provider. The string [id], rather than the Dart
/// library identity of [T], remains stable if the interface moves packages.
final class CCServiceToken<T extends Object> {
  /// Creates a typed token with a globally stable, non-empty [id].
  const CCServiceToken(this.id) : assert(id != '');

  /// Globally stable service contract identity used by Runtime registration.
  final String id;

  /// Compares stable identities so diagnostic collections survive type moves.
  @override
  bool operator ==(Object other) =>
      other is CCServiceToken<Object> && other.id == id;

  /// Hashes only the stable identity used by Runtime lookup.
  @override
  int get hashCode => id.hashCode;

  /// Returns a diagnostic representation without exposing an implementation.
  @override
  String toString() => 'CCServiceToken<$T>($id)';
}

/// Declares one stable cross-component Service contract.
///
/// Apply this annotation to a public, abstract, non-generic interface in a
/// Pure Dart contracts Package. The generator emits a typed
/// `CCServiceToken<T>` and metadata owned by [componentId]. Implementations use
/// that generated token from [CCService.contract], while consumers resolve the
/// interface through `CCRouter.service(contract: ...)`.
final class CCServiceContract {
  /// Creates a generated Service contract declaration.
  const CCServiceContract({
    required this.componentId,
    required this.id,
    this.description = '',
  });

  /// Component that owns implementations of this contract.
  final CCComponentId componentId;

  /// Globally stable Service identity used by Runtime and diagnostics.
  final String id;

  /// Human-readable usage scenario exported to generated documentation.
  final String description;
}

/// Declares a simple component-owned Service implementation.
///
/// Apply this annotation to a public, concrete, non-generic class with an
/// unnamed zero-argument generative constructor. The generator creates a lazy
/// [CCServiceProvider] registration and assigns it to the Package's sole
/// `CCComponent`. Use [contract] for a promoted cross-component interface; omit
/// it for an internal Service whose lookup type is the annotated class.
///
/// This annotation deliberately excludes asynchronous initializers, custom
/// factories, and constructor injection. Register those advanced Providers in
/// a `CCComponentContribution` so construction and readiness remain explicit.
final class CCService {
  /// Creates one generated Service Provider declaration.
  const CCService({
    this.id,
    this.contract,
    this.key,
    this.scope = CCServiceScope.app,
    this.creationPolicy = CCServiceCreationPolicy.singleton,
    this.isDefault = false,
  });

  /// Stable identity required for a component-internal Service.
  ///
  /// Omit this when [contract] is supplied because the generated Token is the
  /// single source of identity. Supplying both is a generation error.
  final String? id;

  /// Generated promoted contract Token, or null for type-local lookup.
  final CCServiceToken<Object>? contract;

  /// Optional stable name for one implementation of the lookup type.
  final String? key;

  /// Lifecycle Scope that owns generated instances.
  final CCServiceScope scope;

  /// Whether the owning Scope caches or recreates the implementation.
  final CCServiceCreationPolicy creationPolicy;

  /// Whether this keyed implementation is selected when callers omit a Key.
  final bool isDefault;
}

/// Identifies one named implementation of service contract [T].
///
/// Use a key when multiple implementations of the same service contract are
/// installed and the caller must select one explicitly.
final class CCServiceKey<T> {
  /// Creates a typed service key with the stable [name].
  const CCServiceKey(this.name);

  /// Stable name used in registration and resolution.
  final String name;

  /// Compares both the service type and stable key name.
  @override
  bool operator ==(Object other) =>
      other is CCServiceKey<T> && other.name == name;

  /// Combines the service contract type and key name.
  @override
  int get hashCode => Object.hash(T, name);

  /// Returns a diagnostic representation of this key.
  @override
  String toString() => 'CCServiceKey<$T>($name)';
}

/// Defines the lifetime that owns a service instance.
///
/// Choose the narrowest scope that matches the instance's state and cleanup
/// needs. This enum answers who owns the instance; it does not decide whether
/// the provider caches or recreates the instance. Use [CCServiceCreationPolicy]
/// for that independent choice.
enum CCServiceScope {
  /// Lives until the owning Runtime shuts down.
  ///
  /// Use for process-wide stateless services or application resources.
  app,

  /// Lives for one authenticated account Session.
  ///
  /// Use for account-specific state that must reset on logout or account switch.
  session,

  /// Lives for one concrete route entry.
  ///
  /// Use for controllers and resources owned by one page instance.
  route,
}

/// Defines how a Provider creates instances inside its owning Scope.
///
/// Creation policy is intentionally separate from [CCServiceScope]. A
/// [newInstance] service is recreated on every lookup, but any disposable
/// instance is still owned by the active parent Scope because a synchronous
/// lookup has no safe end-of-use signal. Prefer [newInstance] for stateless or
/// immutable helpers.
enum CCServiceCreationPolicy {
  /// Creates one lazily initialized instance per owning Scope.
  singleton,

  /// Creates a new instance for every resolution in the owning Scope.
  ///
  /// Do not use this for resources that require immediate per-call disposal;
  /// use a Scope-owned singleton or an explicit operation object instead.
  newInstance,
}
