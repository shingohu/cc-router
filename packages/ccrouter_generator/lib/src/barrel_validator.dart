import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// Checks that exported generated route contracts are deliberately re-exported.
///
/// Run this check from the workspace route-catalog command. Component authors
/// keep generated parts beside their page declarations, while a public barrel
/// must explicitly show both the route and its argument contract. Component
/// routes remain library-private and are therefore excluded from this check.
final class CCRouteBarrelExportValidator {
  /// Finds missing or incomplete public barrel exports below [workspaceRoot].
  ///
  /// [documents] must be the decoded component and route metadata files
  /// emitted by the metadata builders. The method only reports exported routes
  /// whose source file is inside a package `lib` directory; test fixtures are
  /// ignored.
  static List<String> validate(
    Directory workspaceRoot,
    Iterable<Map<String, Object?>> documents,
  ) {
    final packages = _packageRoots(workspaceRoot);
    final errors = <String>[];
    for (final document in documents) {
      final packageName = '${document['package'] ?? ''}';
      final packageRoot = packages[packageName];
      if (packageRoot == null) continue;
      final source = '${document['source'] ?? ''}';
      if (!source.startsWith('lib/')) continue;
      final sourceFile = File(_join(packageRoot.path, source));
      if (!sourceFile.existsSync()) continue;
      final barrels = _dartFiles(packageRoot)
          .where((file) => file.path != sourceFile.path)
          .where((file) => _hasExportDirective(file))
          .toList();
      for (final route in _objects(document['routes'])) {
        if (route['visibility'] != 'exported') continue;
        final contracts = route['contracts'];
        if (contracts is! Map) continue;
        final required = <String>{
          '${contracts['route']}',
          '${contracts['arguments']}',
        };
        if (_isShownByBarrel(sourceFile, required, barrels)) continue;
        errors.add(
          'Exported route "${route['id']}" in $source must be re-exported '
          'with both generated contracts in a public barrel using `show`.',
        );
      }
    }
    errors.sort();
    return errors;
  }

  /// Locates workspace packages by their `pubspec.yaml` name declarations.
  static Map<String, Directory> _packageRoots(Directory root) {
    final packages = <String, Directory>{};
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('pubspec.yaml')) continue;
      if (entity.path.contains(
            '${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}',
          ) ||
          entity.path.contains(
            '${Platform.pathSeparator}build${Platform.pathSeparator}',
          )) {
        continue;
      }
      final name = RegExp(
        r'^name:\s*([A-Za-z0-9_]+)\s*$',
        multiLine: true,
      ).firstMatch(entity.readAsStringSync())?.group(1);
      if (name != null) packages[name] = entity.parent;
    }
    return packages;
  }

  /// Lists source Dart libraries while excluding generated and hidden folders.
  static Iterable<File> _dartFiles(Directory packageRoot) sync* {
    for (final entity in packageRoot.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.contains(
            '${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}',
          ) ||
          entity.path.contains(
            '${Platform.pathSeparator}build${Platform.pathSeparator}',
          )) {
        continue;
      }
      yield entity;
    }
  }

  /// Avoids parsing libraries without any export directive twice conceptually.
  static bool _hasExportDirective(File file) {
    try {
      return _parse(
        file,
      ).unit.directives.any((directive) => directive is ExportDirective);
    } on FormatException {
      return false;
    }
  }

  /// Checks whether one candidate barrel shows every required generated symbol.
  static bool _isShownByBarrel(
    File sourceFile,
    Set<String> required,
    Iterable<File> barrels,
  ) {
    for (final barrel in barrels) {
      ParseStringResult parsed;
      try {
        parsed = _parse(barrel);
      } on FormatException {
        continue;
      }
      for (final directive
          in parsed.unit.directives.whereType<ExportDirective>()) {
        final uri = directive.uri.stringValue;
        if (uri == null) continue;
        final target = File(Uri.file(barrel.path).resolve(uri).toFilePath());
        if (target.path != sourceFile.path) continue;
        final shown = <String>{};
        for (final combinator in directive.combinators) {
          if (combinator is ShowCombinator) {
            shown.addAll(combinator.shownNames.map((name) => name.name));
          }
        }
        if (shown.containsAll(required)) return true;
      }
    }
    return false;
  }

  /// Parses a Dart library with the current language feature set.
  static ParseStringResult _parse(File file) => parseString(
    content: file.readAsStringSync(),
    path: file.path,
    featureSet: FeatureSet.latestLanguageVersion(),
  );

  /// Converts a loosely decoded JSON array into route metadata objects.
  static Iterable<Map<String, Object?>> _objects(Object? value) sync* {
    if (value is! List) return;
    for (final item in value) {
      if (item is Map) yield item.cast<String, Object?>();
    }
  }

  /// Joins a package root and a workspace-relative source path.
  static String _join(String root, String relative) =>
      '$root${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';
}
