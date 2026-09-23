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
/// Creation policy is intentionally separate from [CCServiceScope]. A factory
/// service is recreated on every lookup, but any disposable instance is still
/// owned by the active parent Scope because a synchronous lookup has no safe
/// end-of-use signal. Prefer factories for stateless or immutable helpers.
enum CCServiceCreationPolicy {
  /// Creates one lazily initialized instance per owning Scope.
  singleton,

  /// Creates a new instance for every resolution in the owning Scope.
  ///
  /// Do not use this for resources that require immediate per-call disposal;
  /// use a Scope-owned singleton or an explicit operation object instead.
  factory,
}
