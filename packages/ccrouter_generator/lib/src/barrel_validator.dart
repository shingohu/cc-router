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
  /// Attaches public Package import URIs proven by explicit export chains.
  ///
  /// The generated Package index retains these URIs so read-only tooling does
  /// not need to scan authored source or guess a conventional barrel name.
  /// Missing exports remain absent and are reported by [validate].
  static void annotatePublicLibraries(
    Iterable<Map<String, Object?>> documents, {
    required Map<String, Directory> packageRoots,
  }) {
    final metadata = documents.toList(growable: false);
    final indexes = <String, _PackageBarrelExportIndex>{};
    _PackageBarrelExportIndex? indexFor(String packageName) {
      final root = packageRoots[packageName];
      if (root == null) return null;
      return indexes.putIfAbsent(
        packageName,
        () => _PackageBarrelExportIndex.build(root),
      );
    }

    for (final document in metadata) {
      final packageName = '${document['package'] ?? ''}';
      final packageRoot = packageRoots[packageName];
      final index = indexFor(packageName);
      if (packageRoot == null || index == null) continue;
      final source = '${document['source'] ?? ''}';
      if (!source.startsWith('lib/')) continue;
      final sourceFile = File(_join(packageRoot.path, source));

      for (final route in _mutableObjects(document, 'routes')) {
        if (route['exposure'] == 'internal') continue;
        final contracts = route['contracts'];
        if (contracts is! Map) continue;
        final mutable = Map<String, Object?>.from(contracts);
        route['contracts'] = mutable;
        final library = '${mutable['library'] ?? source}';
        _attachPublicLibraries(
          mutable,
          index.publicLibraries(File(_join(packageRoot.path, library)), {
            '${mutable['route']}',
          }, packageName: packageName),
        );
      }
      for (final group in const [
        'serviceContracts',
        'commandContracts',
        'eventContracts',
        'initTaskContracts',
      ]) {
        for (final contract in _mutableObjects(document, group)) {
          final declaration = contract['declaration'];
          if (declaration is! Map) continue;
          final symbol = '${declaration['symbol'] ?? ''}';
          if (symbol.isEmpty) continue;
          _attachPublicLibraries(
            contract,
            index.publicLibraries(sourceFile, {
              symbol,
            }, packageName: packageName),
          );
        }
      }
    }
  }

  /// Replaces a stale annotation with one deterministic non-empty URI list.
  static void _attachPublicLibraries(
    Map<String, Object?> target,
    List<String> libraries,
  ) {
    if (libraries.isEmpty) {
      target.remove('publicLibraries');
    } else {
      target['publicLibraries'] = libraries;
    }
  }

  /// Normalizes one decoded metadata array before attaching derived facts.
  ///
  /// Analyzer fixtures and programmatic callers may construct a nested
  /// `Map<String, String>`. A cast view would still reject the derived
  /// `List<String>` at runtime, so annotation owns a mutable object-typed copy
  /// and writes it back to the document just like JSON decoding would provide.
  static List<Map<String, Object?>> _mutableObjects(
    Map<String, Object?> document,
    String key,
  ) {
    final value = document[key];
    if (value is! List) return const [];
    final normalized = <Object?>[];
    final objects = <Map<String, Object?>>[];
    for (final entry in value) {
      if (entry is Map) {
        final object = Map<String, Object?>.from(entry);
        normalized.add(object);
        objects.add(object);
      } else {
        normalized.add(entry);
      }
    }
    document[key] = normalized;
    return objects;
  }

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

      for (final contract in _objects(document['uiContracts'])) {
        for (final type in _objects(contract['publicTypes'])) {
          final typePackage = '${type['package'] ?? ''}';
          final typeRoot = packages[typePackage];
          final typeSource = '${type['source'] ?? ''}';
          final symbol = '${type['symbol'] ?? ''}';
          if (typeRoot == null ||
              !typeSource.startsWith('lib/') ||
              symbol.isEmpty)
            continue;
          requirementsByPackage
              .putIfAbsent(typePackage, () => [])
              .add(
                _BarrelExportRequirement(
                  target: File(_join(typeRoot.path, typeSource)),
                  requiredSymbols: {symbol},
                  error:
                      'Public UI contract "${contract['id']}" must re-export '
                      '"$symbol" from $typeSource in a public barrel using `show`.',
                ),
              );
        }
      }

      for (final route in _objects(document['routes'])) {
        if (route['exposure'] == 'internal') continue;
        final contracts = route['contracts'];
        if (contracts is! Map) continue;
        final contractLibrary = '${contracts['library'] ?? source}';
        requirements.add(
          _BarrelExportRequirement(
            target: File(_join(packageRoot.path, contractLibrary)),
            requiredSymbols: {'${contracts['route']}'},
            error:
                'Public route "${route['id']}" in $source must be re-exported '
                'from $contractLibrary with the generated Route in a '
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
  const _PackageBarrelExportIndex(this._packageRoot, this._exportsByTarget);

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
    return _PackageBarrelExportIndex(
      packageRoot.absolute.path,
      exportsByTarget,
    );
  }

  /// Returns whether a transitive explicit export reaches a public library.
  ///
  /// Every hop must retain the complete `show` set. Generated stable barrels
  /// below `lib/src` therefore hide physical files without becoming public API
  /// by themselves.
  bool shows(File target, Set<String> requiredSymbols) {
    return publicLibraries(target, requiredSymbols, packageName: '').isNotEmpty;
  }

  /// Returns every top-level public library reached through explicit exports.
  List<String> publicLibraries(
    File target,
    Set<String> requiredSymbols, {
    required String packageName,
  }) {
    final targetPath = target.absolute.path;
    final pending = <String>[targetPath];
    final visited = <String>{targetPath};
    final publicLibraries = <String>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      for (final export in _exportsByTarget[current] ?? const []) {
        if (!export.shownSymbols.containsAll(requiredSymbols) ||
            !visited.add(export.barrelPath)) {
          continue;
        }
        if (_isPublicLibrary(export.barrelPath)) {
          final relative = export.barrelPath.substring(
            '$_packageRoot${Platform.pathSeparator}lib'.length + 1,
          );
          publicLibraries.add(
            packageName.isEmpty
                ? relative
                : 'package:$packageName/${relative.replaceAll(Platform.pathSeparator, '/')}',
          );
        } else {
          pending.add(export.barrelPath);
        }
      }
    }
    return publicLibraries.toList()..sort();
  }

  /// Whether [filePath] is a top-level library below `lib/`, not `lib/src/`.
  bool _isPublicLibrary(String filePath) {
    final libRoot = '$_packageRoot${Platform.pathSeparator}lib';
    if (!pathIsWithin(libRoot, filePath)) return false;
    final relative = filePath.substring(libRoot.length + 1);
    return !relative.contains(Platform.pathSeparator);
  }

  /// Whether [candidate] is strictly nested under [root].
  static bool pathIsWithin(String root, String candidate) {
    final prefix = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    return candidate.startsWith(prefix);
  }

  /// Absolute Package root used to recognize public entry libraries.
  final String _packageRoot;

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
