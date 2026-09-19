import 'dart:convert';

/// Result of validating every generated component and route metadata document.
final class CCRouteWorkspaceValidationResult {
  /// Creates an immutable validation result and aggregate documentation.
  CCRouteWorkspaceValidationResult({
    required List<String> errors,
    required this.machineDocument,
    required this.markdownDocument,
  }) : errors = List.unmodifiable(errors);

  /// Stable diagnostic messages; an empty list means validation succeeded.
  final List<String> errors;

  /// Aggregate machine-readable document suitable for CI diffing and tooling.
  final Map<String, Object?> machineDocument;

  /// Aggregate Markdown document grouped by owning component.
  final String markdownDocument;

  /// Whether ownership, identities, allowlists and dependency edges are valid.
  bool get isValid => errors.isEmpty;

  /// Pretty-printed deterministic JSON followed by one newline.
  String get machineDocumentJson =>
      '${const JsonEncoder.withIndent('  ').convert(machineDocument)}\n';
}

/// Validates generated route metadata across a complete application workspace.
///
/// Use after route generation in CI. Local builders enforce declaration shape;
/// this validator handles relationships that require seeing every component:
/// unique IDs, declared owners, `visibleTo` targets, and consumer dependencies.
abstract final class CCRouteWorkspaceValidator {
  /// Validates decoded `.ccroute.json` documents and aggregates route docs.
  static CCRouteWorkspaceValidationResult validate(
    Iterable<Map<String, Object?>> documents,
  ) {
    final errors = <String>[];
    final components = <String, Map<String, Object?>>{};
    final componentDeclarationCounts = <String, int>{};
    final routes = <String, Map<String, Object?>>{};
    for (final document in documents) {
      if (document['schemaVersion'] != 1) {
        errors.add(
          'Unsupported route metadata schema in ${document['source'] ?? 'unknown source'}.',
        );
        continue;
      }
      for (final id in _strings(document['componentDeclarations'])) {
        componentDeclarationCounts[id] =
            (componentDeclarationCounts[id] ?? 0) + 1;
      }
      for (final component in _objects(document['components'])) {
        final id = '${component['id']}';
        final existing = components[id];
        if (existing != null && jsonEncode(existing) != jsonEncode(component)) {
          errors.add('Component "$id" has conflicting descriptors.');
        } else {
          components[id] = component;
        }
      }
      for (final route in _objects(document['routes'])) {
        final id = '${route['id']}';
        if (routes.containsKey(id)) {
          errors.add('Route ID "$id" is declared more than once.');
        } else {
          routes[id] = route;
        }
      }
    }
    for (final id in components.keys) {
      final count = componentDeclarationCounts[id] ?? 0;
      if (count != 1) {
        errors.add(
          count == 0
              ? 'Component "$id" has no CCComponent declaration.'
              : 'Component "$id" has more than one CCComponent declaration.',
        );
      }
    }
    for (final route in routes.values) {
      final routeId = '${route['id']}';
      final ownerId = '${route['componentId']}';
      if (!components.containsKey(ownerId)) {
        errors.add(
          'Route "$routeId" references unknown owner component "$ownerId".',
        );
      }
      final visibleTo = _strings(route['visibleTo']);
      if (route['visibility'] == 'component' && visibleTo.isNotEmpty) {
        errors.add('Component route "$routeId" cannot declare visibleTo.');
      }
      for (final consumerId in visibleTo) {
        final consumer = components[consumerId];
        if (consumer == null) {
          errors.add(
            'Route "$routeId" references unknown consumer "$consumerId".',
          );
          continue;
        }
        final dependencies = {
          ..._strings(consumer['dependencies']),
          ..._strings(consumer['optionalDependencies']),
        };
        if (!dependencies.contains(ownerId)) {
          errors.add(
            'Consumer "$consumerId" must depend on "$ownerId" to access route "$routeId".',
          );
        }
      }
    }
    errors.sort();
    final componentList = components.values.toList()
      ..sort((left, right) => '${left['id']}'.compareTo('${right['id']}'));
    final routeList = routes.values.toList()
      ..sort((left, right) {
        final owner = '${left['componentId']}'.compareTo(
          '${right['componentId']}',
        );
        return owner != 0 ? owner : '${left['id']}'.compareTo('${right['id']}');
      });
    final machineDocument = <String, Object?>{
      'schemaVersion': 1,
      'components': componentList,
      'routes': routeList,
    };
    return CCRouteWorkspaceValidationResult(
      errors: errors,
      machineDocument: machineDocument,
      markdownDocument: _markdown(componentList, routeList),
    );
  }

  /// Converts loosely decoded JSON arrays into checked object maps.
  static Iterable<Map<String, Object?>> _objects(Object? value) sync* {
    if (value is! List) return;
    for (final item in value) {
      if (item is Map) yield item.cast<String, Object?>();
    }
  }

  /// Converts loosely decoded JSON values into stable string lists.
  static List<String> _strings(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];

  /// Builds a concise aggregate document without embedding runtime objects.
  static String _markdown(
    List<Map<String, Object?>> components,
    List<Map<String, Object?>> routes,
  ) {
    final out = StringBuffer(
      '# CCRouter Route Catalog\n\nGenerated by `ccrouter_generator`. Do not edit by hand.\n\n',
    );
    for (final component in components) {
      final id = '${component['id']}';
      out.writeln('## `$id`\n');
      out.writeln('- Version: `${component['version']}`');
      final dependencies = _strings(component['dependencies']);
      out.writeln(
        '- Dependencies: ${dependencies.isEmpty ? 'none' : dependencies.map((value) => '`$value`').join(', ')}\n',
      );
      for (final route in routes.where((route) => route['componentId'] == id)) {
        out.writeln('### `${route['id']}`\n');
        if (route['description'] case final String description) {
          out.writeln('$description\n');
        }
        out.writeln(
          '- Visibility: `${route['visibility']}`; deep link: `${route['deepLink']}`; result: `${route['resultType']}`',
        );
        final visibleTo = _strings(route['visibleTo']);
        if (visibleTo.isNotEmpty) {
          out.writeln(
            '- Visible to: ${visibleTo.map((value) => '`$value`').join(', ')}',
          );
        }
        out.writeln('- Patterns:');
        for (final pattern in _objects(route['patterns'])) {
          out.writeln(
            '  - `${pattern['value']}` (${pattern['type']}${pattern['primary'] == true ? ', primary' : ''})',
          );
        }
        final parameters = _objects(route['parameters']).toList();
        if (parameters.isNotEmpty) {
          out.writeln('- Parameters:\n');
          out.writeln(
            '| Name | Wire | Source | Type | Required | Description |',
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
    }
    return out.toString();
  }
}
