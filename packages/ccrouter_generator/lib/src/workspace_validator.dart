import 'dart:convert';

/// Maximum supported length of an identifier carried by generated metadata.
const int _workspaceIdentifierLength = 128;

/// Stable identifier syntax rechecked at Package and Host aggregation.
final RegExp _workspaceIdentifierPattern = RegExp(
  r'^[a-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$',
);

/// Lowercase package-style syntax retained for component ownership IDs.
final RegExp _workspaceComponentIdPattern = RegExp(
  r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$',
);

/// Full SemVer 2.0 syntax rechecked for external Package indexes.
final RegExp _workspaceSemanticVersionPattern = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
  r'(?:-(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)'
  r'(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*)?'
  r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
);

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

/// Validates generated component and route metadata across a complete application workspace.
///
/// Use after route generation in CI. Local builders enforce declaration shape;
/// this validator handles relationships that require seeing every component:
/// unique IDs, dependency graphs, declared owners, public-contract
/// implementation ownership, and route pattern conflicts. Cross-Package import
/// access is enforced by public barrels, Pub dependencies, and the Dart
/// analyzer rather than a second allowlist.
abstract final class CCRouteWorkspaceValidator {
  /// Validates decoded `.component.json` and `.route.json` documents and
  /// aggregates route docs.
  static CCRouteWorkspaceValidationResult validate(
    Iterable<Map<String, Object?>> documents,
  ) {
    final errors = <String>[];
    final components = <String, Map<String, Object?>>{};
    final componentDeclarationCounts = <String, int>{};
    final componentDeclarationPackages = <String, String>{};
    final routes = <String, Map<String, Object?>>{};
    final routeImplementations = <String, Map<String, Object?>>{};
    for (final document in documents) {
      if (document['schemaVersion'] != 2 && document['schemaVersion'] != 3) {
        errors.add(
          'Unsupported metadata schema in ${document['source'] ?? 'unknown source'}.',
        );
        continue;
      }
      for (final id in _strings(document['componentDeclarations'])) {
        componentDeclarationCounts[id] =
            (componentDeclarationCounts[id] ?? 0) + 1;
        final package = '${document['package'] ?? ''}';
        if (package.isNotEmpty) componentDeclarationPackages[id] = package;
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
      for (final implementation in _objects(document['routeImplementations'])) {
        final routeId = '${implementation['routeId']}';
        if (routeImplementations.containsKey(routeId)) {
          errors.add('Route "$routeId" has more than one implementation.');
        } else {
          routeImplementations[routeId] = implementation;
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
    _validateMetadataFields(components, routes, errors);
    final componentList = _validateAndOrderComponents(components, errors);
    for (final route in routes.values) {
      final routeId = '${route['id']}';
      final ownerId = '${route['componentId']}';
      if (!components.containsKey(ownerId)) {
        errors.add(
          'Route "$routeId" references unknown owner component "$ownerId".',
        );
      }
      final sourceExposure = '${route['exposure'] ?? ''}';
      if (sourceExposure != 'internal' && sourceExposure != 'public') {
        errors.add(
          'Route "$routeId" has unknown source exposure "$sourceExposure".',
        );
      }
      final implementation = routeImplementations[routeId];
      if (sourceExposure == 'public' && implementation == null) {
        errors.add(
          'Public route contract "$routeId" has no CCRouteImplementation.',
        );
      }
      if (sourceExposure == 'internal' && implementation != null) {
        errors.add(
          'Route "$routeId" cannot combine a page declaration with CCRouteImplementation.',
        );
      }
      if (implementation != null && implementation['componentId'] != ownerId) {
        errors.add(
          'Route implementation "$routeId" belongs to "${implementation['componentId']}" instead of owner "$ownerId".',
        );
      }
      final implementationPackage = '${implementation?['package'] ?? ''}';
      final ownerPackage = componentDeclarationPackages[ownerId];
      if (implementationPackage.isNotEmpty &&
          ownerPackage != null &&
          implementationPackage != ownerPackage) {
        errors.add(
          'Route implementation "$routeId" is in package '
          '"$implementationPackage" instead of owner package "$ownerPackage".',
        );
      }
    }
    for (final implementation in routeImplementations.values) {
      final routeId = '${implementation['routeId']}';
      if (!routes.containsKey(routeId)) {
        errors.add(
          'CCRouteImplementation references unknown route contract "$routeId".',
        );
      }
    }
    _validateParentRelationships(components, routes, errors);
    _validatePatternConflicts(routes.values, errors);
    errors.sort();
    final routeList =
        routes.values.map((route) {
          final implementation = routeImplementations['${route['id']}'];
          return <String, Object?>{
            ...route,
            'exposure': _resolvedExposure(route, componentDeclarationPackages),
            if (implementation != null) 'implementation': implementation,
          };
        }).toList()..sort((left, right) {
          final owner = '${left['componentId']}'.compareTo(
            '${right['componentId']}',
          );
          return owner != 0
              ? owner
              : '${left['id']}'.compareTo('${right['id']}');
        });
    final machineDocument = <String, Object?>{
      'schemaVersion': 2,
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

  /// Rechecks persisted metadata before trusting external Package indexes.
  static void _validateMetadataFields(
    Map<String, Map<String, Object?>> components,
    Map<String, Map<String, Object?>> routes,
    List<String> errors,
  ) {
    for (final component in components.values) {
      final id = '${component['id']}';
      if (!_validComponentId(id)) {
        errors.add('Component ID "$id" is invalid.');
      }
      final version = '${component['version']}';
      if (!_workspaceSemanticVersionPattern.hasMatch(version)) {
        errors.add('Component "$id" must use a SemVer 2.0 version.');
      }
      final dependencies = [
        ..._strings(component['dependencies']),
        ..._strings(component['optionalDependencies']),
      ];
      final seen = <String>{};
      for (final dependency in dependencies) {
        if (!_validIdentifier(dependency) || !seen.add(dependency)) {
          errors.add(
            'Component "$id" has invalid or duplicate dependency '
            '"$dependency".',
          );
        }
      }
    }
    for (final route in routes.values) {
      final routeId = '${route['id']}';
      if (!_validIdentifier(routeId)) {
        errors.add('Route ID "$routeId" is invalid.');
      }
      final placement = route['placement'];
      if (placement is! Map) continue;
      for (final field in ['hostId', 'navigatorOutlet']) {
        final value = '${placement[field] ?? ''}';
        if (!_validIdentifier(value)) {
          errors.add('Route "$routeId" has invalid $field "$value".');
        }
      }
      for (final field in ['parentRouteId', 'shellId']) {
        final value = placement[field];
        if (value != null && !_validIdentifier('$value')) {
          errors.add('Route "$routeId" has invalid $field "$value".');
        }
      }
      for (final field in ['interceptorIds', 'popGuardIds']) {
        final seen = <String>{};
        for (final id in _strings(route[field])) {
          if (!_validIdentifier(id) || !seen.add(id)) {
            errors.add(
              'Route "$routeId" has invalid or duplicate $field entry "$id".',
            );
          }
        }
      }
    }
  }

  /// Validates explicit parent links, visibility, cycles, and stack placement.
  static void _validateParentRelationships(
    Map<String, Map<String, Object?>> components,
    Map<String, Map<String, Object?>> routes,
    List<String> errors,
  ) {
    final parentByRoute = <String, String>{};
    for (final route in routes.values) {
      final routeId = '${route['id']}';
      final placement = route['placement'];
      if (placement is! Map || placement['parentRouteId'] == null) continue;
      final parentId = '${placement['parentRouteId']}';
      parentByRoute[routeId] = parentId;
      if (parentId == routeId) {
        errors.add('Route "$routeId" cannot be its own parent.');
        continue;
      }
      final parent = routes[parentId];
      if (parent == null) {
        errors.add('Route "$routeId" references unknown parent "$parentId".');
        continue;
      }
      final ownerId = '${route['componentId']}';
      final parentOwnerId = '${parent['componentId']}';
      if (ownerId != parentOwnerId) {
        final dependencies = _transitiveDependencies(ownerId, components);
        if (!dependencies.contains(parentOwnerId) ||
            parent['exposure'] != 'public') {
          errors.add(
            'Route "$routeId" cannot reference parent "$parentId" because '
            'component "$parentOwnerId" is not a visible public dependency.',
          );
        }
      }
      final parentPlacement = parent['placement'];
      if (parentPlacement is Map) {
        for (final field in ['hostId', 'shellId', 'navigatorOutlet']) {
          if (placement[field] != parentPlacement[field]) {
            errors.add(
              'Route "$routeId" parent "$parentId" must use the same $field.',
            );
          }
        }
      }
    }

    final completed = <String>{};
    final visiting = <String>[];
    final reported = <String>{};
    void visit(String routeId) {
      if (completed.contains(routeId)) return;
      final cycleIndex = visiting.indexOf(routeId);
      if (cycleIndex >= 0) {
        final cycle = [...visiting.sublist(cycleIndex), routeId].join(' -> ');
        if (reported.add(cycle)) errors.add('Route parent cycle: $cycle.');
        return;
      }
      visiting.add(routeId);
      final parentId = parentByRoute[routeId];
      if (parentId != null && routes.containsKey(parentId)) visit(parentId);
      visiting.removeLast();
      completed.add(routeId);
    }

    final routeIds = parentByRoute.keys.toList()..sort();
    for (final routeId in routeIds) {
      visit(routeId);
    }
  }

  /// Returns component dependencies reachable through present graph edges.
  static Set<String> _transitiveDependencies(
    String componentId,
    Map<String, Map<String, Object?>> components,
  ) {
    final found = <String>{};
    void visit(String id) {
      final component = components[id];
      if (component == null) return;
      for (final dependency in [
        ..._strings(component['dependencies']),
        ..._strings(component['optionalDependencies']),
      ]) {
        if (components.containsKey(dependency) && found.add(dependency)) {
          visit(dependency);
        }
      }
    }

    visit(componentId);
    return found;
  }

  /// Whether [value] satisfies the persisted stable identifier contract.
  static bool _validIdentifier(String value) =>
      value.length <= _workspaceIdentifierLength &&
      _workspaceIdentifierPattern.hasMatch(value);

  /// Whether [value] satisfies the stricter component identifier contract.
  static bool _validComponentId(String value) =>
      value.length <= _workspaceIdentifierLength &&
      _workspaceComponentIdPattern.hasMatch(value);

  /// Validates the complete dependency graph and returns Runtime-aligned order.
  ///
  /// Required dependencies must exist. Optional dependencies are ignored when
  /// absent and become ordinary ordering edges when present. The sorted DFS is
  /// deliberately equivalent to Runtime component assembly: dependencies are
  /// emitted before consumers, while otherwise unrelated IDs remain stable.
  static List<Map<String, Object?>> _validateAndOrderComponents(
    Map<String, Map<String, Object?>> components,
    List<String> errors,
  ) {
    final dependenciesById = <String, List<String>>{};
    final ids = components.keys.toList()..sort();
    for (final id in ids) {
      final component = components[id]!;
      final required = _strings(component['dependencies']);
      final optional = _strings(component['optionalDependencies']);
      final all = <String>{...required, ...optional};
      if (all.remove(id)) {
        errors.add('Component "$id" cannot depend on itself.');
      }
      for (final dependency in required.toSet().toList()..sort()) {
        if (!components.containsKey(dependency)) {
          errors.add('Component "$id" requires missing "$dependency".');
        }
      }
      dependenciesById[id] = all.where(components.containsKey).toList()..sort();
    }

    final visiting = <String>{};
    final visited = <String>{};
    final path = <String>[];
    final reportedCycles = <String>{};
    final orderedIds = <String>[];

    void visit(String id) {
      if (visited.contains(id)) return;
      if (!visiting.add(id)) {
        final cycleStart = path.indexOf(id);
        final cycle = <String>[
          ...path.sublist(cycleStart < 0 ? 0 : cycleStart),
          id,
        ];
        final message = cycle.join(' -> ');
        if (reportedCycles.add(message)) {
          errors.add('Component dependency cycle: $message.');
        }
        return;
      }
      path.add(id);
      for (final dependency in dependenciesById[id]!) {
        visit(dependency);
      }
      path.removeLast();
      visiting.remove(id);
      if (visited.add(id)) orderedIds.add(id);
    }

    for (final id in ids) {
      visit(id);
    }
    return orderedIds.map((id) => components[id]!).toList(growable: false);
  }

  /// Resolves a public contract to a same-Package or cross-Package boundary.
  ///
  /// Source builders can only distinguish private page contracts from public
  /// schema contracts. Workspace aggregation can additionally compare the
  /// contract Package with the component owner's implementation Package.
  static String _resolvedExposure(
    Map<String, Object?> route,
    Map<String, String> componentDeclarationPackages,
  ) {
    if (route['exposure'] == 'internal') return 'internal';
    final contracts = route['contracts'];
    final contractPackage = contracts is Map
        ? '${contracts['package'] ?? ''}'
        : '';
    final ownerPackage =
        componentDeclarationPackages['${route['componentId']}'];
    if (contractPackage.isNotEmpty && contractPackage == ownerPackage) {
      return 'package';
    }
    return 'external';
  }

  /// Reports only cross-route pattern overlaps that are statically provable.
  ///
  /// Runtime registration remains authoritative for expressions whose language
  /// cannot be compared safely during generation.
  static void _validatePatternConflicts(
    Iterable<Map<String, Object?>> routes,
    List<String> errors,
  ) {
    final ordered = routes.toList()
      ..sort((first, second) => '${first['id']}'.compareTo('${second['id']}'));
    for (var firstIndex = 0; firstIndex < ordered.length; firstIndex++) {
      final firstRoute = ordered[firstIndex];
      for (
        var secondIndex = firstIndex + 1;
        secondIndex < ordered.length;
        secondIndex++
      ) {
        final secondRoute = ordered[secondIndex];
        for (final firstPattern in _objects(firstRoute['patterns'])) {
          for (final secondPattern in _objects(secondRoute['patterns'])) {
            if (!_patternsConflict(firstPattern, secondPattern)) continue;
            errors.add(
              'Routes "${firstRoute['id']}" and "${secondRoute['id']}" '
              'have ambiguous patterns "${_patternLabel(firstPattern)}" '
              'and "${_patternLabel(secondPattern)}" with equal specificity.',
            );
          }
        }
      }
    }
  }

  /// Compares two metadata patterns using the runtime's same-tier rules.
  static bool _patternsConflict(
    Map<String, Object?> first,
    Map<String, Object?> second,
  ) {
    final firstType = '${first['type']}';
    if (firstType != second['type']) return false;
    if (firstType == 'CCRegexPattern') {
      return first['value'] == second['value'];
    }
    final firstTemplate = '${first['value']}';
    final secondTemplate = '${second['value']}';
    if (firstType == 'CCUriPattern') {
      final firstUri = Uri.tryParse(firstTemplate);
      final secondUri = Uri.tryParse(secondTemplate);
      if (firstUri == null || secondUri == null) return false;
      if (firstUri.scheme.toLowerCase() != secondUri.scheme.toLowerCase() ||
          firstUri.host.toLowerCase() != secondUri.host.toLowerCase() ||
          firstUri.port != secondUri.port) {
        return false;
      }
      return _templatesConflict(
        firstUri.path.isEmpty ? '/' : firstUri.path,
        _constraints(first),
        secondUri.path.isEmpty ? '/' : secondUri.path,
        _constraints(second),
      );
    }
    if (firstType == 'CCPathPattern') {
      return _templatesConflict(
        firstTemplate,
        _constraints(first),
        secondTemplate,
        _constraints(second),
      );
    }
    return false;
  }

  /// Whether two same-tier templates can match one location equally.
  static bool _templatesConflict(
    String firstTemplate,
    Map<String, String> firstConstraints,
    String secondTemplate,
    Map<String, String> secondConstraints,
  ) {
    final first = Uri.parse(firstTemplate).pathSegments;
    final second = Uri.parse(secondTemplate).pathSegments;
    final firstHasWildcard = first.isNotEmpty && first.last.startsWith('*');
    final secondHasWildcard = second.isNotEmpty && second.last.startsWith('*');
    if (!firstHasWildcard &&
        !secondHasWildcard &&
        first.length != second.length) {
      return false;
    }
    final comparedLength = first.length < second.length
        ? first.length
        : second.length;
    for (var index = 0; index < comparedLength; index++) {
      final firstSegment = first[index];
      final secondSegment = second[index];
      if (firstSegment.startsWith('*') || secondSegment.startsWith('*')) break;
      final firstExpression = _segmentExpression(
        firstSegment,
        firstConstraints,
      );
      final secondExpression = _segmentExpression(
        secondSegment,
        secondConstraints,
      );
      if (firstExpression == null && secondExpression == null) {
        if (firstSegment != secondSegment) return false;
      } else if (firstExpression == null) {
        if (!_matchesConstraint(secondExpression!, firstSegment)) return false;
      } else if (secondExpression == null) {
        if (!_matchesConstraint(firstExpression, secondSegment)) return false;
      } else if (!_constraintsMayOverlap(firstExpression, secondExpression)) {
        return false;
      }
    }
    return _templateSpecificity(first, firstConstraints) ==
        _templateSpecificity(second, secondConstraints);
  }

  /// Returns a dynamic segment constraint, or null for a fixed segment.
  static String? _segmentExpression(
    String segment,
    Map<String, String> constraints,
  ) {
    if (segment.startsWith('*')) {
      return constraints[segment.substring(1)] ?? r'.*';
    }
    if (!segment.startsWith(':')) return null;
    return constraints[segment.substring(1)] ?? r'[^/]+';
  }

  /// Conservatively proves whether two segment languages may intersect.
  static bool _constraintsMayOverlap(String first, String second) {
    if (first == second) return true;
    final firstLiteral = _literalExpression(first);
    final secondLiteral = _literalExpression(second);
    if (firstLiteral != null && secondLiteral != null) {
      return firstLiteral == secondLiteral;
    }
    if (_isDigits(first) && _isLetters(second) ||
        _isLetters(first) && _isDigits(second)) {
      return false;
    }
    return true;
  }

  /// Returns an exact literal represented by a simple expression.
  static String? _literalExpression(String expression) =>
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(expression) ? expression : null;

  /// Recognizes common digit-only constraints without guessing complex regexes.
  static bool _isDigits(String expression) => RegExp(
    r'^(?:\\d|\[0-9\])(?:\+|\*|\{\d+(?:,\d*)?\})$',
  ).hasMatch(expression);

  /// Recognizes common ASCII-letter-only constraints without guessing regexes.
  static bool _isLetters(String expression) => RegExp(
    r'^(?:\[a-z\]|\[A-Za-z\]|\[A-Z\])(?:\+|\*|\{\d+(?:,\d*)?\})$',
  ).hasMatch(expression);

  /// Matches a fixed segment against a full constraint expression.
  static bool _matchesConstraint(String expression, String value) {
    try {
      return RegExp('^(?:$expression)\$').hasMatch(value);
    } on FormatException {
      return true;
    }
  }

  /// Calculates the same specificity score used by runtime template matching.
  static int _templateSpecificity(
    List<String> segments,
    Map<String, String> constraints,
  ) {
    var score = 0;
    for (final segment in segments) {
      if (segment.startsWith('*')) {
        score -= 10;
      } else if (segment.startsWith(':')) {
        score += constraints.containsKey(segment.substring(1)) ? 20 : 10;
      } else {
        score += 100;
      }
    }
    return score;
  }

  /// Reads validated string constraints from one metadata pattern.
  static Map<String, String> _constraints(Map<String, Object?> pattern) {
    final value = pattern['constraints'];
    if (value is! Map) return const {};
    return value.map((key, value) => MapEntry('$key', '$value'));
  }

  /// Returns a stable human-readable pattern value for diagnostics.
  static String _patternLabel(Map<String, Object?> pattern) =>
      '${pattern['value']}';

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
          '- Exposure: `${route['exposure']}`; deep link: `${route['deepLink']}`; result: `${route['resultType']}`',
        );
        if (route['contracts'] case final Map contracts) {
          out.writeln(
            '- Contract library: `${contracts['package'] ?? 'unknown'}:${contracts['library']}`',
          );
        }
        if (route['implementation'] case final Map implementation) {
          out.writeln(
            '- Implementation: `${implementation['package'] ?? 'unknown'}:${implementation['source'] ?? 'unknown'}`',
          );
        }
        if (route['declaration'] case final Map declaration) {
          out.writeln(
            '- Declaration: `${declaration['package'] ?? 'unknown'}:${declaration['library'] ?? 'unknown'}` (${declaration['kind'] ?? 'unknown'})',
          );
        }
        if (route['placement'] case final Map placement) {
          out.writeln(
            '- Placement: host `${placement['hostId'] ?? 'default'}`, outlet `${placement['navigatorOutlet'] ?? 'root'}`, shell `${placement['shellId'] ?? 'none'}`, parent `${placement['parentRouteId'] ?? 'none'}`',
          );
        }
        if (route['presentation'] case final Map presentation) {
          out.writeln('- Presentation: `${presentation['type'] ?? 'unknown'}`');
        }
        final navigationSources = _strings(route['navigationSources']);
        if (navigationSources.isNotEmpty) {
          out.writeln(
            '- Navigation sources: `${navigationSources.join(', ')}`',
          );
        }
        if (route['restoration'] case final Map restoration) {
          out.writeln(
            '- Restoration: `${restoration['status'] ?? 'unsupported'}`',
          );
        }
        out.writeln('- Patterns:');
        for (final pattern in _objects(route['patterns'])) {
          out.writeln(
            '  - `${pattern['value']}` (${pattern['type']}${pattern['primary'] == true ? ', primary' : ''})',
          );
          final constraints = pattern['constraints'];
          if (constraints is Map && constraints.isNotEmpty) {
            out.writeln('    - Constraints: `${jsonEncode(constraints)}`');
          }
        }
        final parameters = _objects(route['parameters']).toList();
        if (parameters.isNotEmpty) {
          out.writeln('- Parameters:\n');
          out.writeln(
            '| Name | Wire | Source | Type | Cardinality | Codec | Required | Description |',
          );
          out.writeln('| --- | --- | --- | --- | --- | --- | --- | --- |');
          for (final parameter in parameters) {
            final description = '${parameter['description'] ?? ''}'
                .replaceAll('|', r'\|')
                .replaceAll('\n', '<br>');
            out.writeln(
              '| `${parameter['name']}` | `${parameter['wireName']}` | `${parameter['source']}` | `${parameter['type']}` | `${parameter['cardinality'] ?? '-'}` | `${parameter['codec'] ?? '-'}` | ${parameter['required']} | $description |',
            );
          }
        }
        out.writeln();
      }
    }
    return '${out.toString().trimRight()}\n';
  }
}
