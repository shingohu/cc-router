import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

/// Read-only Analyzer bootstrap operation exposed by the CLI.
enum CCAnalyzerBootstrapAction {
  /// Reports installation identity and consistency without running tools.
  status,

  /// Verifies locked dependencies, analysis, and loader compilation.
  doctor,
}

/// Parsed request for one explicit Analyzer bootstrap operation.
final class CCAnalyzerBootstrapRequest {
  /// Creates a request scoped to one application Host directory.
  const CCAnalyzerBootstrapRequest({
    required this.action,
    required this.hostRoot,
  });

  /// Read-only operation selected by the developer.
  final CCAnalyzerBootstrapAction action;

  /// Application Host that owns `analysis_options.yaml` and the bootstrap.
  final String hostRoot;
}

/// Executes one Analyzer bootstrap request and reports whether it is healthy.
Future<bool> runAnalyzerBootstrapCommand(
  CCAnalyzerBootstrapRequest request,
) async {
  final report = _AnalyzerBootstrapReport.inspect(
    Directory(request.hostRoot).absolute,
  );
  report.writeTo(stdout);
  if (report.state != _AnalyzerBootstrapState.healthy) return false;
  if (request.action == CCAnalyzerBootstrapAction.status) return true;
  return _runDoctor(report);
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
      message: 'Analyzer bootstrap is statically consistent.',
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
  void writeTo(IOSink sink) {
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
    sink.writeln('  detail: $message');
  }
}

/// Runs bounded, non-mutating checks inside a healthy isolated bootstrap.
Future<bool> _runDoctor(_AnalyzerBootstrapReport report) async {
  final bootstrapRoot = report.bootstrapRoot!;
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
      stdout.writeln('CCRouter Analyzer doctor: ${check.name}...');
      final result = await Process.run(
        Platform.resolvedExecutable,
        check.arguments,
        workingDirectory: isolatedBootstrap.path,
      );
      if (result.exitCode != 0) {
        stderr.writeln('error: Analyzer doctor failed during ${check.name}.');
        final output = '${result.stderr}'.trim();
        if (output.isNotEmpty) stderr.writeln(output);
        return false;
      }
    }
    stdout.writeln('CCRouter Analyzer doctor passed.');
    return true;
  } finally {
    if (temporary.existsSync()) await temporary.delete(recursive: true);
  }
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
