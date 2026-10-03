import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:ccrouter_analyzer_plugin/src/resolved_symbols.dart';
import 'package:path/path.dart' as path;

/// Capability kinds whose consumers require an explicit component dependency.
enum CCRouterContractKind {
  /// A cross-component Service interface.
  service,

  /// A cross-component Command payload.
  command,
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
/// The index never scans arbitrary workspace source. It visits only Package
/// roots in Pub's `package_config.json`, each Package's exact CCRouter index,
/// and Contract source files named by that index. This keeps editor latency
/// predictable and leaves the Generator/Workspace Validator authoritative.
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
    return candidates.length == 1 ? candidates.single : null;
  }

  /// Finds one unambiguous Contract owner visible from an authored source.
  ///
  /// [importPrefixes] maps an explicit prefix to its imported Package. An
  /// empty-string key contains unprefixed Package imports. A local Contract is
  /// also eligible through [sourcePackage]. Ambiguous type names are ignored
  /// rather than guessed.
  CCRouterContractOwner? resolve({
    required CCRouterContractKind kind,
    required String contractSymbol,
    required String? prefix,
    required Map<String, Set<String>> importPrefixes,
    required String sourcePackage,
  }) {
    final visiblePackages = prefix == null
        ? <String>{sourcePackage, ...?importPrefixes['']}
        : importPrefixes[prefix] ?? const <String>{};
    final candidates = _owners
        .where(
          (owner) =>
              owner.kind == kind &&
              owner.contractSymbol == contractSymbol &&
              visiblePackages.contains(owner.contractPackage),
        )
        .toList(growable: false);
    if (candidates.length != 1) return null;
    return candidates.single;
  }

  /// Returns a component-ID reference that current imports provably expose.
  ///
  /// Every candidate public import is resolved to a concrete library and its
  /// export graph is checked for a top-level `CCComponentId` with exactly the
  /// expected stable value. Missing, hidden, or ambiguous exports decline the
  /// edit so a Quick Fix cannot introduce unresolved or incorrect code.
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
          !_libraryExportsComponentId(
            imported,
            symbol,
            owner.componentId,
            <String>{},
          )) {
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
        final uri = directive.uri.stringValue;
        final imported = uri == null ? null : _resolveLibrary(uri, sourcePath);
        if (imported != null &&
            _libraryExportsComponentId(imported, symbol, null, {}))
          contributors++;
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
        ClassDeclaration d => [d.name.lexeme],
        GenericTypeAlias d => [d.name.lexeme],
        FunctionDeclaration d => [d.name.lexeme],
        EnumDeclaration d => [d.name.lexeme],
        MixinDeclaration d => [d.name.lexeme],
        ExtensionTypeDeclaration d => [d.name.lexeme],
        _ => <String>[],
      },
  };

  /// Resolves one authored import URI against Pub's Package roots.
  String? _resolveLibrary(String uri, String sourcePath) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return null;
    if (parsed.scheme == 'package') {
      final segments = parsed.pathSegments;
      if (segments.length < 2) return null;
      final root = _packageRoots[segments.first];
      if (root == null) return null;
      return path.normalize(
        path.join(root, 'lib', path.joinAll(segments.skip(1))),
      );
    }
    if (parsed.hasScheme) return null;
    return path.normalize(Uri.file(sourcePath).resolveUri(parsed).toFilePath());
  }

  /// Checks one library and its explicit exports for an exact component ID.
  bool _libraryExportsComponentId(
    String libraryPath,
    String symbol,
    String? componentId,
    Set<String> visited,
  ) {
    final normalized = path.normalize(libraryPath);
    if (!visited.add(normalized)) return false;
    final file = File(normalized);
    if (!file.existsSync()) return false;
    late final CompilationUnit unit;
    try {
      unit = parseString(
        content: file.readAsStringSync(),
        path: normalized,
        throwIfDiagnostics: false,
      ).unit;
    } on Object {
      return false;
    }
    if (_declaredNames(unit).contains(symbol)) {
      return componentId == null ||
          _unitDeclaresComponentId(unit, symbol, componentId);
    }
    var contributors = 0;
    var matching = 0;
    for (final directive in unit.directives.whereType<ExportDirective>()) {
      if (directive.configurations.isNotEmpty ||
          !_combinatorsExpose(directive.combinators, symbol)) {
        continue;
      }
      final uri = directive.uri.stringValue;
      if (uri == null) continue;
      final exported = _resolveLibrary(uri, normalized);
      if (exported == null) continue;
      if (_libraryExportsComponentId(exported, symbol, null, {...visited}))
        contributors++;
      if (componentId != null &&
          _libraryExportsComponentId(exported, symbol, componentId, {
            ...visited,
          }))
        matching++;
    }
    return componentId == null
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

  /// Reads the stable value from a direct `CCComponentId('...')` expression.
  static String? _componentIdLiteral(Expression? expression) {
    final arguments = switch (expression) {
      InstanceCreationExpression value
          when value.constructorName.type.name.lexeme == 'CCComponentId' =>
        value.argumentList.arguments,
      MethodInvocation value
          when value.target == null &&
              value.methodName.name == 'CCComponentId' =>
        value.argumentList.arguments,
      _ => null,
    };
    if (arguments == null || arguments.length != 1) return null;
    final value = arguments.single;
    return value is SimpleStringLiteral ? value.value : null;
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

  /// Number of Pub graphs currently retained.
  int get entryCount => _entries.length;

  /// Resolves or builds the ownership index for [sourcePath].
  CCRouterContractOwnerIndex resolve(String sourcePath) {
    final configPath = _findPackageConfig(sourcePath);
    if (configPath == null) return CCRouterContractOwnerIndex.empty();
    final cached = _entries.remove(configPath);
    if (cached != null && _packageConfigMatches(cached)) {
      _entries[configPath] = cached;
      return cached.index;
    }
    final built = _build(configPath);
    if (built == null) return CCRouterContractOwnerIndex.empty();
    _entries[configPath] = built;
    while (_entries.length > maximumEntries) {
      _entries.remove(_entries.keys.first);
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
    _entries.removeWhere((_, entry) {
      final affected =
          metadataChanged ||
          entry.packageConfigPath == normalized ||
          entry.watchedPaths.contains(normalized);
      if (affected) affectedSources.addAll(entry.componentSourcePaths);
      return affected;
    });
    return Set.unmodifiable(affectedSources);
  }

  /// Releases all cached metadata and source path strings.
  void clear() => _entries.clear();

  /// Finds the nearest Pub package configuration above one source file.
  static String? _findPackageConfig(String sourcePath) {
    var current = File(sourcePath).absolute.parent;
    while (true) {
      final candidate = File(
        path.join(current.path, '.dart_tool', 'package_config.json'),
      );
      if (candidate.existsSync()) return path.normalize(candidate.path);
      final parent = current.parent;
      if (parent.path == current.path) return null;
      current = parent;
    }
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
  static _CCRouterContractOwnerCacheEntry? _build(String configPath) {
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
    final watched = <String>{path.normalize(configPath)};
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
        for (final value in metadataDocuments.whereType<Map>()) {
          final metadata = value.cast<String, Object?>();
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
        final parsedUri = Uri.tryParse(packageUri);
        if (parsedUri == null || parsedUri.scheme != 'package') continue;
        final segments = parsedUri.pathSegments;
        if (segments.length < 2) continue;
        final contractPackage = segments.first;
        final contractRoot = roots[contractPackage];
        if (contractRoot == null) continue;
        final sourcePath = path.normalize(
          path.join(contractRoot, 'lib', path.joinAll(segments.skip(1))),
        );
        watched.add(path.normalize(File(sourcePath).absolute.path));
        final pendingOwner = _PendingContractOwner(
          kind: kind,
          contractSymbol: symbol,
          contractPackage: contractPackage,
          componentId: componentId,
          contractSourcePath: sourcePath,
        );
        pending['${kind.name}\u0000$contractPackage\u0000$symbol\u0000$componentId'] =
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
            'package:${item.contractPackage}/${path.relative(item.contractSourcePath, from: path.join(roots[item.contractPackage]!, 'lib')).replaceAll(path.separator, '/')}',
      );
      final identity =
          '${owner.kind.name}\u0000${owner.contractPackage}\u0000'
          '${owner.contractSymbol}\u0000${owner.componentId}';
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
        final expected = owner.kind == CCRouterContractKind.service
            ? 'CCServiceContract'
            : 'CCCommandContract';
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
  });

  /// Contract capability kind.
  final CCRouterContractKind kind;

  /// Contract declaration symbol.
  final String contractSymbol;

  /// Package containing the Contract source.
  final String contractPackage;

  /// Stable owner component value.
  final String componentId;

  /// Exact Contract source path named by metadata.
  final String contractSourcePath;
}
