import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

part 'capability_source_catalog.dart';

/// Current on-disk schema understood by the Package aggregation pipeline.
const int ccrouterPackageIndexSchemaVersion = 2;

/// Generator identity recorded in Package indexes for diagnostics.
const String ccrouterPackageIndexGeneratorVersion = '0.1.0';

/// Failure raised when resolved Pub state cannot form a safe generation graph.
final class CCPackageWorkspaceException implements Exception {
  /// Creates a discovery or Package index validation failure.
  const CCPackageWorkspaceException(this.message);

  /// Actionable explanation intended for CLI output.
  final String message;

  @override
  String toString() => message;
}

/// One Package in the Host's resolved runtime dependency closure.
final class CCResolvedPackage {
  /// Creates immutable resolved Package metadata.
  const CCResolvedPackage({
    required this.name,
    required this.version,
    required this.root,
    required this.dependencies,
    required this.devDependencies,
    required this.writable,
  });

  /// Pub Package name.
  final String name;

  /// Resolved Package version from `package_graph.json`.
  final String version;

  /// Actual Package directory resolved through `package_config.json`.
  final Directory root;

  /// Direct runtime dependency Package names.
  final List<String> dependencies;

  /// Direct development dependency Package names used only for intent checks.
  final List<String> devDependencies;

  /// Whether this generation invocation may update files in [root].
  final bool writable;

  /// Published Package index location included by Git and Pub archives.
  File get indexFile => File(
    path.join(root.path, 'lib', 'ccrouter_generated', 'ccrouter_package.json'),
  );

  /// Generated Dart Bundle entrypoint consumed by direct dependants.
  File get bundleFile =>
      File(path.join(root.path, 'lib', '${name}_ccrouter.g.dart'));

  /// Package-root directory containing the optional readable capability view.
  ///
  /// Builder intermediates never live here; they remain in build_runner's
  /// disposable cache while the published machine index lives below `lib/`.
  Directory get catalogDirectory =>
      Directory(path.join(root.path, 'ccrouter_generated'));

  /// Whether Package tooling declares an intent to produce CCRouter artifacts.
  bool get declaresGenerationIntent =>
      devDependencies.contains('ccrouter_generator') ||
      File(path.join(root.path, 'ccrouter.yaml')).existsSync();

  /// Whether a non-framework dependency must publish a Package index.
  ///
  /// Pub resolution may omit dependency Package dev-dependencies, so direct
  /// use of `ccrouter` or `ccrouter_contracts` is the reliable participation
  /// signal. Packages with no annotations publish an empty index, which keeps
  /// missing external component metadata distinguishable from nonparticipants.
  bool get requiresPackageIndex =>
      !_ccrouterFrameworkPackages.contains(name) &&
      (dependencies.contains('ccrouter') ||
          dependencies.contains('ccrouter_contracts'));
}

/// Framework implementation Packages that do not publish business metadata.
const Set<String> _ccrouterFrameworkPackages = {
  'ccrouter',
  'ccrouter_contracts',
  'ccrouter_core',
  'ccrouter_generator',
  'ccrouter_go_router',
  'ccrouter_test',
};

/// Exact resolved Package universe reachable from one Host.
///
/// Discovery starts from the Host Package and follows only runtime
/// `dependencies`. Workspace siblings and `devDependencies` are deliberately
/// excluded even when they share the same `.dart_tool` directory.
final class CCPackageWorkspace {
  /// Creates a validated dependency closure.
  const CCPackageWorkspace({
    required this.buildRoot,
    required this.host,
    required this.packages,
  });

  /// Directory owning the `.dart_tool` resolution state.
  final Directory buildRoot;

  /// Package selected by the CLI scan-root argument.
  final CCResolvedPackage host;

  /// Runtime dependency closure keyed by Package name.
  final Map<String, CCResolvedPackage> packages;

  /// Locates one writable Package's Builder-owned intermediate metadata.
  ///
  /// The path follows build_runner's `build_to: cache` layout under this
  /// resolved workspace. It is never published and never used for read-only
  /// dependencies, which are consumed only through their Package Index.
  Directory intermediateMetadataDirectory(CCResolvedPackage package) =>
      Directory(
        path.join(
          buildRoot.path,
          '.dart_tool',
          'build',
          'generated',
          package.name,
          'ccrouter_generated',
        ),
      );

  /// Loads resolved Pub state and computes the Host-only runtime closure.
  ///
  /// Missing or stale resolution files are rejected with a `pub get` hint;
  /// generation never falls back to a broad filesystem scan.
  static Future<CCPackageWorkspace> load({
    required Directory buildRoot,
    required Directory hostRoot,
    required bool workspace,
  }) async {
    final dartTool = Directory(path.join(buildRoot.path, '.dart_tool'));
    final graphFile = File(path.join(dartTool.path, 'package_graph.json'));
    final configFile = File(path.join(dartTool.path, 'package_config.json'));
    if (!graphFile.existsSync() || !configFile.existsSync()) {
      throw const CCPackageWorkspaceException(
        'Resolved Package graph is missing. Run `fvm flutter pub get` (or '
        '`fvm dart pub get`) before `ccrouter generate`.',
      );
    }

    final graph = _decodeObject(await graphFile.readAsString(), graphFile.path);
    final config = _decodeObject(
      await configFile.readAsString(),
      configFile.path,
    );
    final graphPackages = <String, Map<String, Object?>>{};
    for (final entry in _objectList(graph['packages'])) {
      final name = '${entry['name'] ?? ''}';
      if (name.isNotEmpty) graphPackages[name] = entry;
    }
    final roots = <String, Directory>{};
    for (final entry in _objectList(config['packages'])) {
      final name = '${entry['name'] ?? ''}';
      final rootUri = '${entry['rootUri'] ?? ''}';
      if (name.isEmpty || rootUri.isEmpty) continue;
      final resolved = configFile.uri.resolve(rootUri);
      if (resolved.scheme != 'file') continue;
      roots[name] = Directory.fromUri(resolved).absolute;
    }

    final normalizedHost = path.normalize(hostRoot.absolute.path);
    String? hostName;
    for (final entry in roots.entries) {
      if (path.equals(path.normalize(entry.value.path), normalizedHost)) {
        hostName = entry.key;
        break;
      }
    }
    if (hostName == null || !graphPackages.containsKey(hostName)) {
      throw CCPackageWorkspaceException(
        'Host Package at "$normalizedHost" is absent from the resolved '
        'Package graph. Run Pub get from "${buildRoot.path}".',
      );
    }

    final closureNames = <String>{};
    void visit(String name) {
      if (!closureNames.add(name)) return;
      final package = graphPackages[name];
      if (package == null) {
        throw CCPackageWorkspaceException(
          'Package "$name" is referenced by the resolved graph but has no '
          'Package record. Run Pub get again.',
        );
      }
      for (final dependency in _stringList(package['dependencies'])) {
        visit(dependency);
      }
    }

    visit(hostName);
    final packages = <String, CCResolvedPackage>{};
    for (final name in closureNames.toList()..sort()) {
      final graphPackage = graphPackages[name]!;
      final root = roots[name];
      if (root == null) {
        throw CCPackageWorkspaceException(
          'Package "$name" has no root in package_config.json. Run Pub get '
          'again before generation.',
        );
      }
      final isHost = name == hostName;
      final writable =
          isHost ||
          (workspace &&
              path.isWithin(
                path.normalize(buildRoot.absolute.path),
                path.normalize(root.absolute.path),
              ) &&
              _usesWorkspaceResolution(root));
      packages[name] = CCResolvedPackage(
        name: name,
        version: '${graphPackage['version'] ?? '0.0.0'}',
        root: root,
        dependencies: List.unmodifiable(
          _stringList(
            graphPackage['dependencies'],
          ).where(closureNames.contains).toList()..sort(),
        ),
        devDependencies: List.unmodifiable(
          _stringList(graphPackage['devDependencies'])..sort(),
        ),
        writable: writable,
      );
    }
    return CCPackageWorkspace(
      buildRoot: buildRoot.absolute,
      host: packages[hostName]!,
      packages: Map.unmodifiable(packages),
    );
  }
}

/// Validated contents of one published `ccrouter_package.json` file.
final class CCPackageIndex {
  /// Creates an immutable Package index snapshot.
  CCPackageIndex({
    required this.packageName,
    required this.packageVersion,
    required this.contentFingerprint,
    this.bundleLibrary,
    this.bundleSymbol,
    required Iterable<CCPackageIndexDependency> dependencies,
    required Iterable<Map<String, Object?>> metadata,
    CCCapabilitySourceCatalog? capabilityCatalog,
  }) : dependencies = List.unmodifiable(dependencies),
       metadata = List.unmodifiable(metadata),
       capabilityCatalog =
           capabilityCatalog ??
           CCCapabilitySourceCatalog.fromMetadata(metadata);

  /// Package identity declared by the index.
  final String packageName;

  /// Package version declared by the index.
  final String packageVersion;

  /// SHA-256 digest of canonical Package inputs.
  final String contentFingerprint;

  /// Package-relative generated Dart Bundle entrypoint.
  final String? bundleLibrary;

  /// Top-level Bundle symbol exported by [bundleLibrary].
  final String? bundleSymbol;

  /// Whether this Package publishes a runtime Host Bundle.
  bool get hasRuntimeBundle => bundleLibrary != null && bundleSymbol != null;

  /// Direct generated dependency identities captured by this Package.
  final List<CCPackageIndexDependency> dependencies;

  /// Full normalized Builder metadata used for Host validation and docs.
  final List<Map<String, Object?>> metadata;

  /// Versioned, backend-neutral source inventory derived from [metadata].
  ///
  /// Tooling reads this precomputed view for fast search, while generation
  /// verifies it against metadata so stale or hand-edited records cannot be
  /// treated as source truth.
  final CCCapabilitySourceCatalog capabilityCatalog;

  /// Reads and validates one existing Package index against Pub resolution.
  static Future<CCPackageIndex> read(
    CCResolvedPackage package, {
    bool verifyBundle = true,
  }) async {
    final file = package.indexFile;
    if (!file.existsSync()) {
      throw CCPackageWorkspaceException(
        'CCRouter Package index is missing for read-only Package '
        '"${package.name}" at ${file.path}. Regenerate and publish that '
        'Package before consuming it.',
      );
    }
    final object = _decodeObject(await file.readAsString(), file.path);
    final schemaVersion = object['schemaVersion'];
    if (schemaVersion != 1 &&
        schemaVersion != ccrouterPackageIndexSchemaVersion) {
      throw CCPackageWorkspaceException(
        'Unsupported CCRouter Package index schema in ${file.path}: '
        '${object['schemaVersion']}. Expected '
        '1 or $ccrouterPackageIndexSchemaVersion.',
      );
    }
    final packageObject = object['package'];
    if (packageObject is! Map) {
      throw CCPackageWorkspaceException(
        'Invalid Package identity in ${file.path}.',
      );
    }
    final packageMap = packageObject.cast<String, Object?>();
    final bundleObject = object['bundle'];
    if (bundleObject != null && bundleObject is! Map) {
      throw CCPackageWorkspaceException(
        'Invalid generated Bundle descriptor in ${file.path}.',
      );
    }
    final bundleMap = bundleObject is Map
        ? bundleObject.cast<String, Object?>()
        : const <String, Object?>{};
    final bundleLibrary = '${bundleMap['library'] ?? ''}'.trim();
    final bundleSymbol = '${bundleMap['symbol'] ?? ''}'.trim();
    if ((bundleLibrary.isEmpty) != (bundleSymbol.isEmpty)) {
      throw CCPackageWorkspaceException(
        'Incomplete generated Bundle descriptor in ${file.path}.',
      );
    }
    final metadata = _objectList(object['metadata']);
    final derivedCatalog = CCCapabilitySourceCatalog.fromMetadata(metadata);
    CCCapabilitySourceCatalog? publishedCatalog;
    if (schemaVersion == ccrouterPackageIndexSchemaVersion) {
      final catalogObject = object['capabilityCatalog'];
      if (catalogObject is! Map) {
        throw CCPackageWorkspaceException(
          'Missing capability source catalog in ${file.path}.',
        );
      }
      try {
        publishedCatalog = CCCapabilitySourceCatalog.fromJson(
          catalogObject.cast<String, Object?>(),
        );
      } on FormatException catch (error) {
        throw CCPackageWorkspaceException(
          'Invalid capability source catalog in ${file.path}: '
          '${error.message}',
        );
      }
      if (computeCCCanonicalJsonFingerprint(publishedCatalog.toJson()) !=
          computeCCCanonicalJsonFingerprint(derivedCatalog.toJson())) {
        throw CCPackageWorkspaceException(
          'Capability source catalog mismatch in ${file.path}. The index is '
          'stale or was edited independently of its metadata.',
        );
      }
    }
    final index = CCPackageIndex(
      packageName: '${packageMap['name'] ?? ''}',
      packageVersion: '${packageMap['version'] ?? ''}',
      contentFingerprint: '${object['contentFingerprint'] ?? ''}',
      bundleLibrary: bundleLibrary.isEmpty ? null : bundleLibrary,
      bundleSymbol: bundleSymbol.isEmpty ? null : bundleSymbol,
      dependencies: _objectList(
        object['dependencies'],
      ).map(CCPackageIndexDependency.fromJson),
      metadata: metadata,
      capabilityCatalog: publishedCatalog ?? derivedCatalog,
    );
    if (index.packageName != package.name ||
        index.packageVersion != package.version) {
      throw CCPackageWorkspaceException(
        'Stale CCRouter Package index for "${package.name}": index records '
        '${index.packageName} ${index.packageVersion}, while Pub resolved '
        '${package.name} ${package.version}.',
      );
    }
    final expectedFingerprint = computeCCPackageFingerprint(
      packageName: index.packageName,
      packageVersion: index.packageVersion,
      bundleLibrary: index.bundleLibrary,
      bundleSymbol: index.bundleSymbol,
      dependencies: index.dependencies,
      metadata: index.metadata,
      includeCapabilityCatalog:
          schemaVersion == ccrouterPackageIndexSchemaVersion,
    );
    if (index.contentFingerprint != expectedFingerprint) {
      throw CCPackageWorkspaceException(
        'CCRouter Package index fingerprint mismatch for "${package.name}". '
        'The index is stale or corrupted.',
      );
    }
    if (verifyBundle) {
      final bundle = index.bundleLibrary == null
          ? null
          : File(path.join(package.root.path, index.bundleLibrary!));
      if (bundle != null && !bundle.existsSync()) {
        throw CCPackageWorkspaceException(
          'Generated Bundle for "${package.name}" is missing: ${bundle.path}.',
        );
      }
    }
    return index;
  }

  /// Encodes this index with stable key ordering and indentation.
  String toJson() =>
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'schemaVersion': ccrouterPackageIndexSchemaVersion,
        'generatorVersion': ccrouterPackageIndexGeneratorVersion,
        'package': <String, Object?>{'name': packageName, 'version': packageVersion},
        'contentFingerprint': contentFingerprint,
        'bundle': bundleLibrary == null ? null : <String, Object?>{'library': bundleLibrary, 'symbol': bundleSymbol},
        'dependencies': [for (final dependency in dependencies) dependency.toJson()],
        'metadata': metadata,
        'capabilityCatalog': capabilityCatalog.toJson(),
      })}\n';
}

/// Immutable generated identity for one direct Package dependency.
final class CCPackageIndexDependency {
  /// Creates a direct dependency identity.
  const CCPackageIndexDependency({
    required this.name,
    required this.version,
    required this.contentFingerprint,
  });

  /// Direct Pub dependency Package name.
  final String name;

  /// Resolved dependency version.
  final String version;

  /// Generated content digest expected by the dependant Bundle.
  final String contentFingerprint;

  /// Decodes a dependency identity from Package index JSON.
  factory CCPackageIndexDependency.fromJson(Map<String, Object?> json) =>
      CCPackageIndexDependency(
        name: '${json['name'] ?? ''}',
        version: '${json['version'] ?? ''}',
        contentFingerprint: '${json['contentFingerprint'] ?? ''}',
      );

  /// Encodes this dependency using canonical key order.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'version': version,
    'contentFingerprint': contentFingerprint,
  };
}

/// Content-addressed snapshot of one Package's Builder metadata.
final class CCPackageMetadataSnapshot {
  /// Creates an immutable metadata snapshot.
  CCPackageMetadataSnapshot({
    required this.fingerprint,
    required Iterable<Map<String, Object?>> documents,
    required this.cacheHit,
  }) : documents = List.unmodifiable(documents);

  /// SHA-256 digest covering relative file names and exact bytes.
  final String fingerprint;

  /// Parsed and test-filtered metadata documents in stable path order.
  final List<Map<String, Object?>> documents;

  /// Whether [documents] came from a matching persistent cache entry.
  final bool cacheHit;
}

/// Reads only Builder-owned metadata from an explicit build cache directory.
///
/// Exact bytes are always hashed. [cachedDocuments] are reused only when their
/// [cachedFingerprint] matches, so timestamp preservation or equal file sizes
/// cannot produce a false cache hit. Callers resolve [metadataDirectory] from
/// the active workspace; this function never falls back to Package sources.
Future<CCPackageMetadataSnapshot> readCCPackageMetadata(
  Directory metadataDirectory, {
  String? cachedFingerprint,
  Iterable<Map<String, Object?>>? cachedDocuments,
}) async {
  final directory = metadataDirectory;
  if (!directory.existsSync()) {
    final fingerprint = sha256.convert(const <int>[]).toString();
    return CCPackageMetadataSnapshot(
      fingerprint: fingerprint,
      documents: const [],
      cacheHit: cachedFingerprint == fingerprint && cachedDocuments != null,
    );
  }
  final files = <File>[];
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && _isCurrentPackageMetadataFile(entity, directory)) {
      files.add(entity);
    }
  }
  files.sort((left, right) => left.path.compareTo(right.path));
  final bytes = BytesBuilder(copy: false);
  final contents = <File, List<int>>{};
  for (final file in files) {
    final relative = path
        .relative(file.path, from: directory.path)
        .replaceAll(path.separator, '/');
    final fileBytes = await file.readAsBytes();
    contents[file] = fileBytes;
    bytes
      ..add(utf8.encode(relative))
      ..addByte(0)
      ..add(fileBytes)
      ..addByte(0);
  }
  final fingerprint = sha256.convert(bytes.takeBytes()).toString();
  if (cachedFingerprint == fingerprint && cachedDocuments != null) {
    return CCPackageMetadataSnapshot(
      fingerprint: fingerprint,
      documents: cachedDocuments,
      cacheHit: true,
    );
  }
  final metadata = <Map<String, Object?>>[];
  for (final file in files) {
    final document = _decodeObject(utf8.decode(contents[file]!), file.path);
    final source = '${document['source'] ?? ''}';
    if (source.startsWith('test/') ||
        source.startsWith('generator_test/') ||
        source.startsWith('integration_test/')) {
      continue;
    }
    metadata.add(document);
  }
  return CCPackageMetadataSnapshot(
    fingerprint: fingerprint,
    documents: metadata,
    cacheHit: false,
  );
}

/// Whether [file] is current metadata rather than a legacy nested artifact.
bool _isCurrentPackageMetadataFile(File file, Directory generatedDirectory) {
  final relative = path
      .relative(file.path, from: generatedDirectory.path)
      .replaceAll(path.separator, '/');
  return !relative.startsWith('metadata/') &&
      (relative.endsWith('.route.json') ||
          relative.endsWith('.component.json'));
}

/// Computes the canonical SHA-256 digest stored in a Package index and Bundle.
String computeCCPackageFingerprint({
  required String packageName,
  required String packageVersion,
  required String? bundleLibrary,
  required String? bundleSymbol,
  required Iterable<CCPackageIndexDependency> dependencies,
  required Iterable<Map<String, Object?>> metadata,
  bool includeCapabilityCatalog = true,
}) {
  final metadataList = metadata.toList();
  final normalized = _canonicalize(<String, Object?>{
    'package': <String, Object?>{
      'name': packageName,
      'version': packageVersion,
    },
    'bundle': bundleLibrary == null
        ? null
        : <String, Object?>{'library': bundleLibrary, 'symbol': bundleSymbol},
    'dependencies': [
      for (final dependency in dependencies) dependency.toJson(),
    ],
    'metadata': metadataList,
    if (includeCapabilityCatalog)
      'capabilityCatalog': CCCapabilitySourceCatalog.fromMetadata(
        metadataList,
      ).toJson(),
  });
  return computeCCCanonicalJsonFingerprint(normalized);
}

/// Computes a canonical SHA-256 digest for JSON-compatible cache data.
///
/// Map keys are sorted recursively while List ordering remains significant.
/// Tooling uses this to detect accidental cache corruption independently of
/// source metadata fingerprints.
String computeCCCanonicalJsonFingerprint(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(_canonicalize(value)))).toString();

/// Decodes one JSON object or raises a path-specific workspace error.
Map<String, Object?> _decodeObject(String source, String filePath) {
  try {
    final decoded = jsonDecode(source);
    if (decoded is Map) return decoded.cast<String, Object?>();
  } on FormatException catch (error) {
    throw CCPackageWorkspaceException(
      'Invalid JSON in $filePath: ${error.message}',
    );
  }
  throw CCPackageWorkspaceException('Expected a JSON object in $filePath.');
}

/// Converts loosely typed JSON arrays into typed object maps.
List<Map<String, Object?>> _objectList(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((entry) => entry.cast<String, Object?>())
          .toList()
    : <Map<String, Object?>>[];

/// Converts a loosely typed JSON array into String values.
List<String> _stringList(Object? value) => value is List
    ? value.whereType<Object>().map((entry) => '$entry').toList()
    : <String>[];

/// Whether a Package explicitly participates in its enclosing Dart workspace.
bool _usesWorkspaceResolution(Directory root) {
  final pubspec = File(path.join(root.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return false;
  return RegExp(
    r'^resolution\s*:\s*workspace\s*$',
    multiLine: true,
  ).hasMatch(pubspec.readAsStringSync());
}

/// Recursively normalizes JSON maps so semantically equal inputs hash equally.
Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) return value.map(_canonicalize).toList();
  return value;
}
