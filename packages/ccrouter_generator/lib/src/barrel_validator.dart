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
    final requirementsByPackage = <String, List<_BarrelExportRequirement>>{};
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
      final requirements = requirementsByPackage.putIfAbsent(
        packageName,
        () => <_BarrelExportRequirement>[],
      );

      for (final route in _objects(document['routes'])) {
        if (route['exposure'] == 'internal') continue;
        final contracts = route['contracts'];
        if (contracts is! Map) continue;
        final contractLibrary = '${contracts['library'] ?? source}';
        requirements.add(
          _BarrelExportRequirement(
            target: File(_join(packageRoot.path, contractLibrary)),
            requiredSymbols: {
              '${contracts['route']}',
              '${contracts['arguments']}',
            },
            error:
                'Public route "${route['id']}" in $source must be re-exported '
                'from $contractLibrary with both generated contracts in a '
                'public barrel using `show`.',
          ),
        );
      }
      for (final contract in _objects(document['serviceContracts'])) {
        final declaration = contract['declaration'];
        if (declaration is! Map) continue;
        final contractSymbol = '${declaration['symbol'] ?? ''}';
        if (contractSymbol.isEmpty) continue;
        requirements.add(
          _BarrelExportRequirement(
            target: sourceFile,
            requiredSymbols: {contractSymbol},
            error:
                'Public Service contract "${contract['id']}" in $source must '
                're-export interface "$contractSymbol" from $source in a '
                'public barrel using `show`.',
          ),
        );
      }
      if (componentPackages.contains(packageName)) continue;
      _collectAuthoredContractRequirements(
        requirements: requirements,
        contracts: _objects(document['commandContracts']),
        capability: 'Command',
        source: source,
        sourceFile: sourceFile,
      );
      _collectAuthoredContractRequirements(
        requirements: requirements,
        contracts: _objects(document['eventContracts']),
        capability: 'Event',
        source: source,
        sourceFile: sourceFile,
      );
      _collectAuthoredContractRequirements(
        requirements: requirements,
        contracts: _objects(document['initTaskContracts']),
        capability: 'InitTask',
        source: source,
        sourceFile: sourceFile,
      );
    }

    final errors = <String>[];
    for (final entry in requirementsByPackage.entries) {
      if (entry.value.isEmpty) continue;
      final packageRoot = packages[entry.key];
      if (packageRoot == null) continue;
      final index = _PackageBarrelExportIndex.build(packageRoot);
      for (final requirement in entry.value) {
        if (!index.shows(requirement.target, requirement.requiredSymbols)) {
          errors.add(requirement.error);
        }
      }
    }
    errors.sort();
    return errors;
  }

  /// Collects authored messaging or startup declarations that require export.
  static void _collectAuthoredContractRequirements({
    required List<_BarrelExportRequirement> requirements,
    required Iterable<Map<String, Object?>> contracts,
    required String capability,
    required String source,
    required File sourceFile,
  }) {
    for (final contract in contracts) {
      final declaration = contract['declaration'];
      if (declaration is! Map) continue;
      final contractSymbol = '${declaration['symbol'] ?? ''}';
      if (contractSymbol.isEmpty) continue;
      requirements.add(
        _BarrelExportRequirement(
          target: sourceFile,
          requiredSymbols: {contractSymbol},
          error:
              'Public $capability contract "${contract['id']}" in $source must '
              're-export declaration "$contractSymbol" from $source in a '
              'public barrel using `show`.',
        ),
      );
    }
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

  /// Parses a Dart library with the current language feature set.
  static ParseStringResult _parse(File file, String content) => parseString(
    content: content,
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

/// One required target library and the public symbols its barrel must show.
final class _BarrelExportRequirement {
  /// Creates one immutable validation requirement.
  const _BarrelExportRequirement({
    required this.target,
    required this.requiredSymbols,
    required this.error,
  });

  /// Library that a public barrel must export.
  final File target;

  /// Symbols that must appear together in one export directive's `show` list.
  final Set<String> requiredSymbols;

  /// Stable validation error emitted when no export satisfies the requirement.
  final String error;
}

/// Package-local index of Analyzer-parsed export directives.
///
/// Each candidate Dart file is read once and parsed at most once, regardless
/// of the number of metadata documents or public contracts in the Package.
final class _PackageBarrelExportIndex {
  /// Creates an index from normalized target paths to their export directives.
  const _PackageBarrelExportIndex(this._exportsByTarget);

  /// Builds one export index for every Dart library below [packageRoot].
  factory _PackageBarrelExportIndex.build(Directory packageRoot) {
    final exportsByTarget = <String, List<_BarrelExport>>{};
    for (final file in CCRouteBarrelExportValidator._dartFiles(packageRoot)) {
      final content = file.readAsStringSync();
      if (!content.contains('export')) continue;
      ParseStringResult parsed;
      try {
        parsed = CCRouteBarrelExportValidator._parse(file, content);
      } on FormatException {
        continue;
      }
      for (final directive
          in parsed.unit.directives.whereType<ExportDirective>()) {
        final uri = directive.uri.stringValue;
        if (uri == null) continue;
        final resolved = Uri.file(file.absolute.path).resolve(uri);
        if (resolved.scheme != 'file') continue;
        final shown = <String>{};
        for (final combinator in directive.combinators) {
          if (combinator is ShowCombinator) {
            shown.addAll(combinator.shownNames.map((name) => name.name));
          }
        }
        final targetPath = File(resolved.toFilePath()).absolute.path;
        exportsByTarget
            .putIfAbsent(targetPath, () => <_BarrelExport>[])
            .add(
              _BarrelExport(
                barrelPath: file.absolute.path,
                shownSymbols: shown,
              ),
            );
      }
    }
    return _PackageBarrelExportIndex(exportsByTarget);
  }

  /// Returns whether one non-self barrel shows every [requiredSymbol].
  bool shows(File target, Set<String> requiredSymbols) {
    final targetPath = target.absolute.path;
    for (final export in _exportsByTarget[targetPath] ?? const []) {
      if (export.barrelPath == targetPath) continue;
      if (export.shownSymbols.containsAll(requiredSymbols)) return true;
    }
    return false;
  }

  /// Export directives grouped by their resolved target library path.
  final Map<String, List<_BarrelExport>> _exportsByTarget;
}

/// One public barrel export and the explicit symbols exposed by its `show`.
final class _BarrelExport {
  /// Creates one parsed export record.
  const _BarrelExport({required this.barrelPath, required this.shownSymbols});

  /// Absolute path of the library that owns the export directive.
  final String barrelPath;

  /// Explicitly shown symbols; an empty set intentionally rejects broad export.
  final Set<String> shownSymbols;
}
