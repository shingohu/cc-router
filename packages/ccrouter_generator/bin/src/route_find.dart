import 'dart:io';

import 'package:ccrouter_generator/src/package_workspace.dart';

/// Prints routes matching an exact ID or declared Pattern in one Host closure.
///
/// This lookup consumes validated published Package indexes without running
/// builders or scanning source files. It does not resolve a concrete URL with
/// dynamic Path parameters; that remains a Runtime navigation operation.
Future<bool> findRoute({
  required Directory buildRoot,
  required Directory hostRoot,
  required bool workspace,
  required String query,
}) async {
  final resolved = await CCPackageWorkspace.load(
    buildRoot: buildRoot,
    hostRoot: hostRoot,
    workspace: workspace,
  );
  final indexes = <String, CCPackageIndex>{};
  final records = <CCCapabilitySourceRecord>[];
  final patterns = <String, Set<_DeclaredPattern>>{};
  final matchingIds = <String>{};
  for (final package in resolved.packages.values) {
    if (!package.indexFile.existsSync()) {
      if (package == resolved.host || package.requiresPackageIndex) {
        throw CCPackageWorkspaceException(
          'CCRouter Package index is missing for "${package.name}". '
          'Run `ccrouter generate ${hostRoot.path}` before searching.',
        );
      }
      continue;
    }
    final index = await CCPackageIndex.read(package, verifyBundle: false);
    indexes[package.name] = index;
    records.addAll(index.capabilityCatalog.records);
    for (final document in index.metadata) {
      final routes = document['routes'];
      if (routes is! List) continue;
      for (final rawRoute in routes.whereType<Map>()) {
        final route = rawRoute.cast<String, Object?>();
        final id = route['id'];
        if (id is! String || id.isEmpty) continue;
        if (id == query) matchingIds.add(id);
        final rawPatterns = route['patterns'];
        if (rawPatterns is! List) continue;
        for (final rawPattern in rawPatterns.whereType<Map>()) {
          final pattern = rawPattern.cast<String, Object?>();
          final value = pattern['value'];
          if (value is! String || value.isEmpty) continue;
          patterns
              .putIfAbsent(id, () => <_DeclaredPattern>{})
              .add(_DeclaredPattern(value, pattern['primary'] == true));
          if (value == query) matchingIds.add(id);
        }
      }
    }
  }

  for (final entry in indexes.entries) {
    final package = resolved.packages[entry.key]!;
    final expectedNames = package.dependencies
        .where(indexes.containsKey)
        .toSet();
    final recorded = {
      for (final dependency in entry.value.dependencies)
        dependency.name: dependency,
    };
    if (recorded.length != entry.value.dependencies.length ||
        !recorded.keys.toSet().containsAll(expectedNames) ||
        !expectedNames.containsAll(recorded.keys)) {
      throw CCPackageWorkspaceException(
        'Package index for "${package.name}" has stale direct generated '
        'dependencies. Run `ccrouter generate ${hostRoot.path}` and retry.',
      );
    }
    for (final name in expectedNames) {
      final expected = indexes[name]!;
      final dependency = recorded[name]!;
      if (dependency.version != expected.packageVersion ||
          dependency.contentFingerprint != expected.contentFingerprint) {
        throw CCPackageWorkspaceException(
          'Package index for "${package.name}" references a different '
          '"$name" identity. Generation may be in progress or the indexes '
          'are stale; retry after `ccrouter generate ${hostRoot.path}`.',
        );
      }
    }
  }

  final catalog = CCCapabilitySourceCatalog(records);
  final matches = catalog.records
      .where(
        (record) => record.kind == 'route' && matchingIds.contains(record.id),
      )
      .toList(growable: false);
  if (matches.isEmpty) {
    stderr.writeln('No route matched the exact ID or declared Pattern.');
    return false;
  }
  for (final record in matches) {
    stdout.writeln('Route ${record.id} (component: ${record.componentId})');
    stdout.writeln('  Declaring package: ${record.packageName}');
    if (record.contract case final contract?) {
      stdout.writeln('  Contract/declaration: ${_sourceLocation(contract)}');
    }
    if (record.implementation case final implementation?) {
      stdout.writeln('  Implementation: ${_sourceLocation(implementation)}');
    }
    final declared = patterns[record.id]?.toList() ?? <_DeclaredPattern>[];
    declared.sort((left, right) {
      if (left.primary != right.primary) return left.primary ? -1 : 1;
      return left.value.compareTo(right.value);
    });
    for (final pattern in declared) {
      stdout.writeln(
        '  Pattern: ${pattern.value}${pattern.primary ? ' (primary)' : ''}',
      );
    }
  }
  return true;
}

/// Renders a portable declaration position without Markdown formatting.
String _sourceLocation(CCSourceReference source) {
  final line = source.line;
  final position = line == null
      ? ''
      : ':$line${source.column == null ? '' : ':${source.column}'}';
  final symbol = source.symbol.isEmpty ? '' : ' (${source.symbol})';
  return '${source.packageUri}$position$symbol';
}

/// One declared, reversible or regex Pattern used only for CLI display.
final class _DeclaredPattern {
  /// Keeps the primary marker alongside its exact declaration text.
  const _DeclaredPattern(this.value, this.primary);

  /// Generated Pattern value, not a URL resolved at runtime.
  final String value;

  /// Whether this Pattern is the canonical address generator.
  final bool primary;

  @override
  bool operator ==(Object other) =>
      other is _DeclaredPattern &&
      other.value == value &&
      other.primary == primary;

  @override
  int get hashCode => Object.hash(value, primary);
}
