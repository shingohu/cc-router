import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// Checks that public cross-Package contracts are re-exported.
///
/// Run this check from the workspace route-catalog command. Component authors
/// keep generated libraries isolated from authored declarations, while a
/// public barrel must explicitly show the generated Route types or authored
/// Service, Command, and Event declarations. Component-internal capabilities
/// remain excluded.
final class CCRouteBarrelExportValidator {
  /// Finds missing or incomplete public barrel exports below [workspaceRoot].
  ///
  /// [documents] must be the decoded component and route metadata files
  /// emitted by the metadata builders. The method only reports public
  /// Contract-first declarations whose source file is inside a package `lib`
  /// directory; test fixtures are ignored. Resolved Host generation supplies
  /// [packageRoots] to avoid scanning unrelated workspace Packages; the legacy
  /// aggregate command may omit it and discover roots below [workspaceRoot].
  static List<String> validate(
    Directory workspaceRoot,
    Iterable<Map<String, Object?>> documents, {
    Map<String, Directory>? packageRoots,
  }) {
    final metadata = documents.toList(growable: false);
    final packages = packageRoots ?? _packageRoots(workspaceRoot);
    final errors = <String>[];
    final componentPackages = <String>{
      for (final document in metadata)
        if (_objects(document['components']).isNotEmpty)
          '${document['package'] ?? ''}',
    };
    for (final document in metadata) {
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
        if (route['exposure'] == 'internal') continue;
        final contracts = route['contracts'];
        if (contracts is! Map) continue;
        final required = <String>{
          '${contracts['route']}',
          '${contracts['arguments']}',
        };
        final contractLibrary = '${contracts['library'] ?? source}';
        final contractFile = File(_join(packageRoot.path, contractLibrary));
        if (_isShownByBarrel(contractFile, required, barrels)) continue;
        errors.add(
          'Public route "${route['id']}" in $source must be re-exported '
          'from $contractLibrary '
          'with both generated contracts in a public barrel using `show`.',
        );
      }
      for (final contract in _objects(document['serviceContracts'])) {
        final declaration = contract['declaration'];
        if (declaration is! Map) continue;
        final contractSymbol = '${declaration['symbol'] ?? ''}';
        if (contractSymbol.isEmpty) continue;
        if (_isShownByBarrel(sourceFile, {contractSymbol}, barrels)) continue;
        errors.add(
          'Public Service contract "${contract['id']}" in $source must '
          're-export interface "$contractSymbol" from $source in a public '
          'barrel using `show`.',
        );
      }
      if (componentPackages.contains(packageName)) continue;
      for (final contract in _objects(document['commandContracts'])) {
        _validateAuthoredContractExport(
          errors: errors,
          contract: contract,
          capability: 'Command',
          source: source,
          sourceFile: sourceFile,
          barrels: barrels,
        );
      }
      for (final contract in _objects(document['eventContracts'])) {
        _validateAuthoredContractExport(
          errors: errors,
          contract: contract,
          capability: 'Event',
          source: source,
          sourceFile: sourceFile,
          barrels: barrels,
        );
      }
    }
    errors.sort();
    return errors;
  }

  /// Requires one authored contracts-Package declaration in a public barrel.
  static void _validateAuthoredContractExport({
    required List<String> errors,
    required Map<String, Object?> contract,
    required String capability,
    required String source,
    required File sourceFile,
    required List<File> barrels,
  }) {
    final declaration = contract['declaration'];
    if (declaration is! Map) return;
    final contractSymbol = '${declaration['symbol'] ?? ''}';
    if (contractSymbol.isEmpty) return;
    if (_isShownByBarrel(sourceFile, {contractSymbol}, barrels)) return;
    errors.add(
      'Public $capability contract "${contract['id']}" in $source must '
      're-export declaration "$contractSymbol" from $source in a public '
      'barrel using `show`.',
    );
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
