import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ccrouter_generator/src/project_context.dart';
import 'package:ccrouter_generator/src/project_role.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

part 'analyzer_installation.dart';
part 'analyzer_installation_files.dart';

/// Explicit Host Analyzer bootstrap operation exposed by the CLI.
enum CCAnalyzerBootstrapAction {
  /// Reports installation identity and consistency without running tools.
  status,

  /// Verifies locked dependencies, analysis, and loader compilation.
  doctor,

  /// Verifies the maintained Git pin and reports production drift after it.
  pinCheck,

  /// Installs a verified, CLI-owned isolated bootstrap.
  install,

  /// Replaces only an unchanged CLI-owned bootstrap with an explicit version.
  upgrade,

  /// Removes only verified CLI-owned files and YAML entries.
  uninstall,
}

/// Parsed request for one explicit Analyzer bootstrap operation.
final class CCAnalyzerBootstrapRequest {
  /// Creates a request scoped to one application Host directory.
  const CCAnalyzerBootstrapRequest({
    required this.action,
    required this.hostRoot,
    this.source,
    this.version,
    this.url,
    this.ref,
    this.gitPath,
    this.dryRun = false,
  });

  /// Operation explicitly selected by the developer.
  final CCAnalyzerBootstrapAction action;

  /// Application Host that owns `analysis_options.yaml` and the bootstrap.
  final String hostRoot;

  /// Hosted by default on install; upgrade inherits its existing source.
  final String? source;

  /// Explicit Hosted version constraint; no unpublished default is assumed.
  final String? version;

  /// Remote Git URL, never a local repository or relative path.
  final String? url;

  /// Full remote Git commit, never a branch, tag, or short SHA.
  final String? ref;

  /// Package directory inside the remote monorepo.
  final String? gitPath;

  /// Prints planned changes without running subprocesses or writing files.
  final bool dryRun;
}

/// Internal CLI process seam for deterministic failure/rollback tests.
/// It is not exported from the generator's package API.
typedef AnalyzerBootstrapProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
      Map<String, String>? environment,
    });

/// Executes one Analyzer bootstrap request and reports whether it is healthy.
Future<bool> runAnalyzerBootstrapCommand(
  CCAnalyzerBootstrapRequest request, {
  AnalyzerBootstrapProcessRunner? processRunner,
  StringSink? output,
  StringSink? error,
  String? homeDirectory,
  String? operatingSystem,
}) async {
  final runner = processRunner ?? _runAnalyzerProcess;
  final readOnly =
      request.action == CCAnalyzerBootstrapAction.status ||
      request.action == CCAnalyzerBootstrapAction.doctor ||
      request.action == CCAnalyzerBootstrapAction.pinCheck;
  if (!readOnly) {
    if (request.action == CCAnalyzerBootstrapAction.install ||
        request.action == CCAnalyzerBootstrapAction.upgrade) {
      stderr.writeln(
        'warning: analyzer ${request.action.name} is a legacy management '
        'path. Prefer a normal Hosted dev_dependency after '
        '`ccrouter_analyzer_plugin` is published; no new management '
        'features will be added here.',
      );
    }
    try {
      return await _runAnalyzerInstallation(request, runner);
    } on Object catch (error) {
      stderr.writeln('error: Analyzer ${request.action.name} failed: $error');
      return false;
    }
  }
  final report = _AnalyzerBootstrapReport.inspect(
    Directory(request.hostRoot).absolute,
  );
  final outputSink = output ?? stdout;
  final errorSink = error ?? stderr;
  report.writeTo(outputSink);
  if (report.state != _AnalyzerBootstrapState.healthy) return false;
  if (request.action == CCAnalyzerBootstrapAction.status) return true;
  if (request.action == CCAnalyzerBootstrapAction.pinCheck) {
    return _runAnalyzerPinCheck(
      report,
      runner: runner,
      output: outputSink,
      error: errorSink,
    );
  }
  return _runDoctor(
    report,
    runner: runner,
    output: outputSink,
    error: errorSink,
    homeDirectory: homeDirectory,
    operatingSystem: operatingSystem,
  );
}

/// Verifies one maintained Git bootstrap without mutating repository state.
///
/// Production drift is advisory because the supported two-stage workflow first
/// pushes Plugin changes and only then updates the Host pin in another commit.
Future<bool> _runAnalyzerPinCheck(
  _AnalyzerBootstrapReport report, {
  AnalyzerBootstrapProcessRunner runner = _runAnalyzerProcess,
  StringSink? output,
  StringSink? error,
}) async {
  final outputSink = output ?? stdout;
  final errorSink = error ?? stderr;
  if (report.source != 'git' || report.bootstrapRoot == null) {
    errorSink.writeln(
      'error: Analyzer pin-check applies only to a Git bootstrap. Hosted '
      'dependencies use their published version and lockfile identity.',
    );
    return false;
  }
  final manifest = _readYamlMap(
    File(path.join(report.bootstrapRoot!.path, 'pubspec.yaml')),
  );
  final dependency = _stringKeyedMap(
    _stringKeyedMap(manifest?['dependencies'])['ccrouter_analyzer_plugin'],
  );
  final git = _stringKeyedMap(dependency['git']);
  final url = git['url']?.toString();
  final gitPath = git['path']?.toString();
  final ref = git['ref']?.toString();
  if (url == null || gitPath == null || ref == null) {
    errorSink.writeln(
      'error: Analyzer pin-check requires Git url, path, and ref in the '
      'active bootstrap manifest.',
    );
    return false;
  }
  late final _AnalyzerSource source;
  try {
    source = _AnalyzerSource.select(
      CCAnalyzerBootstrapRequest(
        action: CCAnalyzerBootstrapAction.pinCheck,
        hostRoot: report.hostRoot.path,
        source: 'git',
        url: url,
        ref: ref,
        gitPath: gitPath,
      ),
      null,
    );
  } on ArgumentError catch (failure) {
    errorSink.writeln(
      'error: Analyzer pin-check rejected the Git identity: '
      '${failure.message}',
    );
    return false;
  }

  final repository = _findGitRepository(report.hostRoot);
  if (repository == null) {
    errorSink.writeln(
      'error: Analyzer pin-check must run from a Host inside the maintained '
      'cc-router Git checkout.',
    );
    return false;
  }
  final productionPath = path.posix.join(source.gitPath!, 'lib');
  final productionDirectory = Directory(
    path.join(repository.path, path.joinAll(productionPath.split('/'))),
  );
  if (!productionDirectory.existsSync()) {
    errorSink.writeln(
      'error: Pinned Plugin production directory was not found in the '
      'maintainer checkout: ${productionDirectory.path}',
    );
    return false;
  }

  outputSink.writeln('CCRouter Analyzer pin check');
  outputSink.writeln('  source pin: current ($ref)');
  outputSink.writeln('  manifest/lock/resolved-ref: current');
  final temporary = await Directory.systemTemp.createTemp(
    'ccrouter-analyzer-pin-check-',
  );
  try {
    final init = await runner(
      'git',
      const ['init', '--bare', '--quiet'],
      workingDirectory: temporary.path,
      environment: const {'GIT_TERMINAL_PROMPT': '0'},
    );
    if (init.exitCode != 0) {
      _writeAnalyzerPinProcessFailure(errorSink, 'prepare remote proof', init);
      return false;
    }
    final fetch = await runner(
      'git',
      ['fetch', '--quiet', '--no-tags', '--depth=1', source.url!, source.ref!],
      workingDirectory: temporary.path,
      environment: const {'GIT_TERMINAL_PROMPT': '0'},
    );
    if (fetch.exitCode != 0) {
      _writeAnalyzerPinProcessFailure(errorSink, 'resolve remote pin', fetch);
      return false;
    }
    outputSink.writeln('  remote ref: resolvable');

    final localCommit = await runner(
      'git',
      ['cat-file', '-e', '${source.ref}^{commit}'],
      workingDirectory: repository.path,
      environment: const {'GIT_TERMINAL_PROMPT': '0'},
    );
    if (localCommit.exitCode != 0) {
      _writeAnalyzerPinProcessFailure(
        errorSink,
        'resolve pinned commit in maintainer checkout',
        localCommit,
      );
      return false;
    }
    final ancestry = await runner(
      'git',
      ['merge-base', '--is-ancestor', source.ref!, 'HEAD'],
      workingDirectory: repository.path,
      environment: const {'GIT_TERMINAL_PROMPT': '0'},
    );
    if (ancestry.exitCode != 0) {
      errorSink.writeln(
        'error: The pinned commit is not an ancestor of the maintainer '
        'checkout HEAD, so changes "after" the pin cannot be classified '
        'reliably.',
      );
      return false;
    }
    final diff = await runner(
      'git',
      ['diff', '--name-only', source.ref!, '--', productionPath],
      workingDirectory: repository.path,
      environment: const {'GIT_TERMINAL_PROMPT': '0'},
    );
    if (diff.exitCode != 0) {
      _writeAnalyzerPinProcessFailure(
        errorSink,
        'compare Plugin production sources',
        diff,
      );
      return false;
    }
    final changed = '${diff.stdout}'
        .split(RegExp(r'\r?\n'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (changed.isEmpty) {
      outputSink.writeln('  production changes after pin: none');
    } else {
      outputSink.writeln(
        '  production changes after pin: pending (${changed.length} file(s))',
      );
      for (final file in changed) {
        outputSink.writeln('    $file');
      }
      outputSink.writeln(
        '  advisory: keep the current pin until the Plugin change is '
        'verified and pushed; then bump manifest/lock in a separate commit.',
      );
    }
    return true;
  } finally {
    if (temporary.existsSync()) await temporary.delete(recursive: true);
  }
}

/// Writes bounded subprocess context for one failed pin proof stage.
void _writeAnalyzerPinProcessFailure(
  StringSink sink,
  String stage,
  ProcessResult result,
) {
  sink.writeln('error: Analyzer pin-check failed to $stage.');
  final detail = '${result.stdout}\n${result.stderr}'.trim();
  if (detail.isNotEmpty) sink.writeln(detail);
}

/// Finds the enclosing Git checkout without invoking or modifying Git.
Directory? _findGitRepository(Directory start) {
  var current = start.absolute;
  while (true) {
    final marker = path.join(current.path, '.git');
    if (FileSystemEntity.typeSync(marker, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return current;
    }
    if (current.path == current.parent.path) return null;
    current = current.parent;
  }
}

/// Stable installation states printed by `status` and consumed by `doctor`.
enum _AnalyzerBootstrapState {
  /// No CCRouter plugin is enabled for this Host.
  notInstalled,

  /// Required files or resolved dependency state are missing.
  incomplete,

  /// Authored and locked bootstrap identities disagree.
  stale,

  /// Analyzer dependency constraints reject their locked versions.
  incompatible,

  /// Configuration uses an unsupported or locally modified source form.
  modified,

  /// Static configuration is complete and internally consistent.
  healthy,
}

/// Immutable result of inspecting one Host-owned Analyzer bootstrap.
final class _AnalyzerBootstrapReport {
  /// Creates one report with sanitized, developer-actionable details.
  const _AnalyzerBootstrapReport({
    required this.hostRoot,
    required this.state,
    required this.message,
    this.pluginName,
    this.bootstrapRoot,
    this.source,
    this.version,
    this.gitRef,
    this.analyzerVersion,
    this.analyzerPluginVersion,
  });

  /// Inspects only the selected Host and its configured bootstrap Package.
  factory _AnalyzerBootstrapReport.inspect(Directory hostRoot) {
    final hostManifest = _readYamlMap(
      File(path.join(hostRoot.path, 'pubspec.yaml')),
    );
    if (hostManifest == null) {
      return _AnalyzerBootstrapReport(
        hostRoot: hostRoot,
        state: _AnalyzerBootstrapState.notInstalled,
        message: 'Host pubspec.yaml was not found or is invalid.',
      );
    }
    final dependencies = _stringKeyedMap(hostManifest['dependencies']);
    if (!dependencies.containsKey('ccrouter')) {
      return _AnalyzerBootstrapReport(
        hostRoot: hostRoot,
        state: _AnalyzerBootstrapState.notInstalled,
        message: 'The selected Package is not a CCRouter Host.',
      );
    }

    final options = _readYamlMap(
      File(path.join(hostRoot.path, 'analysis_options.yaml')),
    );
    final analyzer = _stringKeyedMap(options?['analyzer']);
    final plugins = _stringList(
      analyzer['plugins'],
    ).where((name) => name.contains('ccrouter')).toList(growable: false);
    if (plugins.isEmpty) {
      return _AnalyzerBootstrapReport(
        hostRoot: hostRoot,
        state: _AnalyzerBootstrapState.notInstalled,
        message: 'analysis_options.yaml does not enable a CCRouter plugin.',
      );
    }
    if (plugins.length != 1) {
      return _AnalyzerBootstrapReport(
        hostRoot: hostRoot,
        state: _AnalyzerBootstrapState.modified,
        message: 'Exactly one CCRouter Analyzer plugin must be enabled.',
      );
    }
    final pluginName = plugins.single;
    final pluginRoot = _resolvePackageRoot(hostRoot, pluginName);
    if (pluginRoot == null) {
      return _AnalyzerBootstrapReport(
        hostRoot: hostRoot,
        pluginName: pluginName,
        state: _AnalyzerBootstrapState.incomplete,
        message:
            'The enabled plugin Package is missing from the Host package configuration.',
      );
    }
    final bootstrapRoot = Directory(
      path.join(pluginRoot.path, 'tools', 'analyzer_plugin'),
    );
    final bootstrapManifestFile = File(
      path.join(bootstrapRoot.path, 'pubspec.yaml'),
    );
    final loader = File(path.join(bootstrapRoot.path, 'bin', 'plugin.dart'));
    final bootstrapManifest = _readYamlMap(bootstrapManifestFile);
    if (bootstrapManifest == null || !loader.existsSync()) {
      return _AnalyzerBootstrapReport(
        hostRoot: hostRoot,
        pluginName: pluginName,
        bootstrapRoot: bootstrapRoot,
        state: _AnalyzerBootstrapState.incomplete,
        message: 'Analyzer bootstrap manifest or loader is missing.',
      );
    }
    final bootstrapDependencies = _stringKeyedMap(
      bootstrapManifest['dependencies'],
    );
    final pluginDependency = bootstrapDependencies['ccrouter_analyzer_plugin'];
    final source = _dependencySource(pluginDependency);
    final declaredVersion = pluginDependency is String
        ? pluginDependency
        : _stringKeyedMap(pluginDependency)['version']?.toString();
    final git = _stringKeyedMap(
      pluginDependency is YamlMap || pluginDependency is Map
          ? _stringKeyedMap(pluginDependency)['git']
          : null,
    );
    final gitRef = git['ref']?.toString();
    if (source == null) {
      return _AnalyzerBootstrapReport(
        hostRoot: hostRoot,
        pluginName: pluginName,
        bootstrapRoot: bootstrapRoot,
        state: _AnalyzerBootstrapState.incomplete,
        message: 'ccrouter_analyzer_plugin dependency is missing.',
      );
    }
    if (source == 'path' ||
        (source == 'git' &&
            (gitRef == null || !RegExp(r'^[0-9a-f]{40}$').hasMatch(gitRef)))) {
      return _AnalyzerBootstrapReport(
        hostRoot: hostRoot,
        pluginName: pluginName,
        bootstrapRoot: bootstrapRoot,
        source: source,
        version: declaredVersion,
        gitRef: gitRef,
        state: _AnalyzerBootstrapState.modified,
        message:
            'Analyzer source must be Hosted or a Git dependency pinned to a full commit SHA.',
      );
    }

    final lock = _readYamlMap(
      File(path.join(bootstrapRoot.path, 'pubspec.lock')),
    );
    final lockedPackages = _stringKeyedMap(lock?['packages']);
    final lockedPlugin = _stringKeyedMap(
      lockedPackages['ccrouter_analyzer_plugin'],
    );
    final lockedPluginSource = lockedPlugin['source']?.toString();
    final lockedPluginVersion = _lockedVersion(lockedPlugin);
    final lockedAnalyzer = _lockedVersion(lockedPackages['analyzer']);
    final lockedAnalyzerPlugin = _lockedVersion(
      lockedPackages['analyzer_plugin'],
    );
    final missingLockFields = <String>[
      if (lockedPlugin.isEmpty) 'ccrouter_analyzer_plugin package',
      if (lockedPluginSource == null) 'ccrouter_analyzer_plugin source',
      if (lockedPluginVersion == null) 'ccrouter_analyzer_plugin version',
      if (lockedAnalyzer == null) 'analyzer version',
      if (lockedAnalyzerPlugin == null) 'analyzer_plugin version',
    ];
    if (missingLockFields.isNotEmpty) {
      return _AnalyzerBootstrapReport(
        hostRoot: hostRoot,
        pluginName: pluginName,
        bootstrapRoot: bootstrapRoot,
        source: source,
        version: declaredVersion,
        gitRef: gitRef,
        state: _AnalyzerBootstrapState.incomplete,
        message:
            'Analyzer bootstrap lockfile is missing: '
            '${missingLockFields.join(', ')}.',
      );
    }
    final lockedDescription = _stringKeyedMap(lockedPlugin['description']);
    final resolvedRef = lockedDescription['resolved-ref']?.toString();
    final declaredGitUrl = git['url']?.toString();
    final declaredGitPath = git['path']?.toString();
    if (lockedPluginSource != source ||
        (source == 'git' &&
            (resolvedRef != gitRef ||
                lockedDescription['url']?.toString() != declaredGitUrl ||
                lockedDescription['path']?.toString() != declaredGitPath))) {
      return _AnalyzerBootstrapReport(
        hostRoot: hostRoot,
        pluginName: pluginName,
        bootstrapRoot: bootstrapRoot,
        source: source,
        version: lockedPluginVersion.toString(),
        gitRef: gitRef,
        analyzerVersion: lockedAnalyzer.toString(),
        analyzerPluginVersion: lockedAnalyzerPlugin.toString(),
        state: _AnalyzerBootstrapState.stale,
        message: 'Analyzer dependency source and lockfile identity differ.',
      );
    }
    final pluginConstraint = source == 'hosted'
        ? _constraint(declaredVersion)
        : VersionConstraint.any;
    final analyzerConstraint = _constraint(
      bootstrapDependencies['analyzer']?.toString(),
    );
    final analyzerPluginConstraint = _constraint(
      bootstrapDependencies['analyzer_plugin']?.toString(),
    );
    if (pluginConstraint == null ||
        analyzerConstraint == null ||
        analyzerPluginConstraint == null ||
        !pluginConstraint.allows(lockedPluginVersion!) ||
        !analyzerConstraint.allows(lockedAnalyzer!) ||
        !analyzerPluginConstraint.allows(lockedAnalyzerPlugin!)) {
      return _AnalyzerBootstrapReport(
        hostRoot: hostRoot,
        pluginName: pluginName,
        bootstrapRoot: bootstrapRoot,
        source: source,
        version: lockedPluginVersion.toString(),
        gitRef: gitRef,
        analyzerVersion: lockedAnalyzer.toString(),
        analyzerPluginVersion: lockedAnalyzerPlugin.toString(),
        state: _AnalyzerBootstrapState.incompatible,
        message: 'Locked versions do not satisfy the bootstrap manifest.',
      );
    }
    return _AnalyzerBootstrapReport(
      hostRoot: hostRoot,
      pluginName: pluginName,
      bootstrapRoot: bootstrapRoot,
      source: source,
      version: lockedPluginVersion.toString(),
      gitRef: gitRef,
      analyzerVersion: lockedAnalyzer.toString(),
      analyzerPluginVersion: lockedAnalyzerPlugin.toString(),
      state: _AnalyzerBootstrapState.healthy,
      message:
          'Analyzer bootstrap is statically consistent; loadability is '
          'unchecked until `ccrouter analyzer doctor` passes.',
    );
  }

  /// Application Host selected by the command.
  final Directory hostRoot;

  /// Stable state used for the command exit code.
  final _AnalyzerBootstrapState state;

  /// Concise reason for the reported state.
  final String message;

  /// Analysis Server plugin Package enabled by the Host.
  final String? pluginName;

  /// Isolated loader Package, when it can be resolved.
  final Directory? bootstrapRoot;

  /// Dependency source: `hosted`, `git`, or `path`.
  final String? source;

  /// Resolved plugin Package version, when locked.
  final String? version;

  /// Full Git commit selected by an unreleased bootstrap.
  final String? gitRef;

  /// Locked Analyzer version used by the bootstrap.
  final String? analyzerVersion;

  /// Locked analyzer_plugin version used by the bootstrap.
  final String? analyzerPluginVersion;

  /// Writes stable field names suitable for humans and support logs.
  void writeTo(StringSink sink) {
    sink.writeln('CCRouter Analyzer status');
    sink.writeln('  host: ${hostRoot.path}');
    sink.writeln('  state: ${state.name}');
    if (pluginName != null) sink.writeln('  plugin: $pluginName');
    if (bootstrapRoot != null) {
      sink.writeln('  bootstrap: ${bootstrapRoot!.path}');
    }
    if (source != null) sink.writeln('  source: $source');
    if (version != null) sink.writeln('  version: $version');
    if (gitRef != null) sink.writeln('  ref: $gitRef');
    if (analyzerVersion != null) sink.writeln('  analyzer: $analyzerVersion');
    if (analyzerPluginVersion != null) {
      sink.writeln('  analyzer_plugin: $analyzerPluginVersion');
    }
    if (state == _AnalyzerBootstrapState.healthy && source == 'git') {
      sink.writeln(
        '  source pin: current (manifest/lock/resolved-ref identity only)',
      );
      sink.writeln('  cache artifact: unchecked (run analyzer doctor)');
      sink.writeln('  Analysis Server live state: unverified');
    }
    sink.writeln('  detail: $message');
  }
}

/// Runs bounded, non-mutating checks inside a healthy isolated bootstrap.
Future<bool> _runDoctor(
  _AnalyzerBootstrapReport report, {
  AnalyzerBootstrapProcessRunner runner = _runAnalyzerProcess,
  StringSink? output,
  StringSink? error,
  String? homeDirectory,
  String? operatingSystem,
}) async {
  final outputSink = output ?? stdout;
  final errorSink = error ?? stderr;
  final bootstrapRoot = report.bootstrapRoot!;
  final cacheEntries = _analyzerPluginManagerCaches(
    bootstrapRoot,
    homeDirectory: homeDirectory,
  );
  final staleCaches = cacheEntries
      .where((entry) => !entry.current)
      .map((entry) => entry.directory)
      .toList(growable: false);
  if (staleCaches.isNotEmpty) {
    errorSink.writeln(
      'warning: Analyzer doctor found a stale legacy Analysis Server plugin '
      'cache (advisory only):',
    );
    for (final cache in staleCaches) {
      errorSink.writeln('  ${cache.path}');
    }
    final processReport = await _relatedAnalyzerProcesses(
      bootstrapRoot: bootstrapRoot,
      cacheEntries: staleCaches,
      runner: runner,
      operatingSystem: operatingSystem ?? Platform.operatingSystem,
    );
    if (processReport.error != null) {
      errorSink.writeln(
        'warning: Related process details are unavailable: '
        '${processReport.error}',
      );
    } else if (processReport.processes.isEmpty) {
      errorSink.writeln(
        'No related Analysis Server or exact-path process was identified. '
        'The process list is advisory and may be restricted by the OS.',
      );
    } else {
      errorSink.writeln(
        'Related process candidates (advisory; command matching does not '
        'prove cache ownership):',
      );
      for (final process in processReport.processes) {
        errorSink.writeln(
          '  PID ${process.pid} | PPID ${process.parentPid} | '
          'elapsed ${process.elapsed} | command: ${process.command}',
        );
      }
    }
    errorSink.writeln(
      'The private .plugin_manager cache is not an authoritative cross-SDK '
      'gate. Manual recovery only; doctor will not kill processes, move files, '
      'or delete IDE state:',
    );
    errorSink.writeln(
      '  1. Save editor work and stop the Dart Analysis Server from the IDE '
      '(or close the IDE window that owns this Host).',
    );
    errorSink.writeln(
      '  2. Wait for the relevant process candidates above to exit; do not '
      'kill a PID unless you have independently confirmed its ownership.',
    );
    final backupRoot = Directory(
      path.join(
        staleCaches.first.parent.parent.path,
        'ccrouter-plugin-cache-backup',
      ),
    );
    for (final cache in staleCaches) {
      errorSink.writeln('  3. Move the whole cache entry manually:');
      errorSink.writeln('       source: ${cache.path}');
      errorSink.writeln(
        '       backup: ${path.join(backupRoot.path, path.basename(cache.path))}',
      );
    }
    errorSink.writeln(
      '     If the backup destination exists, choose a new sibling name. Do '
      'not move only the analyzer_plugin child or clear unrelated caches.',
    );
    errorSink.writeln(
      '  4. Restart the Dart Analysis Server, rerun doctor, then verify a real '
      'IDE diagnostic or Quick Fix.',
    );
  }
  final temporary = await Directory.systemTemp.createTemp(
    'ccrouter-analyzer-doctor-',
  );
  try {
    final isolatedBootstrap = Directory(
      path.join(temporary.path, 'analyzer_plugin'),
    )..createSync();
    _copyDirectory(bootstrapRoot, isolatedBootstrap);
    final checks = <({String name, List<String> arguments})>[
      (
        name: 'locked dependencies',
        arguments: const ['pub', 'get', '--enforce-lockfile'],
      ),
      (name: 'bootstrap analysis', arguments: const ['analyze']),
      (
        name: 'loader compilation',
        arguments: [
          'compile',
          'exe',
          'bin/plugin.dart',
          '-o',
          path.join(temporary.path, 'ccrouter_analyzer_plugin'),
        ],
      ),
    ];
    for (final check in checks) {
      outputSink.writeln('CCRouter Analyzer doctor: ${check.name}...');
      final result = await runner(
        Platform.resolvedExecutable,
        check.arguments,
        workingDirectory: isolatedBootstrap.path,
      );
      if (result.exitCode != 0) {
        errorSink.writeln(
          'error: Analyzer doctor failed during ${check.name}.',
        );
        final output = '${result.stdout}\n${result.stderr}'.trim();
        if (output.isNotEmpty) errorSink.writeln(output);
        if (report.source == 'git' && _looksLikeGitCredentialFailure(output)) {
          errorSink.writeln(
            'error: The pinned Git Analyzer dependency could not authenticate. '
            'Configure credentials for the declared Git URL, or switch the '
            'bootstrap to the Hosted package after publication. IDE '
            'diagnostics remain unavailable until doctor passes.',
          );
        }
        return false;
      }
    }
    final cacheState = staleCaches.isNotEmpty
        ? 'stale (manual rebuild pending)'
        : cacheEntries.isEmpty
        ? 'absent (Analysis Server has not built this legacy cache entry)'
        : 'current (${cacheEntries.length} matching legacy cache entry(s))';
    outputSink.writeln('CCRouter Analyzer doctor summary');
    outputSink.writeln(
      report.source == 'git'
          ? '  source pin: current (manifest/lock/resolved-ref identity)'
          : '  source dependency: current (manifest/lock version identity)',
    );
    outputSink.writeln('  cache artifact: $cacheState');
    outputSink.writeln(
      '  loader smoke: passed in a temporary copy (not the IDE session)',
    );
    outputSink.writeln(
      '  Analysis Server restart: required before claiming bootstrap/ref or '
      'cache changes are live',
    );
    outputSink.writeln(
      '  live IDE verification: pending (doctor cannot observe or control the '
      'IDE Analysis Server)',
    );
    return true;
  } finally {
    if (temporary.existsSync()) await temporary.delete(recursive: true);
  }
}

/// One conservatively matched process that may retain Analyzer or cache state.
final class _AnalyzerRelatedProcess {
  const _AnalyzerRelatedProcess({
    required this.pid,
    required this.parentPid,
    required this.elapsed,
    required this.command,
  });

  /// Operating-system process identifier.
  final int pid;

  /// Parent process identifier reported by the operating system.
  final int parentPid;

  /// Human-readable elapsed runtime.
  final String elapsed;

  /// Full command line reported by the operating system.
  final String command;
}

/// Result of one best-effort, read-only process inventory.
typedef _AnalyzerProcessReport = ({
  List<_AnalyzerRelatedProcess> processes,
  String? error,
});

/// Lists only Analysis Server or exact-path process candidates.
Future<_AnalyzerProcessReport> _relatedAnalyzerProcesses({
  required Directory bootstrapRoot,
  required List<Directory> cacheEntries,
  required AnalyzerBootstrapProcessRunner runner,
  required String operatingSystem,
}) async {
  late final ProcessResult result;
  try {
    if (operatingSystem == 'windows') {
      result = await runner('powershell.exe', const [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'$now=[DateTime]::UtcNow; Get-CimInstance Win32_Process | '
            r'ForEach-Object { [PSCustomObject]@{ pid=$_.ProcessId; '
            r'ppid=$_.ParentProcessId; elapsed=[int](($now-'
            r'$_.CreationDate.ToUniversalTime()).TotalSeconds); '
            r'command=$_.CommandLine } } | ConvertTo-Json -Compress',
      ], workingDirectory: bootstrapRoot.path);
    } else {
      result = await runner('ps', const [
        '-axo',
        'pid=,ppid=,etime=,command=',
      ], workingDirectory: bootstrapRoot.path);
    }
  } on Object catch (failure) {
    return (
      processes: const <_AnalyzerRelatedProcess>[],
      error: failure.toString(),
    );
  }
  if (result.exitCode != 0) {
    final detail = '${result.stdout}\n${result.stderr}'.trim();
    return (
      processes: const <_AnalyzerRelatedProcess>[],
      error: detail.isEmpty
          ? 'process inventory exited ${result.exitCode}'
          : detail,
    );
  }
  final candidates = operatingSystem == 'windows'
      ? _parseWindowsAnalyzerProcesses('${result.stdout}')
      : _parsePosixAnalyzerProcesses('${result.stdout}');
  final paths = <String>{
    bootstrapRoot.absolute.path.toLowerCase(),
    for (final cache in cacheEntries) cache.absolute.path.toLowerCase(),
  };
  final filtered = candidates.where((process) {
    final command = process.command.toLowerCase();
    final analysisServer =
        command.contains('analysis_server.dart.snapshot') ||
        command.contains('dart language-server') ||
        command.contains('dart analysis-server') ||
        command.contains('dart analysis server');
    final exactPath = paths.any(command.contains);
    return analysisServer || exactPath;
  }).toList()..sort((left, right) => left.pid.compareTo(right.pid));
  return (
    processes: List<_AnalyzerRelatedProcess>.unmodifiable(filtered),
    error: null,
  );
}

/// Parses POSIX `ps` columns without interpreting command contents.
List<_AnalyzerRelatedProcess> _parsePosixAnalyzerProcesses(String contents) {
  final processes = <_AnalyzerRelatedProcess>[];
  final row = RegExp(r'^\s*(\d+)\s+(\d+)\s+(\S+)\s+(.+)$');
  for (final line in contents.split(RegExp(r'\r?\n'))) {
    final match = row.firstMatch(line);
    if (match == null) continue;
    processes.add(
      _AnalyzerRelatedProcess(
        pid: int.parse(match.group(1)!),
        parentPid: int.parse(match.group(2)!),
        elapsed: match.group(3)!,
        command: match.group(4)!,
      ),
    );
  }
  return processes;
}

/// Parses the bounded PowerShell JSON process projection used on Windows.
List<_AnalyzerRelatedProcess> _parseWindowsAnalyzerProcesses(String contents) {
  if (contents.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(contents);
    final rows = decoded is List<Object?> ? decoded : <Object?>[decoded];
    final processes = <_AnalyzerRelatedProcess>[];
    for (final row in rows.whereType<Map<String, Object?>>()) {
      final pid = row['pid'];
      final parentPid = row['ppid'];
      final elapsed = row['elapsed'];
      final command = row['command'];
      if (pid is! num ||
          parentPid is! num ||
          elapsed is! num ||
          command is! String ||
          command.isEmpty) {
        continue;
      }
      processes.add(
        _AnalyzerRelatedProcess(
          pid: pid.toInt(),
          parentPid: parentPid.toInt(),
          elapsed: _formatElapsedSeconds(elapsed.toInt()),
          command: command,
        ),
      );
    }
    return processes;
  } on FormatException {
    return const [];
  }
}

/// Formats elapsed seconds without locale or wall-clock dependencies.
String _formatElapsedSeconds(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final days = safe ~/ Duration.secondsPerDay;
  final remainder = safe % Duration.secondsPerDay;
  final hours = remainder ~/ Duration.secondsPerHour;
  final minutes =
      (remainder % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
  final secs = remainder % Duration.secondsPerMinute;
  final time =
      '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${secs.toString().padLeft(2, '0')}';
  return days == 0 ? time : '${days}d $time';
}

/// One existing legacy cache entry and its bootstrap-byte consistency.
final class _AnalyzerPluginManagerCacheEntry {
  const _AnalyzerPluginManagerCacheEntry({
    required this.directory,
    required this.current,
  });

  /// Complete hash entry that a developer may back up manually.
  final Directory directory;

  /// Whether the cached manifest and loader match the active bootstrap.
  final bool current;
}

/// Finds existing cache entries for this exact bootstrap path.
///
/// Dart 3.11's legacy PluginManager keys each entry by MD5 of the source path's
/// code units and reuses an existing parent even when its child is missing.
/// This is a read-only SDK compatibility check, not a content integrity hash.
/// Never infer ownership from a shared package name in another Host's cache.
List<_AnalyzerPluginManagerCacheEntry> _analyzerPluginManagerCaches(
  Directory bootstrapRoot, {
  String? homeDirectory,
}) {
  final home =
      homeDirectory ??
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) return const [];
  final manager = Directory(path.join(home, '.dartServer', '.plugin_manager'));
  final sourceManifest = File(path.join(bootstrapRoot.path, 'pubspec.yaml'));
  if (!manager.existsSync() || !sourceManifest.existsSync()) {
    return const [];
  }
  final sourcePaths = {
    path.normalize(bootstrapRoot.absolute.path),
    bootstrapRoot.resolveSymbolicLinksSync(),
  };
  final cacheIds = {
    for (final sourcePath in sourcePaths)
      md5.convert(sourcePath.codeUnits).toString(),
  };
  final entries = <_AnalyzerPluginManagerCacheEntry>[];
  for (final id in cacheIds) {
    final entry = Directory(path.join(manager.path, id));
    if (FileSystemEntity.typeSync(entry.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      continue;
    }
    final cachedRoot = Directory(path.join(entry.path, 'analyzer_plugin'));
    var current = true;
    for (final relative in ['pubspec.yaml', path.join('bin', 'plugin.dart')]) {
      final sourceFile = File(path.join(bootstrapRoot.path, relative));
      final cachedFile = File(path.join(cachedRoot.path, relative));
      if (!cachedFile.existsSync() ||
          !_bytesEqual(
            sourceFile.readAsBytesSync(),
            cachedFile.readAsBytesSync(),
          )) {
        current = false;
        break;
      }
    }
    entries.add(
      _AnalyzerPluginManagerCacheEntry(directory: entry, current: current),
    );
  }
  entries.sort(
    (left, right) => left.directory.path.compareTo(right.directory.path),
  );
  return List<_AnalyzerPluginManagerCacheEntry>.unmodifiable(entries);
}

/// Compares two manifest byte sequences without allocating encoded strings.
bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// Recognizes common non-interactive Git authentication failures.
bool _looksLikeGitCredentialFailure(String output) {
  final normalized = output.toLowerCase();
  return normalized.contains('could not read username') ||
      normalized.contains('authentication failed') ||
      normalized.contains('permission denied (publickey)') ||
      normalized.contains('repository not found');
}

/// Copies authored bootstrap files while excluding mutable tool state.
void _copyDirectory(Directory source, Directory target) {
  for (final entity in source.listSync(followLinks: false)) {
    final basename = path.basename(entity.path);
    if (basename == '.dart_tool') continue;
    final destination = path.join(target.path, basename);
    if (entity is Directory) {
      final child = Directory(destination)..createSync();
      _copyDirectory(entity, child);
    } else if (entity is File) {
      entity.copySync(destination);
    }
  }
}

/// Resolves the enabled outer plugin Package from the Host package config.
Directory? _resolvePackageRoot(Directory hostRoot, String packageName) {
  final configFile = _nearestPackageConfig(hostRoot);
  if (configFile == null) return null;
  try {
    final document = jsonDecode(configFile.readAsStringSync());
    if (document is! Map<String, Object?>) return null;
    final packages = document['packages'];
    if (packages is! List<Object?>) return null;
    for (final package in packages.whereType<Map<String, Object?>>()) {
      if (package['name'] != packageName) continue;
      final rootUri = package['rootUri'];
      if (rootUri is! String) return null;
      final uri = configFile.parent.uri.resolve(rootUri);
      if (uri.scheme != 'file') return null;
      final directory = Directory.fromUri(uri).absolute;
      return directory.existsSync() ? directory : null;
    }
  } on Object {
    return null;
  }
  return null;
}

/// Finds the nearest Package config, including an enclosing Dart workspace.
File? _nearestPackageConfig(Directory start) {
  var current = start.absolute;
  while (true) {
    final candidate = File(
      path.join(current.path, '.dart_tool', 'package_config.json'),
    );
    if (candidate.existsSync()) return candidate;
    final parent = current.parent;
    if (parent.path == current.path) return null;
    current = parent;
  }
}

/// Reads a YAML mapping without allowing malformed tooling config to escape.
Map<Object?, Object?>? _readYamlMap(File file) {
  if (!file.existsSync()) return null;
  try {
    final value = loadYaml(file.readAsStringSync());
    if (value is YamlMap) return value;
    if (value is Map<Object?, Object?>) return value;
  } on Object {
    return null;
  }
  return null;
}

/// Normalizes a YAML mapping to string keys for deterministic lookup.
Map<String, Object?> _stringKeyedMap(Object? value) {
  if (value is! Map) return const {};
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

/// Reads a YAML string list while rejecting maps and scalar coercion.
List<String> _stringList(Object? value) {
  if (value is! Iterable) return const [];
  return value.whereType<String>().toList(growable: false);
}

/// Classifies one dependency declaration without resolving the network.
String? _dependencySource(Object? dependency) {
  if (dependency is String) return 'hosted';
  final map = _stringKeyedMap(dependency);
  if (map.containsKey('git')) return 'git';
  if (map.containsKey('path')) return 'path';
  if (map.containsKey('hosted') && map.containsKey('version')) return 'hosted';
  return null;
}

/// Parses a locked semantic version from one Package record.
Version? _lockedVersion(Object? package) {
  final version = _stringKeyedMap(package)['version']?.toString();
  if (version == null) return null;
  try {
    return Version.parse(version);
  } on FormatException {
    return null;
  }
}

/// Parses a semantic version constraint used by the isolated bootstrap.
VersionConstraint? _constraint(String? value) {
  if (value == null) return null;
  try {
    return VersionConstraint.parse(value);
  } on FormatException {
    return null;
  }
}
