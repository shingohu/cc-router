part of 'route_generator.dart';

/// Generates one Runtime Manifest beside an annotated component Registrar.
///
/// The generated Part shares its library with a private Registrar, allowing
/// Host assembly to expose only the immutable Manifest rather than the
/// Registrar implementation itself.
final class _ComponentGenerator extends Generator {
  /// Validates component declarations and emits deterministic Manifest names.
  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return '';
    final outputs = <String>[];
    final componentIds = <String>{};
    final generatedNames = library.allElements
        .map((element) => element.displayName)
        .toSet();
    for (final annotated in library.annotatedWith(
      _ComponentMetadataBuilder._component,
    )) {
      final element = annotated.element;
      if (element is! ClassElement ||
          element.isAbstract ||
          element.typeParameters.isNotEmpty ||
          !_implementsComponentRegistrar(element)) {
        _fail(
          'CCComponent must annotate a concrete, non-generic '
          'CCComponentRegistrar implementation.',
          element,
        );
      }
      final constructor = element.unnamedConstructor;
      if (constructor == null ||
          !constructor.isConst ||
          constructor.isFactory ||
          constructor.formalParameters.any(
            (parameter) => parameter.isRequired,
          )) {
        _fail(
          'A generated component Manifest requires a const unnamed Registrar '
          'constructor without required parameters.',
          element,
        );
      }
      final component = _ComponentModel.read(
        annotated.annotation.read('descriptor'),
        element,
      );
      if (!componentIds.add(component.id)) {
        _fail(
          'Component "${component.id}" is declared more than once in this library.',
          element,
        );
      }
      final manifestName = _componentManifestName(component.id);
      if (!generatedNames.add(manifestName)) {
        _fail(
          'Generated component Manifest "$manifestName" collides with '
          'another declaration.',
          element,
        );
      }
      outputs.add(_emitComponentManifest(element, component, manifestName));
    }
    return outputs.join('\n');
  }

  /// Returns whether [element] implements the canonical Registrar contract.
  static bool _implementsComponentRegistrar(ClassElement element) =>
      element.allSupertypes.any(
        (type) =>
            type.element.displayName == 'CCComponentRegistrar' &&
            type.element.library.uri.toString().startsWith(
              'package:ccrouter_core/',
            ),
      );

  /// Emits one public Manifest while retaining a private Registrar class.
  static String _emitComponentManifest(
    ClassElement registrar,
    _ComponentModel component,
    String manifestName,
  ) =>
      '''
/// Generated Runtime Manifest for component `${component.id}`.
///
/// Application Hosts consume this through the generated package Host library;
/// business code must not invoke the private Registrar directly.
const $manifestName = CCComponentManifest.fromDescriptor(
  descriptor: CCComponentDescriptor(
    id: ${_quote(component.id)},
    version: ${_quote(component.version)},
    dependencies: ${_stringList(component.dependencies)},
    optionalDependencies: ${_stringList(component.optionalDependencies)},
  ),
  registrar: ${registrar.displayName}(),
);
''';

  /// Serializes immutable component dependency IDs as a const list literal.
  static String _stringList(List<String> values) =>
      'const [${values.map(_quote).join(', ')}]';
}
