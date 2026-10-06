import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// Generator role inferred for one Package without executing Generator code.
enum CCRouterAnalyzerProjectRole {
  /// A Flutter application composition root that owns Host aggregation.
  host,

  /// A component or contracts Package that owns package-local generation.
  package,

  /// A Package that does not directly participate in CCRouter generation.
  skip,
}

/// Direct CCRouter dependency surface declared by an analyzed Package.
enum CCRouterAnalyzerProjectParticipation {
  /// No direct CCRouter runtime or contracts dependency is declared.
  none,

  /// Only the Pure Dart contracts surface is directly consumed.
  contracts,

  /// The Flutter-facing CCRouter runtime is directly consumed.
  runtime,
}

/// Read-only Package role and Pub-resolution identity used by the plugin.
///
/// This intentionally mirrors the Generator's project selection semantics but
/// remains dependency-free from `ccrouter_generator`. Loading Generator and
/// build_runner libraries into Analysis Server would make editor startup and
/// memory proportional to the build tool graph.
final class CCRouterAnalyzerProjectContext {
  /// Creates one already validated context.
  const CCRouterAnalyzerProjectContext({
    required this.requestedRoot,
    required this.resolutionRoot,
    required this.role,
    required this.participation,
    required this.flutterProjectType,
    required this.isFlutterProject,
  });

  /// Nearest Package root owning the analyzed path.
  final Directory requestedRoot;

  /// Package or Workspace root owning Pub's `.dart_tool` state.
  final Directory resolutionRoot;

  /// Generation role selected from direct dependencies and authored markers.
  final CCRouterAnalyzerProjectRole role;

  /// Direct CCRouter dependency surface of [requestedRoot].
  final CCRouterAnalyzerProjectParticipation participation;

  /// Flutter `.metadata` `project_type`, when valid and present.
  final String? flutterProjectType;

  /// Whether a Flutter `.metadata` document exists for this Package.
  final bool isFlutterProject;

  /// Resolves a context for a file or directory and fails closed on malformed
  /// YAML, contradictory role configuration, or stale Workspace identity.
  ///
  /// Analyzer diagnostics are advisory, so unavailable evidence returns null
  /// rather than destabilizing the Analysis Server process.
  static CCRouterAnalyzerProjectContext? resolve(String inputPath) {
    try {
      final requestedRoot = _nearestPackageRoot(inputPath);
      if (requestedRoot == null) return null;
      final manifest = _readYamlMap(
        File(path.join(requestedRoot.path, 'pubspec.yaml')),
      );
      if (manifest == null) return null;
      final resolutionRoot = _resolutionRoot(requestedRoot, manifest);
      if (resolutionRoot == null) return null;
      final dependencies = _mapKeys(manifest['dependencies']);
      final participation = dependencies.contains('ccrouter')
          ? CCRouterAnalyzerProjectParticipation.runtime
          : dependencies.contains('ccrouter_contracts')
          ? CCRouterAnalyzerProjectParticipation.contracts
          : CCRouterAnalyzerProjectParticipation.none;
      final metadataFile = File(path.join(requestedRoot.path, '.metadata'));
      final metadata = _readOptionalYamlMap(metadataFile);
      if (metadataFile.existsSync() && metadata == null) return null;
      final projectType = switch (metadata?['project_type']) {
        final String value when value.trim().isNotEmpty => value.trim(),
        _ => null,
      };
      final configurationFile = File(
        path.join(requestedRoot.path, 'ccrouter.yaml'),
      );
      final configuration = _readOptionalYamlMap(configurationFile);
      if (configurationFile.existsSync() && configuration == null) return null;
      final explicitHost = _hostOverride(configuration);
      if (explicitHost == _invalidHostOverride) return null;
      if (participation == CCRouterAnalyzerProjectParticipation.none &&
          explicitHost == true) {
        return null;
      }
      if (participation == CCRouterAnalyzerProjectParticipation.contracts &&
          explicitHost == true) {
        return null;
      }
      final role = switch (explicitHost) {
        true => CCRouterAnalyzerProjectRole.host,
        false when participation != CCRouterAnalyzerProjectParticipation.none =>
          CCRouterAnalyzerProjectRole.package,
        false => CCRouterAnalyzerProjectRole.skip,
        null
            when projectType == 'app' &&
                participation == CCRouterAnalyzerProjectParticipation.runtime =>
          CCRouterAnalyzerProjectRole.host,
        null when participation != CCRouterAnalyzerProjectParticipation.none =>
          CCRouterAnalyzerProjectRole.package,
        _ => CCRouterAnalyzerProjectRole.skip,
      };
      return CCRouterAnalyzerProjectContext(
        requestedRoot: requestedRoot,
        resolutionRoot: resolutionRoot,
        role: role,
        participation: participation,
        flutterProjectType: projectType,
        isFlutterProject: metadataFile.existsSync(),
      );
    } on Object {
      return null;
    }
  }

  /// Returns the bounded Package roots declared by the input's Pub owner.
  ///
  /// Standalone Packages return only their requested root. Workspace inputs
  /// return the resolution root and its explicit members without scanning the
  /// filesystem. Invalid or unavailable manifests return an empty list so the
  /// diagnostic-only plugin remains fail-open.
  static List<Directory> analysisPackageRoots(String inputPath) {
    try {
      final requestedRoot = _nearestPackageRoot(inputPath);
      if (requestedRoot == null) return const <Directory>[];
      final requestedManifest = _readYamlMap(
        File(path.join(requestedRoot.path, 'pubspec.yaml')),
      );
      if (requestedManifest == null) return const <Directory>[];
      final resolutionRoot = _resolutionRoot(requestedRoot, requestedManifest);
      if (resolutionRoot == null) return const <Directory>[];
      final resolutionManifest = _readYamlMap(
        File(path.join(resolutionRoot.path, 'pubspec.yaml')),
      );
      if (resolutionManifest == null) return const <Directory>[];
      final roots = <String, Directory>{};
      void add(Directory root) {
        final manifest = File(path.join(root.path, 'pubspec.yaml'));
        if (!manifest.existsSync()) return;
        roots[_directoryIdentity(root)] = root.absolute;
      }

      add(resolutionRoot);
      for (final member in _workspaceMembers(resolutionManifest)) {
        add(Directory(path.join(resolutionRoot.path, member)));
      }
      if (roots.isEmpty) add(requestedRoot);
      return List<Directory>.unmodifiable(roots.values);
    } on Object {
      return const <Directory>[];
    }
  }
}

/// Sentinel distinguishing an invalid `host.enabled` from an absent value.
const Object _invalidHostOverride = Object();

/// Finds the nearest Package manifest without crossing filesystem root.
Directory? _nearestPackageRoot(String inputPath) {
  final absolute = path.normalize(File(inputPath).absolute.path);
  var current = FileSystemEntity.isDirectorySync(absolute)
      ? Directory(absolute)
      : File(absolute).parent;
  while (true) {
    if (File(path.join(current.path, 'pubspec.yaml')).existsSync()) {
      return current.absolute;
    }
    final parent = current.parent;
    if (path.equals(parent.path, current.path)) return null;
    current = parent;
  }
}

/// Resolves only the Pub owner explicitly selected by the Package manifest.
Directory? _resolutionRoot(
  Directory requestedRoot,
  Map<String, Object?> manifest,
) {
  if (_workspaceMembers(manifest).isNotEmpty) return requestedRoot;
  if (manifest['resolution'] != 'workspace') return requestedRoot;
  final reference = File(
    path.join(requestedRoot.path, '.dart_tool', 'pub', 'workspace_ref.json'),
  );
  if (reference.existsSync()) {
    try {
      final decoded = jsonDecode(reference.readAsStringSync());
      if (decoded is! Map || decoded['workspaceRoot'] is! String) return null;
      final value = decoded['workspaceRoot'] as String;
      if (value.isEmpty) return null;
      final candidate = Directory(
        path.normalize(path.join(reference.parent.path, value)),
      ).absolute;
      return _ownsWorkspaceMember(candidate, requestedRoot) ? candidate : null;
    } on Object {
      return null;
    }
  }
  var current = requestedRoot.parent;
  while (true) {
    if (_ownsWorkspaceMember(current, requestedRoot)) return current.absolute;
    final parent = current.parent;
    if (path.equals(parent.path, current.path)) return null;
    current = parent;
  }
}

/// Whether a candidate Workspace declares the requested Package exactly.
bool _ownsWorkspaceMember(Directory candidate, Directory requestedRoot) {
  final manifest = _readYamlMap(
    File(path.join(candidate.path, 'pubspec.yaml')),
  );
  if (manifest == null) return false;
  final requestedIdentity = _directoryIdentity(requestedRoot);
  return _workspaceMembers(manifest).any(
    (member) => path.equals(
      _directoryIdentity(Directory(path.join(candidate.path, member))),
      requestedIdentity,
    ),
  );
}

/// Reads relative member paths from a Workspace manifest.
List<String> _workspaceMembers(Map<String, Object?> manifest) {
  final workspace = manifest['workspace'];
  if (workspace is! Iterable) return const <String>[];
  return [
    for (final member in workspace)
      if (member is String) member,
  ];
}

/// Reads string keys from a YAML mapping.
Set<String> _mapKeys(Object? value) {
  if (value is! Map) return const <String>{};
  return {
    for (final key in value.keys)
      if (key is String) key,
  };
}

/// Reads `host.enabled`, returning a sentinel for malformed declarations.
Object? _hostOverride(Map<String, Object?>? configuration) {
  if (configuration == null || !configuration.containsKey('host')) return null;
  final host = configuration['host'];
  if (host is! Map) return _invalidHostOverride;
  final enabled = host['enabled'];
  if (enabled == null || enabled is bool) return enabled;
  return _invalidHostOverride;
}

/// Reads one required YAML mapping without propagating parser failures.
Map<String, Object?>? _readYamlMap(File file) {
  if (!file.existsSync()) return null;
  try {
    final document = loadYaml(file.readAsStringSync());
    if (document is! Map) return null;
    return <String, Object?>{
      for (final entry in document.entries) '${entry.key}': entry.value,
    };
  } on Object {
    return null;
  }
}

/// Reads an optional YAML mapping, treating an empty file as empty config.
Map<String, Object?>? _readOptionalYamlMap(File file) {
  if (!file.existsSync()) return null;
  try {
    final document = loadYaml(file.readAsStringSync());
    if (document == null) return <String, Object?>{};
    if (document is! Map) return null;
    return <String, Object?>{
      for (final entry in document.entries) '${entry.key}': entry.value,
    };
  } on Object {
    return null;
  }
}

/// Produces a stable path identity across symlinks and missing descendants.
String _directoryIdentity(Directory directory) {
  try {
    return path.normalize(directory.resolveSymbolicLinksSync());
  } on FileSystemException {
    return path.normalize(directory.absolute.path);
  }
}
