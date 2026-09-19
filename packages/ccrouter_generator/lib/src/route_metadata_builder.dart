part of 'route_generator.dart';

/// Emits structured route metadata for documentation and CI.
final class _RouteMetadataBuilder implements Builder {
  /// Creates the route metadata builder with package-level output paths.
  _RouteMetadataBuilder()
    : buildExtensions = const {
        r'^lib/{{}}.dart': [
          'ccrouter_generated/metadata/{{}}.route.json',
          'ccrouter_generated/metadata/{{}}.route.md',
        ],
      };

  /// Writes route metadata while preserving the source-relative path.
  @override
  final Map<String, List<String>> buildExtensions;

  /// Emits no files for libraries without route declarations.
  @override
  Future<void> build(BuildStep buildStep) async {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return;
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) return;
    final library = LibraryReader(
      await buildStep.resolver.libraryFor(buildStep.inputId),
    );
    final routes = <_RouteModel>[];
    for (final annotated in library.annotatedWith(_RouteGenerator._route)) {
      routes.add(_RouteModel.read(annotated.element, annotated.annotation));
    }
    if (routes.isEmpty) return;
    final payload = _metadataPayload(
      package: buildStep.inputId.package,
      source: buildStep.inputId.path,
      components: routes.map((route) => route.component).toList(),
      routes: routes,
      componentDeclarations: const [],
    );
    final outputs = buildStep.allowedOutputs.toList();
    final jsonOutput = outputs.singleWhere(
      (output) => output.path.endsWith('.route.json'),
    );
    final markdownOutput = outputs.singleWhere(
      (output) => output.path.endsWith('.route.md'),
    );
    await buildStep.writeAsString(
      jsonOutput,
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
    );
    await buildStep.writeAsString(markdownOutput, _metadataMarkdown(payload));
  }
}

/// Creates a stable metadata schema without exposing analyzer objects.
Map<String, Object?> _metadataPayload({
  required String package,
  required String source,
  required List<_ComponentModel> components,
  required List<_RouteModel> routes,
  List<String>? componentDeclarations,
}) => {
  'schemaVersion': 1,
  'package': package,
  'source': source,
  'componentDeclarations':
      componentDeclarations ??
      components.map((component) => component.id).toList(),
  'components': {
    for (final component in [
      ...components,
      ...routes.map((route) => route.component),
    ])
      component.id: _componentJson(component),
  }.values.toList(),
  'routes': routes.map(_routeJson).toList(),
};

/// Serializes one component descriptor deterministically.
Map<String, Object?> _componentJson(_ComponentModel component) => {
  'id': component.id,
  'version': component.version,
  'dependencies': component.dependencies,
  'optionalDependencies': component.optionalDependencies,
};

/// Serializes ownership, visibility, addresses and documented parameters.
Map<String, Object?> _routeJson(_RouteModel route) => {
  'id': route.id,
  'componentId': route.component.id,
  'visibility': route.exported ? 'exported' : 'component',
  'visibleTo':
      route.annotation
          .read('visibleTo')
          .setValue
          .map((value) => value.toStringValue()!)
          .toList()
        ..sort(),
  'deepLink': _enumValue(
    route.annotation.read('deepLink').objectValue,
  ).split('.').last,
  'description': route.annotation.read('description').isNull
      ? null
      : route.annotation.read('description').stringValue,
  'contracts': {'route': route.api, 'arguments': route.arguments},
  'patterns': route.patterns.indexed.map((entry) {
    final index = entry.$1;
    final pattern = entry.$2;
    final type = (pattern.type as InterfaceType).element.displayName;
    return <String, Object?>{
      'type': type,
      'value': _field(
        pattern,
        type == 'CCRegexPattern' ? 'expression' : 'template',
      ).toStringValue(),
      'primary': index == route.primaryPatternIndex,
      if (type != 'CCRegexPattern')
        'constraints': _field(pattern, 'constraints').toMapValue()!.map(
          (key, value) =>
              MapEntry(key!.toStringValue()!, value!.toStringValue()!),
        ),
    };
  }).toList(),
  'parameters': route.parameters
      .map(
        (parameter) => <String, Object?>{
          'name': parameter.name,
          'wireName': parameter.wireName,
          'source': parameter.source,
          'type': parameter.type,
          'required': parameter.required,
          'default': parameter.defaultCode,
          'description': _documentation(
            parameter.element.documentationComment ??
                route.page.getField(parameter.name)?.documentationComment,
          ),
        },
      )
      .toList(),
  'resultType': route.result,
};

/// Removes source comment markers while retaining authored explanations.
String? _documentation(String? comment) {
  if (comment == null) return null;
  return comment
      .split('\n')
      .map((line) => line.replaceFirst(RegExp(r'^\s*/// ?'), ''))
      .join('\n')
      .trim();
}

/// Produces readable documentation for one annotated source library.
String _metadataMarkdown(Map<String, Object?> payload) {
  final out = StringBuffer('# CCRouter Routes\n\n');
  out.writeln('Generated from `${payload['source']}`. Do not edit by hand.\n');
  for (final route
      in (payload['routes']! as List).cast<Map<String, Object?>>()) {
    out.writeln('## `${route['id']}`\n');
    if (route['description'] case final String description) {
      out.writeln('$description\n');
    }
    out.writeln('- Owner: `${route['componentId']}`');
    out.writeln('- Visibility: `${route['visibility']}`');
    out.writeln('- Deep link: `${route['deepLink']}`');
    out.writeln('- Result: `${route['resultType']}`');
    out.writeln('- Patterns:');
    for (final pattern in (route['patterns']! as List).cast<Map>()) {
      out.writeln(
        '  - `${pattern['value']}` (${pattern['type']}${pattern['primary'] == true ? ', primary' : ''})',
      );
      final constraints = pattern['constraints'];
      if (constraints is Map && constraints.isNotEmpty) {
        out.writeln('    - Constraints: `${jsonEncode(constraints)}`');
      }
    }
    final parameters = (route['parameters']! as List).cast<Map>();
    if (parameters.isNotEmpty) {
      out.writeln('- Parameters:\n');
      out.writeln(
        '| Name | Wire name | Source | Type | Required | Description |',
      );
      out.writeln('| --- | --- | --- | --- | --- | --- |');
      for (final parameter in parameters) {
        final description = '${parameter['description'] ?? ''}'
            .replaceAll('|', r'\|')
            .replaceAll('\n', '<br>');
        out.writeln(
          '| `${parameter['name']}` | `${parameter['wireName']}` | `${parameter['source']}` | `${parameter['type']}` | ${parameter['required']} | $description |',
        );
      }
    }
    out.writeln();
  }
  return out.toString();
}
