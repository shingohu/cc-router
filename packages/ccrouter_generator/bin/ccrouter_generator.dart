import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:ccrouter_generator/ccrouter_generator.dart';
import 'package:ccrouter_generator/src/component_dependency_preflight.dart';
import 'package:ccrouter_generator/src/generated_client_naming.dart';
import 'package:ccrouter_generator/src/internal_api_boundary_validator.dart';
import 'package:ccrouter_generator/src/package_workspace.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import 'src/analyzer_bootstrap.dart';
import 'src/route_find.dart' as route_find;
import 'src/pub_hook.dart';
import 'src/scaffold.dart';

part 'src/build_plan.dart';
part 'src/generation_profile.dart';
part 'src/portable_generation_state.dart';

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

  if (parsed.command == _GeneratorCommand.pubHook) {
    await _runPubHookCommand(parsed.pubHookRequest!);
    return;
  }
  if (parsed.command == _GeneratorCommand.analyzer) {
    if (!await runAnalyzerBootstrapCommand(parsed.analyzerRequest!)) {
      exitCode = 1;
    }
    return;
  }

  final root = Directory(parsed.rootPath).absolute;
  if (!root.existsSync()) {
    stderr.writeln('error: Scan root does not exist: ${root.path}');
    exitCode = 2;
    return;
  }
  if (parsed.command == _GeneratorCommand.create) {
    try {
      final created = await createScaffold(
        kind: parsed.scaffoldKind!,
        name: parsed.scaffoldName!,
        root: root,
        withSubscriber: parsed.scaffoldWithSubscriber,
        withContract: parsed.scaffoldWithContract,
      );
      stdout.writeln(
        'Created ${parsed.scaffoldKind!.name} scaffold:\n'
        '${created.map((file) => '  ${file.path}').join('\n')}',
      );
      final steps = scaffoldCompletionSteps(
        kind: parsed.scaffoldKind!,
        root: root,
        createdFiles: created,
      );
      stdout.writeln(
        'Next steps:\n'
        '${steps.indexed.map((entry) => '  ${entry.$1 + 1}. ${entry.$2}').join('\n')}',
      );
    } on CCScaffoldException catch (error) {
      stderr.writeln('error: ${error.message}');
      exitCode = 1;
    }
    return;
  }
  final buildContext = parsed.command != _GeneratorCommand.aggregate
      ? _findBuildContext(root)
      : null;
  if (parsed.command != _GeneratorCommand.aggregate && buildContext == null) {
    stderr.writeln(
      'error: No standalone Package or enclosing Dart workspace was found '
      'for ${root.path}.',
    );
    exitCode = 2;
    return;
  }
  if (parsed.command == _GeneratorCommand.find) {
    try {
      if (!await route_find.findCapability(
        buildRoot: buildContext!.root,
        hostRoot: root,
        workspace: buildContext.workspace,
        query: parsed.query!,
        usageComponentId: parsed.usageComponentId,
      )) {
        exitCode = 1;
      }
    } on CCPackageWorkspaceException catch (error) {
      stderr.writeln('error: ${error.message}');
      exitCode = 1;
    } on FormatException catch (error) {
      stderr.writeln('error: ${error.message}');
      exitCode = 1;
    }
    return;
  }
  if (parsed.command == _GeneratorCommand.clean) {
    _GenerationLock? cleanLock;
    try {
      cleanLock = await _GenerationLock.acquire(buildContext!.root);
      if (!await _cleanResolvedWorkspace(root, buildContext)) {
        exitCode = 1;
      }
    } on CCPackageWorkspaceException catch (error) {
      stderr.writeln('error: ${error.message}');
      exitCode = 1;
    } finally {
      await cleanLock?.release();
      totalWatch.stop();
    }
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
  CCPackageWorkspace? fastPathWorkspace;
  String? verifiedInputFingerprint;
  _GenerationBuildPlanInspection? buildPlan;
  try {
    if (buildContext != null) {
      generationLock = await _GenerationLock.acquire(buildContext.root);
    }
    if (buildContext != null &&
        parsed.command == _GeneratorCommand.generate &&
        parsed.outputDirectoryPath == null) {
      fastPathWorkspace = await CCPackageWorkspace.load(
        buildRoot: buildContext.root,
        hostRoot: root,
        workspace: buildContext.workspace,
      );
      if (parsed.noCache) {
        verifiedInputFingerprint =
            await _GenerationStateFingerprint.captureInput(fastPathWorkspace);
        buildPlan = const _GenerationBuildPlanInspection.runBuilder(
          reasons: ['no-cache-reference'],
        );
      } else {
        final fastPath = await _GenerationFastPath.inspect(
          workspace: fastPathWorkspace,
        );
        verifiedInputFingerprint = fastPath.inputFingerprint;
        if (fastPath.matches) {
          stdout.writeln(
            'CCRouter generation fast path hit; inputs and outputs are unchanged.',
          );
          if (parsed.check) {
            stdout.writeln('CCRouter generated artifacts are up to date.');
          }
          if (parsed.profile) {
            stdout.writeln('CCRouter profile fast-path=hit');
            stdout.writeln(
              'CCRouter profile build-plan suggested=unchanged '
              'actual=unchanged reasons=verified-fast-path',
            );
            stdout.writeln('CCRouter profile input-delta=unchanged');
            _GenerationProfile.writeOutputs(const []);
          }
          return;
        }
        if (parsed.profile) stdout.writeln('CCRouter profile fast-path=miss');
        buildPlan = await _GenerationBuildPlanner.inspect(
          workspace: fastPathWorkspace,
          fastPathMissReason: fastPath.missReason,
          profile: parsed.profile,
        );
      }
      verifiedInputFingerprint ??=
          await _GenerationStateFingerprint.captureInput(fastPathWorkspace);
      if (parsed.profile) {
        stdout.writeln(buildPlan.profileDescription);
        stdout.writeln(
          'CCRouter profile input-delta=${jsonEncode(buildPlan.inputDelta ?? const {'status': 'unavailable'})}',
        );
      }
    }
    if (parsed.command == _GeneratorCommand.generate) {
      fastPathWorkspace ??= await CCPackageWorkspace.load(
        buildRoot: buildContext!.root,
        hostRoot: root,
        workspace: buildContext.workspace,
      );
      // build_runner cannot repair read-only dependency artifacts. Reject
      // stale external files before it sees missing generated libraries and
      // attempts incremental cleanup outside its writable build Packages.
      if (!await _CCPortableGenerationState.verifyReadOnly(fastPathWorkspace)) {
        exitCode = 1;
        return;
      }
      final preflightWatch = Stopwatch()..start();
      final issues = await _componentDependencyPreflight(fastPathWorkspace);
      preflightWatch.stop();
      if (parsed.profile) {
        stdout.writeln(
          'CCRouter profile dependency-preflight='
          '${preflightWatch.elapsedMilliseconds}ms',
        );
      }
      if (issues.isNotEmpty) {
        _writeComponentDependencyPreflightIssues(issues);
        exitCode = 1;
        return;
      }
    }
    final needsBootstrap =
        parsed.command == _GeneratorCommand.generate &&
        fastPathWorkspace != null &&
        await _hasMissingGeneratedComponentImport(fastPathWorkspace);
    snapshot = parsed.command == _GeneratorCommand.generate
        ? await _GeneratedArtifactsSnapshot.capture(
            buildContext!.root,
            explicitFiles: [
              if (parsed.outputDirectoryPath case final output?)
                for (final name in const [
                  'cc_routes.json',
                  'cc_catalog.md',
                  'cc_routes.md',
                  'cc_sources.md',
                ])
                  File(path.join(output, name)).absolute,
            ],
          )
        : null;
    if (needsBootstrap) {
      try {
        if (await _bootstrapGeneratedComponentApis(fastPathWorkspace)) {
          stdout.writeln(
            'Bootstrapped generated component APIs from validated build metadata.',
          );
        }
      } on Object {
        await snapshot!.restore();
      }
    }
    var buildDuration = Duration.zero;
    if (buildPlan?.runsBuilder ?? true) {
      final buildWatch = Stopwatch()..start();
      if (buildContext != null &&
          !await _runBuildRunner(buildContext, root, profile: parsed.profile)) {
        if (snapshot != null) await snapshot.restore();
        exitCode = 1;
        return;
      }
      buildWatch.stop();
      buildDuration = buildWatch.elapsed;
    } else {
      stdout.writeln(
        'CCRouter generation aggregate-only path; verified Builder inputs '
        'are unchanged.',
      );
    }
    final succeeded = parsed.command == _GeneratorCommand.generate
        ? await _generateResolvedWorkspace(
            root,
            parsed,
            buildContext!,
            buildDuration: buildDuration,
            prebuiltPackages:
                buildPlan?.actualPrebuiltPackages ?? const <String>{},
          )
        : await _aggregate(root, parsed);
    if (!succeeded) {
      if (snapshot != null) await snapshot.restore();
      exitCode = 1;
      return;
    }
    List<String>? outputChanges;
    if (parsed.profile && snapshot != null) {
      try {
        final watch = Stopwatch()..start();
        outputChanges = await snapshot.changes();
        _GenerationProfile.writeOutputs(outputChanges);
        stdout.writeln(
          'CCRouter profile output-delta-scan=${watch.elapsedMilliseconds}ms',
        );
      } on Object {
        stdout.writeln('CCRouter profile output-delta=unavailable');
      }
    }
    if (parsed.check && snapshot != null) {
      final changes = outputChanges ?? await snapshot.changes();
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
    if (buildContext != null &&
        parsed.command == _GeneratorCommand.generate &&
        parsed.outputDirectoryPath == null) {
      fastPathWorkspace ??= await CCPackageWorkspace.load(
        buildRoot: buildContext.root,
        hostRoot: root,
        workspace: buildContext.workspace,
      );
      await _GenerationFastPath.write(
        workspace: fastPathWorkspace,
        expectedInputFingerprint: verifiedInputFingerprint!,
      );
      try {
        await _GenerationBuildPlanner.write(
          workspace: fastPathWorkspace,
          expectedInputFingerprint: verifiedInputFingerprint,
        );
      } on Object {
        if (parsed.profile) {
          stdout.writeln(
            'CCRouter profile build-plan-state=write-failed; '
            'future runs will conservatively use runBuilder.',
          );
        }
      }
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

/// Executes an install, uninstall, status, or post-pub generation operation.
Future<void> _runPubHookCommand(CCPubHookRequest request) async {
  try {
    if (request.action == CCPubHookAction.run) {
      final projectRoot = Directory(
        request.projectRoot ?? Directory.current.path,
      ).absolute;
      if (!projectRoot.existsSync()) {
        stderr.writeln(
          'error: Pub hook project root does not exist: ${projectRoot.path}',
        );
        exitCode = 2;
        return;
      }
      if (!await runCCPubHook(
        projectRoot: projectRoot,
        pubCommand: request.pubCommand,
      )) {
        exitCode = 1;
      }
      return;
    }
    final sdk = CCPubHookManager.resolveSdk(request.sdkPath);
    final manager = CCPubHookManager(sdk);
    switch (request.action) {
      case CCPubHookAction.install:
        await manager.install();
      case CCPubHookAction.uninstall:
        await manager.uninstall();
      case CCPubHookAction.status:
        if (!manager.status()) exitCode = 1;
      case CCPubHookAction.run:
        throw StateError('The run action is handled above.');
    }
  } on Object catch (error) {
    stderr.writeln('error: $error');
    exitCode = 1;
  }
}

/// Aggregates current metadata into validated documentation and Host sources.
Future<bool> _aggregate(Directory root, _Arguments parsed) async {
  final outputDirectory = Directory(
    parsed.outputDirectoryPath ??
        path.join(root.path, 'lib', 'src', 'ccrouter_generated', 'metadata'),
  ).absolute;
  final metadataFiles = <_MetadataFile>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File ||
        (!entity.path.endsWith('.route.json') &&
            !entity.path.endsWith('.component.json') &&
            !entity.path.endsWith('.service.json') &&
            !entity.path.endsWith('.command.json') &&
            !entity.path.endsWith('.event.json') &&
            !entity.path.endsWith('.init_task.json'))) {
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
      final packageRoot = _findPackageRoot(entity);
      if (packageRoot == null) continue;
      metadataFiles.add(
        _MetadataFile(entity, document, packageRoot: packageRoot),
      );
    }
  }
  final documents = _resolvePackageComponentOwners(
    metadataFiles.map((entry) => entry.document),
  );
  final resolvedMetadataFiles = <_MetadataFile>[
    for (var index = 0; index < metadataFiles.length; index++)
      _MetadataFile(
        metadataFiles[index].file,
        documents[index],
        packageRoot: metadataFiles[index].packageRoot,
      ),
  ];
  final contractApiOutputs = await _generateContractApiEntrypoints(
    resolvedMetadataFiles,
  );
  CCRouteBarrelExportValidator.annotatePublicLibraries(
    documents,
    packageRoots: {
      for (final metadata in resolvedMetadataFiles)
        '${metadata.document['package'] ?? ''}': metadata.packageRoot,
    },
  );
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
    final catalogs = await _generateComponentRouteIndexes(
      resolvedMetadataFiles,
    );
    await _generateHostRouteCatalog(root, catalogs);
    await _deleteObsoleteAggregateOutputs(
      root,
      catalogs,
      contractApiOutputs: contractApiOutputs,
    );
  }
  await outputDirectory.create(recursive: true);
  await _writeIfChanged(
    File('${outputDirectory.path}${Platform.pathSeparator}cc_routes.json'),
    result.machineDocumentJson,
  );
  final sourceCatalog = CCCapabilitySourceCatalog.fromMetadata(
    documents,
  ).toMarkdown(scope: 'host:${root.uri.pathSegments.last}');
  await _writeIfChanged(
    File('${outputDirectory.path}${Platform.pathSeparator}cc_catalog.md'),
    _catalogMarkdown(
      routeCatalog: result.markdownDocument,
      initTaskCatalog: _initTaskDagMarkdown(documents),
      sourceCatalog: sourceCatalog,
    ),
  );
  await _deleteManagedCatalogFiles(outputDirectory, const [
    'cc_routes.md',
    'cc_sources.md',
  ]);
  await _removeLegacyMetadataArtifacts([
    Directory(path.join(root.path, 'ccrouter_generated')),
    Directory(path.join(root.path, 'lib', 'ccrouter_generated')),
  ]);
  await _removeEmptyGeneratedSourceDirectories(root);
  stdout.writeln(
    'Validated ${result.machineDocument['components'] is List ? (result.machineDocument['components']! as List).length : 0} components and ${result.machineDocument['routes'] is List ? (result.machineDocument['routes']! as List).length : 0} routes.',
  );
  return true;
}

/// Removes only CCRouter-owned source outputs from writable Packages.
///
/// The command deliberately leaves build_runner caches, user files below a
/// generated directory, read-only dependency Packages, and application build
/// products untouched. Run `generate` afterwards to recreate the source
/// catalogs and Dart glue.
Future<bool> _cleanResolvedWorkspace(
  Directory hostRoot,
  _BuildContext buildContext,
) async {
  final workspace = await CCPackageWorkspace.load(
    buildRoot: buildContext.root,
    hostRoot: hostRoot,
    workspace: buildContext.workspace,
  );
  var removed = 0;
  for (final package in workspace.packages.values.where(
    (package) => package.writable,
  )) {
    final generated = await _readManagedGeneratedFiles(package.root);
    for (final relative in generated.keys) {
      final file = File(_absolutePath(package.root, relative));
      if (!file.existsSync()) continue;
      await file.delete();
      removed++;
    }
    final legacyDirectories = [
      Directory(path.join(package.root.path, 'ccrouter_generated')),
      Directory(path.join(package.root.path, 'lib', 'ccrouter_generated')),
    ];
    final beforeLegacy = await _countExistingFiles(legacyDirectories);
    await _removeLegacyMetadataArtifacts(legacyDirectories);
    removed += beforeLegacy;
    await _removeEmptyGeneratedSourceDirectories(package.root);
  }
  stdout.writeln('Removed $removed CCRouter generated source artifact(s).');
  return true;
}

/// Counts files in legacy generated directories before migration cleanup.
Future<int> _countExistingFiles(Iterable<Directory> directories) async {
  var count = 0;
  for (final directory in directories) {
    if (!directory.existsSync()) continue;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && _isLegacyMetadataArtifact(entity)) count++;
    }
  }
  return count;
}

const _usage = '''Usage:
  ccrouter generate [scan-root] [--output-dir <directory>] [--check] [--no-cache] [--profile]
  ccrouter find <capability-id-or-route-pattern> [host-root] [--usage <component-id>]
  ccrouter clean [host-root]
  ccrouter aggregate [scan-root] [--output-dir <directory>] [--generate-component-registrars]
  ccrouter create component <package-name> [parent-directory]
  ccrouter create page <PageName> [component-directory]
  ccrouter create service <ServiceName> [component-directory]
  ccrouter create command <CommandName> [component-directory]
  ccrouter create event <EventName> [component-directory] [--with-subscriber]
  ccrouter create init-task <TaskName> [component-directory] [--with-contract]
  ccrouter analyzer status [host-root]
  ccrouter analyzer doctor [host-root]
  ccrouter analyzer install [host-root] [--source hosted|git] [--version <range>] [--url <git-url>] [--ref <full-sha>] [--git-path <package-path>] [--dry-run]
  ccrouter analyzer upgrade [host-root] [--version <range>] [--ref <full-sha>] [--dry-run]
  ccrouter analyzer uninstall [host-root] [--dry-run]
  ccrouter pub-hook install [--sdk <flutter-sdk-root>]
  ccrouter pub-hook uninstall [--sdk <flutter-sdk-root>]
  ccrouter pub-hook status [--sdk <flutter-sdk-root>]
  ccrouter pub-hook run --project-root <host-root> [--pub-command <command>]

`generate` runs build_runner for the enclosing Dart workspace or package, then
validates metadata and writes component indexes, Host assembly, and route docs.
`--check` restores the original files and fails when generation would change a
CCRouter-managed artifact. `--no-cache` forces the reference full-parse path.
`--profile` reports phase timings, build targets, cache hits, and dirty reasons.
`find` reads existing Package indexes without generating and matches exact
capability IDs or Route Pattern values. `--usage` adds a read-only integration
recipe for one existing consumer component; it never edits dependencies.
`clean` removes only CCRouter-owned source outputs in writable Packages; it
preserves build caches, read-only dependencies, and unknown user files.
`aggregate` preserves the metadata-only legacy path.
`analyzer status` inspects one Host-owned Analysis Server bootstrap without
modifying it. `analyzer doctor` additionally verifies its locked dependencies,
analysis, and loader compilation. Analyzer commands never run generation.
`analyzer install/upgrade/uninstall` manage only an explicitly selected Flutter
Host and CLI-owned files. Use `--dry-run` to preview without subprocesses or writes.
Hosted installs require an explicit published `--version`; Git installs require
a remote `--url` and full `--ref`. Existing manual bootstraps are never adopted.
`pub-hook install` wraps the selected SDK entrypoints with a reversible post-pub
and run/build preflight generator hook. Non-CCRouter projects are skipped. The
hook is not installed automatically and is not part of Flutter's internal tool
snapshot.
`create component <package-name> [parent-directory]` creates a new component
Package without overwriting existing files. `create page <PageName>
[component-directory]` creates an internal typed Route page. `create service`,
`create command`, `create event`, and `create init-task` create one internal
capability template in an existing component Package. Event Subscribers and
reusable InitTask Contracts are opt-in because they express additional behavior.
All scaffold commands
refuse to overwrite files and never modify Host dependencies or generated
output.''';

/// Runs dependency-accurate Package generation for one resolved Host.
Future<bool> _generateResolvedWorkspace(
  Directory hostRoot,
  _Arguments parsed,
  _BuildContext buildContext, {
  required Duration buildDuration,
  Set<String> prebuiltPackages = const <String>{},
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
  final internalApiErrors = CCGeneratedInternalApiBoundaryValidator.validate(
    workspace.packages.values,
  );
  if (internalApiErrors.isNotEmpty) {
    for (final error in internalApiErrors) {
      stderr.writeln('error: $error');
    }
    return false;
  }
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
  final portableVerifications = await _CCPortableGenerationState.verify(
    workspace,
    packageNames: {
      ...prebuiltPackages,
      for (final package in workspace.packages.values)
        if (!package.writable && package.requiresPackageIndex) package.name,
    },
  );
  for (final package in workspace.packages.values) {
    if (package.writable) {
      if (prebuiltPackages.contains(package.name)) {
        final verification = portableVerifications[package.name];
        if (verification == null || !verification.valid) {
          stderr.writeln(
            'error: Prebuilt CCRouter Package "${package.name}" no longer '
            'matches its Portable Generation State '
            '(${verification?.reason.name ?? 'missing'}). Rerun generation.',
          );
          return false;
        }
        try {
          final index = await CCPackageIndex.read(package);
          localMetadata[package.name] = _resolvePackageComponentOwners(
            index.metadata,
          );
          metadataSnapshots[package.name] = CCPackageMetadataSnapshot(
            fingerprint: verification.state!.metadataFingerprint,
            documents: index.metadata,
            cacheHit: false,
          );
          participating.add(package.name);
          continue;
        } on CCPackageWorkspaceException catch (error) {
          stderr.writeln('error: ${error.message}');
          return false;
        }
      }
      final cached = parsed.noCache ? null : cache.entries[package.name];
      final snapshot = await readCCPackageMetadata(
        workspace.intermediateMetadataDirectory(package),
        cachedFingerprint: cached?.fingerprint,
        cachedDocuments: cached?.documents,
      );
      metadataSnapshots[package.name] = snapshot;
      localMetadata[package.name] = _resolvePackageComponentOwners(
        snapshot.documents,
      );
      if (snapshot.documents.isNotEmpty ||
          package.declaresGenerationIntent ||
          package.requiresPackageIndex ||
          package.indexFile.existsSync()) {
        participating.add(package.name);
      }
      continue;
    }
    if (package.indexFile.existsSync()) {
      if (package.requiresPackageIndex) {
        final verification = portableVerifications[package.name];
        if (verification == null || !verification.valid) {
          stderr.writeln(
            'error: Read-only CCRouter Package "${package.name}" has an '
            'invalid Portable Generation State '
            '(${verification?.reason.name ?? 'missing'}). Regenerate and '
            'republish that Package before consuming it.',
          );
          return false;
        }
      }
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
        'lib/src/ccrouter_generated/metadata/ccrouter_package.json. Regenerate that '
        'Package before consuming it.',
      );
      return false;
    }
  }
  parseWatch.stop();

  final localMetadataFiles = <_MetadataFile>[
    for (final entry in localMetadata.entries)
      for (final document in entry.value)
        _MetadataFile(
          workspace.packages[entry.key]!.indexFile,
          document,
          packageRoot: workspace.packages[entry.key]!.root,
        ),
  ];
  final contractApiOutputs = await _generateContractApiEntrypoints(
    localMetadataFiles,
  );
  CCRouteBarrelExportValidator.annotatePublicLibraries(
    localMetadata.values.expand((documents) => documents),
    packageRoots: {
      for (final package in workspace.packages.values)
        if (package.writable) package.name: package.root,
    },
  );

  _annotateConsumerContractMetadata(
    localMetadata,
    externalIndexes.values.expand((index) => index.metadata),
  );

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
    final bundleLibrary = hasBundle
        ? 'lib/src/ccrouter_generated/host/${name}_ccrouter.g.dart'
        : null;
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

  final dirtySet = await _GenerationDirtySet.compute(
    workspace: workspace,
    cache: cache,
    snapshots: metadataSnapshots,
    indexes: indexes,
  );

  final localFiles = _resolveMetadataFiles([
    ...await _readWritableMetadataFiles(
      workspace,
      excludingPackages: prebuiltPackages,
    ),
    for (final packageName in prebuiltPackages)
      for (final document in localMetadata[packageName] ?? const [])
        _MetadataFile(
          workspace.packages[packageName]!.indexFile,
          document,
          packageRoot: workspace.packages[packageName]!.root,
        ),
  ]);

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
  final catalogs = await _generateComponentRouteIndexes(
    localFiles,
    generateLegacyEntrypoints: false,
    dirtyPackages: dirtySet.dirtyPackages,
  );
  await _generateResolvedPackageBundles(
    workspace: workspace,
    indexes: indexes,
    runtimeBundles: runtimeBundles,
    catalogs: catalogs,
    dirtyPackages: dirtySet.dirtyPackages,
  );
  await _generateResolvedHostCatalog(workspace, indexes);
  for (final name in order) {
    final package = workspace.packages[name]!;
    final index = indexes[name];
    if (!package.writable || index == null) continue;
    await _writeIfChanged(package.indexFile, index.toJson());
  }
  await _writePackageCapabilityCatalogs(
    workspace: workspace,
    indexes: indexes,
    dirtyPackages: dirtySet.dirtyPackages,
  );
  await _deleteObsoleteResolvedOutputs(
    workspace: workspace,
    runtimeBundles: runtimeBundles,
    catalogs: catalogs,
    contractApiOutputs: contractApiOutputs,
  );

  final outputDirectory = Directory(
    parsed.outputDirectoryPath ??
        path.join(
          hostRoot.path,
          'lib',
          'src',
          'ccrouter_generated',
          'metadata',
        ),
  ).absolute;
  await outputDirectory.create(recursive: true);
  await _writeIfChanged(
    File(path.join(outputDirectory.path, 'cc_routes.json')),
    validation.machineDocumentJson,
  );
  await _writeIfChanged(
    File(path.join(outputDirectory.path, 'cc_catalog.md')),
    _catalogMarkdown(
      routeCatalog: validation.markdownDocument,
      initTaskCatalog: _initTaskDagMarkdown(documents),
      sourceCatalog: CCCapabilitySourceCatalog.fromMetadata(
        documents,
      ).toMarkdown(scope: 'host:${workspace.host.name}'),
    ),
  );
  await _deleteManagedCatalogFiles(outputDirectory, const [
    'cc_routes.md',
    'cc_sources.md',
  ]);
  await _removeLegacyMetadataArtifacts(
    workspace.packages.values
        .where((package) => package.writable)
        .expand(
          (package) => [
            Directory(path.join(package.root.path, 'ccrouter_generated')),
            Directory(
              path.join(package.root.path, 'lib', 'ccrouter_generated'),
            ),
          ],
        ),
  );
  for (final package in workspace.packages.values.where(
    (package) => package.writable,
  )) {
    await _removeEmptyGeneratedSourceDirectories(package.root);
  }
  await _CCPortableGenerationState.write(workspace, indexes: indexes);
  stdout.writeln(
    'Validated ${validation.machineDocument['components'] is List ? (validation.machineDocument['components']! as List).length : 0} components and ${validation.machineDocument['routes'] is List ? (validation.machineDocument['routes']! as List).length : 0} routes across ${indexes.length} generated Packages.',
  );
  if (!parsed.noCache && !parsed.check) {
    final persistedOutputFingerprints = <String, String>{};
    for (final package in workspace.packages.values.where(
      (package) => package.writable,
    )) {
      persistedOutputFingerprints[package.name] =
          _GenerationStateFingerprint.digestEntries(
            await _GenerationStateFingerprint.capturePackageOutput(package),
          );
    }
    await cache.write(
      metadataSnapshots,
      outputFingerprints: persistedOutputFingerprints,
      dependencyFingerprints: dirtySet.dependencyFingerprints,
    );
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
      'cache=$hits/${metadataSnapshots.length} '
      'dirty=${dirtySet.dirtyPackages.length}/${workspace.packages.values.where((package) => package.writable).length}',
    );
    stdout.writeln(
      'CCRouter profile dirty-packages=${dirtySet.profileDescription}',
    );
  }
  return true;
}

/// Adds exact generated Contract requirements to local consumer metadata.
///
/// The source annotations intentionally stay small: consumers declare a typed
/// dependency and the generator copies the resolved owner's version and shape
/// fingerprint into metadata. This keeps handwritten code free of duplicated
/// compatibility strings while making stale generated output detectable.
void _annotateConsumerContractMetadata(
  Map<String, List<Map<String, Object?>>> localMetadata,
  Iterable<Map<String, Object?>> externalMetadata,
) {
  final allDocuments = <Map<String, Object?>>[
    for (final documents in localMetadata.values) ...documents,
    ...externalMetadata,
  ];
  final contracts = _collectContractRecordsFromMetadata(allDocuments);
  for (final documents in localMetadata.values) {
    for (final document in documents) {
      for (final component in _objects(document['components'])) {
        for (final dependency in _objects(component['serviceDependencies'])) {
          _copyConsumerContractFields(
            dependency,
            contracts['service:${dependency['id']}'],
          );
        }
        for (final dependency in _objects(component['commandDependencies'])) {
          _copyConsumerContractFields(
            dependency,
            contracts['command:${dependency['id']}'],
          );
        }
      }
      for (final subscription in _objects(document['eventSubscriptions'])) {
        _copyConsumerContractFields(
          subscription,
          contracts['event:${subscription['eventId']}'],
        );
      }
      for (final task in _objects(document['initTasks'])) {
        final dependencies = <Map<String, Object?>>[];
        for (final dependencyId in _strings(task['dependsOn'])) {
          final contract = contracts['initTask:$dependencyId'];
          if (contract == null) continue;
          dependencies.add(<String, Object?>{
            'id': dependencyId,
            'componentId': contract['componentId'],
            'requiredVersionRange': contract['version'],
            'requiredShapeFingerprint': contract['shapeFingerprint'],
          });
        }
        if (dependencies.isNotEmpty) {
          task['contractDependencies'] = dependencies;
        }
      }
    }
  }
}

Map<String, Map<String, Object?>> _collectContractRecordsFromMetadata(
  Iterable<Map<String, Object?>> documents,
) {
  final records = <String, Map<String, Object?>>{};
  const groups = <String, String>{
    'serviceContracts': 'service',
    'commandContracts': 'command',
    'eventContracts': 'event',
    'initTaskContracts': 'initTask',
  };
  for (final document in documents) {
    for (final entry in groups.entries) {
      for (final contract in _objects(document[entry.key])) {
        final id = '${contract['id'] ?? ''}';
        if (id.isNotEmpty) {
          records.putIfAbsent('${entry.value}:$id', () => contract);
        }
      }
    }
  }
  return records;
}

void _copyConsumerContractFields(
  Map<String, Object?> consumer,
  Map<String, Object?>? contract,
) {
  if (contract == null) return;
  consumer['requiredVersionRange'] ??= contract['version'];
  consumer['requiredShapeFingerprint'] ??= contract['shapeFingerprint'];
}

/// Writes non-empty Package-local capability discovery views.
///
/// The Host catalog is written separately because it combines route contracts
/// with the complete source index. Read-only Pub or Git dependencies are never
/// modified, and empty local catalogs are deleted instead of being published.
Future<void> _writePackageCapabilityCatalogs({
  required CCPackageWorkspace workspace,
  required Map<String, CCPackageIndex> indexes,
  required Set<String> dirtyPackages,
}) async {
  for (final package in workspace.packages.values) {
    if (!package.writable || package.name == workspace.host.name) continue;
    final index = indexes[package.name];
    if (index == null) continue;
    if (!dirtyPackages.contains(package.name)) continue;
    final catalog = index.capabilityCatalog;
    final output = File(
      path.join(
        package.root.path,
        'lib',
        'src',
        'ccrouter_generated',
        'metadata',
        'cc_catalog.md',
      ),
    );
    if (catalog.records.isEmpty) {
      if (output.existsSync()) await output.delete();
    } else {
      await _writeIfChanged(
        output,
        _catalogMarkdown(
          initTaskCatalog: _initTaskDagMarkdown(index.metadata),
          sourceCatalog: catalog.toMarkdown(scope: 'package:${package.name}'),
        ),
      );
    }
    await _deleteManagedCatalogFiles(
      Directory(
        path.join(
          package.root.path,
          'lib',
          'src',
          'ccrouter_generated',
          'metadata',
        ),
      ),
      const ['cc_sources.md'],
    );
  }
}

/// Combines machine-derived route and source views into one readable catalog.
String _catalogMarkdown({
  String? routeCatalog,
  String? initTaskCatalog,
  required String sourceCatalog,
}) {
  final out = StringBuffer('# CCRouter Catalog\n\n')
    ..writeln('Generated by `ccrouter_generator`. Do not edit by hand.\n');
  if (routeCatalog != null) {
    out
      ..writeln('## Route Definitions\n')
      ..writeln(_catalogBody(routeCatalog))
      ..writeln();
  }
  if (initTaskCatalog != null && initTaskCatalog.isNotEmpty) {
    out
      ..writeln('## Initialization DAG\n')
      ..writeln(initTaskCatalog)
      ..writeln();
  }
  out
    ..writeln('## Capability Sources\n')
    ..writeln(_catalogBody(sourceCatalog));
  return '${out.toString().trimRight()}\n';
}

/// Renders generated InitTask execution metadata as a deterministic DAG table.
String _initTaskDagMarkdown(Iterable<Map<String, Object?>> documents) {
  final tasks = <Map<String, Object?>>[
    for (final document in documents) ..._objects(document['initTasks']),
  ]..sort((left, right) => '${left['id']}'.compareTo('${right['id']}'));
  if (tasks.isEmpty) return '';
  final out = StringBuffer()
    ..writeln('| Task | Owner | Gate | Policy | Timeout | Depends on |')
    ..writeln('| --- | --- | --- | --- | --- | --- |');
  for (final task in tasks) {
    final timeout = task['timeoutMicroseconds'];
    final timeoutLabel = timeout is int ? '${timeout}us' : '-';
    final dependencies = _strings(task['dependsOn']);
    out.writeln(
      '| `${task['id']}` | `${task['componentId']}` | '
      '`${task['gateId']}` | `${task['failurePolicy']}` | $timeoutLabel | '
      '${dependencies.isEmpty ? '-' : dependencies.map((id) => '`$id`').join(', ')} |',
    );
  }
  return out.toString().trimRight();
}

/// Removes one generated document's top-level heading before nesting it.
String _catalogBody(String document) {
  final lines = document.trim().split('\n');
  if (lines.isNotEmpty && lines.first.startsWith('# ')) lines.removeAt(0);
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  return lines.join('\n').trimRight();
}

/// Deletes known obsolete catalog names inside one generated directory.
Future<void> _deleteManagedCatalogFiles(
  Directory directory,
  Iterable<String> names,
) async {
  for (final name in names) {
    final file = File(path.join(directory.path, name));
    if (!file.existsSync()) continue;
    final contents = await file.readAsString();
    if (!contents.startsWith('# CCRouter ')) continue;
    await file.delete();
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

/// Reads current file-associated metadata from writable build caches only.
Future<List<_MetadataFile>> _readWritableMetadataFiles(
  CCPackageWorkspace workspace, {
  Set<String> excludingPackages = const <String>{},
}) async {
  final result = <_MetadataFile>[];
  for (final package in workspace.packages.values.where(
    (package) => package.writable && !excludingPackages.contains(package.name),
  )) {
    final directory = workspace.intermediateMetadataDirectory(package);
    if (!directory.existsSync()) continue;
    final files = <File>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File &&
          (entity.path.endsWith('.route.json') ||
              entity.path.endsWith('.component.json') ||
              entity.path.endsWith('.service.json') ||
              entity.path.endsWith('.command.json') ||
              entity.path.endsWith('.event.json') ||
              entity.path.endsWith('.init_task.json'))) {
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
      result.add(_MetadataFile(file, document, packageRoot: package.root));
    }
  }
  return result;
}

/// Detects authored imports whose CLI-owned component API is currently absent.
///
/// Builder-owned Service APIs are excluded because build_runner already knows
/// their declared outputs. Route, Command, Event, and stable component API
/// barrels are CLI aggregates; restoring them before build_runner prevents a
/// clean rebuild from first resolving authored libraries against temporarily
/// missing imports.
Future<bool> _hasMissingGeneratedComponentImport(
  CCPackageWorkspace workspace,
) async {
  const cliApiSuffixes = <String>[
    '.route_api.g.dart',
    '.command_api.g.dart',
    '.event_api.g.dart',
    '.api.g.dart',
  ];
  for (final package in workspace.packages.values.where(
    (package) => package.writable && package.declaresGenerationIntent,
  )) {
    final lib = Directory(path.join(package.root.path, 'lib'));
    if (!lib.existsSync()) continue;
    await for (final entity in lib.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = _relativePath(package.root, entity);
      if (relative.split('/').contains('ccrouter_generated')) continue;
      final contents = await entity.readAsString();
      if (!contents.contains('ccrouter_generated/')) continue;
      final unit = parseString(
        content: contents,
        path: entity.path,
        featureSet: FeatureSet.latestLanguageVersion(),
      ).unit;
      for (final directive in unit.directives.whereType<UriBasedDirective>()) {
        final uriText = directive.uri.stringValue;
        if (uriText == null ||
            !uriText.contains('ccrouter_generated/') ||
            !cliApiSuffixes.any(uriText.endsWith)) {
          continue;
        }
        final target = _resolveImportedFile(
          workspace: workspace,
          source: entity,
          uriText: uriText,
        );
        if (target != null && !target.existsSync()) return true;
      }
    }
  }
  return false;
}

/// Resolves one relative or Package import without consulting Analyzer state.
File? _resolveImportedFile({
  required CCPackageWorkspace workspace,
  required File source,
  required String uriText,
}) {
  final uri = Uri.tryParse(uriText);
  if (uri == null) return null;
  if (uri.scheme.isEmpty) return File.fromUri(source.uri.resolveUri(uri));
  if (uri.scheme != 'package' || uri.pathSegments.length < 2) return null;
  final package = workspace.packages[uri.pathSegments.first];
  if (package == null) return null;
  return File(
    path.joinAll([package.root.path, 'lib', ...uri.pathSegments.skip(1)]),
  );
}

/// Restores only CLI-owned component aggregates from cached Builder metadata.
///
/// This bootstrap never replaces final generation. It exists solely so
/// build_runner resolves authored imports after `ccrouter clean`; the normal
/// post-build pipeline regenerates, validates, and removes outputs using the
/// current metadata before the command succeeds.
Future<bool> _bootstrapGeneratedComponentApis(
  CCPackageWorkspace workspace,
) async {
  var changed = await _bootstrapMissingContractApiPlaceholders(workspace);
  final files = await _readWritableMetadataFiles(workspace);
  if (files.isNotEmpty) {
    final resolved = _resolveMetadataFiles(files);
    await _generateContractApiEntrypoints(resolved);
    await _generateComponentRouteIndexes(
      resolved,
      generateLegacyEntrypoints: false,
    );
    changed = true;
  }
  return changed;
}

/// Creates empty managed Contract barrels only for explicit missing references.
///
/// This breaks the first-build cycle where an authored public barrel exports a
/// CLI aggregate that cannot be populated until build_runner emits metadata.
/// Final aggregation always replaces the placeholder before validation.
Future<bool> _bootstrapMissingContractApiPlaceholders(
  CCPackageWorkspace workspace,
) async {
  var changed = false;
  for (final package in workspace.packages.values.where(
    (package) => package.writable && package.declaresGenerationIntent,
  )) {
    final lib = Directory(path.join(package.root.path, 'lib'));
    if (!lib.existsSync()) continue;
    await for (final entity in lib.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = _relativePath(package.root, entity);
      if (relative.split('/').contains('ccrouter_generated')) continue;
      final contents = await entity.readAsString();
      if (!contents.contains('.contracts.api.g.dart')) continue;
      final unit = parseString(
        content: contents,
        path: entity.path,
        featureSet: FeatureSet.latestLanguageVersion(),
      ).unit;
      for (final directive in unit.directives.whereType<UriBasedDirective>()) {
        final uriText = directive.uri.stringValue;
        if (uriText == null || !uriText.endsWith('.contracts.api.g.dart')) {
          continue;
        }
        final target = _resolveImportedFile(
          workspace: workspace,
          source: entity,
          uriText: uriText,
        );
        if (target == null || target.existsSync()) continue;
        final generatedRoot = path.normalize(
          path.join(package.root.path, 'lib', 'src', 'ccrouter_generated'),
        );
        if (!path.isWithin(
          generatedRoot,
          path.normalize(target.absolute.path),
        )) {
          continue;
        }
        await _writeIfChanged(
          target,
          '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
          '// ignore_for_file: type=lint\n\n'
          '/// Stable generated Contract API entry point placeholder.\n',
        );
        changed = true;
      }
    }
  }
  return changed;
}

/// Top-level operation selected by the CLI.
enum _GeneratorCommand {
  /// Reads existing metadata without invoking build_runner.
  aggregate,

  /// Runs build_runner before producing every aggregate artifact.
  generate,

  /// Searches validated Package indexes without generating artifacts.
  find,

  /// Removes CCRouter-owned source artifacts from writable Packages.
  clean,

  /// Creates a new component or page source template.
  create,

  /// Installs or runs the post-pub generation hook.
  pubHook,

  /// Inspects or verifies one Host-owned Analysis Server bootstrap.
  analyzer,
}

/// Parsed inputs shared by generation, aggregation, and read-only lookup.
final class _Arguments {
  const _Arguments({
    required this.command,
    required this.rootPath,
    required this.outputDirectoryPath,
    this.query,
    this.usageComponentId,
    this.generateComponentRegistrars = false,
    this.check = false,
    this.noCache = false,
    this.profile = false,
    this.help = false,
    this.error,
    this.scaffoldKind,
    this.scaffoldName,
    this.scaffoldWithSubscriber = false,
    this.scaffoldWithContract = false,
    this.pubHookRequest,
    this.analyzerRequest,
  });

  /// Requested orchestration mode.
  final _GeneratorCommand command;

  /// Directory whose generated metadata is aggregated.
  final String rootPath;

  /// Optional override for aggregate JSON and Markdown output.
  final String? outputDirectoryPath;

  /// Exact capability ID or Route Pattern used only by `find`.
  final String? query;

  /// Existing consumer component used for a read-only integration recipe.
  final String? usageComponentId;

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

  /// Template kind selected by the `create` command.
  final CCScaffoldKind? scaffoldKind;

  /// Package or page name passed to the scaffold command.
  final String? scaffoldName;

  /// Whether an Event scaffold also emits one local Subscriber.
  final bool scaffoldWithSubscriber;

  /// Whether an InitTask scaffold emits a reusable typed Task Contract.
  final bool scaffoldWithContract;

  /// Parsed request for the pub hook command.
  final CCPubHookRequest? pubHookRequest;

  /// Parsed request for the Analyzer bootstrap command.
  final CCAnalyzerBootstrapRequest? analyzerRequest;
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
  } else if (arguments.isNotEmpty && arguments.first == 'find') {
    command = _GeneratorCommand.find;
    argumentStart = 1;
  } else if (arguments.isNotEmpty && arguments.first == 'clean') {
    command = _GeneratorCommand.clean;
    argumentStart = 1;
  } else if (arguments.isNotEmpty && arguments.first == 'create') {
    return _parseCreateArguments(arguments);
  } else if (arguments.isNotEmpty && arguments.first == 'pub-hook') {
    return _parsePubHookArguments(arguments);
  } else if (arguments.isNotEmpty && arguments.first == 'analyzer') {
    return _parseAnalyzerArguments(arguments);
  }
  var rootPath = Directory.current.path;
  String? outputDirectoryPath;
  var rootProvided = false;
  String? query;
  String? usageComponentId;
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
    if (argument == '--usage') {
      if (index + 1 >= arguments.length ||
          arguments[index + 1].startsWith('-')) {
        return _Arguments(
          command: command,
          rootPath: '',
          outputDirectoryPath: null,
          error: 'Missing value for --usage.',
        );
      }
      usageComponentId = arguments[++index];
      continue;
    }
    if (argument.startsWith('--usage=')) {
      usageComponentId = argument.substring('--usage='.length);
      if (usageComponentId.isEmpty) {
        return _Arguments(
          command: command,
          rootPath: '',
          outputDirectoryPath: null,
          error: 'Missing value for --usage.',
        );
      }
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
    if (command == _GeneratorCommand.find && query == null) {
      query = argument;
      continue;
    }
    rootPath = argument;
    rootProvided = true;
  }

  if (command == _GeneratorCommand.find && query == null) {
    return _Arguments(
      command: command,
      rootPath: '',
      outputDirectoryPath: null,
      error: 'find requires a capability ID or Route declared Pattern.',
    );
  }
  if (command == _GeneratorCommand.find &&
      (outputDirectoryPath != null ||
          generateComponentRegistrars ||
          check ||
          noCache ||
          profile)) {
    return _Arguments(
      command: command,
      rootPath: '',
      outputDirectoryPath: null,
      error: 'find accepts only a query and optional Host root.',
    );
  }
  if (usageComponentId != null && command != _GeneratorCommand.find) {
    return _Arguments(
      command: command,
      rootPath: '',
      outputDirectoryPath: null,
      error: '--usage is only available with the find command.',
    );
  }

  if (command == _GeneratorCommand.clean &&
      (outputDirectoryPath != null ||
          generateComponentRegistrars ||
          check ||
          noCache ||
          profile)) {
    return _Arguments(
      command: command,
      rootPath: '',
      outputDirectoryPath: null,
      error: 'clean accepts only an optional Host root.',
    );
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
    query: query,
    usageComponentId: usageComponentId,
    generateComponentRegistrars: generateComponentRegistrars,
    check: check,
    noCache: noCache,
    profile: profile,
  );
}

/// Parses explicit Host Analyzer commands; write options never apply to doctor.
_Arguments _parseAnalyzerArguments(List<String> arguments) {
  if (arguments.length < 2 ||
      arguments[1] == '--help' ||
      arguments[1] == '-h') {
    return const _Arguments(
      command: _GeneratorCommand.analyzer,
      rootPath: '',
      outputDirectoryPath: null,
      help: true,
    );
  }
  final action = switch (arguments[1]) {
    'status' => CCAnalyzerBootstrapAction.status,
    'doctor' => CCAnalyzerBootstrapAction.doctor,
    'install' => CCAnalyzerBootstrapAction.install,
    'upgrade' => CCAnalyzerBootstrapAction.upgrade,
    'uninstall' => CCAnalyzerBootstrapAction.uninstall,
    _ => null,
  };
  if (action == null) {
    return const _Arguments(
      command: _GeneratorCommand.analyzer,
      rootPath: '',
      outputDirectoryPath: null,
      error: 'analyzer requires status, doctor, install, upgrade or uninstall.',
    );
  }
  String? root;
  final options = <String, String>{};
  var dryRun = false;
  String? error;
  final allowed = switch (action) {
    CCAnalyzerBootstrapAction.install => {
      '--source',
      '--version',
      '--url',
      '--ref',
      '--git-path',
    },
    CCAnalyzerBootstrapAction.upgrade => {'--version', '--ref'},
    _ => <String>{},
  };
  for (var index = 2; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--dry-run' &&
        action != CCAnalyzerBootstrapAction.status &&
        action != CCAnalyzerBootstrapAction.doctor) {
      if (dryRun) error = 'Duplicate --dry-run.';
      dryRun = true;
    } else if (allowed.contains(argument)) {
      if (options.containsKey(argument) ||
          index + 1 >= arguments.length ||
          arguments[index + 1].startsWith('--')) {
        error = 'Missing or duplicate value for $argument.';
        break;
      }
      options[argument] = arguments[++index];
    } else if (argument.startsWith('-')) {
      error = 'Unsupported analyzer ${action.name} option: $argument';
      break;
    } else if (root != null) {
      error = 'analyzer accepts one action and one optional Host root.';
      break;
    } else {
      root = argument;
    }
  }
  root ??= Directory.current.path;
  return _Arguments(
    command: _GeneratorCommand.analyzer,
    rootPath: root,
    outputDirectoryPath: null,
    error: error,
    analyzerRequest: CCAnalyzerBootstrapRequest(
      action: action,
      hostRoot: root,
      source: options['--source'],
      version: options['--version'],
      url: options['--url'],
      ref: options['--ref'],
      gitPath: options['--git-path'],
      dryRun: dryRun,
    ),
  );
}

/// Parses the explicit SDK hook management command.
_Arguments _parsePubHookArguments(List<String> arguments) {
  if (arguments.length < 2 ||
      arguments[1] == '--help' ||
      arguments[1] == '-h') {
    return const _Arguments(
      command: _GeneratorCommand.pubHook,
      rootPath: '',
      outputDirectoryPath: null,
      help: true,
    );
  }
  final action = switch (arguments[1]) {
    'install' => CCPubHookAction.install,
    'uninstall' => CCPubHookAction.uninstall,
    'status' => CCPubHookAction.status,
    'run' => CCPubHookAction.run,
    _ => null,
  };
  if (action == null) {
    return const _Arguments(
      command: _GeneratorCommand.pubHook,
      rootPath: '',
      outputDirectoryPath: null,
      error: 'pub-hook requires `install`, `uninstall`, `status`, or `run`.',
    );
  }
  String? sdkPath;
  String? projectRoot;
  String? pubCommand;
  for (var index = 2; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--help' || argument == '-h') {
      return const _Arguments(
        command: _GeneratorCommand.pubHook,
        rootPath: '',
        outputDirectoryPath: null,
        help: true,
      );
    }
    String? value;
    String? option;
    if (argument == '--sdk' ||
        argument == '--project-root' ||
        argument == '--pub-command') {
      if (index + 1 >= arguments.length ||
          arguments[index + 1].startsWith('-')) {
        return const _Arguments(
          command: _GeneratorCommand.pubHook,
          rootPath: '',
          outputDirectoryPath: null,
          error: 'Missing value for pub-hook option.',
        );
      }
      option = argument;
      value = arguments[++index];
    } else if (argument.startsWith('--sdk=')) {
      option = '--sdk';
      value = argument.substring('--sdk='.length);
    } else if (argument.startsWith('--project-root=')) {
      option = '--project-root';
      value = argument.substring('--project-root='.length);
    } else if (argument.startsWith('--pub-command=')) {
      option = '--pub-command';
      value = argument.substring('--pub-command='.length);
    } else {
      return _Arguments(
        command: _GeneratorCommand.pubHook,
        rootPath: '',
        outputDirectoryPath: null,
        error: 'Unknown pub-hook option: $argument',
      );
    }
    if (value.isEmpty) {
      return const _Arguments(
        command: _GeneratorCommand.pubHook,
        rootPath: '',
        outputDirectoryPath: null,
        error: 'Pub-hook option values cannot be empty.',
      );
    }
    switch (option) {
      case '--sdk':
        sdkPath = value;
      case '--project-root':
        projectRoot = value;
      case '--pub-command':
        pubCommand = value;
    }
  }
  if (action == CCPubHookAction.run && projectRoot == null) {
    return const _Arguments(
      command: _GeneratorCommand.pubHook,
      rootPath: '',
      outputDirectoryPath: null,
      error: 'pub-hook run requires --project-root.',
    );
  }
  if (action != CCPubHookAction.run && projectRoot != null) {
    return const _Arguments(
      command: _GeneratorCommand.pubHook,
      rootPath: '',
      outputDirectoryPath: null,
      error: '--project-root is only available with pub-hook run.',
    );
  }
  return _Arguments(
    command: _GeneratorCommand.pubHook,
    rootPath: '',
    outputDirectoryPath: null,
    pubHookRequest: CCPubHookRequest(
      action: action,
      sdkPath: sdkPath,
      projectRoot: projectRoot,
      pubCommand: pubCommand,
    ),
  );
}

/// Parses the intentionally small, non-overwriting scaffold command surface.
_Arguments _parseCreateArguments(List<String> arguments) {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    return const _Arguments(
      command: _GeneratorCommand.create,
      rootPath: '',
      outputDirectoryPath: null,
      help: true,
    );
  }
  const kinds = <String>{
    'component',
    'page',
    'service',
    'command',
    'event',
    'init-task',
  };
  if (arguments.length < 3 || !kinds.contains(arguments[1])) {
    return const _Arguments(
      command: _GeneratorCommand.create,
      rootPath: '',
      outputDirectoryPath: null,
      error:
          'create requires `component`, `page`, `service`, `command`, `event`, or `init-task`.',
    );
  }
  final kind = switch (arguments[1]) {
    'component' => CCScaffoldKind.component,
    'page' => CCScaffoldKind.page,
    'service' => CCScaffoldKind.service,
    'command' => CCScaffoldKind.command,
    'event' => CCScaffoldKind.event,
    'init-task' => CCScaffoldKind.initTask,
    _ => throw StateError('Unsupported scaffold kind.'),
  };
  final name = arguments[2];
  var withSubscriber = false;
  var withContract = false;
  String? root;
  for (final argument in arguments.skip(3)) {
    if (argument == '--with-subscriber') {
      if (kind != CCScaffoldKind.event || withSubscriber) {
        return const _Arguments(
          command: _GeneratorCommand.create,
          rootPath: '',
          outputDirectoryPath: null,
          error: '--with-subscriber is available only once for `create event`.',
        );
      }
      withSubscriber = true;
      continue;
    }
    if (argument == '--with-contract') {
      if (kind != CCScaffoldKind.initTask || withContract) {
        return const _Arguments(
          command: _GeneratorCommand.create,
          rootPath: '',
          outputDirectoryPath: null,
          error:
              '--with-contract is available only once for `create init-task`.',
        );
      }
      withContract = true;
      continue;
    }
    if (argument.startsWith('-') || root != null) {
      return const _Arguments(
        command: _GeneratorCommand.create,
        rootPath: '',
        outputDirectoryPath: null,
        error:
            'create accepts one optional directory and only the documented template flags.',
      );
    }
    root = argument;
  }
  return _Arguments(
    command: _GeneratorCommand.create,
    rootPath: root ?? Directory.current.path,
    outputDirectoryPath: null,
    scaffoldKind: kind,
    scaffoldName: name,
    scaffoldWithSubscriber: withSubscriber,
    scaffoldWithContract: withContract,
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
    this.outputFingerprint,
    this.dependencyFingerprints = const <String, String>{},
  });

  /// Exact metadata byte digest.
  final String fingerprint;

  /// Previously parsed documents reused only after digest equality.
  final List<Map<String, Object?>> documents;

  /// Exact digest of CCRouter-owned source outputs from the last run.
  ///
  /// Older cache entries do not have this value and therefore conservatively
  /// classify the Package as dirty once before being reseeded.
  final String? outputFingerprint;

  /// Content fingerprints of direct generated dependencies from the last run.
  final Map<String, String> dependencyFingerprints;
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
          decoded['schemaVersion'] != 2 ||
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
        final outputFingerprint = value['outputFingerprint'];
        if (outputFingerprint != null && outputFingerprint is! String) {
          throw const FormatException('Invalid cached output fingerprint.');
        }
        final dependencyFingerprints = <String, String>{};
        final rawDependencies = value['dependencyFingerprints'];
        if (rawDependencies != null) {
          if (rawDependencies is! Map) {
            throw const FormatException('Invalid cached dependencies.');
          }
          for (final dependency in rawDependencies.entries) {
            if (dependency.key is! String || dependency.value is! String) {
              throw const FormatException('Invalid cached dependency.');
            }
            dependencyFingerprints[dependency.key as String] =
                dependency.value as String;
          }
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
          outputFingerprint: outputFingerprint as String?,
          dependencyFingerprints: Map.unmodifiable(dependencyFingerprints),
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
  Future<void> write(
    Map<String, CCPackageMetadataSnapshot> snapshots, {
    required Map<String, String> outputFingerprints,
    required Map<String, Map<String, String>> dependencyFingerprints,
  }) async {
    final names = snapshots.keys.toList()..sort();
    final payload = <String, Object?>{
      'schemaVersion': 2,
      'generatorVersion': ccrouterPackageIndexGeneratorVersion,
      'entries': <String, Object?>{
        for (final name in names)
          name: <String, Object?>{
            'fingerprint': snapshots[name]!.fingerprint,
            'documents': snapshots[name]!.documents,
            'outputFingerprint': outputFingerprints[name],
            'dependencyFingerprints':
                dependencyFingerprints[name] ?? const <String, String>{},
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

/// Content-verified shortcut for a completely unchanged generated workspace.
///
/// The manifest is disposable acceleration state. A missing, malformed, or
/// mismatched field always falls back to build_runner and full validation.
/// The reference `--no-cache` path never consults this manifest.
abstract final class _GenerationFastPath {
  /// Manifest schema invalidated whenever the covered input set changes.
  static const int _schemaVersion = 1;

  /// Inspects exact inputs first and avoids output work after an input change.
  static Future<_GenerationFastPathInspection> inspect({
    required CCPackageWorkspace workspace,
  }) async {
    final file = _manifestFile(workspace);
    if (!file.existsSync()) {
      return _GenerationFastPathInspection.miss(
        missReason: _GenerationFastPathMissReason.manifestMissing,
        inputFingerprint: await _GenerationStateFingerprint.captureInput(
          workspace,
        ),
      );
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return const _GenerationFastPathInspection.miss(
          missReason: _GenerationFastPathMissReason.manifestInvalid,
        );
      }
      final document = decoded.cast<String, Object?>();
      if (document['schemaVersion'] != _schemaVersion ||
          document['generatorVersion'] !=
              ccrouterPackageIndexGeneratorVersion ||
          document['hostPackage'] != workspace.host.name ||
          document['inputFingerprint'] is! String ||
          document['outputFingerprint'] is! String ||
          document['contentFingerprint'] is! String) {
        return const _GenerationFastPathInspection.miss(
          missReason: _GenerationFastPathMissReason.manifestInvalid,
        );
      }
      final payload = <String, Object?>{
        'schemaVersion': document['schemaVersion'],
        'generatorVersion': document['generatorVersion'],
        'hostPackage': document['hostPackage'],
        'inputFingerprint': document['inputFingerprint'],
        'outputFingerprint': document['outputFingerprint'],
      };
      if (computeCCCanonicalJsonFingerprint(payload) !=
          document['contentFingerprint']) {
        return const _GenerationFastPathInspection.miss(
          missReason: _GenerationFastPathMissReason.manifestInvalid,
        );
      }
      final cache = await _GenerationCache.load(workspace.buildRoot);
      if (cache.corrupted) {
        return const _GenerationFastPathInspection.miss(
          missReason: _GenerationFastPathMissReason.cacheInvalid,
        );
      }
      final input = await _GenerationStateFingerprint.captureInput(workspace);
      if (input != document['inputFingerprint']) {
        return _GenerationFastPathInspection.miss(
          missReason: _GenerationFastPathMissReason.inputChanged,
          inputFingerprint: input,
        );
      }
      final output = await _GenerationStateFingerprint.captureOutput(workspace);
      if (output != document['outputFingerprint']) {
        return _GenerationFastPathInspection.miss(
          missReason: _GenerationFastPathMissReason.outputChanged,
          inputFingerprint: input,
        );
      }
      return _GenerationFastPathInspection(
        matches: true,
        inputFingerprint: input,
      );
    } on Object {
      return const _GenerationFastPathInspection.miss(
        missReason: _GenerationFastPathMissReason.manifestInvalid,
      );
    }
  }

  /// Atomically records one successful full generation as the next baseline.
  static Future<void> write({
    required CCPackageWorkspace workspace,
    required String expectedInputFingerprint,
  }) async {
    final input = await _GenerationStateFingerprint.captureInput(workspace);
    if (input != expectedInputFingerprint) return;
    final output = await _GenerationStateFingerprint.captureOutput(workspace);
    final payload = <String, Object?>{
      'schemaVersion': _schemaVersion,
      'generatorVersion': ccrouterPackageIndexGeneratorVersion,
      'hostPackage': workspace.host.name,
      'inputFingerprint': input,
      'outputFingerprint': output,
    };
    final contents =
        '${const JsonEncoder.withIndent('  ').convert({...payload, 'contentFingerprint': computeCCCanonicalJsonFingerprint(payload)})}\n';
    await _writeIfChanged(_manifestFile(workspace), contents);
  }

  /// Uses a Host-specific filename so one workspace may generate several apps.
  static File _manifestFile(CCPackageWorkspace workspace) {
    final identity = computeCCCanonicalJsonFingerprint(<String, Object?>{
      'host': workspace.host.name,
      'root': path.relative(
        workspace.host.root.path,
        from: workspace.buildRoot.path,
      ),
    });
    return File(
      path.join(
        workspace.buildRoot.path,
        '.dart_tool',
        'ccrouter',
        'v1',
        'manifests',
        '$identity.json',
      ),
    );
  }
}

/// Result of one fail-closed generation-manifest inspection.
final class _GenerationFastPathInspection {
  /// Creates an inspection with an optional verified current input digest.
  const _GenerationFastPathInspection({
    required this.matches,
    required this.inputFingerprint,
  }) : missReason = null;

  /// Creates a miss when the manifest cannot be trusted or inputs differ.
  const _GenerationFastPathInspection.miss({
    required this.missReason,
    this.inputFingerprint,
  }) : matches = false;

  /// Whether both authoritative inputs and managed outputs are unchanged.
  final bool matches;

  /// Current input digest reusable after a full run, when it was computed.
  final String? inputFingerprint;

  /// Exact conservative reason the shortcut could not be trusted.
  final _GenerationFastPathMissReason? missReason;
}

/// Fail-closed reason supplied to the diagnostic Build Plan.
enum _GenerationFastPathMissReason {
  /// No previous successful manifest exists for this Host.
  manifestMissing,

  /// The manifest schema, fingerprint, or JSON could not be trusted.
  manifestInvalid,

  /// The metadata cache failed its independent integrity check.
  cacheInvalid,

  /// At least one generation input differs from the successful baseline.
  inputChanged,

  /// Managed output bytes differ despite unchanged input bytes.
  outputChanged,
}

/// Exact content digests for generation inputs and source-tree outputs.
abstract final class _GenerationStateFingerprint {
  /// Captures authored sources, resolution state, and generator implementation.
  static Future<String> captureInput(CCPackageWorkspace workspace) async {
    final inputs = <String, List<int>>{};
    // Use the same source/dependency/tool identities as full external Package
    // verification. In particular, a mutable transitive Path dependency can
    // sit outside the Host runtime closure and still affect generated code.
    final portable = await _CCPortableGenerationContext.capture(workspace);
    inputs['portable/authored'] = utf8.encode(
      computeCCCanonicalJsonFingerprint(portable.authoredFingerprints),
    );
    inputs['portable/resolution'] = utf8.encode(
      computeCCCanonicalJsonFingerprint(portable.resolutionFingerprints),
    );
    inputs['portable/tool'] = utf8.encode(portable.toolFingerprint);
    for (final package in workspace.packages.values) {
      if (!package.writable) {
        // An intact index/state cannot prove that its Dart outputs still
        // exist or match. Re-read every managed artifact before a cache hit.
        for (final entry in (await capturePackageOutput(package)).entries) {
          inputs['external/${package.name}/${entry.key}'] = entry.value;
        }
        await _addFile(
          inputs,
          'external/${package.name}/ccrouter_package.json',
          package.indexFile,
        );
        await _addFile(
          inputs,
          'external/${package.name}/${package.bundleFile.uri.pathSegments.last}',
          package.bundleFile,
        );
        await _addFile(
          inputs,
          'external/${package.name}/${_CCPortableGenerationState.fileName}',
          File(
            path.join(
              package.catalogDirectory.path,
              _CCPortableGenerationState.fileName,
            ),
          ),
        );
      }
    }
    await _addBuildStateInputs(inputs, workspace.buildRoot);
    inputs['tool/dart-version'] = utf8.encode(Platform.version);
    inputs['tool/dart-executable'] = utf8.encode(
      path.normalize(Platform.resolvedExecutable),
    );
    return _digestEntries(inputs);
  }

  /// Captures portable authored inputs for one resolved Package.
  static Future<String> capturePackageAuthoredInput(
    CCResolvedPackage package,
  ) async {
    final inputs = <String, List<int>>{};
    await _addAuthoredPackageInputs(inputs, package);
    return _digestEntries(inputs);
  }

  /// Captures generator source, build configuration, and Dart SDK identity.
  ///
  /// Unlike the process-local fast path, this digest intentionally excludes
  /// the absolute Dart executable path so equal clones can compare it.
  static Future<String> capturePortableToolInput(
    Map<String, Object?> resolutionIdentity,
  ) async {
    final inputs = <String, List<int>>{};
    await _addGeneratorInputs(inputs);
    inputs['tool/dart-version'] = utf8.encode(_portableDartVersion());
    inputs['tool/resolution'] = utf8.encode(
      computeCCCanonicalJsonFingerprint(resolutionIdentity),
    );
    return _digestEntries(inputs);
  }

  /// Captures every CCRouter-owned generated source-tree artifact.
  static Future<String> captureOutput(CCPackageWorkspace workspace) async {
    final outputs = <String, List<int>>{};
    for (final package in workspace.packages.values.where(
      (package) => package.writable,
    )) {
      final generated = await capturePackageOutput(package);
      for (final entry in generated.entries) {
        outputs['${package.name}/${entry.key}'] = entry.value;
      }
    }
    return _digestEntries(outputs);
  }

  /// Captures exact managed output bytes for one writable Package.
  static Future<Map<String, List<int>>> capturePackageOutput(
    CCResolvedPackage package,
  ) => _readManagedGeneratedFiles(package.root);

  /// Computes a deterministic digest for one logical byte map.
  static String digestEntries(Map<String, List<int>> entries) =>
      _digestEntries(entries);

  /// Adds generation-relevant authored files for one writable Package.
  static Future<void> _addAuthoredPackageInputs(
    Map<String, List<int>> inputs,
    CCResolvedPackage package,
  ) async {
    final lib = Directory(path.join(package.root.path, 'lib'));
    if (lib.existsSync()) {
      final files = <File>[];
      await for (final entity in lib.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final relative = _relativePath(package.root, entity);
        if (relative.split('/').contains('ccrouter_generated')) continue;
        files.add(entity);
      }
      files.sort((left, right) => left.path.compareTo(right.path));
      for (final file in files) {
        inputs['package/${package.name}/${_relativePath(package.root, file)}'] =
            await file.readAsBytes();
      }
    }
    for (final name in const ['pubspec.yaml', 'build.yaml', 'ccrouter.yaml']) {
      await _addFile(
        inputs,
        'package/${package.name}/$name',
        File(path.join(package.root.path, name)),
      );
    }
  }

  /// Adds Pub graph state that governs Package discovery and dependencies.
  static Future<void> _addBuildStateInputs(
    Map<String, List<int>> inputs,
    Directory buildRoot,
  ) async {
    for (final relative in const [
      'pubspec.yaml',
      'pubspec.lock',
      '.dart_tool/package_config.json',
      '.dart_tool/package_graph.json',
    ]) {
      await _addFile(
        inputs,
        'build/$relative',
        File(path.joinAll([buildRoot.path, ...relative.split('/')])),
      );
    }
  }

  /// Adds local generator code so same-version path edits cannot false-hit.
  static Future<void> _addGeneratorInputs(Map<String, List<int>> inputs) async {
    final library = await Isolate.resolvePackageUri(
      Uri.parse('package:ccrouter_generator/ccrouter_generator.dart'),
    );
    if (library == null || library.scheme != 'file') return;
    final root = File.fromUri(library).parent.parent;
    for (final directoryName in const ['lib', 'bin']) {
      final directory = Directory(path.join(root.path, directoryName));
      if (!directory.existsSync()) continue;
      final files = <File>[];
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File && entity.path.endsWith('.dart')) files.add(entity);
      }
      files.sort((left, right) => left.path.compareTo(right.path));
      for (final file in files) {
        inputs['generator/${_relativePath(root, file)}'] = await file
            .readAsBytes();
      }
    }
    for (final name in const ['pubspec.yaml', 'build.yaml']) {
      await _addFile(
        inputs,
        'generator/$name',
        File(path.join(root.path, name)),
      );
    }
  }

  /// Adds [file] only when it exists; absence remains part of the file set.
  static Future<void> _addFile(
    Map<String, List<int>> files,
    String identity,
    File file,
  ) async {
    if (file.existsSync()) files[identity] = await file.readAsBytes();
  }

  /// Hashes logical names and exact bytes without trusting timestamps or sizes.
  static String _digestEntries(Map<String, List<int>> entries) {
    final names = entries.keys.toList()..sort();
    final bytes = BytesBuilder(copy: false);
    for (final name in names) {
      bytes
        ..add(utf8.encode(name))
        ..addByte(0)
        ..add(entries[name]!)
        ..addByte(0);
    }
    return sha256.convert(bytes.takeBytes()).toString();
  }
}

/// Classifies writable Packages whose aggregate output can be reused safely.
///
/// The set is deliberately conservative. A Package is dirty when its Builder
/// metadata, managed source outputs, or direct dependency Index fingerprint
/// changed. Dirty state then propagates through the workspace dependency graph
/// so a consumer is regenerated when an upstream generated contract changes.
final class _GenerationDirtySet {
  /// Computes dirty Packages and current state used to seed the next cache.
  static Future<_GenerationDirtySet> compute({
    required CCPackageWorkspace workspace,
    required _GenerationCache cache,
    required Map<String, CCPackageMetadataSnapshot> snapshots,
    required Map<String, CCPackageIndex> indexes,
  }) async {
    final dirty = <String>{};
    final reasons = <String, Set<String>>{};
    void markDirty(String packageName, String reason) {
      dirty.add(packageName);
      (reasons[packageName] ??= <String>{}).add(reason);
    }

    markDirty(workspace.host.name, 'host');
    final outputFingerprints = <String, String>{};
    final dependencyFingerprints = <String, Map<String, String>>{};
    for (final package in workspace.packages.values.where(
      (package) => package.writable,
    )) {
      final output = await _GenerationStateFingerprint.capturePackageOutput(
        package,
      );
      outputFingerprints[package.name] =
          _GenerationStateFingerprint.digestEntries(output);
      final dependencies = <String, String>{};
      for (final dependencyName in package.dependencies) {
        final dependency = indexes[dependencyName];
        if (dependency != null) {
          dependencies[dependencyName] = dependency.contentFingerprint;
        }
      }
      dependencyFingerprints[package.name] = Map.unmodifiable(dependencies);
      final previous = cache.entries[package.name];
      final snapshot = snapshots[package.name];
      if (previous == null) {
        markDirty(package.name, 'cache-missing');
      } else {
        if (snapshot == null || previous.fingerprint != snapshot.fingerprint) {
          markDirty(package.name, 'metadata');
        }
        if (previous.outputFingerprint != outputFingerprints[package.name]) {
          markDirty(package.name, 'output');
        }
        if (!_sameStringMap(previous.dependencyFingerprints, dependencies)) {
          markDirty(package.name, 'dependency-index');
        }
      }
    }

    // Any changed dependency can alter a generated Bundle or public API. The
    // reverse closure is safer than trying to infer which declaration changed.
    var changed = true;
    while (changed) {
      changed = false;
      for (final package in workspace.packages.values.where(
        (package) => package.writable,
      )) {
        if (dirty.contains(package.name)) continue;
        final dirtyDependencies =
            package.dependencies.where(dirty.contains).toList()..sort();
        if (dirtyDependencies.isNotEmpty) {
          markDirty(
            package.name,
            'propagated-from:${dirtyDependencies.join('+')}',
          );
          changed = true;
        }
      }
    }
    final immutableDependencyFingerprints = <String, Map<String, String>>{
      for (final entry in dependencyFingerprints.entries)
        entry.key: Map.unmodifiable(entry.value),
    };
    return _GenerationDirtySet._(
      dirtyPackages: Set.unmodifiable(dirty),
      reasons: Map.unmodifiable({
        for (final entry in reasons.entries)
          entry.key: Set.unmodifiable(entry.value),
      }),
      outputFingerprints: Map.unmodifiable(outputFingerprints),
      dependencyFingerprints: Map.unmodifiable(immutableDependencyFingerprints),
    );
  }

  const _GenerationDirtySet._({
    required this.dirtyPackages,
    required this.reasons,
    required this.outputFingerprints,
    required this.dependencyFingerprints,
  });

  /// Writable Packages that must regenerate source aggregates.
  final Set<String> dirtyPackages;

  /// Exact reasons each Package aggregate could not be reused.
  final Map<String, Set<String>> reasons;

  /// Stable profile rendering for diagnosing invalidation propagation.
  String get profileDescription {
    final packages = dirtyPackages.toList()..sort();
    return packages
        .map((packageName) {
          final packageReasons = reasons[packageName]?.toList() ?? <String>[];
          packageReasons.sort();
          return '$packageName[${packageReasons.join('+')}]';
        })
        .join(',');
  }

  /// Current managed output fingerprints for cache persistence.
  final Map<String, String> outputFingerprints;

  /// Current direct dependency fingerprints for cache persistence.
  final Map<String, Map<String, String>> dependencyFingerprints;
}

bool _sameStringMap(Map<String, String> left, Map<String, String> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
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
/// Build filters include source code and logical metadata output assets. Cache
/// builders materialize the latter below `.dart_tool/build/generated`; external
/// path/Git/pub dependencies remain read-only and consume published indexes.
Future<bool> _runBuildRunner(
  _BuildContext context,
  Directory hostRoot, {
  required bool profile,
}) async {
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
  if (profile) {
    stdout.writeln(
      'CCRouter profile build-targets=${targets.length} '
      'packages=${targets.join(',')}',
    );
  }
  if (targets.isEmpty) {
    stdout.writeln(
      'No writable CCRouter Builder Packages were found; skipping build_runner.',
    );
    return true;
  }
  final targetRoots = <Directory>[
    for (final name in targets) workspace.packages[name]!.root,
  ];
  final protectedOutputs = <_GeneratedArtifactsSnapshot>[
    await _GeneratedArtifactsSnapshot.captureOutside(context.root, targetRoots),
    for (final package in workspace.packages.values)
      if (!package.writable && !_isWithin(context.root, package.root))
        await _GeneratedArtifactsSnapshot.capture(package.root),
  ];
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
    for (final snapshot in protectedOutputs) {
      await snapshot.restore();
    }
  }
  if (processExitCode == 0) return true;
  stderr.writeln('error: build_runner failed with exit code $processExitCode.');
  return false;
}

/// Parses only CCRouter declaration sources for a conservative fast failure.
Future<List<CCComponentDependencyPreflightIssue>> _componentDependencyPreflight(
  CCPackageWorkspace workspace,
) async {
  final sources = <CCComponentDependencyPreflightSource>[];
  for (final package in workspace.packages.values.where(
    (package) =>
        package.declaresGenerationIntent ||
        package.requiresPackageIndex ||
        package.indexFile.existsSync(),
  )) {
    final lib = Directory(path.join(package.root.path, 'lib'));
    if (!lib.existsSync()) continue;
    await for (final entity in lib.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = _relativePath(package.root, entity);
      if (relative.split('/').contains('ccrouter_generated')) continue;
      final source = await entity.readAsString();
      if (!source.contains('CCComponent(') &&
          !source.contains('CCComponentId(') &&
          !source.contains('@CCServiceContract') &&
          !source.contains('@CCCommandContract')) {
        continue;
      }
      sources.add(
        CCComponentDependencyPreflightSource(
          packageName: package.name,
          path: 'package:${package.name}/$relative',
          contents: source,
          writable: package.writable,
        ),
      );
    }
  }
  return CCComponentDependencyPreflight.inspect(sources);
}

/// Writes one deterministic block instead of duplicate per-Builder errors.
void _writeComponentDependencyPreflightIssues(
  List<CCComponentDependencyPreflightIssue> issues,
) {
  stderr.writeln(
    'error: CCRouter component dependency preflight failed before '
    'build_runner:',
  );
  for (final issue in issues) {
    stderr.writeln(
      '  ${issue.componentId} is missing required owner '
      '${issue.ownerComponentId}',
    );
    for (final capability in issue.capabilities) {
      stderr.writeln('    - ${capability.kind} "${capability.id}"');
    }
    stderr.writeln('    source: ${issue.sourcePath}');
  }
  stderr.writeln(
    'Add every owner to CCComponent.dependencies; optionalDependencies '
    'cannot satisfy required capabilities. No generated source was changed.',
  );
}

/// Immutable content snapshot for every CCRouter-managed generated file.
final class _GeneratedArtifactsSnapshot {
  /// Captures exact bytes relative to [root] for later comparison or restore.
  const _GeneratedArtifactsSnapshot._(
    this.root,
    this.files, {
    this.excludedRoots = const <String>[],
    this.explicitPaths = const <String>[],
  });

  /// Root whose source-controlled CCRouter outputs are guarded.
  final Directory root;

  /// Original generated file bytes keyed by normalized relative path.
  final Map<String, List<int>> files;

  /// Absolute subtrees outside this snapshot's ownership.
  final List<String> excludedRoots;

  /// Exact catalog targets, including legacy names, outside default discovery.
  /// These paths never grant ownership of other files in the same directory.
  final List<String> explicitPaths;

  /// Reads the complete set of managed outputs below [root].
  /// Explicit targets also participate when their directory is named build or
  /// lacks ccrouter_generated; absent files are tracked for creation rollback.
  static Future<_GeneratedArtifactsSnapshot> capture(
    Directory root, {
    Iterable<File> explicitFiles = const [],
  }) async {
    final explicitPaths = explicitFiles
        .map((file) => _relativePath(root, file))
        .toSet()
        .toList(growable: false);
    final snapshot = _GeneratedArtifactsSnapshot._(
      root,
      await _readManagedGeneratedFiles(root),
      explicitPaths: explicitPaths,
    );
    await snapshot._addExplicitFiles(snapshot.files);
    return snapshot;
  }

  /// Adds only existing regular files; a directory occupying a target is not
  /// removed or converted, and any write failure restores earlier file writes.
  Future<void> _addExplicitFiles(Map<String, List<int>> target) async {
    for (final relative in explicitPaths) {
      final file = File(_absolutePath(root, relative));
      if (await file.exists()) target[relative] = await file.readAsBytes();
    }
  }

  /// Captures managed files outside [excludedRoots] for deletion protection.
  ///
  /// Workspace build_runner may invalidate stale outputs globally when a
  /// Builder changes even though build filters select only the Host closure.
  /// The protected snapshot restores exact managed bytes after the subprocess,
  /// preventing cleanup or rewrites from mutating unrelated Packages without
  /// treating those Packages as generation inputs.
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
    return _GeneratedArtifactsSnapshot._(
      root,
      files,
      excludedRoots: List.unmodifiable(normalizedRoots),
    );
  }

  /// Reports added, removed, or modified generated artifacts deterministically.
  Future<List<String>> changes() async {
    final current = await _readManagedGeneratedFiles(root);
    await _addExplicitFiles(current);
    _removeExcluded(current);
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
    await _addExplicitFiles(current);
    _removeExcluded(current);
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

  /// Removes files that belong to explicitly excluded Package roots.
  void _removeExcluded(Map<String, List<int>> current) {
    if (excludedRoots.isEmpty) return;
    current.removeWhere((relative, _) {
      final absolute = path.normalize(_absolutePath(root, relative));
      return excludedRoots.any(
        (excluded) =>
            path.equals(absolute, excluded) ||
            path.isWithin(excluded, absolute),
      );
    });
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
    if (!_isManagedGeneratedArtifact(segments, name)) continue;
    files[relative] = await entity.readAsBytes();
  }
  return files;
}

/// Whether a source-tree file is owned by CCRouter generation.
///
/// Unknown files below a generated directory remain user-owned and are not
/// compared, restored, or deleted by `--check`.
bool _isManagedGeneratedArtifact(List<String> segments, String name) {
  if (name.endsWith('_ccrouter.g.dart')) return true;
  if (!segments.contains('ccrouter_generated')) return false;
  return name.endsWith('.g.dart') ||
      name == 'ccrouter_package.json' ||
      name == _CCPortableGenerationState.fileName ||
      name == 'cc_routes.json' ||
      name == 'cc_catalog.md' ||
      name == 'cc_routes.md' ||
      name == 'cc_sources.md' ||
      name.endsWith('.route.json') ||
      name.endsWith('.service.json') ||
      name.endsWith('.command.json') ||
      name.endsWith('.event.json') ||
      name.endsWith('.init_task.json') ||
      name.endsWith('.route.md') ||
      name.endsWith('.component.json') ||
      name.endsWith('.component.md');
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

/// Resolves package-owned capabilities against one top-level component.
///
/// Builder metadata deliberately leaves internal Route and implementation
/// ownership unset so individual libraries never repeat or scan for a
/// Package-level declaration. Aggregation fills the owner before validation,
/// fingerprinting, documentation, or publication. Public contracts retain
/// their explicit owner and are never inferred from their contracts Package.
List<Map<String, Object?>> _resolvePackageComponentOwners(
  Iterable<Map<String, Object?>> documents,
) {
  final resolved = documents
      .map(
        (document) =>
            (jsonDecode(jsonEncode(document)) as Map).cast<String, Object?>(),
      )
      .toList(growable: false);
  final ownersByPackage = <String, Set<String>>{};
  for (final document in resolved) {
    final package = '${document['package'] ?? ''}';
    final owners = ownersByPackage.putIfAbsent(package, () => <String>{});
    owners.addAll(_strings(document['componentDeclarations']));
  }
  for (final entry in ownersByPackage.entries) {
    if (entry.value.length > 1) {
      final owners = entry.value.toList()..sort();
      throw CCPackageWorkspaceException(
        'Package "${entry.key}" declares more than one CCComponent: '
        '${owners.join(', ')}. A component implementation Package must own '
        'exactly one top-level const CCComponent.',
      );
    }
  }
  for (final document in resolved) {
    final package = '${document['package'] ?? ''}';
    final packageOwners = ownersByPackage[package] ?? const <String>{};
    final owner = packageOwners.length == 1 ? packageOwners.first : null;
    for (final route in _objects(document['routes'])) {
      final exposure = '${route['exposure'] ?? ''}';
      final declaredOwner = '${route['componentId'] ?? ''}'.trim();
      if (exposure == 'internal' && declaredOwner.isEmpty) {
        if (owner == null) {
          throw CCPackageWorkspaceException(
            'Package "$package" declares internal route "${route['id']}" '
            'but has no top-level const CCComponent.',
          );
        }
        route['componentId'] = owner;
      } else if (exposure == 'public' && declaredOwner.isEmpty) {
        throw CCPackageWorkspaceException(
          'Public route contract "${route['id']}" must declare componentId.',
        );
      }
    }
    for (final implementation in _objects(document['routeImplementations'])) {
      final declaredOwner = '${implementation['componentId'] ?? ''}'.trim();
      if (declaredOwner.isNotEmpty) continue;
      if (owner == null) {
        throw CCPackageWorkspaceException(
          'Package "$package" implements route '
          '"${implementation['routeId']}" but has no top-level const '
          'CCComponent.',
        );
      }
      implementation['componentId'] = owner;
    }
    for (final contribution in _objects(document['contributions'])) {
      final declaredOwner = '${contribution['componentId'] ?? ''}'.trim();
      if (declaredOwner.isNotEmpty) continue;
      if (owner == null) {
        throw CCPackageWorkspaceException(
          'Package "$package" declares contribution '
          '"${contribution['id']}" but has no top-level const CCComponent.',
        );
      }
      contribution['componentId'] = owner;
    }
    for (final contract in _objects(document['serviceContracts'])) {
      final declaredOwner = '${contract['componentId'] ?? ''}'.trim();
      if (declaredOwner.isEmpty) {
        throw CCPackageWorkspaceException(
          'Public Service contract "${contract['id']}" must declare '
          'componentId.',
        );
      }
    }
    for (final implementation in _objects(document['serviceImplementations'])) {
      final declaredOwner = '${implementation['componentId'] ?? ''}'.trim();
      if (declaredOwner.isNotEmpty) continue;
      if (owner == null) {
        throw CCPackageWorkspaceException(
          'Package "$package" implements Service '
          '"${implementation['id']}" but has no top-level const '
          'CCComponent.',
        );
      }
      implementation['componentId'] = owner;
    }
    for (final contract in _objects(document['commandContracts'])) {
      final declaredOwner = '${contract['componentId'] ?? ''}'.trim();
      if (declaredOwner.isNotEmpty) continue;
      if (owner == null) {
        throw CCPackageWorkspaceException(
          'Command contract "${contract['id']}" omits componentId but '
          'Package "$package" has no top-level const CCComponent.',
        );
      }
      contract['componentId'] = owner;
    }
    for (final handler in _objects(document['commandHandlers'])) {
      final declaredOwner = '${handler['componentId'] ?? ''}'.trim();
      if (declaredOwner.isNotEmpty) continue;
      if (owner == null) {
        throw CCPackageWorkspaceException(
          'Command Handler "${handler['id']}" has no resolvable component owner.',
        );
      }
      handler['componentId'] = owner;
    }
    for (final contract in _objects(document['eventContracts'])) {
      final declaredOwner = '${contract['componentId'] ?? ''}'.trim();
      if (declaredOwner.isNotEmpty) continue;
      if (owner == null) {
        throw CCPackageWorkspaceException(
          'Event contract "${contract['id']}" omits componentId but Package '
          '"$package" has no top-level const CCComponent.',
        );
      }
      contract['componentId'] = owner;
    }
    for (final subscription in _objects(document['eventSubscriptions'])) {
      final declaredOwner = '${subscription['componentId'] ?? ''}'.trim();
      if (declaredOwner.isEmpty) {
        if (owner == null) {
          throw CCPackageWorkspaceException(
            'Event Subscription "${subscription['implementation']}" has no '
            'resolvable component owner.',
          );
        }
        subscription['componentId'] = owner;
      }
      if ('${subscription['eventComponentId'] ?? ''}'.trim().isEmpty) {
        subscription['eventComponentId'] = owner;
      }
    }
    for (final contract in _objects(document['initTaskContracts'])) {
      final declaredOwner = '${contract['componentId'] ?? ''}'.trim();
      if (declaredOwner.isNotEmpty) continue;
      if (owner == null) {
        throw CCPackageWorkspaceException(
          'InitTask Contract "${contract['id']}" omits componentId but '
          'Package "$package" has no top-level const CCComponent.',
        );
      }
      contract['componentId'] = owner;
    }
    for (final task in _objects(document['initTasks'])) {
      final declaredOwner = '${task['componentId'] ?? ''}'.trim();
      if (declaredOwner.isNotEmpty) continue;
      if (owner == null) {
        throw CCPackageWorkspaceException(
          'InitTask "${task['id']}" has no resolvable component owner.',
        );
      }
      task['componentId'] = owner;
    }
  }
  final subscriptions = <Map<String, Object?>>[
    for (final document in resolved)
      ..._objects(document['eventSubscriptions']),
  ];
  final groups = <String, List<Map<String, Object?>>>{};
  for (final subscription in subscriptions) {
    final key =
        '${subscription['componentId']}\u0000${subscription['eventId']}';
    groups.putIfAbsent(key, () => []).add(subscription);
  }
  final subscriberIds = <String>{};
  for (final group in groups.values) {
    final missing = group
        .where(
          (subscription) => '${subscription['subscriberId'] ?? ''}'.isEmpty,
        )
        .toList();
    if (group.length > 1 && missing.isNotEmpty) {
      throw CCPackageWorkspaceException(
        'Component "${group.first['componentId']}" declares multiple '
        'subscribers for Event "${group.first['eventId']}"; every '
        'CCEventSubscription must provide an explicit id.',
      );
    }
    if (missing.length == 1) {
      missing.single['subscriberId'] =
          '${missing.single['componentId']}.${missing.single['eventId']}';
    }
    for (final subscription in group) {
      final id = '${subscription['subscriberId'] ?? ''}';
      if (!subscriberIds.add(id)) {
        throw CCPackageWorkspaceException(
          'Event Subscriber ID "$id" is declared more than once.',
        );
      }
    }
  }
  return resolved;
}

/// Retains metadata file locations while replacing documents with resolved owners.
List<_MetadataFile> _resolveMetadataFiles(List<_MetadataFile> files) {
  final documents = _resolvePackageComponentOwners(
    files.map((file) => file.document),
  );
  return <_MetadataFile>[
    for (var index = 0; index < files.length; index++)
      _MetadataFile(
        files[index].file,
        documents[index],
        packageRoot: files[index].packageRoot,
      ),
  ];
}

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
  const _MetadataFile(this.file, this.document, {required this.packageRoot});

  /// Generated JSON file containing [document].
  final File file;

  /// Decoded component or route metadata payload.
  final Map<String, Object?> document;

  /// Source Package root that owns this metadata document.
  final Directory packageRoot;
}

/// Writes one stable generated Route Contract entry point per Package.
///
/// Authored public barrels remain the exposure boundary. This generated layer
/// only hides per-source Route Contract output paths and deliberately excludes
/// authored Service, Command, Event, and InitTask declarations.
Future<Set<String>> _generateContractApiEntrypoints(
  Iterable<_MetadataFile> metadataFiles,
) async {
  final exportsByPackage = <String, Map<String, Set<String>>>{};
  final rootsByPackage = <String, Directory>{};
  for (final metadata in metadataFiles) {
    final packageName = '${metadata.document['package'] ?? ''}';
    if (packageName.isEmpty) continue;
    rootsByPackage[packageName] = metadata.packageRoot;
    for (final route in _objects(metadata.document['routes'])) {
      if (route['exposure'] == 'internal') continue;
      final contracts = route['contracts'];
      if (contracts is! Map || contracts['package'] != packageName) continue;
      final library = '${contracts['library'] ?? ''}';
      const prefix = 'lib/src/ccrouter_generated/';
      if (!library.startsWith(prefix) || !library.endsWith('.g.dart')) {
        continue;
      }
      final symbols = exportsByPackage
          .putIfAbsent(packageName, () => <String, Set<String>>{})
          .putIfAbsent(library.substring(prefix.length), () => <String>{});
      for (final key in const ['route', 'arguments']) {
        final symbol = '${contracts[key] ?? ''}';
        if (symbol.isNotEmpty) symbols.add(symbol);
      }
    }
  }

  final outputs = <String>{};
  for (final packageName in exportsByPackage.keys.toList()..sort()) {
    final root = rootsByPackage[packageName]!;
    final output = File(
      path.join(
        root.path,
        'lib',
        'src',
        'ccrouter_generated',
        '${_fileStem(packageName)}.contracts.api.g.dart',
      ),
    );
    final exports = exportsByPackage[packageName]!;
    final source = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln('// ignore_for_file: type=lint')
      ..writeln()
      ..writeln(
        '/// Stable generated Contract API entry point for Package `$packageName`.',
      )
      ..writeln('///')
      ..writeln(
        '/// Authored public barrels decide whether this generated API is exposed.',
      );
    for (final library in exports.keys.toList()..sort()) {
      final symbols = exports[library]!.toList()..sort();
      source.writeln("export '$library' show ${symbols.join(', ')};");
    }
    await _writeIfChanged(output, _dartFormatter.format(source.toString()));
    outputs.add(path.normalize(output.absolute.path));
  }
  return outputs;
}

/// Writes deterministic registration, Manifest, and route assembly per component.
Future<List<_GeneratedComponentCatalog>> _generateComponentRouteIndexes(
  Iterable<_MetadataFile> metadataFiles, {
  bool generateLegacyEntrypoints = true,
  Set<String>? dirtyPackages,
}) async {
  final componentSources = <String, _ComponentSource>{};
  final routes = <String, List<_RouteRegistration>>{};
  final contributions = <String, List<_ContributionRegistration>>{};
  final commandContracts = <String, Map<String, Object?>>{};
  final eventContracts = <String, Map<String, Object?>>{};
  for (final metadata in metadataFiles) {
    for (final contract in _objects(metadata.document['commandContracts'])) {
      commandContracts['${contract['id'] ?? ''}'] = contract;
    }
    for (final contract in _objects(metadata.document['eventContracts'])) {
      eventContracts['${contract['id'] ?? ''}'] = contract;
    }
  }
  final commandClients = <String, List<_CommandClientEntry>>{};
  final eventClients = <String, List<_EventClientEntry>>{};
  final serviceApiLibraries = <String, Set<String>>{};
  for (final metadata in metadataFiles) {
    final document = metadata.document;
    final package = '${document['package'] ?? ''}';
    final source = '${document['source'] ?? ''}';
    final componentManifests = document['componentManifests'];
    final manifestMap = componentManifests is Map
        ? componentManifests.cast<Object?, Object?>()
        : const <Object?, Object?>{};
    final componentSymbols = document['componentSymbols'];
    final symbolMap = componentSymbols is Map
        ? componentSymbols.cast<Object?, Object?>()
        : const <Object?, Object?>{};
    for (final component in _objects(document['components'])) {
      final id = '${component['id']}';
      if (_strings(document['componentDeclarations']).contains(id)) {
        final symbol = '${symbolMap[id] ?? ''}';
        if (symbol.isEmpty) {
          throw CCPackageWorkspaceException(
            'Component "$id" metadata does not identify its top-level const '
            'CCComponent symbol. Regenerate the Package.',
          );
        }
        componentSources[id] = _ComponentSource(
          package: package,
          source: source,
          symbol: symbol,
          manifest: '${manifestMap[id] ?? '${_camelIdentifier(id)}Manifest'}',
          packageRoot: metadata.packageRoot,
        );
      }
      for (final dependency in _objects(component['commandDependencies'])) {
        final commandId = '${dependency['id'] ?? ''}';
        final contract = commandContracts[commandId];
        if (contract == null) continue;
        commandClients
            .putIfAbsent(id, () => [])
            .add(
              _CommandClientEntry.fromMetadata(
                contract,
                member: '${dependency['member'] ?? ''}',
                library: '${dependency['library'] ?? ''}',
              ),
            );
      }
      final serviceDependencies = _objects(component['serviceDependencies']);
      if (serviceDependencies.isNotEmpty) {
        final libraries = serviceApiLibraries.putIfAbsent(id, () => <String>{});
        for (final dependency in serviceDependencies) {
          final generated = dependency['generatedArtifact'];
          final packageUri = generated is Map
              ? '${generated['packageUri'] ?? ''}'
              : '';
          final packagePrefix = 'package:$package/';
          if (packageUri.startsWith(packagePrefix)) {
            final library = packageUri.substring(packagePrefix.length);
            if (library.startsWith('src/ccrouter_generated/')) {
              libraries.add(
                library.substring('src/ccrouter_generated/'.length),
              );
              continue;
            }
          }
          libraries.add(_generatedServiceApiLibraryPath(source));
        }
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
      final internalRoute = '${route['exposure'] ?? ''}' == 'internal';
      final registrationLibrary =
          '${route['registrationLibrary'] ?? destinationMap['library'] ?? (internalRoute ? _generatedRouteLibraryPath(source) : source)}';
      final builderLibrary =
          '${destinationMap['builderLibrary'] ?? (internalRoute ? _generatedRouteBindingPath(source) : registrationLibrary)}';
      final intentFactory = contracts is Map
          ? '${contracts['intentFactory'] ?? (internalRoute ? _intentFactoryFromContract(routeContract) : '')}'
          : '';
      if ('${route['registration'] ?? ''}'.trim().isEmpty &&
          destinationMap.isEmpty) {
        continue;
      }
      routes
          .putIfAbsent(componentId, () => [])
          .add(
            _RouteRegistration(
              package: package,
              source: registrationLibrary,
              builderSource: builderLibrary,
              routeId: '${route['id'] ?? ''}',
              registration: registration,
              descriptor:
                  '${destinationMap['descriptor'] ?? _descriptorFromContract(routeContract)}',
              builder:
                  '${destinationMap['builder'] ?? _builderFromContract(routeContract)}',
              intentFactory: intentFactory,
            ),
          );
    }
    for (final implementation in _objects(document['routeImplementations'])) {
      final destination = implementation['destination'];
      final destinationMap = destination is Map
          ? destination.cast<Object?, Object?>()
          : const <Object?, Object?>{};
      final registrationLibrary =
          '${implementation['registrationLibrary'] ?? destinationMap['library'] ?? source}';
      final builderLibrary =
          '${destinationMap['builderLibrary'] ?? registrationLibrary}';
      routes
          .putIfAbsent('${implementation['componentId'] ?? ''}', () => [])
          .add(
            _RouteRegistration(
              package: package,
              source: registrationLibrary,
              builderSource: builderLibrary,
              routeId: '${implementation['routeId'] ?? ''}',
              registration: '${implementation['registration'] ?? ''}',
              descriptor: '${destinationMap['descriptor'] ?? ''}',
              builder: '${destinationMap['builder'] ?? ''}',
              intentFactory: '',
            ),
          );
    }
    for (final contribution in _objects(document['contributions'])) {
      final componentId = '${contribution['componentId'] ?? ''}';
      contributions
          .putIfAbsent(componentId, () => [])
          .add(
            _ContributionRegistration(
              package: package,
              source: source,
              id: '${contribution['id'] ?? ''}',
              symbol: '${contribution['symbol'] ?? ''}',
            ),
          );
    }
    for (final service in _objects(document['serviceImplementations'])) {
      final componentId = '${service['componentId'] ?? ''}';
      final id = '${service['id'] ?? ''}';
      final key = '${service['key'] ?? ''}';
      contributions
          .putIfAbsent(componentId, () => [])
          .add(
            _ContributionRegistration(
              package: package,
              source: '${service['registrationLibrary'] ?? source}',
              id: 'service:$id:$key',
              symbol: '${service['registration'] ?? ''}',
            ),
          );
    }
    for (final handler in _objects(document['commandHandlers'])) {
      final componentId = '${handler['componentId'] ?? ''}';
      contributions
          .putIfAbsent(componentId, () => [])
          .add(
            _ContributionRegistration(
              package: package,
              source: '${handler['registrationLibrary'] ?? source}',
              id: 'command:${handler['id'] ?? ''}',
              symbol: '${handler['registration'] ?? ''}',
            ),
          );
    }
    for (final subscription in _objects(document['eventSubscriptions'])) {
      final componentId = '${subscription['componentId'] ?? ''}';
      contributions
          .putIfAbsent(componentId, () => [])
          .add(
            _ContributionRegistration(
              package: package,
              source: '${subscription['registrationLibrary'] ?? source}',
              id: 'event:${subscription['subscriberId'] ?? ''}',
              symbol: '${subscription['registration'] ?? ''}',
              subscriberId: '${subscription['subscriberId'] ?? ''}',
            ),
          );
    }
    for (final task in _objects(document['initTasks'])) {
      final componentId = '${task['componentId'] ?? ''}';
      contributions
          .putIfAbsent(componentId, () => [])
          .add(
            _ContributionRegistration(
              package: package,
              source: '${task['registrationLibrary'] ?? source}',
              id: 'initTask:${task['id'] ?? ''}',
              symbol: '${task['registration'] ?? ''}',
            ),
          );
    }
  }

  for (final contract in commandContracts.values) {
    final componentId = '${contract['componentId'] ?? ''}';
    if (componentId.isEmpty) continue;
    commandClients
        .putIfAbsent(componentId, () => [])
        .add(_CommandClientEntry.fromMetadata(contract));
  }
  for (final contract in eventContracts.values) {
    final componentId = '${contract['componentId'] ?? ''}';
    if (componentId.isEmpty) continue;
    eventClients
        .putIfAbsent(componentId, () => [])
        .add(_EventClientEntry.fromMetadata(contract));
  }

  final generatedCatalogs = <_GeneratedComponentCatalog>[];
  final componentIds = componentSources.keys.toList()..sort();
  for (final componentId in componentIds) {
    final component = componentSources[componentId];
    if (component == null) continue;
    final componentRoutes = routes[componentId] ?? <_RouteRegistration>[];
    componentRoutes.sort(_compareRoutes);
    final componentContributions =
        contributions[componentId] ?? <_ContributionRegistration>[];
    componentContributions.sort(_compareContributions);
    final componentCommandClients =
        commandClients[componentId] ?? <_CommandClientEntry>[];
    componentCommandClients.sort(
      (left, right) => left.member.compareTo(right.member),
    );
    final componentEventClients =
        eventClients[componentId] ?? <_EventClientEntry>[];
    componentEventClients.sort(
      (left, right) => left.member.compareTo(right.member),
    );
    final packageRoot = component.packageRoot;
    final packageDirty =
        dirtyPackages == null || dirtyPackages.contains(component.package);
    final outputDirectory = Directory(
      '${packageRoot.path}${Platform.pathSeparator}lib${Platform.pathSeparator}src${Platform.pathSeparator}ccrouter_generated${Platform.pathSeparator}component',
    )..createSync(recursive: true);
    final output = File(
      '${outputDirectory.path}${Platform.pathSeparator}${_fileStem(componentId)}.component.g.dart',
    );
    final componentServiceApiLibraries =
        serviceApiLibraries[componentId]?.toList(growable: false) ??
        const <String>[];
    final hasServiceApi = componentServiceApiLibraries.isNotEmpty;
    if (packageDirty) {
      await _writeIfChanged(
        output,
        _dartFormatter.format(
          _emitComponentAssembly(
            componentId,
            component,
            componentRoutes,
            componentContributions,
          ),
        ),
      );
    }
    final hasRouteApi = componentRoutes.any(
      (route) => route.intentFactory.isNotEmpty,
    );
    if (hasRouteApi) {
      final routeApiOutput = File(
        '${outputDirectory.path}${Platform.pathSeparator}${_fileStem(componentId)}.route_api.g.dart',
      );
      if (packageDirty) {
        await _writeIfChanged(
          routeApiOutput,
          _dartFormatter.format(
            _emitComponentRouteApi(componentId, componentRoutes),
          ),
        );
      }
    }
    final hasCommandApi = componentCommandClients.isNotEmpty;
    if (hasCommandApi) {
      final commandApiOutput = File(
        '${outputDirectory.path}${Platform.pathSeparator}${_fileStem(componentId)}.command_api.g.dart',
      );
      if (packageDirty) {
        await _writeIfChanged(
          commandApiOutput,
          _dartFormatter.format(
            _emitComponentCommandApi(componentId, componentCommandClients),
          ),
        );
      }
    }
    final hasEventApi = componentEventClients.isNotEmpty;
    if (hasEventApi) {
      final eventApiOutput = File(
        '${outputDirectory.path}${Platform.pathSeparator}${_fileStem(componentId)}.event_api.g.dart',
      );
      if (packageDirty) {
        await _writeIfChanged(
          eventApiOutput,
          _dartFormatter.format(
            _emitComponentEventApi(componentId, componentEventClients),
          ),
        );
      }
    }
    final hasStableApi =
        hasRouteApi || hasServiceApi || hasCommandApi || hasEventApi;
    if (hasStableApi && packageDirty) {
      final apiOutput = File(
        path.join(
          packageRoot.path,
          'lib',
          'src',
          'ccrouter_generated',
          '${_fileStem(componentId)}.api.g.dart',
        ),
      );
      await _writeIfChanged(
        apiOutput,
        _emitComponentApi(
          componentId: componentId,
          hasRouteApi: hasRouteApi,
          serviceApiLibraries: componentServiceApiLibraries,
          hasCommandApi: hasCommandApi,
          hasEventApi: hasEventApi,
        ),
      );
    }
    generatedCatalogs.add(
      _GeneratedComponentCatalog(
        componentId: componentId,
        package: component.package,
        packageRoot: packageRoot,
        registrarSource:
            'lib/src/ccrouter_generated/component/${_fileStem(componentId)}.component.g.dart',
        manifest: component.manifest,
        hasRouteApi: hasRouteApi,
        hasServiceApi: hasServiceApi,
        hasCommandApi: hasCommandApi,
        hasEventApi: hasEventApi,
      ),
    );
  }
  if (generateLegacyEntrypoints) {
    await _generatePackageHostEntrypoints(generatedCatalogs);
  }
  return generatedCatalogs;
}

/// Emits one stable component API barrel over the allowed typed entry points.
String _emitComponentApi({
  required String componentId,
  required bool hasRouteApi,
  required List<String> serviceApiLibraries,
  required bool hasCommandApi,
  required bool hasEventApi,
}) {
  final stem = _fileStem(componentId);
  final owner = _pascalIdentifier(_componentApiOwner(componentId));
  final out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln('// ignore_for_file: type=lint')
    ..writeln()
    ..writeln('/// Stable typed API entry point for component `$componentId`.')
    ..writeln('///')
    ..writeln(
      '/// This barrel intentionally excludes Registrar, Binding, Host, and metadata glue.',
    );
  if (hasRouteApi) {
    out..writeln(
      "export 'component/$stem.route_api.g.dart' show ${owner}Routes;",
    );
  }
  for (final library in serviceApiLibraries.toList()..sort()) {
    out.writeln("export '$library' show ${owner}Services;");
  }
  if (hasCommandApi) {
    out.writeln(
      "export 'component/$stem.command_api.g.dart' show ${owner}Commands;",
    );
  }
  if (hasEventApi) {
    out.writeln(
      "export 'component/$stem.event_api.g.dart' show ${owner}Events;",
    );
  }
  return '${out.toString().trimRight()}\n';
}

/// Generates one component Registrar, Manifest, and route catalog.
String _emitComponentAssembly(
  String componentId,
  _ComponentSource component,
  List<_RouteRegistration> routes,
  List<_ContributionRegistration> contributions,
) {
  final className = '_${_pascalIdentifier(componentId)}GeneratedRegistrar';
  final imports = <String, String>{};
  for (final route in routes) {
    imports.putIfAbsent(route.source, () => _sourceAlias(route.source));
    imports.putIfAbsent(
      route.builderSource,
      () => _sourceAlias(route.builderSource),
    );
  }
  for (final contribution in contributions) {
    imports.putIfAbsent(
      contribution.source,
      () => _sourceAlias(contribution.source),
    );
  }
  final out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln('// ignore_for_file: type=lint, unused_element')
    ..writeln()
    ..writeln("import 'package:ccrouter/ccrouter.dart';")
    ..writeln("import 'package:ccrouter/ccrouter_host.dart';")
    ..writeln(
      "import 'package:${component.package}/${component.source.substring('lib/'.length)}' as component_source;",
    );
  for (final entry
      in imports.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key))) {
    final source = entry.key;
    final generated = source.startsWith('lib/src/ccrouter_generated/');
    out.writeln(
      generated
          ? "import '${_componentGeneratedImport(source)}' as ${entry.value};"
          : "import 'package:${component.package}/${source.substring('lib/'.length)}' as ${entry.value};",
    );
  }
  out
    ..writeln()
    ..writeln(
      '/// Generated capability Registrar for component `$componentId`.',
    )
    ..writeln('final class $className implements CCComponentRegistrar {')
    ..writeln('  /// Creates the stateless generated Registrar.')
    ..writeln('  const $className();')
    ..writeln()
    ..writeln('  /// Registers every generated capability in stable order.')
    ..writeln('  @override')
    ..writeln('  void register(CCRegistry registry) {');
  for (final route in routes) {
    final alias = imports[route.source]!;
    out
      ..writeln('    $alias.${route.registration}(')
      ..writeln('      registry,')
      ..writeln('    );');
  }
  for (final contribution in contributions) {
    final alias = imports[contribution.source]!;
    final subscriberId = contribution.subscriberId;
    if (subscriberId == null) {
      out.writeln('    $alias.${contribution.symbol}(registry);');
    } else {
      out
        ..writeln('    $alias.${contribution.symbol}(')
        ..writeln('      registry,')
        ..writeln('      subscriberId: ${jsonEncode(subscriberId)},')
        ..writeln('    );');
    }
  }
  out
    ..writeln('  }')
    ..writeln('}')
    ..writeln()
    ..writeln('/// Generated Runtime Manifest for component `$componentId`.')
    ..writeln(
      'const ${component.manifest} = CCComponentManifest.fromComponent(',
    )
    ..writeln('  component: component_source.${component.symbol},')
    ..writeln('  registrar: $className(),')
    ..writeln(');')
    ..writeln()
    ..writeln(
      '/// Backend-neutral Flutter destinations owned by `$componentId`.',
    )
    ..writeln(
      'final ${_camelIdentifier(componentId)}RouteCatalog = CCFlutterRouteCatalog([',
    );
  for (final route in routes) {
    final descriptorAlias = imports[route.source]!;
    final builderAlias = imports[route.builderSource]!;
    out
      ..writeln('  CCFlutterRouteDestination.fromDefinition(')
      ..writeln('    definition:')
      ..writeln('        $descriptorAlias.${route.descriptor}(),')
      ..writeln('    builder: (arguments) =>')
      ..writeln('        $builderAlias.${route.builder}(arguments),')
      ..writeln('  ),');
  }
  out
    ..writeln(']);')
    ..writeln();
  return out.toString();
}

/// Generates the component's single typed API for its internal routes.
String _emitComponentRouteApi(
  String componentId,
  List<_RouteRegistration> routes,
) {
  final internalRoutes = routes
      .where((route) => route.intentFactory.isNotEmpty)
      .toList(growable: false);
  final className =
      '${_pascalIdentifier(_componentApiOwner(componentId))}Routes';
  final imports = <String, String>{};
  final members = <String, _RouteRegistration>{};
  for (final route in internalRoutes) {
    imports.putIfAbsent(route.source, () => _sourceAlias(route.source));
    final member = _componentRouteMember(componentId, route.routeId);
    final previous = members[member];
    if (previous != null) {
      throw CCPackageWorkspaceException(
        'Routes "${previous.routeId}" and "${route.routeId}" both generate '
        'component Route API member "$member". Rename one Route ID.',
      );
    }
    members[member] = route;
  }
  final out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln('// ignore_for_file: type=lint')
    ..writeln()
    ..writeln("import 'package:flutter/foundation.dart' show internal;");
  for (final entry
      in imports.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key))) {
    out.writeln(
      "import '${_componentGeneratedImport(entry.key)}' as ${entry.value};",
    );
  }
  if (imports.isNotEmpty) out.writeln();
  out
    ..writeln(
      '/// Typed navigation entry points for routes internal to `$componentId`.',
    )
    ..writeln('@internal')
    ..writeln('abstract final class $className {');
  for (final entry
      in members.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key))) {
    final route = entry.value;
    final alias = imports[route.source]!;
    out
      ..writeln('  /// Creates an Intent for `${route.routeId}`.')
      ..writeln(
        '  static const ${entry.key} = $alias.${route.intentFactory}();',
      );
  }
  out
    ..writeln('}')
    ..writeln();
  return out.toString();
}

/// Generates one typed Command Client for an owning or consuming component.
String _emitComponentCommandApi(
  String componentId,
  List<_CommandClientEntry> entries,
) {
  final className =
      '${_pascalIdentifier(_componentApiOwner(componentId))}Commands';
  final unique = <String, _CommandClientEntry>{};
  for (final entry in entries) {
    final previous = unique[entry.member];
    if (previous != null && previous.id != entry.id) {
      throw CCPackageWorkspaceException(
        'Commands "${previous.id}" and "${entry.id}" both generate member '
        '"${entry.member}" for component "$componentId".',
      );
    }
    unique[entry.member] = entry;
  }
  final libraries = unique.values.map((entry) => entry.library).toSet().toList()
    ..sort();
  final aliases = <String, String>{
    for (var index = 0; index < libraries.length; index++)
      libraries[index]: 'command_type_$index',
  };
  final out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln('// ignore_for_file: type=lint')
    ..writeln()
    ..writeln("import 'package:ccrouter/ccrouter_generated.dart';");
  for (final library in libraries) {
    out.writeln("import '$library' as ${aliases[library]};");
  }
  out
    ..writeln()
    ..writeln('/// Typed Command entry points for component `$componentId`.')
    ..writeln('abstract final class $className {');
  for (final entry
      in unique.values.toList()
        ..sort((left, right) => left.member.compareTo(right.member))) {
    final alias = aliases[entry.library]!;
    final result = _commandApiType(entry.resultType, alias);
    out
      ..writeln('  /// Dispatches `${entry.id}` through its single owner.')
      ..writeln('  static Future<$result> ${entry.member}(')
      ..writeln('    $alias.${entry.type} command, {')
      ..writeln('    Duration? timeout,')
      ..writeln('    CCCancellationToken? cancellation,')
      ..writeln('  }) => CCRouterGeneratedCommandBinding.invoke(')
      ..writeln('    command,')
      ..writeln('    commandId: ${jsonEncode(entry.id)},')
      ..writeln('    callerComponentId: ${jsonEncode(componentId)},')
      ..writeln('    timeout: timeout,')
      ..writeln('    cancellation: cancellation,')
      ..writeln('  );')
      ..writeln();
  }
  out
    ..writeln('}')
    ..writeln();
  return out.toString();
}

/// Generates one typed Event publication Client for its owning component.
String _emitComponentEventApi(
  String componentId,
  List<_EventClientEntry> entries,
) {
  final className =
      '${_pascalIdentifier(_componentApiOwner(componentId))}Events';
  final unique = <String, _EventClientEntry>{};
  for (final entry in entries) {
    final previous = unique[entry.member];
    if (previous != null && previous.id != entry.id) {
      throw CCPackageWorkspaceException(
        'Events "${previous.id}" and "${entry.id}" both generate member '
        '"${entry.member}" for component "$componentId".',
      );
    }
    unique[entry.member] = entry;
  }
  final libraries = unique.values.map((entry) => entry.library).toSet().toList()
    ..sort();
  final aliases = <String, String>{
    for (var index = 0; index < libraries.length; index++)
      libraries[index]: 'event_type_$index',
  };
  final out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln('// ignore_for_file: type=lint')
    ..writeln()
    ..writeln("import 'package:ccrouter/ccrouter_generated.dart';");
  for (final library in libraries) {
    out.writeln("import '$library' as ${aliases[library]};");
  }
  out
    ..writeln()
    ..writeln(
      '/// Typed Event publication entry points for component `$componentId`.',
    )
    ..writeln('abstract final class $className {');
  for (final entry
      in unique.values.toList()
        ..sort((left, right) => left.member.compareTo(right.member))) {
    final alias = aliases[entry.library]!;
    out
      ..writeln('  /// Publishes `${entry.id}` to its static subscribers.')
      ..writeln('  static Future<void> ${entry.member}(')
      ..writeln('    $alias.${entry.type} event, {')
      ..writeln('    Duration? timeout,')
      ..writeln('    CCCancellationToken? cancellation,')
      ..writeln('  }) => CCRouterGeneratedEventBinding.publish(')
      ..writeln('    event,')
      ..writeln('    eventId: ${jsonEncode(entry.id)},')
      ..writeln('    publisherComponentId: ${jsonEncode(componentId)},')
      ..writeln('    timeout: timeout,')
      ..writeln('    cancellation: cancellation,')
      ..writeln('  );')
      ..writeln();
  }
  out
    ..writeln('}')
    ..writeln();
  return out.toString();
}

/// Qualifies simple non-core result types through the Contract library alias.
String _commandApiType(String type, String alias) {
  const core = <String>{
    'void',
    'Never',
    'Object',
    'String',
    'bool',
    'int',
    'double',
    'num',
    'List',
    'Set',
    'Map',
    'Iterable',
    'Future',
    'Duration',
    'DateTime',
    'Uri',
  };
  return type.replaceAllMapped(RegExp(r'\b[A-Za-z_]\w*\b'), (match) {
    final value = match.group(0)!;
    return core.contains(value) || value == 'dynamic' ? value : '$alias.$value';
  });
}

/// Derives one short lower-camel member from a component-owned Route ID.
String _componentRouteMember(String componentId, String routeId) {
  final owner = _componentApiOwner(componentId);
  final local = routeId.startsWith('$owner.')
      ? routeId.substring(owner.length + 1)
      : routeId;
  return _camelIdentifier(local);
}

/// Makes generated component imports relative to their shared output root.
String _componentGeneratedImport(String library) {
  const root = 'lib/src/ccrouter_generated/';
  if (!library.startsWith(root)) {
    throw CCPackageWorkspaceException(
      'Component generated library must remain below $root: $library',
    );
  }
  return '../${library.substring(root.length)}';
}

/// Removes a conventional descriptor suffix from generated business API names.
String _componentApiOwner(String componentId) =>
    componentId.endsWith('_component')
    ? componentId.substring(0, componentId.length - '_component'.length)
    : componentId;

/// Derives the migration-safe standalone route output from a source library.
String _generatedRouteLibraryPath(String source) {
  const prefix = 'lib/src/';
  if (!source.startsWith(prefix) || !source.endsWith('.dart')) return source;
  final relative = source.substring(prefix.length, source.length - 5);
  return 'lib/src/ccrouter_generated/route/$relative.route.g.dart';
}

/// Derives the migration-safe page-binding output from a source library.
String _generatedRouteBindingPath(String source) {
  const prefix = 'lib/src/';
  if (!source.startsWith(prefix) || !source.endsWith('.dart')) return source;
  final relative = source.substring(prefix.length, source.length - 5);
  return 'lib/src/ccrouter_generated/binding/$relative.route_binding.g.dart';
}

/// Derives a component-relative Service Proxy library from an authored source.
String _generatedServiceApiLibraryPath(String source) {
  const prefix = 'lib/';
  if (!source.startsWith(prefix) || !source.endsWith('.dart')) return source;
  var relative = source.substring(prefix.length, source.length - 5);
  if (relative.startsWith('src/')) relative = relative.substring(4);
  return 'component/$relative.service_api.g.dart';
}

/// Derives the callable factory emitted for one legacy internal route record.
String _intentFactoryFromContract(String contract) {
  final stem = contract.startsWith('_') ? contract.substring(1) : contract;
  return stem.isEmpty ? '' : 'CCGenerated${stem}Factory';
}

/// Writes Package Bundles without importing any transitive Pub dependency.
Future<void> _generateResolvedPackageBundles({
  required CCPackageWorkspace workspace,
  required Map<String, CCPackageIndex> indexes,
  required Set<String> runtimeBundles,
  required Iterable<_GeneratedComponentCatalog> catalogs,
  required Set<String> dirtyPackages,
}) async {
  final contractRecords = _collectContractRecords(indexes.values);
  final catalogsByPackage = <String, List<_GeneratedComponentCatalog>>{};
  for (final catalog in catalogs) {
    catalogsByPackage.putIfAbsent(catalog.package, () => []).add(catalog);
  }
  for (final packageName in runtimeBundles.toList()..sort()) {
    final package = workspace.packages[packageName];
    final index = indexes[packageName];
    if (package == null || index == null || !package.writable) continue;
    if (!dirtyPackages.contains(packageName)) continue;
    final packageCatalogs = catalogsByPackage[packageName] ?? [];
    packageCatalogs.sort(
      (left, right) => left.componentId.compareTo(right.componentId),
    );
    final dependencyNames =
        package.dependencies.where(runtimeBundles.contains).toList()..sort();
    // Contract-only Packages intentionally remain Pure Dart and do not need
    // to publish a Flutter/Host Bundle. The generated implementation Bundle
    // carries descriptors for contracts owned by its local Components so the
    // Host can still validate the boundary without importing a transitive
    // contract Package directly.
    final localComponentIds = {
      for (final catalog in packageCatalogs) catalog.componentId,
    };
    final contractMetadata = <Map<String, Object?>>[
      for (final candidate in indexes.values) ...candidate.metadata,
    ];
    final contractDescriptorSource = _emitPackageContractDescriptors(
      contractMetadata,
      packageName,
      ownerComponentIds: localComponentIds,
    );
    final contractRequirementSource = _emitPackageContractRequirements(
      index.metadata,
      packageName,
      contractRecords,
    );
    final contractImports = <String>[
      'CCContractBundleDescriptor',
      if (contractDescriptorSource.trim().isNotEmpty) 'CCContractDescriptor',
      if (contractDescriptorSource.trim().isNotEmpty ||
          contractRequirementSource.trim().isNotEmpty)
        'CCContractKind',
      if (contractRequirementSource.trim().isNotEmpty) 'CCContractRequirement',
      'CCFlutterRouteCatalog',
      'CCGeneratedPackageBundle',
    ];
    final out = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln('// ignore_for_file: type=lint')
      ..writeln()
      ..writeln('/// Host-only generated Package Bundle for `$packageName`.')
      ..writeln('library;')
      ..writeln()
      ..writeln(
        "import 'package:ccrouter/ccrouter_host.dart' "
        'show ${contractImports.join(', ')};',
      );
    for (var index = 0; index < packageCatalogs.length; index++) {
      final catalog = packageCatalogs[index];
      out.writeln(
        "import 'package:${catalog.package}/${catalog.registrarSource.substring('lib/'.length)}' "
        'as component_$index;',
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
      ..writeln('  contractBundle: CCContractBundleDescriptor(')
      ..writeln("    packageName: '$packageName',")
      ..writeln("    packageVersion: '${package.version}',")
      ..writeln('    contracts: [');
    out.write(contractDescriptorSource);
    out
      ..writeln('    ],')
      ..writeln('    requirements: [');
    out.write(contractRequirementSource);
    out
      ..writeln('    ],')
      ..writeln('  ),')
      ..writeln('  componentManifests: [');
    for (var index = 0; index < packageCatalogs.length; index++) {
      out.writeln('    component_$index.${packageCatalogs[index].manifest},');
    }
    out
      ..writeln('  ],')
      ..writeln('  routeCatalog: CCFlutterRouteCatalog.merge([');
    for (var index = 0; index < packageCatalogs.length; index++) {
      out.writeln(
        '    component_$index.${_camelIdentifier(packageCatalogs[index].componentId)}RouteCatalog,',
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

/// One normalized Contract record used while emitting Package Bundles.
Map<String, Map<String, Object?>> _collectContractRecords(
  Iterable<CCPackageIndex> indexes,
) {
  final records = <String, Map<String, Object?>>{};
  for (final index in indexes) {
    for (final document in index.metadata) {
      for (final entry in <String, String>{
        'routes': 'route',
        'serviceContracts': 'service',
        'commandContracts': 'command',
        'eventContracts': 'event',
        'initTaskContracts': 'initTask',
      }.entries) {
        for (final contract in _objects(document[entry.key])) {
          final id = '${contract['id'] ?? ''}';
          if (id.isEmpty) continue;
          records.putIfAbsent(
            id,
            () => <String, Object?>{...contract, '_kind': entry.value},
          );
        }
      }
    }
  }
  return records;
}

String _emitPackageContractDescriptors(
  Iterable<Map<String, Object?>> metadata,
  String packageName, {
  Set<String> ownerComponentIds = const <String>{},
}) {
  final records = <String, Map<String, Object?>>{};
  for (final document in metadata) {
    for (final entry in <String, String>{
      'routes': 'route',
      'serviceContracts': 'service',
      'commandContracts': 'command',
      'eventContracts': 'event',
      'initTaskContracts': 'initTask',
    }.entries) {
      for (final contract in _objects(document[entry.key])) {
        final id = '${contract['id'] ?? ''}';
        if (id.isEmpty) continue;
        final owner = '${contract['componentId'] ?? ''}';
        if (ownerComponentIds.isNotEmpty &&
            !ownerComponentIds.contains(owner)) {
          continue;
        }
        records.putIfAbsent(
          id,
          () => <String, Object?>{
            ...contract,
            '_kind': entry.value,
            '_package': packageName,
          },
        );
      }
    }
  }
  final out = StringBuffer();
  for (final id in records.keys.toList()..sort()) {
    final record = records[id]!;
    out
      ..writeln('      CCContractDescriptor(')
      ..writeln('        kind: CCContractKind.${record['_kind']},')
      ..writeln('        id: ${jsonEncode(id)},')
      ..writeln(
        '        ownerComponentId: ${jsonEncode('${record['componentId'] ?? ''}')},',
      )
      ..writeln('        version: ${jsonEncode('${record['version'] ?? ''}')},')
      ..writeln(
        '        shapeFingerprint: ${jsonEncode('${record['shapeFingerprint'] ?? ''}')},',
      )
      ..writeln('      ),');
  }
  return out.toString();
}

String _emitPackageContractRequirements(
  Iterable<Map<String, Object?>> metadata,
  String packageName,
  Map<String, Map<String, Object?>> records,
) {
  final requirements = <String, Map<String, Object?>>{};
  void add({required String kind, required String id, required String owner}) {
    final record = records[id];
    if (record == null || id.isEmpty) return;
    final key = '$kind\u0000$id\u0000$owner';
    requirements.putIfAbsent(
      key,
      () => <String, Object?>{
        'kind': kind,
        'id': id,
        'owner': owner,
        'version': '${record['version'] ?? ''}',
        'fingerprint': '${record['shapeFingerprint'] ?? ''}',
      },
    );
  }

  for (final document in metadata) {
    for (final component in _objects(document['components'])) {
      final componentOwner = '${component['id'] ?? ''}';
      for (final dependency in _objects(component['serviceDependencies'])) {
        add(
          kind: 'service',
          id: '${dependency['id'] ?? ''}',
          owner: '${dependency['componentId'] ?? ''}',
        );
      }
      for (final dependency in _objects(component['commandDependencies'])) {
        add(
          kind: 'command',
          id: '${dependency['id'] ?? ''}',
          owner: '${dependency['componentId'] ?? ''}',
        );
      }
      if (componentOwner.isEmpty) continue;
    }
    for (final subscription in _objects(document['eventSubscriptions'])) {
      add(
        kind: 'event',
        id: '${subscription['eventId'] ?? ''}',
        owner: '${subscription['eventComponentId'] ?? ''}',
      );
    }
    for (final task in _objects(document['initTasks'])) {
      for (final dependencyId in _strings(task['dependsOn'])) {
        final record = records[dependencyId];
        add(
          kind: 'initTask',
          id: dependencyId,
          owner: '${record?['componentId'] ?? ''}',
        );
      }
    }
  }
  final out = StringBuffer();
  for (final key in requirements.keys.toList()..sort()) {
    final requirement = requirements[key]!;
    out
      ..writeln('      CCContractRequirement(')
      ..writeln('        kind: CCContractKind.${requirement['kind']},')
      ..writeln('        contractId: ${jsonEncode(requirement['id'])},')
      ..writeln('        consumerPackage: ${jsonEncode(packageName)},')
      ..writeln(
        '        ownerComponentId: ${jsonEncode(requirement['owner'])},',
      )
      ..writeln(
        '        requiredVersionRange: ${jsonEncode(requirement['version'])},',
      )
      ..writeln(
        '        requiredShapeFingerprint: ${jsonEncode(requirement['fingerprint'])},',
      )
      ..writeln('      ),');
  }
  return out.toString();
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
      'src',
      'ccrouter_generated',
      'host',
      'ccrouter_host.routes.g.dart',
    ),
  );
  final devToolsEnabled = host.dependencies.contains('ccrouter_devtools');
  final devToolsCatalog = devToolsEnabled
      ? _emitGeneratedDevToolsCatalog(indexes)
      : '';
  final devToolsImport = devToolsEnabled
      ? "import 'package:ccrouter_devtools/ccrouter_devtools.dart';\n"
      : '';
  final hostToolArgument = devToolsEnabled
      ? '''
  hostToolIntegrations: [
    CCDevToolsHostIntegration(catalog: ccrouterGeneratedDevToolsCatalog),
  ],'''
      : '';
  final source = _dartFormatter.format('''
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

import 'package:ccrouter/ccrouter_host.dart'
    show CCHostAssembly;
$devToolsImport
import 'package:${host.name}/src/ccrouter_generated/host/${host.name}_ccrouter.g.dart'
    as host_package;

$devToolsCatalog
/// Validated generated Package graph installed in this Host.
final ccrouterGeneratedHostAssembly = CCHostAssembly.fromPackageBundles([
  host_package.${hostIndex.bundleSymbol},
],$hostToolArgument);
''');
  await _writeIfChanged(output, source);
  await _generateHostApiEntrypoint(host.root);
}

/// Writes the stable Host-facing barrel without exposing Host glue paths.
Future<void> _generateHostApiEntrypoint(Directory hostRoot) async {
  final output = File(
    path.join(
      hostRoot.path,
      'lib',
      'src',
      'ccrouter_generated',
      'ccrouter_host.api.g.dart',
    ),
  );
  final source = _dartFormatter.format('''
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

/// Stable Host-facing CCRouter API.
///
/// This barrel intentionally excludes Package Bundles and generated Host glue.
export 'host/ccrouter_host.routes.g.dart'
    show ccrouterGeneratedHostAssembly;
''');
  await _writeIfChanged(output, source);
}

/// Emits a deterministic DevTools Catalog from validated Package indexes.
String _emitGeneratedDevToolsCatalog(Map<String, CCPackageIndex> indexes) {
  final documents = <Map<String, Object?>>[
    for (final name in indexes.keys.toList()..sort())
      ...indexes[name]!.metadata,
  ];
  final components = <String, _DevToolsComponentData>{};
  final descriptions = <String, String>{};
  final relations = <String, _DevToolsRelationData>{};
  final capabilityKeys = <String>{};

  void addRelation(String sourceId, String targetId, String kind) {
    if (sourceId.isEmpty || targetId.isEmpty) return;
    final relation = _DevToolsRelationData(sourceId, targetId, kind);
    relations.putIfAbsent(relation.key, () => relation);
  }

  for (final document in documents) {
    for (final component in _objects(document['components'])) {
      final id = '${component['id'] ?? ''}';
      final version = '${component['version'] ?? ''}';
      if (id.isEmpty || version.isEmpty) continue;
      final dependencies = _strings(component['dependencies'])..sort();
      final optionalDependencies = _strings(component['optionalDependencies'])
        ..sort();
      final candidate = _DevToolsComponentData(
        id: id,
        version: version,
        dependencies: dependencies,
        optionalDependencies: optionalDependencies,
      );
      final existing = components[id];
      if (existing == null ||
          candidate.dependencies.length +
                  candidate.optionalDependencies.length >
              existing.dependencies.length +
                  existing.optionalDependencies.length) {
        components[id] = candidate;
      }
      for (final dependency in dependencies) {
        addRelation(id, dependency, 'dependsOn');
      }
      for (final dependency in optionalDependencies) {
        addRelation(id, dependency, 'optionallyDependsOn');
      }
      for (final dependency in _objects(component['serviceDependencies'])) {
        addRelation(id, '${dependency['id'] ?? ''}', 'calls');
      }
      for (final dependency in _objects(component['commandDependencies'])) {
        addRelation(id, '${dependency['id'] ?? ''}', 'executes');
      }
    }
    for (final route in _objects(document['routes'])) {
      _captureDevToolsDescription(descriptions, route);
      _captureDevToolsCapabilityKey(capabilityKeys, 'route', route, 'id');
    }
    for (final implementation in _objects(document['routeImplementations'])) {
      _captureDevToolsCapabilityKey(
        capabilityKeys,
        'route',
        implementation,
        'routeId',
      );
    }
    for (final entry in const {
      'serviceContracts': 'service',
      'serviceImplementations': 'service',
      'commandContracts': 'command',
      'commandHandlers': 'command',
      'eventContracts': 'event',
      'initTaskContracts': 'initTask',
      'initTasks': 'initTask',
    }.entries) {
      for (final contract in _objects(document[entry.key])) {
        _captureDevToolsDescription(descriptions, contract);
        _captureDevToolsCapabilityKey(
          capabilityKeys,
          entry.value,
          contract,
          'id',
        );
      }
    }
    for (final subscription in _objects(document['eventSubscriptions'])) {
      addRelation(
        '${subscription['componentId'] ?? ''}',
        '${subscription['eventId'] ?? ''}',
        'subscribes',
      );
    }
    for (final task in _objects(document['initTasks'])) {
      final taskId = '${task['id'] ?? ''}';
      for (final dependency in _strings(task['dependsOn'])) {
        addRelation(taskId, dependency, 'dependsOn');
      }
    }
  }

  final records = <String, _DevToolsRecordData>{};
  for (final name in indexes.keys.toList()..sort()) {
    for (final record in indexes[name]!.capabilityCatalog.records) {
      if (!capabilityKeys.contains('${record.kind}\u0000${record.id}')) {
        continue;
      }
      final key = '${record.kind}\u0000${record.id}\u0000${record.componentId}';
      final source = record.implementation ?? record.contract;
      final sourcePackage = source?.packageName ?? '';
      final candidate = _DevToolsRecordData(
        kind: record.kind,
        id: record.id,
        ownerComponentId: record.componentId,
        packageName: sourcePackage.isEmpty ? record.packageName : sourcePackage,
        source: source,
        description: descriptions['${record.kind}\u0000${record.id}'],
        implementationSource: record.implementation != null,
      );
      final existing = records[key];
      if (existing == null ||
          (!existing.implementationSource && candidate.implementationSource) ||
          (existing.source == null && candidate.source != null)) {
        records[key] = candidate;
      }
    }
  }

  final componentValues = components.values.toList()
    ..sort((left, right) => left.id.compareTo(right.id));
  final recordValues = records.values.toList()
    ..sort((left, right) {
      final kind = left.kind.compareTo(right.kind);
      if (kind != 0) return kind;
      final id = left.id.compareTo(right.id);
      if (id != 0) return id;
      return left.ownerComponentId.compareTo(right.ownerComponentId);
    });
  final relationValues = relations.values.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  final fingerprint = computeCCCanonicalJsonFingerprint({
    'components': [for (final component in componentValues) component.toJson()],
    'records': [for (final record in recordValues) record.toJson()],
    'relations': [for (final relation in relationValues) relation.toJson()],
  });

  final out = StringBuffer()
    ..writeln('/// Generated static source and dependency index for DevTools.')
    ..writeln(
      'final ccrouterGeneratedDevToolsCatalog = CCDevToolsStaticCatalogSnapshot(',
    )
    ..writeln(
      '  capturedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),',
    )
    ..writeln('  catalogFingerprint: ${jsonEncode(fingerprint)},')
    ..writeln('  components: [');
  for (final component in componentValues) {
    out
      ..writeln('    CCDevToolsCatalogComponent(')
      ..writeln('      id: ${jsonEncode(component.id)},')
      ..writeln('      version: ${jsonEncode(component.version)},')
      ..writeln('      dependencies: ${jsonEncode(component.dependencies)},')
      ..writeln(
        '      optionalDependencies: ${jsonEncode(component.optionalDependencies)},',
      )
      ..writeln('    ),');
  }
  out
    ..writeln('  ],')
    ..writeln('  records: [');
  for (final record in recordValues) {
    final source = record.source;
    out
      ..writeln('    CCDevToolsCatalogRecord(')
      ..writeln('      kind: ${jsonEncode(record.kind)},')
      ..writeln('      id: ${jsonEncode(record.id)},')
      ..writeln(
        '      ownerComponentId: ${jsonEncode(record.ownerComponentId)},',
      )
      ..writeln('      packageName: ${jsonEncode(record.packageName)},');
    if (record.description case final description?) {
      out.writeln('      description: ${jsonEncode(description)},');
    }
    if (source != null && source.line != null && source.column != null) {
      out
        ..writeln('      source: CCDevToolsSourceLocation(')
        ..writeln('        packageName: ${jsonEncode(source.packageName)},')
        ..writeln('        packageUri: ${jsonEncode(source.packageUri)},')
        ..writeln('        line: ${source.line},')
        ..writeln('        column: ${source.column},')
        ..writeln('      ),');
    }
    out.writeln('    ),');
  }
  out
    ..writeln('  ],')
    ..writeln('  relations: [');
  for (final relation in relationValues) {
    out
      ..writeln('    CCDevToolsCatalogRelation(')
      ..writeln('      sourceId: ${jsonEncode(relation.sourceId)},')
      ..writeln('      targetId: ${jsonEncode(relation.targetId)},')
      ..writeln('      kind: ${jsonEncode(relation.kind)},')
      ..writeln('    ),');
  }
  out
    ..writeln('  ],')
    ..writeln(');')
    ..writeln();
  return out.toString();
}

/// Adds one real capability identity while excluding implementation helpers.
void _captureDevToolsCapabilityKey(
  Set<String> keys,
  String kind,
  Map<String, Object?> metadata,
  String idField,
) {
  final id = '${metadata[idField] ?? ''}';
  if (id.isNotEmpty) keys.add('$kind\u0000$id');
}

/// Retains a non-empty capability description by stable kind and ID.
void _captureDevToolsDescription(
  Map<String, String> descriptions,
  Map<String, Object?> metadata,
) {
  final id = '${metadata['id'] ?? ''}';
  final description = '${metadata['description'] ?? ''}'.trim();
  if (id.isEmpty || description.isEmpty) return;
  final kind = metadata.containsKey('patterns')
      ? 'route'
      : metadata.containsKey('resultType')
      ? 'command'
      : metadata.containsKey('eventType')
      ? 'event'
      : metadata.containsKey('gate')
      ? 'initTask'
      : 'service';
  descriptions.putIfAbsent('$kind\u0000$id', () => description);
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

/// Removes obsolete per-source metadata and documentation from source trees.
///
/// Migration runs only after new outputs have been validated and written.
/// Host aggregates, current catalogs, and unknown user files are preserved;
/// only CCRouter-owned per-source suffixes and the former nested `metadata/`
/// contents are eligible for deletion.
Future<void> _removeLegacyMetadataArtifacts(
  Iterable<Directory> generatedDirectories,
) async {
  for (final generatedDirectory in generatedDirectories) {
    if (!generatedDirectory.existsSync()) continue;
    final directories = <Directory>[];
    final unknownFiles = <String>[];
    await for (final entity in generatedDirectory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Directory) {
        if (!path.equals(entity.path, generatedDirectory.path)) {
          directories.add(entity);
        }
        continue;
      }
      if (entity is! File) continue;
      if (_isLegacyMetadataArtifact(entity)) {
        await entity.delete();
      } else if (_isWithinLegacyMetadataDirectory(generatedDirectory, entity)) {
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
        'directory ${path.join(generatedDirectory.path, 'metadata')}:',
      );
      for (final file in unknownFiles) {
        stderr.writeln('  $file');
      }
    }
  }
}

/// Removes empty managed source directories without touching unknown files.
///
/// The walk is bounded to `lib/src/ccrouter_generated` in one Package and
/// proceeds from leaves to the root. A directory containing a user-owned file
/// or subdirectory remains intact, so cleanup cannot broaden ownership beyond
/// files already recognized by the generator.
Future<void> _removeEmptyGeneratedSourceDirectories(
  Directory packageRoot,
) async {
  final generatedRoot = Directory(
    path.join(packageRoot.path, 'lib', 'src', 'ccrouter_generated'),
  );
  if (!generatedRoot.existsSync()) return;
  final directories = <Directory>[generatedRoot];
  await for (final entity in generatedRoot.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is Directory) directories.add(entity);
  }
  directories.sort(
    (left, right) => right.path.length.compareTo(left.path.length),
  );
  for (final directory in directories) {
    if (directory.existsSync() && await directory.list().isEmpty) {
      await directory.delete();
    }
  }
}

/// Whether [file] is nested below the former `metadata/` directory.
bool _isWithinLegacyMetadataDirectory(Directory generatedDirectory, File file) {
  final legacyDirectory = Directory(
    path.join(generatedDirectory.path, 'metadata'),
  );
  return path.isWithin(
    path.normalize(legacyDirectory.absolute.path),
    path.normalize(file.absolute.path),
  );
}

/// Whether [file] is an obsolete CCRouter-owned metadata or route-doc output.
bool _isLegacyMetadataArtifact(File file) {
  final name = path.basename(file.path);
  return name == 'ccrouter_package.json' ||
      name == 'cc_catalog.md' ||
      name == 'cc_routes.json' ||
      name == 'cc_routes.md' ||
      name == 'cc_sources.md' ||
      name.endsWith('.route.json') ||
      name.endsWith('.service.json') ||
      name.endsWith('.command.json') ||
      name.endsWith('.event.json') ||
      name.endsWith('.init_task.json') ||
      name.endsWith('.route.md') ||
      name.endsWith('.component.json') ||
      name.endsWith('.component.md');
}

/// Deletes stale CLI aggregates only inside explicitly writable Packages.
Future<void> _deleteObsoleteResolvedOutputs({
  required CCPackageWorkspace workspace,
  required Set<String> runtimeBundles,
  required Iterable<_GeneratedComponentCatalog> catalogs,
  required Set<String> contractApiOutputs,
}) async {
  final expected = <String>{
    ...contractApiOutputs,
    path.normalize(
      path.join(
        workspace.host.root.path,
        'lib',
        'src',
        'ccrouter_generated',
        'ccrouter_host.api.g.dart',
      ),
    ),
    path.normalize(
      path.join(
        workspace.host.root.path,
        'lib',
        'src',
        'ccrouter_generated',
        'host',
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
          'component',
          '${_fileStem(catalog.componentId)}.component.g.dart',
        ),
      ),
    for (final catalog in catalogs)
      if (catalog.hasRouteApi)
        path.normalize(
          path.join(
            catalog.packageRoot.path,
            'lib',
            'src',
            'ccrouter_generated',
            'component',
            '${_fileStem(catalog.componentId)}.route_api.g.dart',
          ),
        ),
    for (final catalog in catalogs)
      if (catalog.hasCommandApi)
        path.normalize(
          path.join(
            catalog.packageRoot.path,
            'lib',
            'src',
            'ccrouter_generated',
            'component',
            '${_fileStem(catalog.componentId)}.command_api.g.dart',
          ),
        ),
    for (final catalog in catalogs)
      if (catalog.hasEventApi)
        path.normalize(
          path.join(
            catalog.packageRoot.path,
            'lib',
            'src',
            'ccrouter_generated',
            'component',
            '${_fileStem(catalog.componentId)}.event_api.g.dart',
          ),
        ),
    for (final catalog in catalogs)
      if (catalog.hasRouteApi ||
          catalog.hasServiceApi ||
          catalog.hasCommandApi ||
          catalog.hasEventApi)
        path.normalize(
          path.join(
            catalog.packageRoot.path,
            'lib',
            'src',
            'ccrouter_generated',
            '${_fileStem(catalog.componentId)}.api.g.dart',
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
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File &&
            (entity.path.endsWith('.component.g.dart') ||
                entity.path.endsWith('.routes.g.dart') ||
                entity.path.endsWith('.route_api.g.dart') ||
                entity.path.endsWith('.command_api.g.dart') ||
                entity.path.endsWith('.event_api.g.dart') ||
                entity.path.endsWith('.api.g.dart'))) {
          candidates.add(entity);
        }
      }
    }
    final packageBundle = package.bundleFile;
    if (packageBundle.existsSync()) candidates.add(packageBundle);
    final legacyPackageBundle = File(
      path.join(package.root.path, 'lib', '${package.name}_ccrouter.g.dart'),
    );
    if (legacyPackageBundle.existsSync()) candidates.add(legacyPackageBundle);
    if (package.name == workspace.host.name) {
      final hostCatalog = File(
        path.join(
          package.root.path,
          'lib',
          'src',
          'ccrouter_generated',
          'host',
          'ccrouter_host.routes.g.dart',
        ),
      );
      if (hostCatalog.existsSync()) candidates.add(hostCatalog);
      final legacyHostCatalog = File(
        path.join(
          package.root.path,
          'lib',
          'ccrouter_generated',
          'ccrouter_host.routes.g.dart',
        ),
      );
      if (legacyHostCatalog.existsSync()) candidates.add(legacyHostCatalog);
      final nestedLegacyHostCatalog = File(
        path.join(
          package.root.path,
          'lib',
          'ccrouter_generated',
          'host',
          'ccrouter_host.routes.g.dart',
        ),
      );
      if (nestedLegacyHostCatalog.existsSync()) {
        candidates.add(nestedLegacyHostCatalog);
      }
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
      '${packageCatalogs.first.packageRoot.path}${Platform.pathSeparator}lib${Platform.pathSeparator}src${Platform.pathSeparator}ccrouter_generated${Platform.pathSeparator}host${Platform.pathSeparator}${entry.key}_ccrouter.g.dart',
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
          "export 'package:${entry.key}/${catalog.registrarSource.substring('lib/'.length)}'",
        )
        ..writeln(
          '    show ${catalog.manifest}, ${_camelIdentifier(catalog.componentId)}RouteCatalog;',
        );
    }
    await output.parent.create(recursive: true);
    await _writeIfChanged(output, _dartFormatter.format(out.toString()));
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
    '${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}src${Platform.pathSeparator}ccrouter_generated${Platform.pathSeparator}host',
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
    ..writeln("import 'package:ccrouter/ccrouter_host.dart';");
  for (final entry
      in aliases.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key))) {
    out.writeln(
      "import 'package:${entry.key}/src/ccrouter_generated/host/${entry.key}_ccrouter.g.dart' as ${entry.value};",
    );
  }
  out
    ..writeln()
    ..writeln('/// Complete generated assembly installed in this Host.')
    ..writeln(
      'final ccrouterGeneratedHostAssembly = CCHostAssembly.fromComponents(',
    )
    ..writeln('  components: [');
  for (final catalog in sorted) {
    out.writeln('  ${aliases[catalog.package]}.${catalog.manifest},');
  }
  out
    ..writeln('  ],')
    ..writeln('  routeCatalog: CCFlutterRouteCatalog.merge([');
  for (final catalog in sorted) {
    out.writeln(
      '  ${aliases[catalog.package]}.${_camelIdentifier(catalog.componentId)}RouteCatalog,',
    );
  }
  out
    ..writeln('  ]),')
    ..writeln(');')
    ..writeln();
  await File(
    '${outputDirectory.path}${Platform.pathSeparator}ccrouter_host.routes.g.dart',
  ).writeAsString(_dartFormatter.format(out.toString()));
  await _generateHostApiEntrypoint(root);
}

/// Deletes obsolete aggregate indexes that no current component can own.
///
/// Only files with CCRouter-specific aggregate signatures and suffixes are
/// eligible. Builder-owned route libraries and bindings, handwritten sources,
/// and another generator's files remain untouched even if they share the
/// standard header.
Future<void> _deleteObsoleteAggregateOutputs(
  Directory root,
  Iterable<_GeneratedComponentCatalog> catalogs, {
  required Set<String> contractApiOutputs,
}) async {
  final expected = <String>{
    ...contractApiOutputs,
    '${root.absolute.path}${Platform.pathSeparator}lib${Platform.pathSeparator}src${Platform.pathSeparator}ccrouter_generated${Platform.pathSeparator}ccrouter_host.api.g.dart',
    '${root.absolute.path}${Platform.pathSeparator}lib${Platform.pathSeparator}src${Platform.pathSeparator}ccrouter_generated${Platform.pathSeparator}host${Platform.pathSeparator}ccrouter_host.routes.g.dart',
  };
  for (final catalog in catalogs) {
    expected.add(
      '${catalog.packageRoot.absolute.path}${Platform.pathSeparator}lib${Platform.pathSeparator}src${Platform.pathSeparator}ccrouter_generated${Platform.pathSeparator}component${Platform.pathSeparator}${_fileStem(catalog.componentId)}.component.g.dart',
    );
    if (catalog.hasRouteApi) {
      expected.add(
        '${catalog.packageRoot.absolute.path}${Platform.pathSeparator}lib${Platform.pathSeparator}src${Platform.pathSeparator}ccrouter_generated${Platform.pathSeparator}component${Platform.pathSeparator}${_fileStem(catalog.componentId)}.route_api.g.dart',
      );
    }
    if (catalog.hasCommandApi) {
      expected.add(
        '${catalog.packageRoot.absolute.path}${Platform.pathSeparator}lib${Platform.pathSeparator}src${Platform.pathSeparator}ccrouter_generated${Platform.pathSeparator}component${Platform.pathSeparator}${_fileStem(catalog.componentId)}.command_api.g.dart',
      );
    }
    if (catalog.hasEventApi) {
      expected.add(
        '${catalog.packageRoot.absolute.path}${Platform.pathSeparator}lib${Platform.pathSeparator}src${Platform.pathSeparator}ccrouter_generated${Platform.pathSeparator}component${Platform.pathSeparator}${_fileStem(catalog.componentId)}.event_api.g.dart',
      );
    }
    if (catalog.hasRouteApi ||
        catalog.hasServiceApi ||
        catalog.hasCommandApi ||
        catalog.hasEventApi) {
      expected.add(
        '${catalog.packageRoot.absolute.path}${Platform.pathSeparator}lib${Platform.pathSeparator}src${Platform.pathSeparator}ccrouter_generated${Platform.pathSeparator}${_fileStem(catalog.componentId)}.api.g.dart',
      );
    }
    expected.add(
      '${catalog.packageRoot.absolute.path}${Platform.pathSeparator}lib${Platform.pathSeparator}src${Platform.pathSeparator}ccrouter_generated${Platform.pathSeparator}host${Platform.pathSeparator}${catalog.package}_ccrouter.g.dart',
    );
  }

  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final segments = _relativePath(root, entity).split('/');
    if (segments.contains('.dart_tool') || segments.contains('build')) continue;
    final name = entity.uri.pathSegments.last;
    if (!name.endsWith('.component.g.dart') &&
        !name.endsWith('.routes.g.dart') &&
        !name.endsWith('.route_api.g.dart') &&
        !name.endsWith('.command_api.g.dart') &&
        !name.endsWith('.event_api.g.dart') &&
        !name.endsWith('.api.g.dart') &&
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
    return contents.contains('ccrouterGeneratedHostAssembly') ||
        (contents.contains('ccrouterGeneratedComponentManifests') &&
            contents.contains('ccrouterGeneratedRouteCatalog'));
  }
  if (name.endsWith('.route_api.g.dart')) {
    return contents.contains(
      'Typed navigation entry points for routes internal',
    );
  }
  if (name.endsWith('.command_api.g.dart')) {
    return contents.contains('Typed Command entry points for component');
  }
  if (name.endsWith('.event_api.g.dart')) {
    return contents.contains(
      'Typed Event publication entry points for component',
    );
  }
  if (name.endsWith('.api.g.dart')) {
    return contents.contains('Stable typed API entry point for component') ||
        contents.contains('Stable Host-facing CCRouter API') ||
        contents.contains('Stable generated Contract API entry point');
  }
  if (name.endsWith('.component.g.dart')) {
    return contents.contains('Generated capability Registrar for component');
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

/// Sorts manual contributions by stable identity and source location.
int _compareContributions(
  _ContributionRegistration left,
  _ContributionRegistration right,
) {
  final id = left.id.compareTo(right.id);
  if (id != 0) return id;
  final source = left.source.compareTo(right.source);
  return source == 0 ? left.symbol.compareTo(right.symbol) : source;
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
    required this.symbol,
    required this.manifest,
    required this.packageRoot,
  });

  /// Package name used by generated package imports.
  final String package;

  /// Component registrar source path relative to `lib/`.
  final String source;

  /// Public top-level const CCComponent read by generated assembly code.
  final String symbol;

  /// Generated Manifest symbol exported through the package Host library.
  final String manifest;

  /// Source Package root where generated registration code is published.
  final Directory packageRoot;
}

/// Describes one route contribution for a generated component index.
final class _RouteRegistration {
  /// Creates a normalized route contribution record.
  const _RouteRegistration({
    required this.package,
    required this.source,
    required this.builderSource,
    required this.routeId,
    required this.registration,
    required this.descriptor,
    required this.builder,
    required this.intentFactory,
  });

  /// Package name used by generated package imports.
  final String package;

  /// Source library containing the generated registration bridge.
  final String source;

  /// Generated library containing the Flutter page-construction bridge.
  final String builderSource;

  /// Stable route ID used for deterministic sorting.
  final String routeId;

  /// Generated bridge symbol exposed only to package-internal code.
  final String registration;

  /// Generated bridge returning adapter-neutral route metadata.
  final String descriptor;

  /// Generated bridge decoding arguments and creating the Flutter page.
  final String builder;

  /// Callable factory exported through the component Route API when internal.
  final String intentFactory;
}

/// Describes one restricted manual registration contribution.
final class _ContributionRegistration {
  /// Creates a generated contribution call record.
  const _ContributionRegistration({
    required this.package,
    required this.source,
    required this.id,
    required this.symbol,
    this.subscriberId,
  });

  /// Package containing the contribution function.
  final String package;

  /// Source library imported by generated component assembly.
  final String source;

  /// Stable identity controlling deterministic invocation order.
  final String id;

  /// Public top-level function invoked with the restricted Registry.
  final String symbol;

  /// Stable generated Subscriber ID passed to an Event registration bridge.
  final String? subscriberId;
}

/// One generated Command Client method derived from static metadata.
final class _CommandClientEntry {
  /// Creates a normalized Client entry.
  const _CommandClientEntry({
    required this.id,
    required this.library,
    required this.type,
    required this.resultType,
    required this.member,
  });

  /// Reads one Contract record and derives its default method name.
  factory _CommandClientEntry.fromMetadata(
    Map<String, Object?> metadata, {
    String? member,
    String? library,
  }) {
    final type = '${metadata['type'] ?? ''}';
    final declaration = metadata['declaration'];
    final declarationMap = declaration is Map
        ? declaration.cast<Object?, Object?>()
        : const <Object?, Object?>{};
    return _CommandClientEntry(
      id: '${metadata['id'] ?? ''}',
      library: library == null || library.isEmpty
          ? '${declarationMap['packageUri'] ?? ''}'
          : library,
      type: type,
      resultType: '${metadata['resultType'] ?? 'Object?'}',
      member: member == null || member.isEmpty
          ? '${metadata['alias'] ?? ''}'.isNotEmpty
                ? '${metadata['alias']}'
                : defaultCommandClientMember(type)
          : member,
    );
  }

  /// Stable Contract identity.
  final String id;

  /// Public source library containing the Command class.
  final String library;

  /// Command class name.
  final String type;

  /// Static Command result type.
  final String resultType;

  /// Generated lower-camel method.
  final String member;
}

/// One generated Event publication method derived from static metadata.
final class _EventClientEntry {
  /// Creates one normalized Event publication entry.
  const _EventClientEntry({
    required this.id,
    required this.library,
    required this.type,
    required this.member,
  });

  /// Reads one Event Contract and derives its publication method name.
  factory _EventClientEntry.fromMetadata(Map<String, Object?> metadata) {
    final type = '${metadata['type'] ?? ''}';
    final declaration = metadata['declaration'];
    final declarationMap = declaration is Map
        ? declaration.cast<Object?, Object?>()
        : const <Object?, Object?>{};
    return _EventClientEntry(
      id: '${metadata['id'] ?? ''}',
      library: '${declarationMap['packageUri'] ?? ''}',
      type: type,
      member: _eventClientMember(type),
    );
  }

  /// Stable Event identity.
  final String id;

  /// Public source library containing the Event class.
  final String library;

  /// Event class name.
  final String type;

  /// Generated lower-camel publication method.
  final String member;
}

/// Derives a concise generated Event publication method name.
String _eventClientMember(String type) {
  final stem = type.endsWith('Event')
      ? type.substring(0, type.length - 'Event'.length)
      : type;
  final name = stem.isEmpty
      ? 'event'
      : '${stem[0].toUpperCase()}${stem.substring(1)}';
  return 'publish$name';
}

/// Normalized Component node emitted into the generated DevTools Catalog.
final class _DevToolsComponentData {
  /// Creates one deterministic Component node.
  const _DevToolsComponentData({
    required this.id,
    required this.version,
    required this.dependencies,
    required this.optionalDependencies,
  });

  /// Stable Component identity.
  final String id;

  /// Component contract version.
  final String version;

  /// Required Component dependencies.
  final List<String> dependencies;

  /// Optional dependencies present in the resolved Host.
  final List<String> optionalDependencies;

  /// Canonical JSON used only for deterministic fingerprinting.
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'dependencies': dependencies,
    'optionalDependencies': optionalDependencies,
  };
}

/// Normalized capability record emitted into the generated DevTools Catalog.
final class _DevToolsRecordData {
  /// Creates one record from a validated Package capability index.
  const _DevToolsRecordData({
    required this.kind,
    required this.id,
    required this.ownerComponentId,
    required this.packageName,
    required this.source,
    required this.description,
    required this.implementationSource,
  });

  /// Closed capability category.
  final String kind;

  /// Stable capability identity.
  final String id;

  /// Component owning the capability.
  final String ownerComponentId;

  /// Package declaring the selected source.
  final String packageName;

  /// Preferred implementation or Contract source location.
  final CCSourceReference? source;

  /// Optional authored description.
  final String? description;

  /// Whether [source] points at an implementation instead of only a Contract.
  final bool implementationSource;

  /// Canonical JSON used only for deterministic fingerprinting.
  Map<String, Object?> toJson() => {
    'kind': kind,
    'id': id,
    'ownerComponentId': ownerComponentId,
    'packageName': packageName,
    'source': source?.toJson(),
    'description': description,
  };
}

/// Normalized static dependency or invocation relation.
final class _DevToolsRelationData {
  /// Creates one graph edge.
  const _DevToolsRelationData(this.sourceId, this.targetId, this.kind);

  /// Stable source node identity.
  final String sourceId;

  /// Stable target node identity.
  final String targetId;

  /// Relation category interpreted by read-only tooling.
  final String kind;

  /// Deterministic deduplication and ordering key.
  String get key => '$kind\u0000$sourceId\u0000$targetId';

  /// Canonical JSON used only for deterministic fingerprinting.
  Map<String, Object?> toJson() => {
    'sourceId': sourceId,
    'targetId': targetId,
    'kind': kind,
  };
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
    required this.hasRouteApi,
    required this.hasServiceApi,
    required this.hasCommandApi,
    required this.hasEventApi,
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

  /// Whether the component owns internal routes needing a typed package API.
  final bool hasRouteApi;

  /// Whether the component consumes generated Service Proxies.
  final bool hasServiceApi;

  /// Whether the component owns or consumes generated Command contracts.
  final bool hasCommandApi;

  /// Whether the component owns generated Event publication contracts.
  final bool hasEventApi;
}
