part of 'route_generator.dart';

/// Emits component identity and dependency metadata for workspace tooling.
final class _ComponentMetadataBuilder implements Builder {
  /// Creates the component metadata builder with package-level output paths.
  _ComponentMetadataBuilder()
    : buildExtensions = const {
        r'^lib/{{}}.dart': [
          'ccrouter_generated/metadata/{{}}.component.json',
          'ccrouter_generated/metadata/{{}}.component.md',
        ],
      };

  /// Matches registrar annotations from the canonical contracts package.
  static const _component = TypeChecker.typeNamedLiterally(
    'CCComponent',
    inPackage: 'ccrouter_contracts',
  );

  /// Writes package-level component metadata while preserving source paths.
  @override
  final Map<String, List<String>> buildExtensions;

  /// Emits no files for libraries without a component registrar annotation.
  @override
  Future<void> build(BuildStep buildStep) async {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return;
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) return;
    final library = LibraryReader(
      await buildStep.resolver.libraryFor(buildStep.inputId),
    );
    final components = <_ComponentModel>[];
    for (final annotated in library.annotatedWith(_component)) {
      final element = annotated.element;
      if (element is! ClassElement ||
          !_ComponentGenerator._implementsComponentRegistrar(element)) {
        _fail(
          'CCComponent must annotate a CCComponentRegistrar implementation.',
          element,
        );
      }
      components.add(
        _ComponentModel.read(annotated.annotation.read('descriptor'), element),
      );
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
    );
    final outputs = buildStep.allowedOutputs.toList();
    final jsonOutput = outputs.singleWhere(
      (output) => output.path.endsWith('.component.json'),
    );
    final markdownOutput = outputs.singleWhere(
      (output) => output.path.endsWith('.component.md'),
    );
    await buildStep.writeAsString(
      jsonOutput,
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
    );
    await buildStep.writeAsString(
      markdownOutput,
      _componentMetadataMarkdown(payload),
    );
  }
}

/// Produces readable documentation for one component metadata document.
String _componentMetadataMarkdown(Map<String, Object?> payload) {
  final out = StringBuffer('# CCRouter Components\n\n');
  out.writeln('Generated from `${payload['source']}`. Do not edit by hand.\n');
  for (final component
      in (payload['components']! as List).cast<Map<String, Object?>>()) {
    out.writeln('## `${component['id']}`\n');
    out.writeln('- Version: `${component['version']}`');
    final dependencies = (component['dependencies']! as List).cast<String>();
    final optional = (component['optionalDependencies']! as List)
        .cast<String>();
    out.writeln(
      '- Dependencies: ${dependencies.isEmpty ? 'none' : dependencies.map((id) => '`$id`').join(', ')}',
    );
    out.writeln(
      '- Optional dependencies: ${optional.isEmpty ? 'none' : optional.map((id) => '`$id`').join(', ')}',
    );
    out.writeln();
  }
  return out.toString();
}
