import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:ccrouter_analyzer_plugin/src/filesystem_identity_index.dart';
import 'package:ccrouter_analyzer_plugin/src/project_context.dart';
import 'package:ccrouter_analyzer_plugin/src/resolved_symbols.dart';
import 'package:path/path.dart' as path;

/// Capability kinds whose consumers require an explicit component dependency.
enum CCRouterContractKind {
  /// A cross-component Service interface.
  service,

  /// A cross-component Command payload.
  command,

  /// An optional typed UI Fragment marker with a required Owner edge.
  uiFragment,
}

/// Metadata-proven owner of one cross-component Contract type.
final class CCRouterContractOwner {
  /// Creates an immutable Contract-to-component ownership record.
  const CCRouterContractOwner({
    required this.kind,
    required this.contractSymbol,
    required this.contractPackage,
    required this.componentId,
    required this.componentIdSymbol,
    this.contractLibraryUri,
  });

  /// Whether this is a Service or Command Contract.
  final CCRouterContractKind kind;

  /// Public Dart type used by `CCServiceDependency<T>` or
  /// `CCCommandDependency<T>`.
  final String contractSymbol;

  /// Package containing the Contract declaration recorded by metadata.
  final String contractPackage;

  /// Stable owner identity required in `CCComponent.dependencies`.
  final String componentId;

  /// Source-level `CCComponentId` constant used by the Contract annotation.
  ///
  /// This is `null` when metadata proves the owner value but the authored
  /// Contract does not reference a reusable top-level identifier. Diagnostics
  /// remain available in that case, while Quick Fixes are deliberately
  /// withheld.
  final String? componentIdSymbol;

  /// Exact declaration library when provided by generated metadata.
  final String? contractLibraryUri;
}

/// Immutable Contract ownership snapshot built from resolved Package indexes.
///
/// The snapshot loads Pub's Package roots, exact CCRouter indexes and referenced
/// Contract sources. Parser-only checks additionally follow exact authored
/// import/export edges to prove visibility; they never scan whole Packages or
/// create another Analyzer session. Generator/Workspace Validator stays authoritative.
/// Defining Libraries remain part of identity even when type names, Owners or
/// shared part locations coincide; source and Library paths invalidate together.
final class CCRouterContractOwnerIndex {
  /// Creates a normalized index for one Pub resolution graph.
  CCRouterContractOwnerIndex({
    required Iterable<CCRouterContractOwner> owners,
    required Map<String, String> packageRoots,
  }) : _owners = List.unmodifiable(owners),
       _packageRoots = Map.unmodifiable(packageRoots);

  /// Empty ownership information used when Pub or generated metadata is not
  /// available yet.
  factory CCRouterContractOwnerIndex.empty() => CCRouterContractOwnerIndex(
    owners: const <CCRouterContractOwner>[],
    packageRoots: const <String, String>{},
  );

  /// Metadata-proven records in deterministic Package order.
  final List<CCRouterContractOwner> _owners;

  /// Resolved Package roots keyed by Pub Package name.
  final Map<String, String> _packageRoots;

  /// Resolves a Contract's real declaration, including typedefs and re-exports.
  /// Missing, duplicate or changed current annotations defer stale metadata.
  CCRouterContractOwner? resolveType(
    CCRouterContractKind kind,
    DartType? type,
  ) {
    if (type is! InterfaceType) return null;
    final uri = type.element.library.uri;
    if (uri.scheme != 'package' || uri.pathSegments.isEmpty) return null;
    final candidates = _owners
        .where(
          (owner) =>
              owner.kind == kind &&
              owner.contractSymbol == type.element.name &&
              owner.contractPackage == uri.pathSegments.first &&
              (owner.contractLibraryUri == null ||
                  owner.contractLibraryUri == uri.toString()),
        )
        .toList();
    if (candidates.length != 1) return null;
    final owner = candidates.single;
    final (annotationName, file) = switch (kind) {
      CCRouterContractKind.service => ('CCServiceContract', 'service'),
      CCRouterContractKind.command => ('CCCommandContract', 'messaging'),
      CCRouterContractKind.uiFragment => (
        'CCUIFragmentContract',
        'ui_fragment',
      ),
    };
    // Generated facts can outlive edits; require one current matching Owner.
    final annotations = type.element.metadata.annotations.where((annotation) {
      final annotationType = annotation.computeConstantValue()?.type;
      return annotationType is InterfaceType &&
          CCRouterResolvedSymbols.isFrameworkType(
            annotationType,
            annotationName,
            file,
          );
    }).toList();
    if (annotations.length != 1) return null;
    final currentOwner = annotations.single
        .computeConstantValue()
        ?.getField('componentId')
        ?.getField('value')
        ?.toStringValue();
    if (currentOwner != owner.componentId) return null;
    return owner;
  }

  /// Finds one unambiguous Contract owner visible from an authored source.
  ///
  /// [importPrefixes] maps an explicit prefix to its imported Package. An
  /// empty-string key contains unprefixed Package imports. A local Contract is
  /// also eligible through [sourcePackage]. Ambiguous type names are ignored
  /// rather than guessed. With source context, exact Library metadata must also
  /// match the imported declaration through its complete export namespace.
  CCRouterContractOwner? resolve({
    required CCRouterContractKind kind,
    required String contractSymbol,
    required String? prefix,
    required Map<String, Set<String>> importPrefixes,
    required String sourcePackage,
    CompilationUnit? unit,
    String? sourcePath,
  }) {
    final visiblePackages = prefix == null
        ? <String>{sourcePackage, ...?importPrefixes['']}
        : importPrefixes[prefix] ?? const <String>{};
    final candidates = _owners
        .where(
          (owner) =>
              owner.kind == kind &&
              owner.contractSymbol == contractSymbol &&
              (unit != null &&
                      sourcePath != null &&
                      owner.contractLibraryUri != null
                  ? _importsExposeContract(unit, sourcePath, prefix, owner)
                  : visiblePackages.contains(owner.contractPackage)),
        )
        .toList(growable: false);
    if (candidates.length != 1) return null;
    return candidates.single;
  }

  /// Proves one imported Contract's defining Library without a second session.
  /// Unknown or competing namespaces defer; local declarations need resolution.
  bool _importsExposeContract(
    CompilationUnit unit,
    String sourcePath,
    String? prefix,
    CCRouterContractOwner owner,
  ) {
    final symbol = owner.contractSymbol;
    if (_declaredNames(unit).contains(prefix ?? symbol)) return false;
    final library = _resolveLibrary(owner.contractLibraryUri!, sourcePath);
    if (library == null) return false;
    var contributors = 0;
    var matching = 0;
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      if (directive.prefix?.name != prefix ||
          !_combinatorsExpose(directive.combinators, symbol))
        continue;
      if (directive.configurations.isNotEmpty ||
          directive.deferredKeyword != null)
        return false;
      final uri = directive.uri.stringValue;
      final imported = uri == null ? null : _resolveLibrary(uri, sourcePath);
      if (imported == null) return false;
      final exposes = _libraryExposesSymbol(imported, symbol, null, {});
      if (exposes == null) return false;
      if (exposes) contributors++;
      final matches = _libraryExposesSymbol(
        imported,
        symbol,
        null,
        {},
        declaringLibrary: library,
      );
      if (matches == null) return false;
      if (matches) matching++;
    }
    return contributors == 1 && matching == 1;
  }

  /// Returns a component-ID reference that current imports provably expose.
  ///
  /// Every candidate public import is resolved to a concrete library and its
  /// export graph is checked for a top-level `CCComponentId` with exactly the
  /// expected stable value. Missing, hidden, or ambiguous exports decline the
  /// edit so a Quick Fix cannot introduce unresolved or incorrect code.
  /// Parser-only part libraries defer until their complete namespace resolves.
  String? visibleComponentIdReference({
    required CompilationUnit unit,
    required String sourcePath,
    required CCRouterContractOwner owner,
  }) {
    final symbol = owner.componentIdSymbol;
    if (symbol == null) return null;
    if (unit.declaredFragment != null) {
      final references = CCRouterResolvedSymbols.references(unit, symbol)
          .entries
          .where(
            (entry) =>
                CCRouterResolvedSymbols.componentId(entry.value) ==
                owner.componentId,
          )
          .toList();
      return references.length == 1 ? references.single.key : null;
    }
    if (unit.directives.any((d) => d is PartDirective || d is PartOfDirective))
      return null;
    final references = <String>{};
    final localNames = _declaredNames(unit);
    if (_unitDeclaresComponentId(unit, symbol, owner.componentId)) {
      references.add(symbol);
    }
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue;
      if (uri == null ||
          directive.deferredKeyword != null ||
          directive.configurations.isNotEmpty ||
          !_combinatorsExpose(directive.combinators, symbol)) {
        continue;
      }
      final imported = _resolveLibrary(uri, sourcePath);
      if (imported == null ||
          _libraryExposesSymbol(
                imported,
                symbol,
                owner.componentId,
                <String>{},
              ) !=
              true) {
        continue;
      }
      final prefix = directive.prefix?.name;
      if (localNames.contains(prefix ?? symbol)) continue;
      references.add(prefix == null ? symbol : '$prefix.$symbol');
    }
    // Parser-only clients must also reject ambiguous imported bindings.
    references.removeWhere((reference) {
      if (localNames.contains(reference)) return false;
      final prefix = reference.contains('.')
          ? reference.split('.').first
          : null;
      var contributors = 0;
      for (final directive in unit.directives.whereType<ImportDirective>()) {
        if (directive.prefix?.name != prefix ||
            !_combinatorsExpose(directive.combinators, symbol))
          continue;
        if (directive.configurations.isNotEmpty) return true;
        final uri = directive.uri.stringValue;
        final imported = uri == null ? null : _resolveLibrary(uri, sourcePath);
        final exports = imported == null
            ? null
            : _libraryExposesSymbol(imported, symbol, null, {});
        if (exports == null) return true;
        if (exports) contributors++;
      }
      return contributors != 1;
    });
    return references.length == 1 ? references.single : null;
  }

  /// Top-level declarations that shadow imported names in parser-only analysis.
  static Set<String> _declaredNames(CompilationUnit unit) => {
    for (final declaration in unit.declarations)
      ...switch (declaration) {
        TopLevelVariableDeclaration d => d.variables.variables.map(
          (v) => v.name.lexeme,
        ),
        NamedCompilationUnitMember d => [d.name.lexeme],
        ExtensionDeclaration d => [if (d.name != null) d.name!.lexeme],
        _ => <String>[],
      },
  };

  /// Resolves one authored import URI against Pub's Package roots.
  String? _resolveLibrary(String uri, String sourcePath) {
    try {
      final parsed = Uri.tryParse(uri);
      if (parsed == null ||
          parsed.hasAuthority ||
          parsed.hasQuery ||
          parsed.hasFragment)
        return null;
      if (parsed.scheme == 'package') {
        if (_contractMetadataUri(uri) == null) return null;
        final segments = parsed.pathSegments;
        if (segments.length < 2) return null;
        final root = _packageRoots[segments.first];
        if (root == null) return null;
        return path.normalize(
          path.join(root, 'lib', path.joinAll(segments.skip(1))),
        );
      }
      if (parsed.hasScheme) return null;
      final target = path.normalize(
        Uri.file(sourcePath).resolveUri(parsed).toFilePath(),
      );
      return target.contains('\u0000') ? null : target;
    } on FormatException {
      return null;
    } on UnsupportedError {
      return null;
    }
  }

  /// Checks exact symbol exports, optionally matching an ID or defining Library.
  /// Null means namespace evidence is incomplete.
  /// Unknown branches must not be counted as proof that another binding is unique.
  bool? _libraryExposesSymbol(
    String libraryPath,
    String symbol,
    String? componentId,
    Set<String> visited, {
    String? declaringLibrary,
  }) {
    final normalized = path.normalize(libraryPath);
    if (!visited.add(normalized)) return false;
    final file = File(normalized);
    if (!file.existsSync()) return null;
    late final CompilationUnit unit;
    try {
      final parsed = parseString(
        content: file.readAsStringSync(),
        path: normalized,
        throwIfDiagnostics: false,
      );
      if (parsed.errors.isNotEmpty) return null;
      unit = parsed.unit;
    } on Object {
      return null;
    }
    if (unit.directives.any((d) => d is PartDirective || d is PartOfDirective))
      return null;
    if (_declaredNames(unit).contains(symbol)) {
      return declaringLibrary != null
          ? path.equals(normalized, declaringLibrary)
          : componentId == null ||
                _unitDeclaresComponentId(unit, symbol, componentId);
    }
    var contributors = 0;
    var matching = 0;
    for (final directive in unit.directives.whereType<ExportDirective>()) {
      if (!_combinatorsExpose(directive.combinators, symbol)) continue;
      if (directive.configurations.isNotEmpty) return null;
      final uri = directive.uri.stringValue;
      if (uri == null) return null;
      final exported = _resolveLibrary(uri, normalized);
      if (exported == null) return null;
      final declares = _libraryExposesSymbol(exported, symbol, null, {
        ...visited,
      });
      if (declares == null) return null;
      if (declares) contributors++;
      if (componentId != null || declaringLibrary != null) {
        final matches = _libraryExposesSymbol(exported, symbol, componentId, {
          ...visited,
        }, declaringLibrary: declaringLibrary);
        if (matches == null) return null;
        if (matches) matching++;
      }
    }
    return componentId == null && declaringLibrary == null
        ? contributors > 0
        : contributors == 1 && matching == 1;
  }

  /// Whether one library directly declares the expected typed constant.
  static bool _unitDeclaresComponentId(
    CompilationUnit unit,
    String symbol,
    String componentId,
  ) {
    for (final declaration
        in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
      if (!declaration.variables.isConst) continue;
      for (final variable in declaration.variables.variables) {
        if (variable.name.lexeme != symbol) continue;
        if (_componentIdLiteral(variable.initializer) == componentId) {
          return true;
        }
      }
    }
    return false;
  }

  /// Reads only literal values from proven framework Component ID constructors.
  static String? _componentIdLiteral(Expression? expression) {
    if (expression == null) return null;
    final arguments = CCRouterResolvedSymbols.constructorArguments(
      expression,
      'CCComponentId',
      'component',
    )?.arguments;
    if (arguments == null || arguments.length != 1) return null;
    final value = arguments.single;
    return value is StringLiteral ? value.stringValue : null;
  }

  /// Applies Dart `show` and `hide` combinators for one requested symbol.
  static bool _combinatorsExpose(
    NodeList<Combinator> combinators,
    String symbol,
  ) {
    for (final combinator in combinators) {
      if (combinator is ShowCombinator &&
          !combinator.shownNames.any((name) => name.name == symbol)) {
        return false;
      }
      if (combinator is HideCombinator &&
          combinator.hiddenNames.any((name) => name.name == symbol)) {
        return false;
      }
    }
    return true;
  }
}

/// One bounded cache entry for a resolved Pub graph and its owner index.
final class _CCRouterContractOwnerCacheEntry {
  /// Captures an index plus the configuration and Contract sources that built
  /// it so watch events can invalidate only affected workspaces.
  const _CCRouterContractOwnerCacheEntry({
    required this.index,
    required this.packageConfigPath,
    required this.packageConfigModifiedMilliseconds,
    required this.packageConfigSize,
    required this.watchedPaths,
    required this.componentSourcePaths,
  });

  /// Immutable ownership snapshot.
  final CCRouterContractOwnerIndex index;

  /// Pub resolution file used to discover exact Package roots.
  final String packageConfigPath;

  /// Configuration modification time used for cheap stale detection.
  final int packageConfigModifiedMilliseconds;

  /// Configuration size paired with the modification time.
  final int packageConfigSize;

  /// Metadata and Contract source files that contributed to [index].
  final Set<String> watchedPaths;

  /// Exact authored component descriptors refreshed after index changes.
  final Set<String> componentSourcePaths;
}

/// Bounded cache of Metadata-driven Contract owner indexes.
///
/// One index is built per Pub resolution graph and reused across editor edits.
/// Generated metadata or Contract source watch events evict the affected entry;
/// the LRU bound prevents a long-lived Analysis Server from retaining every
/// workspace ever opened.
final class CCRouterContractOwnerIndexCache {
  /// Creates a cache retaining at most [maximumEntries] Pub graphs.
  CCRouterContractOwnerIndexCache({this.maximumEntries = 8})
    : assert(maximumEntries > 0);

  /// Maximum number of workspace indexes retained by this plugin isolate.
  final int maximumEntries;

  /// Least-recently-used entries keyed by normalized package-config path.
  final LinkedHashMap<String, _CCRouterContractOwnerCacheEntry> _entries =
      LinkedHashMap<String, _CCRouterContractOwnerCacheEntry>();

  /// Deduplicated exact inputs shared by retained Pub graph entries.
  final CCRouterFilesystemIdentityIndex _filesystemIdentities =
      CCRouterFilesystemIdentityIndex();

  /// Number of Pub graphs currently retained.
  int get entryCount => _entries.length;

  /// Authored component descriptors affected by any retained owner index.
  Set<String> get affectedPaths => Set.unmodifiable({
    for (final entry in _entries.values) ...entry.componentSourcePaths,
  });

  /// Resolves or builds the ownership index for [sourcePath].
  CCRouterContractOwnerIndex resolve(String sourcePath) {
    final context = CCRouterAnalyzerProjectContext.resolve(sourcePath);
    if (context == null) return CCRouterContractOwnerIndex.empty();
    final configPath = path.normalize(
      path.join(
        context.resolutionRoot.path,
        '.dart_tool',
        'package_config.json',
      ),
    );
    if (!File(configPath).existsSync()) {
      return CCRouterContractOwnerIndex.empty();
    }
    final cached = _entries.remove(configPath);
    if (cached != null && _packageConfigMatches(cached)) {
      _entries[configPath] = cached;
      return cached.index;
    }
    if (cached != null) _filesystemIdentities.remove(configPath);
    final built = _build(configPath, context);
    if (built == null) return CCRouterContractOwnerIndex.empty();
    _entries[configPath] = built;
    _filesystemIdentities.replace(
      configPath,
      watchedPaths: built.watchedPaths,
      affectedPaths: built.componentSourcePaths,
    );
    while (_entries.length > maximumEntries) {
      final evicted = _entries.keys.first;
      _entries.remove(evicted);
      _filesystemIdentities.remove(evicted);
    }
    return built.index;
  }

  /// Invalidates indexes affected by a Package config, generated metadata, or
  /// Contract source change and returns component descriptors to refresh.
  Set<String> invalidate(String changedPath) {
    final normalized = path.normalize(File(changedPath).absolute.path);
    final metadataChanged = normalized.endsWith(
      path.join(
        'lib',
        'src',
        'ccrouter_generated',
        'metadata',
        'ccrouter_package.json',
      ),
    );
    final affectedSources = <String>{};
    _entries.removeWhere((registration, entry) {
      final affected =
          metadataChanged ||
          entry.packageConfigPath == normalized ||
          entry.watchedPaths.contains(normalized);
      if (affected) {
        affectedSources.addAll(entry.componentSourcePaths);
        _filesystemIdentities.remove(registration);
      }
      return affected;
    });
    return Set.unmodifiable(affectedSources);
  }

  /// Evicts cached indexes whose exact metadata or source inputs changed.
  ///
  /// Analysis Server does not consistently forward generated JSON changes to
  /// legacy plugins. Polling only paths already used by a cached index keeps
  /// the fallback bounded by resolved Pub evidence rather than the workspace.
  Set<String> pollChangedPaths({int? shardIndex, int? shardCount}) {
    final result = shardIndex == null || shardCount == null
        ? _filesystemIdentities.pollAll()
        : _filesystemIdentities.pollShard(
            shardIndex: shardIndex,
            shardCount: shardCount,
          );
    for (final registration in result.changedRegistrations) {
      _entries.remove(registration);
      _filesystemIdentities.remove(registration);
    }
    return result.affectedPaths;
  }

  /// Releases all cached metadata and source path strings.
  void clear() {
    _entries.clear();
    _filesystemIdentities.clear();
  }

  /// Verifies the cheap identity of one cached Pub resolution file.
  static bool _packageConfigMatches(_CCRouterContractOwnerCacheEntry entry) {
    final file = File(entry.packageConfigPath);
    if (!file.existsSync()) return false;
    final stat = file.statSync();
    return stat.modified.millisecondsSinceEpoch ==
            entry.packageConfigModifiedMilliseconds &&
        stat.size == entry.packageConfigSize;
  }

  /// Builds one index from exact resolved Package metadata paths.
  static _CCRouterContractOwnerCacheEntry? _build(
    String configPath,
    CCRouterAnalyzerProjectContext context,
  ) {
    final configFile = File(configPath);
    late final Map<String, Object?> config;
    try {
      final decoded = jsonDecode(configFile.readAsStringSync());
      if (decoded is! Map) return null;
      config = decoded.cast<String, Object?>();
    } on Object {
      return null;
    }
    final roots = <String, String>{};
    final packages = config['packages'];
    if (packages is! List) return null;
    for (final value in packages.whereType<Map>()) {
      final item = value.cast<String, Object?>();
      final name = item['name'];
      final rootUri = item['rootUri'];
      if (name is! String || rootUri is! String) continue;
      try {
        roots[name] = path.normalize(
          configFile.uri.resolve(rootUri).toFilePath(),
        );
      } on Object {
        continue;
      }
    }
    final watched = <String>{
      path.normalize(configPath),
      path.normalize(path.join(context.requestedRoot.path, 'pubspec.yaml')),
      path.normalize(path.join(context.requestedRoot.path, '.metadata')),
      path.normalize(path.join(context.requestedRoot.path, 'ccrouter.yaml')),
      path.normalize(
        path.join(
          context.requestedRoot.path,
          '.dart_tool',
          'pub',
          'workspace_ref.json',
        ),
      ),
      path.normalize(path.join(context.resolutionRoot.path, 'pubspec.yaml')),
    };
    final componentSources = <String>{};
    final pending = <String, _PendingContractOwner>{};
    final packageNames = roots.keys.toList()..sort();
    for (final packageName in packageNames) {
      final root = roots[packageName]!;
      final metadataFile = File(
        path.join(
          root,
          'lib',
          'src',
          'ccrouter_generated',
          'metadata',
          'ccrouter_package.json',
        ),
      );
      if (!metadataFile.existsSync()) continue;
      watched.add(path.normalize(metadataFile.absolute.path));
      late final Map<String, Object?> document;
      try {
        final decoded = jsonDecode(metadataFile.readAsStringSync());
        if (decoded is! Map) continue;
        document = decoded.cast<String, Object?>();
      } on Object {
        continue;
      }
      final metadataDocuments = document['metadata'];
      if (metadataDocuments is List) {
        final usableUI = _usableUIOwnerMetadata(
          metadataDocuments,
          document['schemaVersion'],
        );
        for (final value in metadataDocuments.whereType<Map>()) {
          final metadata = value.cast<String, Object?>();
          if (usableUI && metadata['uiContracts'] is List) {
            for (final ui
                in (metadata['uiContracts'] as List).whereType<Map>()) {
              final declaration = ui['declaration'];
              if (declaration is! Map ||
                  declaration['symbol'] is! String ||
                  ui['componentId'] is! String)
                continue;
              final uri = _contractMetadataUri(declaration['packageUri']);
              if (uri == null) continue;
              final contractPackage = uri.pathSegments.first;
              final sourceRoot = roots[contractPackage];
              if (sourceRoot == null) continue;
              final sourcePath = path.normalize(
                path.join(
                  sourceRoot,
                  'lib',
                  path.joinAll(uri.pathSegments.skip(1)),
                ),
              );
              if (!path.isWithin(path.join(sourceRoot, 'lib'), sourcePath))
                continue;
              final libraryUri = !declaration.containsKey('libraryUri')
                  ? uri
                  : _contractMetadataUri(declaration['libraryUri']);
              // Keep source locations separate from the defining library.
              // Invalid explicit identity never falls back to Package + name.
              if (libraryUri == null ||
                  libraryUri.pathSegments.first != contractPackage)
                continue;
              final libraryPath = path.normalize(
                path.join(
                  sourceRoot,
                  'lib',
                  path.joinAll(libraryUri.pathSegments.skip(1)),
                ),
              );
              if (!path.isWithin(path.join(sourceRoot, 'lib'), libraryPath))
                continue;
              watched.add(sourcePath);
              watched.add(libraryPath);
              final item = _PendingContractOwner(
                kind: CCRouterContractKind.uiFragment,
                contractSymbol: declaration['symbol'] as String,
                contractPackage: contractPackage,
                componentId: ui['componentId'] as String,
                contractSourcePath: sourcePath,
                contractLibraryUri: libraryUri.toString(),
              );
              pending['uiFragment\u0000$contractPackage\u0000${item.contractSymbol}\u0000${item.componentId}\u0000$sourcePath\u0000$libraryUri'] =
                  item;
            }
          }
          final components = metadata['components'];
          final sourcePackage = metadata['package'];
          final source = metadata['source'];
          if (components is! List ||
              components.isEmpty ||
              sourcePackage is! String ||
              source is! String) {
            continue;
          }
          final sourceRoot = roots[sourcePackage];
          if (sourceRoot != null) {
            componentSources.add(path.normalize(path.join(sourceRoot, source)));
          }
        }
      }
      final catalog = document['capabilityCatalog'];
      if (catalog is! Map) continue;
      final records = catalog['records'];
      if (records is! List) continue;
      for (final value in records.whereType<Map>()) {
        final record = value.cast<String, Object?>();
        final kind = switch (record['kind']) {
          'service' => CCRouterContractKind.service,
          'command' => CCRouterContractKind.command,
          _ => null,
        };
        final componentId = record['componentId'];
        final contract = record['contract'];
        if (kind == null || componentId is! String || contract is! Map) {
          continue;
        }
        final contractMap = contract.cast<String, Object?>();
        final symbol = contractMap['symbol'];
        final packageUri = contractMap['packageUri'];
        if (symbol is! String || packageUri is! String) continue;
        final parsedUri = _contractMetadataUri(packageUri);
        if (parsedUri == null) continue;
        final segments = parsedUri.pathSegments;
        final contractPackage = segments.first;
        final contractRoot = roots[contractPackage];
        if (contractRoot == null) continue;
        final sourcePath = path.normalize(
          path.join(contractRoot, 'lib', path.joinAll(segments.skip(1))),
        );
        if (!path.isWithin(path.join(contractRoot, 'lib'), sourcePath))
          continue;
        final libraryUri = contractMap.containsKey('libraryUri')
            ? _contractMetadataUri(contractMap['libraryUri'])
            : parsedUri;
        if (libraryUri == null ||
            libraryUri.pathSegments.first != contractPackage)
          continue;
        final libraryPath = path.normalize(
          path.join(
            contractRoot,
            'lib',
            path.joinAll(libraryUri.pathSegments.skip(1)),
          ),
        );
        if (!path.isWithin(path.join(contractRoot, 'lib'), libraryPath))
          continue;
        watched.add(path.normalize(File(sourcePath).absolute.path));
        watched.add(path.normalize(File(libraryPath).absolute.path));
        final pendingOwner = _PendingContractOwner(
          kind: kind,
          contractSymbol: symbol,
          contractPackage: contractPackage,
          componentId: componentId,
          contractSourcePath: sourcePath,
          contractLibraryUri: libraryUri.toString(),
        );
        pending['${kind.name}\u0000$contractPackage\u0000$symbol\u0000$componentId\u0000$sourcePath\u0000$libraryUri'] =
            pendingOwner;
      }
    }
    final ownersByIdentity = <String, CCRouterContractOwner>{};
    for (final item in pending.values) {
      final owner = CCRouterContractOwner(
        kind: item.kind,
        contractSymbol: item.contractSymbol,
        contractPackage: item.contractPackage,
        componentId: item.componentId,
        componentIdSymbol: _componentIdSymbol(item),
        contractLibraryUri:
            item.contractLibraryUri ??
            'package:${item.contractPackage}/${path.relative(item.contractSourcePath, from: path.join(roots[item.contractPackage]!, 'lib')).replaceAll(path.separator, '/')}',
      );
      final identity =
          '${owner.kind.name}\u0000${owner.contractPackage}\u0000'
          '${owner.contractSymbol}\u0000${owner.componentId}\u0000'
          '${owner.contractLibraryUri}';
      ownersByIdentity[identity] = owner;
    }
    final owners = ownersByIdentity.values.toList()
      ..sort((left, right) {
        final packageOrder = left.contractPackage.compareTo(
          right.contractPackage,
        );
        if (packageOrder != 0) return packageOrder;
        final kindOrder = left.kind.name.compareTo(right.kind.name);
        if (kindOrder != 0) return kindOrder;
        return left.contractSymbol.compareTo(right.contractSymbol);
      });
    final stat = configFile.statSync();
    return _CCRouterContractOwnerCacheEntry(
      index: CCRouterContractOwnerIndex(owners: owners, packageRoots: roots),
      packageConfigPath: path.normalize(configPath),
      packageConfigModifiedMilliseconds: stat.modified.millisecondsSinceEpoch,
      packageConfigSize: stat.size,
      watchedPaths: Set.unmodifiable(watched),
      componentSourcePaths: Set.unmodifiable(componentSources),
    );
  }

  /// Reads the component-ID source identifier from the exact Contract
  /// declaration named by generated metadata.
  static String? _componentIdSymbol(_PendingContractOwner owner) {
    final file = File(owner.contractSourcePath);
    if (!file.existsSync()) return null;
    late final CompilationUnit unit;
    try {
      unit = parseString(
        content: file.readAsStringSync(),
        path: owner.contractSourcePath,
        throwIfDiagnostics: false,
      ).unit;
    } on Object {
      return null;
    }
    for (final declaration in unit.declarations) {
      final (name, metadata) = switch (declaration) {
        ClassDeclaration value => (value.name.lexeme, value.metadata),
        EnumDeclaration value => (value.name.lexeme, value.metadata),
        MixinDeclaration value => (value.name.lexeme, value.metadata),
        ExtensionTypeDeclaration value => (value.name.lexeme, value.metadata),
        _ => (null, const <Annotation>[]),
      };
      if (name != owner.contractSymbol) continue;
      for (final annotation in metadata) {
        final expected = switch (owner.kind) {
          CCRouterContractKind.service => 'CCServiceContract',
          CCRouterContractKind.command => 'CCCommandContract',
          CCRouterContractKind.uiFragment => 'CCUIFragmentContract',
        };
        if (_annotationName(annotation) != expected) continue;
        final expression = _namedArgument(annotation, 'componentId');
        return switch (expression) {
          SimpleIdentifier value => value.name,
          PrefixedIdentifier value => value.identifier.name,
          PropertyAccess value => value.propertyName.name,
          _ => null,
        };
      }
    }
    return null;
  }

  /// Reads an annotation's unqualified source name.
  static String _annotationName(Annotation annotation) {
    final source = annotation.name.toSource();
    return source.substring(source.lastIndexOf('.') + 1);
  }

  /// Finds one named annotation argument without evaluating application code.
  static Expression? _namedArgument(Annotation annotation, String name) {
    for (final argument
        in annotation.arguments?.arguments.whereType<NamedExpression>() ??
            const <NamedExpression>[]) {
      if (argument.name.label.name == name) return argument.expression;
    }
    return null;
  }
}

/// Metadata record awaiting source-level component-ID extraction.
final class _PendingContractOwner {
  /// Creates one normalized pending record.
  const _PendingContractOwner({
    required this.kind,
    required this.contractSymbol,
    required this.contractPackage,
    required this.componentId,
    required this.contractSourcePath,
    this.contractLibraryUri,
  });

  /// Contract capability kind.
  final CCRouterContractKind kind;

  /// Contract declaration symbol.
  final String contractSymbol;

  /// Package containing the Contract source.
  final String contractPackage;

  /// Stable owner component value.
  final String componentId;

  /// Exact Contract source path named by metadata, including part files.
  final String contractSourcePath;

  /// Defining library identity when metadata distinguishes it from the source.
  final String? contractLibraryUri;
}

/// Accepts portable Contract identity URIs without queries, fragments or path escapes.
/// Source location and defining Library each require this proof before file access.
Uri? _contractMetadataUri(Object? value) {
  if (value is! String) return null;
  try {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'package' ||
        uri.hasAuthority ||
        uri.hasAbsolutePath ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length < 2 ||
        uri.pathSegments.any(
          (segment) =>
              segment.isEmpty ||
              segment == '.' ||
              segment == '..' ||
              segment.contains('/') ||
              segment.contains(r'\') ||
              segment.contains('\u0000'),
        ))
      return null;
    return uri;
  } on FormatException {
    return null;
  }
}

/// Defers UI Owner fixes when format evidence cannot prove current UI metadata.
///
/// Legacy indexes may omit their outer version, but explicit document/record
/// versions must be integers and agree. Other capability families are unaffected.
/// The authoritative Generator still owns full schema and content verification.
bool _usableUIOwnerMetadata(List<Object?> documents, Object? indexVersion) {
  var highest = 0;
  for (final document in documents.whereType<Map>()) {
    final tagged = document.containsKey('uiSchemaVersion');
    final declared = document['uiSchemaVersion'];
    var populated = false;
    var required = 1;
    for (final key in ['uiContracts', 'uiRenderers', 'uiRequirements']) {
      if (!document.containsKey(key)) continue;
      final records = document[key];
      if (records is! List) return false;
      for (final record in records) {
        if (record is! Map) return false;
        populated = true;
        final version = record.containsKey('uiSchemaVersion')
            ? record['uiSchemaVersion']
            : 1;
        if (version is! int || version < 1 || version > 3) return false;
        if (version > required) required = version;
      }
    }
    if (!tagged && !populated) continue;
    if (declared is! int || declared < 1 || declared > 3) return false;
    if (populated && declared != required) return false;
    final sourceVersion = document['schemaVersion'];
    if (sourceVersion != null && (sourceVersion is! int || sourceVersion != 5))
      return false;
    if (declared > highest) highest = declared;
  }
  return highest > 0 &&
      (indexVersion == null ||
          indexVersion is int && indexVersion == highest + 2);
}
