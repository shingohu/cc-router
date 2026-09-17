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
/// needs; do not use a longer-lived scope for dependencies with shorter lives.
enum CCServiceScope {
  /// Lives until the owning Runtime shuts down.
  ///
  /// Use for process-wide stateless services or application resources.
  app,

  /// Lives for one authenticated account Session.
  ///
  /// Use for account-specific state that must reset on logout or account switch.
  session,

  /// Lives while its declaring component remains enabled.
  ///
  /// Use for resources shared only by one dynamically managed component.
  component,

  /// Lives for one concrete route entry.
  ///
  /// Use for controllers and resources owned by one page instance.
  route,

  /// Creates a fresh instance for every resolution.
  ///
  /// Use for lightweight, stateful helpers that must never be shared.
  transient,
}
