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
    required String id,
    required String version,
    required this.registrar,
    List<String> dependencies = const [],
    List<String> optionalDependencies = const [],
  }) : _descriptor = null,
       _id = id,
       _version = version,
       _dependencies = dependencies,
       _optionalDependencies = optionalDependencies;

  /// Creates Runtime metadata from the descriptor used by route tooling.
  ///
  /// Generated-route components use this constructor so ownership and
  /// dependency information has one source while [registrar] remains a
  /// Runtime capability rather than part of the pure-Dart descriptor.
  const CCComponentManifest.fromDescriptor({
    required CCComponentDescriptor descriptor,
    required this.registrar,
  }) : _descriptor = descriptor,
       _id = null,
       _version = null,
       _dependencies = null,
       _optionalDependencies = null;

  /// Descriptor retained by generated-route components, when supplied.
  final CCComponentDescriptor? _descriptor;

  /// Legacy direct ID storage used by handwritten manifests.
  final String? _id;

  /// Legacy direct version storage used by handwritten manifests.
  final String? _version;

  /// Legacy direct dependency storage used by handwritten manifests.
  final List<String>? _dependencies;

  /// Legacy direct optional dependency storage used by handwritten manifests.
  final List<String>? _optionalDependencies;

  /// Globally unique stable component identifier.
  String get id => _descriptor?.id ?? _id!;

  /// Semantic version of the component contract.
  String get version => _descriptor?.version ?? _version!;

  /// Generated or handwritten capability registrar.
  final CCComponentRegistrar registrar;

  /// Component identifiers that must be installed.
  List<String> get dependencies => _descriptor?.dependencies ?? _dependencies!;

  /// Component identifiers ordered first only when present.
  List<String> get optionalDependencies =>
      _descriptor?.optionalDependencies ?? _optionalDependencies!;
}
