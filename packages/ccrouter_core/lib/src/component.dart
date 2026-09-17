part of 'runtime.dart';

/// Registers one component's capabilities with the Runtime.
///
/// Generated component code implements this interface to register routes,
/// services, and handlers during `CCRouter.initialize`. Registrars must not be
/// invoked directly by business code or retain the supplied Registry.
abstract interface class CCComponentRegistrar {
  /// Adds this component's capabilities to the restricted [registry].
  void register(CCRegistry registry);
}

/// Machine-readable description and capability registrar for one component.
///
/// Application assembly supplies manifests to `CCRouter.initialize` so the
/// Runtime can validate dependencies and install capabilities deterministically.
final class CCComponentManifest {
  /// Creates an immutable component manifest.
  const CCComponentManifest({
    required this.id,
    required this.version,
    required this.registrar,
    this.dependencies = const [],
    this.optionalDependencies = const [],
  });

  /// Globally unique stable component identifier.
  final String id;

  /// Semantic version of the component contract.
  final String version;

  /// Generated or handwritten capability registrar.
  final CCComponentRegistrar registrar;

  /// Component identifiers that must be installed.
  final List<String> dependencies;

  /// Component identifiers ordered first only when present.
  final List<String> optionalDependencies;
}
