part of 'route_generator.dart';

/// Emits component identity and dependency metadata for workspace tooling.
final class _ComponentMetadataBuilder implements Builder {
  /// Creates the component metadata builder with package-level output paths.
  _ComponentMetadataBuilder()
    : buildExtensions = const {
        r'^lib/{{}}.dart': [
          'lib/src/ccrouter_generated/metadata/{{}}.component.json',
        ],
      };

  /// Matches the canonical top-level component definition type.
  static const _component = TypeChecker.typeNamedLiterally(
    'CCComponent',
    inPackage: 'ccrouter_contracts',
  );

  /// Writes package-level component metadata while preserving source paths.
  @override
  final Map<String, List<String>> buildExtensions;

  /// Emits no files for libraries without a top-level component definition.
  @override
  Future<void> build(BuildStep buildStep) async {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return;
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) return;
    final library = LibraryReader(
      await buildStep.resolver.libraryFor(buildStep.inputId),
    );
    final components = <_ComponentModel>[];
    final symbols = <String, String>{};
    for (final element
        in library.allElements.whereType<TopLevelVariableElement>()) {
      if (!_component.isExactlyType(element.type)) continue;
      if (!element.isConst || element.computeConstantValue() == null) {
        _fail(
          'CCComponent declarations must be top-level const values.',
          element,
        );
      }
      if (element.displayName.startsWith('_')) {
        _fail(
          'CCComponent declarations must be public because generated assembly '
          'is emitted in a separate library.',
          element,
        );
      }
      final component = _ComponentModel.read(
        ConstantReader(element.computeConstantValue()),
        element,
      );
      components.add(component);
      symbols[component.id] = element.displayName;
    }
    if (components.isEmpty) return;
    final payload = _metadataPayload(
      package: buildStep.inputId.package,
      source: buildStep.inputId.path,
      components: components,
      routes: const [],
      componentManifests: {
        for (final component in components)
          component.id: _componentManifestName(component.id),
      },
      componentSymbols: symbols,
    );
    final jsonOutput = buildStep.allowedOutputs.singleWhere(
      (output) => output.path.endsWith('.component.json'),
    );
    await buildStep.writeAsString(
      jsonOutput,
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
    );
  }
}
