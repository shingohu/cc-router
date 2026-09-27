part of 'runtime.dart';

/// Registers one component's capabilities with the Runtime.
///
/// Generated component code implements this interface to register routes,
/// services, and handlers during Runtime initialization. Registrars must not be
/// invoked directly by business code or retain the supplied Registry.
abstract interface class CCComponentRegistrar {
  /// Adds this component's capabilities to the restricted [registry].
  void register(CCRegistry registry);
}

/// Machine-readable description and capability registrar for one component.
///
/// Application assembly supplies manifests during Runtime initialization so
/// dependencies can be validated and capabilities installed deterministically.
final class CCComponentManifest {
  /// Creates an immutable component manifest.
  const CCComponentManifest({
    required String id,
    required String version,
    required this.registrar,
    List<String> dependencies = const [],
    List<String> optionalDependencies = const [],
  }) : _component = null,
       _id = id,
       _version = version,
       _dependencies = dependencies,
       _optionalDependencies = optionalDependencies;

  /// Creates Runtime metadata from the build-time component definition.
  ///
  /// Generated-route components use this constructor so ownership and
  /// dependency information has one source while [registrar] remains a
  /// Runtime capability rather than part of the Pure Dart definition.
  const CCComponentManifest.fromComponent({
    required CCComponent component,
    required this.registrar,
  }) : _component = component,
       _id = null,
       _version = null,
       _dependencies = null,
       _optionalDependencies = null;

  /// Build-time definition retained by generated components, when supplied.
  final CCComponent? _component;

  /// Legacy direct ID storage used by handwritten manifests.
  final String? _id;

  /// Legacy direct version storage used by handwritten manifests.
  final String? _version;

  /// Legacy direct dependency storage used by handwritten manifests.
  final List<String>? _dependencies;

  /// Legacy direct optional dependency storage used by handwritten manifests.
  final List<String>? _optionalDependencies;

  /// Globally unique stable component identifier.
  ///
  /// Handwritten manifests follow the generated component's bounded lowercase
  /// segment syntax and are rejected before any Registrar executes otherwise.
  String get id => _component?.id.value ?? _id!;

  /// SemVer 2.0 version of the component contract.
  String get version => _component?.version ?? _version!;

  /// Generated or handwritten capability registrar.
  final CCComponentRegistrar registrar;

  /// Component identifiers that must be installed.
  List<String> get dependencies =>
      _component?.dependencies.map((dependency) => dependency.value).toList() ??
      _dependencies!;

  /// Component identifiers ordered first only when present.
  List<String> get optionalDependencies =>
      _component?.optionalDependencies
          .map((dependency) => dependency.value)
          .toList() ??
      _optionalDependencies!;
}
