part of 'runtime.dart';

/// Registers one component's capabilities with the Runtime.
abstract interface class CCComponentRegistrar {
  /// Adds this component's capabilities to the restricted [registry].
  void register(CCRegistry registry);
}

/// Machine-readable description and capability registrar for one component.
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
