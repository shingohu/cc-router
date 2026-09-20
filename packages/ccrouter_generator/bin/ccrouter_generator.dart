import 'dart:convert';
import 'dart:io';

import 'package:ccrouter_generator/ccrouter_generator.dart';
import 'package:ccrouter_generator/src/package_workspace.dart';
import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as path;

final _dartFormatter = DartFormatter(
  languageVersion: DartFormatter.latestLanguageVersion,
);

/// Monotonic suffix preventing temporary output collisions within one process.
var _temporaryWriteSequence = 0;

Future<void> main(List<String> arguments) async {
  final totalWatch = Stopwatch()..start();
  final parsed = _parseArguments(arguments);
  if (parsed.help) {
    stdout.writeln(_usage);
    return;
  }
  if (parsed.error != null) {
    stderr.writeln('error: ${parsed.error}');
    stderr.writeln(_usage);
    exitCode = 2;
    return;
  }

  final root = Directory(parsed.rootPath).absolute;
  if (!root.existsSync()) {
    stderr.writeln('error: Scan root does not exist: ${root.path}');
    exitCode = 2;
    return;
  }
  final buildContext = parsed.command == _GeneratorCommand.generate
      ? _findBuildContext(root)
      : null;
  if (parsed.command == _GeneratorCommand.generate && buildContext == null) {
    stderr.writeln(
      'error: No standalone Package or enclosing Dart workspace was found '
      'for ${root.path}.',
    );
    exitCode = 2;
    return;
  }
  if (parsed.check &&
      parsed.outputDirectoryPath != null &&
      !_isWithin(
        buildContext!.root,
        Directory(parsed.outputDirectoryPath!).absolute,
      )) {
    stderr.writeln(
      'error: --check requires --output-dir to remain inside '
      '${buildContext.root.path}.',
    );
    exitCode = 2;
    return;
  }
  _GenerationLock? generationLock;
  _GeneratedArtifactsSnapshot? snapshot;
  try {
    if (buildContext != null) {
      generationLock = await _GenerationLock.acquire(buildContext.root);
    }
    snapshot = parsed.check
        ? await _GeneratedArtifactsSnapshot.capture(buildContext!.root)
        : null;
    final buildWatch = Stopwatch()..start();
    if (buildContext != null && !await _runBuildRunner(buildContext, root)) {
      if (snapshot != null) await snapshot.restore();
      exitCode = 1;
      return;
    }
    buildWatch.stop();
    final succeeded = parsed.command == _GeneratorCommand.generate
        ? await _generateResolvedWorkspace(
            root,
            parsed,
            buildContext!,
            buildDuration: buildWatch.elapsed,
          )
        : await _aggregate(root, parsed);
    if (!succeeded) {
      if (snapshot != null) await snapshot.restore();
      exitCode = 1;
      return;
    }
    if (snapshot != null) {
      final changes = await snapshot.changes();
      await snapshot.restore();
      if (changes.isNotEmpty) {
        stderr.writeln('error: CCRouter generated artifacts are stale:');
        for (final change in changes) {
          stderr.writeln('  $change');
        }
        exitCode = 1;
        return;
      }
      stdout.writeln('CCRouter generated artifacts are up to date.');
    }
  } on CCPackageWorkspaceException catch (error) {
    if (snapshot != null) await snapshot.restore();
    stderr.writeln('error: ${error.message}');
    exitCode = 1;
  } catch (_) {
    if (snapshot != null) await snapshot.restore();
    rethrow;
  } finally {
    await generationLock?.release();
    totalWatch.stop();
    if (parsed.profile) {
      stdout.writeln(
        'CCRouter profile total=${totalWatch.elapsedMilliseconds}ms',
      );
    }
  }
}

/// Aggregates current metadata into validated documentation and Host sources.
Future<bool> _aggregate(Directory root, _Arguments parsed) async {
  final outputDirectory = Directory(
    parsed.outputDirectoryPath ??
        '${root.path}${Platform.pathSeparator}ccrouter_generated',
  ).absolute;
  final metadataFiles = <_MetadataFile>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File ||
        (!entity.path.endsWith('.route.json') &&
            !entity.path.endsWith('.component.json'))) {
      continue;
    }
    if (entity.path.contains(
      '${Platform.pathSeparator}ccrouter_generated${Platform.pathSeparator}metadata${Platform.pathSeparator}',
    )) {
      continue;
    }
    if (entity.path.contains(
          '${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}',
        ) ||
        entity.path.contains(
          '${Platform.pathSeparator}build${Platform.pathSeparator}',
        )) {
      continue;
    }
    final decoded = jsonDecode(await entity.readAsString());
    if (decoded is Map) {
      final document = decoded.cast<String, Object?>();
      final source = '${document['source'] ?? ''}';
      if (source.startsWith('test/') ||
          source.startsWith('generator_test/') ||
          source.startsWith('integration_test/')) {
        continue;
      }
      metadataFiles.add(_MetadataFile(entity, document));
    }
  }
  final documents = metadataFiles.map((entry) => entry.document).toList();
  final result = CCRouteWorkspaceValidator.validate(documents);
  final errors = [
    ...result.errors,
    ...CCRouteBarrelExportValidator.validate(root, documents),
  ]..sort();
  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln('error: $error');
    }
    return false;
  }
  if (parsed.generateComponentRegistrars) {
    final catalogs = await _generateComponentRouteIndexes(metadataFiles);
    await _generateHostRouteCatalog(root, catalogs);
    await _deleteObsoleteAggregateOutputs(root, catalogs);
  }
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}${Platform.pathSeparator}cc_routes.json',
  ).writeAsString(result.machineDocumentJson);
  await File(
    '${outputDirectory.path}${Platform.pathSeparator}cc_routes.md',
  ).writeAsString(result.markdownDocument);
  await _removeLegacyMetadataArtifacts([
    Directory(path.join(root.path, 'ccrouter_generated')),
  ]);
  stdout.writeln(
    'Validated ${result.machineDocument['components'] is List ? (result.machineDocument['components']! as List).length : 0} components and ${result.machineDocument['routes'] is List ? (result.machineDocument['routes']! as List).length : 0} routes.',
  );
  return true;
}

const _usage = '''Usage:
  ccrouter generate [scan-root] [--output-dir <directory>] [--check] [--no-cache] [--profile]
  ccrouter aggregate [scan-root] [--output-dir <directory>] [--generate-component-registrars]

`generate` runs build_runner for the enclosing Dart workspace or package, then
validates metadata and writes component indexes, Host assembly, and route docs.
`--check` restores the original files and fails when generation would change a
CCRouter-managed artifact. `--no-cache` forces the reference full-parse path.
`--profile` reports phase timings and cache hits. `aggregate` preserves the
metadata-only legacy path.''';

/// Runs dependency-accurate Package generation for one resolved Host.
Future<bool> _generateResolvedWorkspace(
  Directory hostRoot,
  _Arguments parsed,
  _BuildContext buildContext, {
  required Duration buildDuration,
}) async {
  final discoveryWatch = Stopwatch()..start();
  CCPackageWorkspace workspace;
  try {
    workspace = await CCPackageWorkspace.load(
      buildRoot: buildContext.root,
      hostRoot: hostRoot,
      workspace: buildContext.workspace,
    );
  } on CCPackageWorkspaceException catch (error) {
    stderr.writeln('error: ${error.message}');
    return false;
  }
  discoveryWatch.stop();
  if (!workspace.host.dependencies.contains('ccrouter')) {
    stderr.writeln(
      'error: Host Package "${workspace.host.name}" must directly depend on '
      '`ccrouter` before generated Host assembly can be imported.',
    );
    return false;
  }

  final cache = parsed.noCache
      ? _GenerationCache.empty(buildContext.root)
      : await _GenerationCache.load(buildContext.root);
  if (cache.corrupted) {
    stdout.writeln(
      'CCRouter cache was invalid and has been ignored; running a full parse.',
    );
  }

  final parseWatch = Stopwatch()..start();
  final localMetadata = <String, List<Map<String, Object?>>>{};
  final metadataSnapshots = <String, CCPackageMetadataSnapshot>{};
  final externalIndexes = <String, CCPackageIndex>{};
  final participating = <String>{workspace.host.name};
  for (final package in workspace.packages.values) {
    if (package.writable) {
      final cached = parsed.noCache ? null : cache.entries[package.name];
      final snapshot = await readCCPackageMetadata(
        package,
        cachedFingerprint: cached?.fingerprint,
        cachedDocuments: cached?.documents,
      );
      metadataSnapshots[package.name] = snapshot;
      localMetadata[package.name] = snapshot.documents;
      if (snapshot.documents.isNotEmpty ||
          package.declaresGenerationIntent ||
          package.requiresPackageIndex ||
          package.indexFile.existsSync()) {
        participating.add(package.name);
      }
      continue;
    }
    if (package.indexFile.existsSync()) {
      try {
        final index = await CCPackageIndex.read(package);
        externalIndexes[package.name] = index;
        participating.add(package.name);
      } on CCPackageWorkspaceException catch (error) {
        stderr.writeln('error: ${error.message}');
        return false;
      }
    } else if (package.declaresGenerationIntent ||
        package.requiresPackageIndex) {
      stderr.writeln(
        'error: Read-only CCRouter Package "${package.name}" has no published '
        'lib/ccrouter_generated/ccrouter_package.json. Regenerate that '
        'Package before consuming it.',
      );
      return false;
    }
  }
  parseWatch.stop();

  final runtimeBundles = <String>{
    for (final entry in localMetadata.entries)
      if (_hasRuntimeContribution(entry.value)) entry.key,
    for (final entry in externalIndexes.entries)
      if (entry.value.hasRuntimeBundle) entry.key,
  };
  var changed = true;
  while (changed) {
    changed = false;
    for (final package in workspace.packages.values) {
      if (runtimeBundles.contains(package.name)) continue;
      if (!package.dependencies.any(runtimeBundles.contains)) continue;
      if (package.name != workspace.host.name &&
          !package.dependencies.contains('ccrouter')) {
        stderr.writeln(
          'error: Package "${package.name}" contains a transitive CCRouter '
          'runtime Package but cannot publish a forwarding Bundle because it '
          'does not directly depend on `ccrouter`. Add that dependency and '
          'regenerate the Package.',
        );
        return false;
      }
      if (!package.writable &&
          !(externalIndexes[package.name]?.hasRuntimeBundle ?? false)) {
        stderr.writeln(
          'error: Read-only Package "${package.name}" must publish a '
          'CCRouter Package index and forwarding Bundle for its transitive '
          'runtime components.',
        );
        return false;
      }
      runtimeBundles.add(package.name);
      participating.add(package.name);
      changed = true;
    }
  }
  runtimeBundles.add(workspace.host.name);

  final order = _dependencyOrder(workspace, participating);
  final indexes = <String, CCPackageIndex>{};
  for (final name in order) {
    final package = workspace.packages[name]!;
    if (!package.writable) {
      final index = externalIndexes[name];
      if (index == null) continue;
      indexes[name] = index;
      continue;
    }
    final dependencyIndexes = <CCPackageIndexDependency>[];
    for (final dependencyName in package.dependencies) {
      final dependency = indexes[dependencyName];
      if (dependency == null) continue;
      dependencyIndexes.add(
        CCPackageIndexDependency(
          name: dependency.packageName,
          version: dependency.packageVersion,
          contentFingerprint: dependency.contentFingerprint,
        ),
      );
    }
    dependencyIndexes.sort((left, right) => left.name.compareTo(right.name));
    final hasBundle = runtimeBundles.contains(name);
    final bundleLibrary = hasBundle ? 'lib/${name}_ccrouter.g.dart' : null;
    const bundleSymbol = 'ccrouterGeneratedPackageBundle';
    final metadata = localMetadata[name] ?? const <Map<String, Object?>>[];
    final fingerprint = computeCCPackageFingerprint(
      packageName: name,
      packageVersion: package.version,
      bundleLibrary: bundleLibrary,
      bundleSymbol: hasBundle ? bundleSymbol : null,
      dependencies: dependencyIndexes,
      metadata: metadata,
    );
    indexes[name] = CCPackageIndex(
      packageName: name,
      packageVersion: package.version,
      contentFingerprint: fingerprint,
      bundleLibrary: bundleLibrary,
      bundleSymbol: hasBundle ? bundleSymbol : null,
      dependencies: dependencyIndexes,
      metadata: metadata,
    );
  }

  for (final entry in externalIndexes.entries) {
    final package = workspace.packages[entry.key]!;
    final actual = {
      for (final dependency in entry.value.dependencies)
        dependency.name: dependency,
    };
    final expectedNames = package.dependencies
        .where(indexes.containsKey)
        .toSet();
    if (!actual.keys.toSet().containsAll(expectedNames) ||
        !expectedNames.containsAll(actual.keys)) {
      stderr.writeln(
        'error: Package index for "${entry.key}" has stale direct generated '
        'dependencies. Regenerate and republish that Package.',
      );
      return false;
    }
    for (final dependencyName in expectedNames) {
      final expected = indexes[dependencyName]!;
      final recorded = actual[dependencyName]!;
      if (recorded.version != expected.packageVersion ||
          recorded.contentFingerprint != expected.contentFingerprint) {
        stderr.writeln(
          'error: Package index for "${entry.key}" was generated against a '
          'different "$dependencyName" identity. Regenerate and republish '
          'that Package.',
        );
        return false;
      }
    }
  }

  final documents = <Map<String, Object?>>[
    for (final name in order) ...?indexes[name]?.metadata,
  ];
  final validationWatch = Stopwatch()..start();
  final validation = CCRouteWorkspaceValidator.validate(documents);
  final errors = [
    ...validation.errors,
    ...CCRouteBarrelExportValidator.validate(
      hostRoot,
      documents,
      packageRoots: {
        for (final package in workspace.packages.values)
          package.name: package.root,
      },
    ),
  ]..sort();
  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln('error: $error');
    }
    return false;
  }
  validationWatch.stop();

  final aggregateWatch = Stopwatch()..start();
  final localFiles = await _readWritableMetadataFiles(
    workspace.packages.values.where((package) => package.writable),
  );
  final catalogs = await _generateComponentRouteIndexes(
    localFiles,
    generateLegacyEntrypoints: false,
  );
  await _generateResolvedPackageBundles(
    workspace: workspace,
    indexes: indexes,
    runtimeBundles: runtimeBundles,
    catalogs: catalogs,
  );
  await _generateResolvedHostCatalog(workspace, indexes);
  for (final name in order) {
    final package = workspace.packages[name]!;
    final index = indexes[name];
    if (!package.writable || index == null) continue;
    await _writeIfChanged(package.indexFile, index.toJson());
  }
  await _writeCapabilitySourceCatalogs(
    workspace: workspace,
    indexes: indexes,
    hostDocuments: documents,
  );
  await _deleteObsoleteResolvedOutputs(
    workspace: workspace,
    runtimeBundles: runtimeBundles,
    catalogs: catalogs,
  );

  final outputDirectory = Directory(
    parsed.outputDirectoryPath ??
        path.join(hostRoot.path, 'ccrouter_generated'),
  ).absolute;
  await outputDirectory.create(recursive: true);
  await _writeIfChanged(
    File(path.join(outputDirectory.path, 'cc_routes.json')),
    validation.machineDocumentJson,
  );
  await _writeIfChanged(
    File(path.join(outputDirectory.path, 'cc_routes.md')),
    validation.markdownDocument,
  );
  await _removeLegacyMetadataArtifacts(
    workspace.packages.values
        .where((package) => package.writable)
        .map((package) => package.generatedDirectory),
  );
  stdout.writeln(
    'Validated ${validation.machineDocument['components'] is List ? (validation.machineDocument['components']! as List).length : 0} components and ${validation.machineDocument['routes'] is List ? (validation.machineDocument['routes']! as List).length : 0} routes across ${indexes.length} generated Packages.',
  );
  if (!parsed.noCache && !parsed.check) {
    await cache.write(metadataSnapshots);
  }
  aggregateWatch.stop();
  if (parsed.profile) {
    final hits = metadataSnapshots.values
        .where((snapshot) => snapshot.cacheHit)
        .length;
    stdout.writeln(
      'CCRouter profile build=${buildDuration.inMilliseconds}ms '
      'discovery=${discoveryWatch.elapsedMilliseconds}ms '
      'parse=${parseWatch.elapsedMilliseconds}ms '
      'validate=${validationWatch.elapsedMilliseconds}ms '
      'aggregate/format/write=${aggregateWatch.elapsedMilliseconds}ms '
      'cache=$hits/${metadataSnapshots.length}',
    );
  }
  return true;
}

/// Writes Package-local and Host-wide capability source discovery views.
///
/// The Host view merges its resolved dependency closure, while component and
/// contracts Packages retain a narrow local view suitable for code review.
/// Read-only Pub or Git dependencies are never modified.
Future<void> _writeCapabilitySourceCatalogs({
  required CCPackageWorkspace workspace,
  required Map<String, CCPackageIndex> indexes,
  required List<Map<String, Object?>> hostDocuments,
}) async {
  final hostCatalog = CCCapabilitySourceCatalog.fromMetadata(hostDocuments);
  for (final package in workspace.packages.values) {
    if (!package.writable) continue;
    final index = indexes[package.name];
    if (index == null) continue;
    final isHost = package.name == workspace.host.name;
    final catalog = isHost ? hostCatalog : index.capabilityCatalog;
    final output = File(
      path.join(package.root.path, 'ccrouter_generated', 'cc_sources.md'),
    );
    await _writeIfChanged(
      output,
      catalog.toMarkdown(
        scope: isHost
            ? 'host:${workspace.host.name}'
            : 'package:${package.name}',
      ),
    );
  }
}

/// Whether Package metadata declares at least one runtime component.
bool _hasRuntimeContribution(Iterable<Map<String, Object?>> documents) =>
    documents.any(
      (document) =>
          _strings(document['componentDeclarations']).isNotEmpty ||
          _objects(document['routeImplementations']).isNotEmpty,
    );

/// Returns participating Packages in dependency-before-dependant order.
List<String> _dependencyOrder(
  CCPackageWorkspace workspace,
  Set<String> participating,
) {
  final ordered = <String>[];
  final visited = <String>{};
  final visiting = <String>{};
  void visit(String name) {
    if (!participating.contains(name) || visited.contains(name)) return;
    if (!visiting.add(name)) {
      throw CCPackageWorkspaceException(
        'Resolved generated Package dependencies contain a cycle at "$name".',
      );
    }
    final dependencies = workspace.packages[name]!.dependencies.toList()
      ..sort();
    for (final dependency in dependencies) {
      visit(dependency);
    }
    visiting.remove(name);
    visited.add(name);
    ordered.add(name);
  }

  final names = participating.toList()..sort();
  for (final name in names) {
    visit(name);
  }
  return ordered;
}

/// Reads file-associated metadata only from writable resolved Packages.
Future<List<_MetadataFile>> _readWritableMetadataFiles(
  Iterable<CCResolvedPackage> packages,
) async {
  final result = <_MetadataFile>[];
  for (final package in packages) {
    final directory = package.generatedDirectory;
    if (!directory.existsSync()) continue;
    final files = <File>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File &&
          !path
              .relative(entity.path, from: directory.path)
              .replaceAll(path.separator, '/')
              .startsWith('metadata/') &&
          (entity.path.endsWith('.route.json') ||
              entity.path.endsWith('.component.json'))) {
        files.add(entity);
      }
    }
    files.sort((left, right) => left.path.compareTo(right.path));
    for (final file in files) {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) continue;
      final document = decoded.cast<String, Object?>();
      final source = '${document['source'] ?? ''}';
      if (source.startsWith('test/') ||
          source.startsWith('generator_test/') ||
          source.startsWith('integration_test/')) {
        continue;
      }
      result.add(_MetadataFile(file, document));
    }
  }
  return result;
}

/// Top-level operation selected by the CLI.
enum _GeneratorCommand {
  /// Reads existing metadata without invoking build_runner.
  aggregate,

  /// Runs build_runner before producing every aggregate artifact.
  generate,
}

final class _Arguments {
  const _Arguments({
    required this.command,
    required this.rootPath,
    required this.outputDirectoryPath,
    this.generateComponentRegistrars = false,
    this.check = false,
    this.noCache = false,
    this.profile = false,
    this.help = false,
    this.error,
  });

  /// Requested orchestration mode.
  final _GeneratorCommand command;

  /// Directory whose generated metadata is aggregated.
  final String rootPath;

  /// Optional override for aggregate JSON and Markdown output.
  final String? outputDirectoryPath;

  /// Whether component indexes and Host assembly are emitted.
  final bool generateComponentRegistrars;

  /// Whether generated file changes should fail without persisting them.
  final bool check;

  /// Whether persistent metadata cache reads and writes are disabled.
  final bool noCache;

  /// Whether phase timings and cache hit counts are printed.
  final bool profile;

  /// Whether command help was requested.
  final bool help;

  /// Argument validation failure, when parsing could not continue.
  final String? error;
}

/// Parses the unified command while retaining the previous aggregate syntax.
_Arguments _parseArguments(List<String> arguments) {
  var command = _GeneratorCommand.aggregate;
  var argumentStart = 0;
  if (arguments.isNotEmpty && arguments.first == 'generate') {
    command = _GeneratorCommand.generate;
    argumentStart = 1;
  } else if (arguments.isNotEmpty && arguments.first == 'aggregate') {
    argumentStart = 1;
  }
  var rootPath = Directory.current.path;
  String? outputDirectoryPath;
  var rootProvided = false;
  var generateComponentRegistrars = command == _GeneratorCommand.generate;
  var check = false;
  var noCache = false;
  var profile = false;

  for (var index = argumentStart; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--help' || argument == '-h') {
      return _Arguments(
        command: command,
        rootPath: '',
        outputDirectoryPath: null,
        help: true,
      );
    }
    if (argument == '--output-dir' || argument == '--output') {
      if (index + 1 >= arguments.length ||
          arguments[index + 1].startsWith('-')) {
        return _Arguments(
          command: command,
          rootPath: '',
          outputDirectoryPath: null,
          error: 'Missing value for --output-dir.',
        );
      }
      outputDirectoryPath = arguments[++index];
      continue;
    }
    if (argument == '--check') {
      check = true;
      continue;
    }
    if (argument == '--no-cache') {
      noCache = true;
      continue;
    }
    if (argument == '--profile') {
      profile = true;
      continue;
    }
    if (argument == '--generate-component-registrars') {
      generateComponentRegistrars = true;
      continue;
    }
    if (argument.startsWith('--output-dir=')) {
      outputDirectoryPath = argument.substring('--output-dir='.length);
      if (outputDirectoryPath.isEmpty) {
        return _Arguments(
          command: command,
          rootPath: '',
          outputDirectoryPath: null,
          error: 'Missing value for --output-dir.',
        );
      }
      continue;
    }
    if (argument.startsWith('-')) {
      return _Arguments(
        command: command,
        rootPath: '',
        outputDirectoryPath: null,
        error: 'Unknown option: $argument',
      );
    }
    if (rootProvided) {
      return _Arguments(
        command: command,
        rootPath: '',
        outputDirectoryPath: null,
        error: 'Only one scan root may be provided.',
      );
    }
    rootPath = argument;
    rootProvided = true;
  }

  if (check && command != _GeneratorCommand.generate) {
    return _Arguments(
      command: command,
      rootPath: '',
      outputDirectoryPath: null,
      error: '--check is only available with the generate command.',
    );
  }
  if ((noCache || profile) && command != _GeneratorCommand.generate) {
    return _Arguments(
      command: command,
      rootPath: '',
      outputDirectoryPath: null,
      error: '--no-cache and --profile are only available with generate.',
    );
  }

  return _Arguments(
    command: command,
    rootPath: rootPath,
    outputDirectoryPath: outputDirectoryPath,
    generateComponentRegistrars: generateComponentRegistrars,
    check: check,
    noCache: noCache,
    profile: profile,
  );
}

/// Build-runner root and mode selected from enclosing pubspec files.
final class _BuildContext {
  /// Creates the process context for a workspace or standalone package.
  const _BuildContext({required this.root, required this.workspace});

  /// Directory where build_runner resolves the package configuration.
  final Directory root;

  /// Whether build_runner must traverse every package in a Dart workspace.
  final bool workspace;
}

/// Process-wide filesystem lock serializing generation for one build root.
final class _GenerationLock {
  /// Creates a held lock around [file].
  const _GenerationLock._(this.file);

  /// Open lock file whose exclusive lock remains held for this instance.
  final RandomAccessFile file;

  /// Waits for and acquires the versioned CCRouter generation lock.
  static Future<_GenerationLock> acquire(Directory buildRoot) async {
    final lockFile = File(
      path.join(
        buildRoot.path,
        '.dart_tool',
        'ccrouter',
        'v1',
        'generation.lock',
      ),
    );
    await lockFile.parent.create(recursive: true);
    final file = await lockFile.open(mode: FileMode.append);
    await file.lock(FileLock.blockingExclusive);
    return _GenerationLock._(file);
  }

  /// Releases the exclusive lock and closes its file descriptor.
  Future<void> release() async {
    await file.unlock();
    await file.close();
  }
}

/// One content-addressed metadata cache entry.
final class _GenerationCacheEntry {
  /// Creates cached parsed documents for one exact metadata digest.
  const _GenerationCacheEntry({
    required this.fingerprint,
    required this.documents,
  });

  /// Exact metadata byte digest.
  final String fingerprint;

  /// Previously parsed documents reused only after digest equality.
  final List<Map<String, Object?>> documents;
}

/// Versioned, disposable acceleration cache for metadata JSON parsing.
///
/// Cache failure never changes generated behavior: malformed or incompatible
/// data is discarded and the caller performs the full reference parse.
final class _GenerationCache {
  /// Creates one cache view for [buildRoot].
  const _GenerationCache._({
    required this.buildRoot,
    required this.entries,
    required this.corrupted,
  });

  /// Build root owning this cache.
  final Directory buildRoot;

  /// Cached Package metadata keyed by resolved Package name.
  final Map<String, _GenerationCacheEntry> entries;

  /// Whether an existing cache was ignored because validation failed.
  final bool corrupted;

  /// Creates an empty cache without reading persistent state.
  factory _GenerationCache.empty(Directory buildRoot) => _GenerationCache._(
    buildRoot: buildRoot,
    entries: const {},
    corrupted: false,
  );

  /// Loads the current schema or returns a marked empty cache on any mismatch.
  static Future<_GenerationCache> load(Directory buildRoot) async {
    final file = _cacheFile(buildRoot);
    if (!file.existsSync()) return _GenerationCache.empty(buildRoot);
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map ||
          decoded['schemaVersion'] != 1 ||
          decoded['generatorVersion'] != ccrouterPackageIndexGeneratorVersion ||
          decoded['contentFingerprint'] is! String ||
          decoded['entries'] is! Map) {
        throw const FormatException('Unsupported cache schema.');
      }
      final payload = <String, Object?>{
        'schemaVersion': decoded['schemaVersion'],
        'generatorVersion': decoded['generatorVersion'],
        'entries': decoded['entries'],
      };
      if (computeCCCanonicalJsonFingerprint(payload) !=
          decoded['contentFingerprint']) {
        throw const FormatException('Cache fingerprint mismatch.');
      }
      final entries = <String, _GenerationCacheEntry>{};
      for (final entry in (decoded['entries']! as Map).entries) {
        if (entry.key is! String || entry.value is! Map) {
          throw const FormatException('Invalid cache entry.');
        }
        final value = (entry.value as Map).cast<String, Object?>();
        final fingerprint = value['fingerprint'];
        final documents = value['documents'];
        if (fingerprint is! String || documents is! List) {
          throw const FormatException('Invalid cached metadata.');
        }
        if (documents.any((document) => document is! Map)) {
          throw const FormatException('Invalid cached metadata document.');
        }
        entries[entry.key as String] = _GenerationCacheEntry(
          fingerprint: fingerprint,
          documents: documents
              .whereType<Map>()
              .map((document) => document.cast<String, Object?>())
              .toList(),
        );
      }
      return _GenerationCache._(
        buildRoot: buildRoot,
        entries: Map.unmodifiable(entries),
        corrupted: false,
      );
    } catch (_) {
      return _GenerationCache._(
        buildRoot: buildRoot,
        entries: const {},
        corrupted: true,
      );
    }
  }

  /// Atomically replaces cached entries with this successful generation run.
  Future<void> write(Map<String, CCPackageMetadataSnapshot> snapshots) async {
    final names = snapshots.keys.toList()..sort();
    final payload = <String, Object?>{
      'schemaVersion': 1,
      'generatorVersion': ccrouterPackageIndexGeneratorVersion,
      'entries': <String, Object?>{
        for (final name in names)
          name: <String, Object?>{
            'fingerprint': snapshots[name]!.fingerprint,
            'documents': snapshots[name]!.documents,
          },
      },
    };
    final contents =
        '${const JsonEncoder.withIndent('  ').convert({...payload, 'contentFingerprint': computeCCCanonicalJsonFingerprint(payload)})}\n';
    await _writeIfChanged(_cacheFile(buildRoot), contents);
  }

  /// Resolves the cache file without consulting mutable process state.
  static File _cacheFile(Directory buildRoot) => File(
    path.join(buildRoot.path, '.dart_tool', 'ccrouter', 'v1', 'cache.json'),
  );
}

/// Finds the build root while honoring a Package's workspace opt-in.
///
/// A standalone Package remains independent even when it is physically nested
/// below an unrelated workspace. Only `resolution: workspace` causes the
/// search to continue to an enclosing pubspec with a `workspace` declaration.
_BuildContext? _findBuildContext(Directory scanRoot) {
  Directory? nearestPackage;
  var requiresWorkspace = false;
  var current = scanRoot.absolute;
  while (true) {
    final pubspec = File(
      '${current.path}${Platform.pathSeparator}pubspec.yaml',
    );
    if (pubspec.existsSync()) {
      final contents = pubspec.readAsStringSync();
      if (nearestPackage == null) {
        nearestPackage = current;
        requiresWorkspace = RegExp(
          r'^resolution\s*:\s*workspace\s*$',
          multiLine: true,
        ).hasMatch(contents);
        if (!requiresWorkspace) {
          return _BuildContext(root: current, workspace: false);
        }
      }
      if (RegExp(r'^workspace\s*:', multiLine: true).hasMatch(contents)) {
        return _BuildContext(root: current, workspace: true);
      }
    }
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  return null;
}

/// Runs build_runner only for writable generator Packages in the Host closure.
///
/// Build filters include both `lib/` code and Package-root metadata outputs;
/// external path/Git/pub dependencies remain read-only and consume indexes.
Future<bool> _runBuildRunner(_BuildContext context, Directory hostRoot) async {
  final workspace = await CCPackageWorkspace.load(
    buildRoot: context.root,
    hostRoot: hostRoot,
    workspace: context.workspace,
  );
  final targets =
      workspace.packages.values
          .where(
            (package) => package.writable && package.declaresGenerationIntent,
          )
          .map((package) => package.name)
          .toList()
        ..sort();
  if (targets.isEmpty) {
    stdout.writeln(
      'No writable CCRouter Builder Packages were found; skipping build_runner.',
    );
    return true;
  }
  final targetRoots = <Directory>[
    for (final name in targets) workspace.packages[name]!.root,
  ];
  final protectedOutputs = await _GeneratedArtifactsSnapshot.captureOutside(
    context.root,
    targetRoots,
  );
  final arguments = <String>[
    'run',
    'build_runner',
    'build',
    if (context.workspace) '--workspace',
    for (final package in targets) ...[
      '--build-filter',
      'asset:$package/lib/**',
      '--build-filter',
      'asset:$package/ccrouter_generated/**',
    ],
  ];
  stdout.writeln(
    'Generating Package artifacts for ${targets.join(', ')} from '
    '${context.root.path}...',
  );
  late final int processExitCode;
  try {
    final process = await Process.start(
      Platform.resolvedExecutable,
      arguments,
      workingDirectory: context.root.path,
    );
    final forwarding = Future.wait<void>([
      stdout.addStream(process.stdout),
      stderr.addStream(process.stderr),
    ]);
    processExitCode = await process.exitCode;
    await forwarding;
  } finally {
    await protectedOutputs.restoreMissing();
  }
  if (processExitCode == 0) return true;
  stderr.writeln('error: build_runner failed with exit code $processExitCode.');
  return false;
}

/// Immutable content snapshot for every CCRouter-managed generated file.
final class _GeneratedArtifactsSnapshot {
  /// Captures exact bytes relative to [root] for later comparison or restore.
  const _GeneratedArtifactsSnapshot._(this.root, this.files);

  /// Root whose source-controlled CCRouter outputs are guarded.
  final Directory root;

  /// Original generated file bytes keyed by normalized relative path.
  final Map<String, List<int>> files;

  /// Reads the complete set of managed outputs below [root].
  static Future<_GeneratedArtifactsSnapshot> capture(Directory root) async =>
      _GeneratedArtifactsSnapshot._(
        root,
        await _readManagedGeneratedFiles(root),
      );

  /// Captures managed files outside [excludedRoots] for deletion protection.
  ///
  /// Workspace build_runner may invalidate stale outputs globally when a
  /// Builder changes even though build filters select only the Host closure.
  /// The protected snapshot prevents that cleanup from mutating unrelated
  /// Packages without treating those Packages as generation inputs.
  static Future<_GeneratedArtifactsSnapshot> captureOutside(
    Directory root,
    Iterable<Directory> excludedRoots,
  ) async {
    final normalizedRoots = excludedRoots
        .map((directory) => path.normalize(directory.absolute.path))
        .toList(growable: false);
    final files = await _readManagedGeneratedFiles(root);
    files.removeWhere((relative, _) {
      final absolute = path.normalize(_absolutePath(root, relative));
      return normalizedRoots.any(
        (excluded) =>
            path.equals(absolute, excluded) ||
            path.isWithin(excluded, absolute),
      );
    });
    return _GeneratedArtifactsSnapshot._(root, files);
  }

  /// Reports added, removed, or modified generated artifacts deterministically.
  Future<List<String>> changes() async {
    final current = await _readManagedGeneratedFiles(root);
    final paths = <String>{...files.keys, ...current.keys}.toList()..sort();
    return [
      for (final path in paths)
        if (!files.containsKey(path))
          'added: $path'
        else if (!current.containsKey(path))
          'removed: $path'
        else if (!_bytesEqual(files[path]!, current[path]!))
          'modified: $path',
    ];
  }

  /// Restores the guarded output set so `--check` remains read-only.
  Future<void> restore() async {
    final current = await _readManagedGeneratedFiles(root);
    for (final path in current.keys.where((path) => !files.containsKey(path))) {
      await File(_absolutePath(root, path)).delete();
    }
    for (final entry in files.entries) {
      final currentBytes = current[entry.key];
      if (currentBytes != null && _bytesEqual(entry.value, currentBytes)) {
        continue;
      }
      final file = File(_absolutePath(root, entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value, flush: true);
    }
  }

  /// Restores only captured files that disappeared during an external build.
  ///
  /// Existing files are never overwritten, so a concurrent developer edit is
  /// preserved. Newly created unrelated files are also left untouched.
  Future<void> restoreMissing() async {
    for (final entry in files.entries) {
      final file = File(_absolutePath(root, entry.key));
      if (file.existsSync()) continue;
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value, flush: true);
    }
  }
}

/// Reads managed generated outputs while excluding caches and build products.
Future<Map<String, List<int>>> _readManagedGeneratedFiles(
  Directory root,
) async {
  final files = <String, List<int>>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = _relativePath(root, entity);
    final segments = relative.split('/');
    if (segments.contains('.dart_tool') || segments.contains('build')) continue;
    final name = segments.last;
    if (!segments.contains('ccrouter_generated') &&
        !name.endsWith('_ccrouter.g.dart')) {
      continue;
    }
    files[relative] = await entity.readAsBytes();
  }
  return files;
}

/// Compares exact file bytes without retaining mutable aliases.
bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// Returns a normalized slash-separated path relative to [root].
String _relativePath(Directory root, File file) {
  return path
      .relative(file.absolute.path, from: root.absolute.path)
      .replaceAll(path.separator, '/');
}

/// Resolves a normalized relative generated path below [root].
String _absolutePath(Directory root, String relative) =>
    path.joinAll([root.absolute.path, ...relative.split('/')]);

/// Whether [candidate] is within [root], including the root itself.
bool _isWithin(Directory root, Directory candidate) {
  final rootPath = path.normalize(root.absolute.path);
  final candidatePath = path.normalize(candidate.absolute.path);
  return path.equals(candidatePath, rootPath) ||
      path.isWithin(rootPath, candidatePath);
}

/// Associates one generated metadata document with its source file on disk.
final class _MetadataFile {
  /// Creates a metadata record used by workspace validation and codegen.
  const _MetadataFile(this.file, this.document);

  /// Generated JSON file containing [document].
  final File file;

  /// Decoded component or route metadata payload.
  final Map<String, Object?> document;
}

/// Writes deterministic registration, Manifest, and route assembly per component.
Future<List<_GeneratedComponentCatalog>> _generateComponentRouteIndexes(
  Iterable<_MetadataFile> metadataFiles, {
  bool generateLegacyEntrypoints = true,
}) async {
  final componentSources = <String, _ComponentSource>{};
  final routes = <String, List<_RouteRegistration>>{};
  for (final metadata in metadataFiles) {
    final document = metadata.document;
    final package = '${document['package'] ?? ''}';
    final source = '${document['source'] ?? ''}';
    final componentManifests = document['componentManifests'];
    final manifestMap = componentManifests is Map
        ? componentManifests.cast<Object?, Object?>()
        : const <Object?, Object?>{};
    for (final component in _objects(document['components'])) {
      final id = '${component['id']}';
      if (_strings(document['componentDeclarations']).contains(id)) {
        componentSources[id] = _ComponentSource(
          package: package,
          source: source,
          manifest: '${manifestMap[id] ?? '${_camelIdentifier(id)}Manifest'}',
          metadataFile: metadata.file,
        );
      }
    }
    for (final route in _objects(document['routes'])) {
      final componentId = '${route['componentId'] ?? ''}';
      final contracts = route['contracts'];
      final routeContract = contracts is Map
          ? '${contracts['route'] ?? ''}'
          : '';
      final registration = '${route['registration'] ?? ''}'.trim().isEmpty
          ? _registrationFromContract(routeContract)
          : '${route['registration']}';
      final destination = route['destination'];
      final destinationMap = destination is Map
          ? destination.cast<Object?, Object?>()
          : const <Object?, Object?>{};
      if ('${route['registration'] ?? ''}'.trim().isEmpty &&
          destinationMap.isEmpty) {
        continue;
      }
      routes
          .putIfAbsent(componentId, () => [])
          .add(
            _RouteRegistration(
              package: package,
              source: source,
              routeId: '${route['id'] ?? ''}',
              registration: registration,
              descriptor:
                  '${destinationMap['descriptor'] ?? _descriptorFromContract(routeContract)}',
              builder:
                  '${destinationMap['builder'] ?? _builderFromContract(routeContract)}',
            ),
          );
    }
    for (final implementation in _objects(document['routeImplementations'])) {
      final destination = implementation['destination'];
      final destinationMap = destination is Map
          ? destination.cast<Object?, Object?>()
          : const <Object?, Object?>{};
      routes
          .putIfAbsent('${implementation['componentId'] ?? ''}', () => [])
          .add(
            _RouteRegistration(
              package: package,
              source: source,
              routeId: '${implementation['routeId'] ?? ''}',
              registration: '${implementation['registration'] ?? ''}',
              descriptor: '${destinationMap['descriptor'] ?? ''}',
              builder: '${destinationMap['builder'] ?? ''}',
            ),
          );
    }
  }

  final generatedCatalogs = <_GeneratedComponentCatalog>[];
  final componentIds = componentSources.keys.toList()..sort();
  for (final componentId in componentIds) {
    final component = componentSources[componentId];
    if (component == null) continue;
    final componentRoutes = routes[componentId] ?? <_RouteRegistration>[];
    componentRoutes.sort(_compareRoutes);
    final packageRoot = _findPackageRoot(component.metadataFile);
    if (packageRoot == null) continue;
    final outputDirectory = Directory(
      '${packageRoot.path}${Platform.pathSeparator}lib${Platform.pathSeparator}src${Platform.pathSeparator}ccrouter_generated',
    )..createSync(recursive: true);
    final output = File(
      '${outputDirectory.path}${Platform.pathSeparator}${_fileStem(componentId)}.routes.g.dart',
    );
    await output.writeAsString(
      _dartFormatter.format(
        _emitComponentRouteIndex(componentId, componentRoutes),
      ),
    );
    generatedCatalogs.add(
      _GeneratedComponentCatalog(
        componentId: componentId,
        package: component.package,
        packageRoot: packageRoot,
        registrarSource: component.source,
        manifest: component.manifest,
      ),
    );
  }
  if (generateLegacyEntrypoints) {
    await _generatePackageHostEntrypoints(generatedCatalogs);
  }
  return generatedCatalogs;
}

/// Generates a component registrar source with stable imports and ordering.
String _emitComponentRouteIndex(
  String componentId,
  List<_RouteRegistration> routes,
) {
  final className = _pascalIdentifier(componentId) + 'GeneratedRoutes';
  final constantName = '${className[0].toLowerCase()}${className.substring(1)}';
  final imports = <String, String>{};
  for (final route in routes) {
    imports.putIfAbsent(route.source, () => _sourceAlias(route.source));
  }
  final out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln('// ignore_for_file: type=lint, unused_element')
    ..writeln()
    ..writeln("import 'package:ccrouter/ccrouter.dart';")
    ..writeln("import 'package:ccrouter/ccrouter_host.dart';");
  for (final entry
      in imports.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key))) {
    final source = entry.key;
    final package = routes
        .firstWhere((route) => route.source == source)
        .package;
    out.writeln(
      "import 'package:$package/${source.substring('lib/'.length)}' as ${entry.value};",
    );
  }
  out
    ..writeln()
    ..writeln('/// Generated registration index for component `$componentId`.')
    ..writeln('final class $className {')
    ..writeln('  /// Creates the immutable component route index.')
    ..writeln('  const $className();')
    ..writeln()
    ..writeln(
      '  /// Registers every route owned by `$componentId` in stable order.',
    )
    ..writeln('  void register(CCRegistry registry) {');
  for (final route in routes) {
    final alias = imports[route.source]!;
    out
      ..writeln('    $alias.${route.registration}(')
      ..writeln('      registry,')
      ..writeln('    );');
  }
  out
    ..writeln('  }')
    ..writeln('}')
    ..writeln()
    ..writeln('/// Shared generated index used by the component Registrar.')
    ..writeln('const $constantName = $className();')
    ..writeln()
    ..writeln(
      '/// Backend-neutral Flutter destinations owned by `$componentId`.',
    )
    ..writeln(
      'final ${_camelIdentifier(componentId)}RouteCatalog = CCFlutterRouteCatalog([',
    );
  for (final route in routes) {
    final alias = imports[route.source]!;
    out
      ..writeln('  CCFlutterRouteDestination.fromDefinition(')
      ..writeln('    definition:')
      ..writeln('        $alias.${route.descriptor}(),')
      ..writeln('    builder: (arguments) =>')
      ..writeln('        $alias.${route.builder}(arguments),')
      ..writeln('  ),');
  }
  out
    ..writeln(']);')
    ..writeln();
  return out.toString();
}

/// Writes Package Bundles without importing any transitive Pub dependency.
Future<void> _generateResolvedPackageBundles({
  required CCPackageWorkspace workspace,
  required Map<String, CCPackageIndex> indexes,
  required Set<String> runtimeBundles,
  required Iterable<_GeneratedComponentCatalog> catalogs,
}) async {
  final catalogsByPackage = <String, List<_GeneratedComponentCatalog>>{};
  for (final catalog in catalogs) {
    catalogsByPackage.putIfAbsent(catalog.package, () => []).add(catalog);
  }
  for (final packageName in runtimeBundles.toList()..sort()) {
    final package = workspace.packages[packageName];
    final index = indexes[packageName];
    if (package == null || index == null || !package.writable) continue;
    final packageCatalogs = catalogsByPackage[packageName] ?? [];
    packageCatalogs.sort(
      (left, right) => left.componentId.compareTo(right.componentId),
    );
    final dependencyNames =
        package.dependencies.where(runtimeBundles.contains).toList()..sort();
    final out = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln('// ignore_for_file: type=lint')
      ..writeln()
      ..writeln('/// Host-only generated Package Bundle for `$packageName`.')
      ..writeln('library;')
      ..writeln()
      ..writeln(
        "import 'package:ccrouter/ccrouter_host.dart' "
        'show CCFlutterRouteCatalog, CCGeneratedPackageBundle;',
      );
    for (var index = 0; index < packageCatalogs.length; index++) {
      final catalog = packageCatalogs[index];
      out
        ..writeln(
          "import '${catalog.registrarSource.substring('lib/'.length)}' "
          'as component_$index;',
        )
        ..writeln(
          "import 'src/ccrouter_generated/${_fileStem(catalog.componentId)}.routes.g.dart' "
          'as component_routes_$index;',
        );
    }
    for (final dependencyName in dependencyNames) {
      final dependencyIndex = indexes[dependencyName]!;
      final library = dependencyIndex.bundleLibrary;
      if (library == null || !library.startsWith('lib/')) {
        throw CCPackageWorkspaceException(
          'Runtime dependency "$dependencyName" does not publish a valid '
          'Bundle library.',
        );
      }
      out.writeln(
        "import 'package:$dependencyName/${library.substring('lib/'.length)}' "
        'as dependency_${_snakeIdentifier(dependencyName)};',
      );
    }
    out
      ..writeln()
      ..writeln(
        '/// Generated runtime contribution and direct dependency graph for '
        '`$packageName`.',
      )
      ..writeln(
        'final ccrouterGeneratedPackageBundle = CCGeneratedPackageBundle(',
      )
      ..writeln("  packageName: '$packageName',")
      ..writeln("  packageVersion: '${package.version}',")
      ..writeln("  contentFingerprint: '${index.contentFingerprint}',")
      ..writeln('  componentManifests: [');
    for (var index = 0; index < packageCatalogs.length; index++) {
      out.writeln('    component_$index.${packageCatalogs[index].manifest},');
    }
    out
      ..writeln('  ],')
      ..writeln('  routeCatalog: CCFlutterRouteCatalog.merge([');
    for (var index = 0; index < packageCatalogs.length; index++) {
      out.writeln(
        '    component_routes_$index.${_camelIdentifier(packageCatalogs[index].componentId)}RouteCatalog,',
      );
    }
    out
      ..writeln('  ]),')
      ..writeln('  dependencies: [');
    for (final dependencyName in dependencyNames) {
      final dependencyIndex = indexes[dependencyName]!;
      out.writeln(
        '    dependency_${_snakeIdentifier(dependencyName)}.'
        '${dependencyIndex.bundleSymbol},',
      );
    }
    out
      ..writeln('  ],')
      ..writeln(');')
      ..writeln();
    await _writeIfChanged(
      package.bundleFile,
      _dartFormatter.format(out.toString()),
    );
  }
}

/// Writes the Host facade from only its own generated Package Bundle.
Future<void> _generateResolvedHostCatalog(
  CCPackageWorkspace workspace,
  Map<String, CCPackageIndex> indexes,
) async {
  final host = workspace.host;
  final hostIndex = indexes[host.name];
  if (hostIndex == null || !hostIndex.hasRuntimeBundle) {
    throw CCPackageWorkspaceException(
      'Host Package "${host.name}" has no generated runtime Bundle.',
    );
  }
  final output = File(
    path.join(
      host.root.path,
      'lib',
      'ccrouter_generated',
      'ccrouter_host.routes.g.dart',
    ),
  );
  final source = _dartFormatter.format('''
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

import 'package:ccrouter/ccrouter.dart' show CCComponentManifest;
import 'package:ccrouter/ccrouter_host.dart'
    show CCFlutterRouteCatalog, CCGeneratedPackageBundle;
import 'package:${host.name}/${host.name}_ccrouter.g.dart' as host_package;

/// Validated generated Package graph installed in this Host.
final ccrouterGeneratedHostAssembly = CCGeneratedPackageBundle.resolve([
  host_package.${hostIndex.bundleSymbol},
]);

/// All generated component Manifests installed in this Host.
final List<CCComponentManifest> ccrouterGeneratedComponentManifests =
    ccrouterGeneratedHostAssembly.componentManifests;

/// All generated component destinations installed in this Host.
final CCFlutterRouteCatalog ccrouterGeneratedRouteCatalog =
    ccrouterGeneratedHostAssembly.routeCatalog;
''');
  await _writeIfChanged(output, source);
}

/// Writes UTF-8 text only when its exact contents changed.
Future<bool> _writeIfChanged(File file, String contents) async {
  if (file.existsSync() && await file.readAsString() == contents) return false;
  await file.parent.create(recursive: true);
  final sequence = _temporaryWriteSequence++;
  final temporary = File('${file.path}.ccrouter.$pid.$sequence.tmp');
  final backup = File('${file.path}.ccrouter.$pid.$sequence.bak');
  await temporary.writeAsString(contents, flush: true);
  var committed = false;
  try {
    await temporary.rename(file.path);
    committed = true;
  } on FileSystemException {
    final hadOriginal = file.existsSync();
    if (hadOriginal) await file.rename(backup.path);
    try {
      await temporary.rename(file.path);
      committed = true;
    } catch (_) {
      if (file.existsSync()) await file.delete();
      if (backup.existsSync()) await backup.rename(file.path);
      rethrow;
    }
  } finally {
    if (temporary.existsSync()) await temporary.delete();
    if (committed && backup.existsSync()) await backup.delete();
  }
  return true;
}

/// Removes known outputs from the former nested `metadata/` directory.
///
/// Migration runs only after new outputs have been validated and written.
/// Unknown files are preserved and reported instead of deleting an entire
/// directory that may contain user-owned data.
Future<void> _removeLegacyMetadataArtifacts(
  Iterable<Directory> generatedDirectories,
) async {
  for (final generatedDirectory in generatedDirectories) {
    final legacyDirectory = Directory(
      path.join(generatedDirectory.path, 'metadata'),
    );
    if (!legacyDirectory.existsSync()) continue;
    final directories = <Directory>[legacyDirectory];
    final unknownFiles = <String>[];
    await for (final entity in legacyDirectory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Directory) {
        directories.add(entity);
        continue;
      }
      if (entity is! File) continue;
      if (_isLegacyMetadataArtifact(entity)) {
        await entity.delete();
      } else {
        unknownFiles.add(entity.path);
      }
    }
    directories.sort(
      (left, right) => right.path.length.compareTo(left.path.length),
    );
    for (final directory in directories) {
      if (directory.existsSync() && await directory.list().isEmpty) {
        await directory.delete();
      }
    }
    if (unknownFiles.isNotEmpty) {
      unknownFiles.sort();
      stderr.writeln(
        'warning: Preserved unknown files in legacy CCRouter metadata '
        'directory ${legacyDirectory.path}:',
      );
      for (final file in unknownFiles) {
        stderr.writeln('  $file');
      }
    }
  }
}

/// Whether [file] is an obsolete CCRouter-owned metadata or route-doc output.
bool _isLegacyMetadataArtifact(File file) {
  final name = path.basename(file.path);
  return name == 'cc_routes.json' ||
      name == 'cc_routes.md' ||
      name.endsWith('.route.json') ||
      name.endsWith('.route.md') ||
      name.endsWith('.component.json') ||
      name.endsWith('.component.md');
}

/// Deletes stale CLI aggregates only inside explicitly writable Packages.
Future<void> _deleteObsoleteResolvedOutputs({
  required CCPackageWorkspace workspace,
  required Set<String> runtimeBundles,
  required Iterable<_GeneratedComponentCatalog> catalogs,
}) async {
  final expected = <String>{
    path.normalize(
      path.join(
        workspace.host.root.path,
        'lib',
        'ccrouter_generated',
        'ccrouter_host.routes.g.dart',
      ),
    ),
    for (final packageName in runtimeBundles)
      if (workspace.packages[packageName]?.writable ?? false)
        path.normalize(workspace.packages[packageName]!.bundleFile.path),
    for (final catalog in catalogs)
      path.normalize(
        path.join(
          catalog.packageRoot.path,
          'lib',
          'src',
          'ccrouter_generated',
          '${_fileStem(catalog.componentId)}.routes.g.dart',
        ),
      ),
  };
  for (final package in workspace.packages.values.where(
    (package) => package.writable,
  )) {
    final candidates = <File>[];
    final generatedSource = Directory(
      path.join(package.root.path, 'lib', 'src', 'ccrouter_generated'),
    );
    if (generatedSource.existsSync()) {
      await for (final entity in generatedSource.list(
        recursive: false,
        followLinks: false,
      )) {
        if (entity is File && entity.path.endsWith('.routes.g.dart')) {
          candidates.add(entity);
        }
      }
    }
    final packageBundle = package.bundleFile;
    if (packageBundle.existsSync()) candidates.add(packageBundle);
    if (package.name == workspace.host.name) {
      final hostCatalog = File(
        path.join(
          package.root.path,
          'lib',
          'ccrouter_generated',
          'ccrouter_host.routes.g.dart',
        ),
      );
      if (hostCatalog.existsSync()) candidates.add(hostCatalog);
    }
    for (final candidate in candidates) {
      if (expected.contains(path.normalize(candidate.path))) continue;
      final contents = await candidate.readAsString();
      if (!_isCCRouterAggregateOutput(
        candidate.uri.pathSegments.last,
        contents,
      )) {
        continue;
      }
      await candidate.delete();
    }
  }
}

/// Writes one public Host-only integration library per component package.
Future<void> _generatePackageHostEntrypoints(
  Iterable<_GeneratedComponentCatalog> catalogs,
) async {
  final byPackage = <String, List<_GeneratedComponentCatalog>>{};
  for (final catalog in catalogs) {
    byPackage.putIfAbsent(catalog.package, () => []).add(catalog);
  }
  for (final entry in byPackage.entries) {
    final packageCatalogs = entry.value
      ..sort((left, right) => left.componentId.compareTo(right.componentId));
    final manifestSymbols = <String>{};
    final catalogSymbols = <String>{};
    for (final catalog in packageCatalogs) {
      if (!manifestSymbols.add(catalog.manifest) ||
          !catalogSymbols.add(
            '${_camelIdentifier(catalog.componentId)}RouteCatalog',
          )) {
        throw StateError(
          'Generated Host symbols collide in package "${entry.key}". '
          'Use component IDs with distinct Dart identifier forms.',
        );
      }
    }
    final output = File(
      '${packageCatalogs.first.packageRoot.path}${Platform.pathSeparator}lib${Platform.pathSeparator}${entry.key}_ccrouter.g.dart',
    );
    final out = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln()
      ..writeln(
        '/// Host-only generated component assembly for `${entry.key}`.',
      )
      ..writeln('library;')
      ..writeln();
    for (final catalog in packageCatalogs) {
      out
        ..writeln(
          "export '${catalog.registrarSource.substring('lib/'.length)}'",
        )
        ..writeln('    show ${catalog.manifest};')
        ..writeln(
          "export 'src/ccrouter_generated/${_fileStem(catalog.componentId)}.routes.g.dart'",
        )
        ..writeln(
          '    show ${_camelIdentifier(catalog.componentId)}RouteCatalog;',
        );
    }
    await output.writeAsString(_dartFormatter.format(out.toString()));
  }
}

/// Writes Host Manifest and route catalogs for all scanned components.
Future<void> _generateHostRouteCatalog(
  Directory root,
  Iterable<_GeneratedComponentCatalog> catalogs,
) async {
  final sorted = catalogs.toList()
    ..sort((left, right) => left.componentId.compareTo(right.componentId));
  final outputDirectory = Directory(
    '${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}ccrouter_generated',
  );
  await outputDirectory.create(recursive: true);
  final aliases = <String, String>{};
  for (final package in sorted.map((catalog) => catalog.package).toSet()) {
    aliases[package] = 'component_${_snakeIdentifier(package)}';
  }
  final out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln('// ignore_for_file: type=lint')
    ..writeln()
    ..writeln(
      "import 'package:ccrouter/ccrouter.dart' show CCComponentManifest;",
    )
    ..writeln("import 'package:ccrouter/ccrouter_host.dart';");
  for (final entry
      in aliases.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key))) {
    out.writeln(
      "import 'package:${entry.key}/${entry.key}_ccrouter.g.dart' as ${entry.value};",
    );
  }
  out
    ..writeln()
    ..writeln('/// All generated component Manifests installed in this Host.')
    ..writeln(
      'const ccrouterGeneratedComponentManifests = <CCComponentManifest>[',
    );
  for (final catalog in sorted) {
    out.writeln('  ${aliases[catalog.package]}.${catalog.manifest},');
  }
  out
    ..writeln('];')
    ..writeln()
    ..writeln(
      '/// All generated component destinations installed in this Host.',
    )
    ..writeln(
      'final ccrouterGeneratedRouteCatalog = CCFlutterRouteCatalog.merge([',
    );
  for (final catalog in sorted) {
    out.writeln(
      '  ${aliases[catalog.package]}.${_camelIdentifier(catalog.componentId)}RouteCatalog,',
    );
  }
  out
    ..writeln('], componentVersions: {')
    ..writeln('  for (final manifest in ccrouterGeneratedComponentManifests)')
    ..writeln('    manifest.id: manifest.version,')
    ..writeln('});')
    ..writeln();
  await File(
    '${outputDirectory.path}${Platform.pathSeparator}ccrouter_host.routes.g.dart',
  ).writeAsString(_dartFormatter.format(out.toString()));
}

/// Deletes obsolete aggregate indexes that no current component can own.
///
/// Only files with CCRouter-specific aggregate signatures and suffixes are
/// eligible. Builder-owned route Parts, handwritten sources, and another
/// generator's files remain untouched even if they share the standard header.
Future<void> _deleteObsoleteAggregateOutputs(
  Directory root,
  Iterable<_GeneratedComponentCatalog> catalogs,
) async {
  final expected = <String>{
    '${root.absolute.path}${Platform.pathSeparator}lib${Platform.pathSeparator}ccrouter_generated${Platform.pathSeparator}ccrouter_host.routes.g.dart',
  };
  for (final catalog in catalogs) {
    expected.add(
      '${catalog.packageRoot.absolute.path}${Platform.pathSeparator}lib${Platform.pathSeparator}src${Platform.pathSeparator}ccrouter_generated${Platform.pathSeparator}${_fileStem(catalog.componentId)}.routes.g.dart',
    );
    expected.add(
      '${catalog.packageRoot.absolute.path}${Platform.pathSeparator}lib${Platform.pathSeparator}${catalog.package}_ccrouter.g.dart',
    );
  }

  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final segments = _relativePath(root, entity).split('/');
    if (segments.contains('.dart_tool') || segments.contains('build')) continue;
    final name = entity.uri.pathSegments.last;
    if (!name.endsWith('.routes.g.dart') &&
        !name.endsWith('_ccrouter.g.dart')) {
      continue;
    }
    if (expected.contains(entity.absolute.path)) continue;
    final contents = await entity.readAsString();
    if (!_isCCRouterAggregateOutput(name, contents)) continue;
    await entity.delete();
  }
}

/// Recognizes only aggregate sources emitted by this CCRouter CLI.
bool _isCCRouterAggregateOutput(String name, String contents) {
  if (!contents.startsWith('// GENERATED CODE - DO NOT MODIFY BY HAND')) {
    return false;
  }
  if (name.endsWith('_ccrouter.g.dart')) {
    return contents.contains('Host-only generated component assembly for') ||
        contents.contains('Host-only generated Package Bundle for');
  }
  if (name == 'ccrouter_host.routes.g.dart') {
    return contents.contains('ccrouterGeneratedComponentManifests') &&
        contents.contains('ccrouterGeneratedRouteCatalog');
  }
  return name.endsWith('.routes.g.dart') &&
      contents.contains('Generated registration index for component');
}

/// Finds a package root by walking up from one metadata file.
Directory? _findPackageRoot(File metadataFile) {
  var directory = metadataFile.parent;
  while (true) {
    if (File(
      '${directory.path}${Platform.pathSeparator}pubspec.yaml',
    ).existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}

/// Returns a stable Dart import alias for one package-relative source path.
String _sourceAlias(String source) =>
    'route_${source.substring('lib/'.length).replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}';

/// Converts a component ID into a valid generated Dart class stem.
String _pascalIdentifier(String value) => value
    .split(RegExp(r'[^A-Za-z0-9]+'))
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join();

/// Converts a component ID into a lower-camel generated symbol stem.
String _camelIdentifier(String value) {
  final pascal = _pascalIdentifier(value);
  return '${pascal[0].toLowerCase()}${pascal.substring(1)}';
}

/// Converts a package name into a valid snake-style import alias.
String _snakeIdentifier(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');

/// Converts a component ID into a stable generated file stem.
String _fileStem(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

/// Derives a bridge name for metadata generated before the registration field.
String _registrationFromContract(String contract) {
  final name = contract
      .replaceFirst(RegExp(r'^_'), '')
      .replaceFirst(RegExp(r'Route$'), '');
  return 'ccrouterRegister${name}Route';
}

/// Derives a descriptor bridge name for metadata generated by older versions.
String _descriptorFromContract(String contract) {
  final name = contract
      .replaceFirst(RegExp(r'^_'), '')
      .replaceFirst(RegExp(r'Route$'), '');
  return 'ccrouterDescribe${name}Route';
}

/// Derives a page-builder bridge name for metadata generated by older versions.
String _builderFromContract(String contract) {
  final name = contract
      .replaceFirst(RegExp(r'^_'), '')
      .replaceFirst(RegExp(r'Route$'), '');
  return 'ccrouterBuild${name}Route';
}

/// Sorts route contributions independently of filesystem traversal order.
int _compareRoutes(_RouteRegistration left, _RouteRegistration right) {
  final source = left.source.compareTo(right.source);
  return source == 0 ? left.routeId.compareTo(right.routeId) : source;
}

/// Reads object arrays from loosely typed metadata safely.
Iterable<Map<String, Object?>> _objects(Object? value) sync* {
  if (value is! List) return;
  for (final item in value) {
    if (item is Map) yield item.cast<String, Object?>();
  }
}

/// Reads a string array from loosely typed metadata safely.
List<String> _strings(Object? value) => value is List
    ? value.whereType<Object>().map((item) => '$item').toList()
    : const [];

/// Describes the annotated component declaration that owns generated routes.
final class _ComponentSource {
  /// Creates a component source record.
  const _ComponentSource({
    required this.package,
    required this.source,
    required this.manifest,
    required this.metadataFile,
  });

  /// Package name used by generated package imports.
  final String package;

  /// Component registrar source path relative to `lib/`.
  final String source;

  /// Generated Manifest symbol exported through the package Host library.
  final String manifest;

  /// Metadata file used to locate the package root.
  final File metadataFile;
}

/// Describes one route contribution for a generated component index.
final class _RouteRegistration {
  /// Creates a normalized route contribution record.
  const _RouteRegistration({
    required this.package,
    required this.source,
    required this.routeId,
    required this.registration,
    required this.descriptor,
    required this.builder,
  });

  /// Package name used by generated package imports.
  final String package;

  /// Source library containing the generated registration bridge.
  final String source;

  /// Stable route ID used for deterministic sorting.
  final String routeId;

  /// Generated bridge symbol exposed only to package-internal code.
  final String registration;

  /// Generated bridge returning adapter-neutral route metadata.
  final String descriptor;

  /// Generated bridge decoding arguments and creating the Flutter page.
  final String builder;
}

/// Describes one generated component catalog and its public Host entrypoint.
final class _GeneratedComponentCatalog {
  /// Creates a generated catalog record used for package and Host aggregation.
  const _GeneratedComponentCatalog({
    required this.componentId,
    required this.package,
    required this.packageRoot,
    required this.registrarSource,
    required this.manifest,
  });

  /// Stable component identity used in generated symbol names.
  final String componentId;

  /// Dart package containing the generated component catalog.
  final String package;

  /// Package root where the Host integration library is written.
  final Directory packageRoot;

  /// Registrar library exported only through the generated Host entrypoint.
  final String registrarSource;

  /// Generated Manifest symbol consumed by the Host aggregate.
  final String manifest;
}
