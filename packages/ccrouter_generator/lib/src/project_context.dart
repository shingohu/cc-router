import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// Resolved identity of the Package requested by a command and the Pub state
/// that owns its dependency resolution.
///
/// A Workspace member keeps its own [requestedRoot] while sharing the
/// Workspace [resolutionRoot]. A standalone Package uses the same directory
/// for both values, even when it is physically nested below a Workspace.
final class CCProjectContext {
  /// Creates an already validated project context.
  const CCProjectContext({
    required this.requestedRoot,
    required this.resolutionRoot,
    required this.isWorkspace,
  });

  /// The nearest Package root selected by the caller's path.
  final Directory requestedRoot;

  /// The Package or Workspace root that owns `.dart_tool` Pub resolution.
  final Directory resolutionRoot;

  /// Whether [resolutionRoot] is a Dart Pub Workspace.
  final bool isWorkspace;

  /// Resolves a Package request without treating an unrelated ancestor
  /// Workspace as its Pub owner.
  ///
  /// A present `workspace_ref.json` is authoritative and is rejected when it
  /// is malformed or stale. This prevents tooling from silently consuming a
  /// different ancestor's Package graph after Pub state becomes inconsistent.
  static CCProjectContext resolve(Directory start) {
    final requestedRoot = _nearestPackageRoot(start);
    final manifest = _readYamlMap(
      File(path.join(requestedRoot.path, 'pubspec.yaml')),
    );
    if (_workspaceMembers(manifest).isNotEmpty) {
      return CCProjectContext(
        requestedRoot: requestedRoot,
        resolutionRoot: requestedRoot,
        isWorkspace: true,
      );
    }
    if (manifest['resolution'] != 'workspace') {
      return CCProjectContext(
        requestedRoot: requestedRoot,
        resolutionRoot: requestedRoot,
        isWorkspace: false,
      );
    }

    final workspaceRef = File(
      path.join(requestedRoot.path, '.dart_tool', 'pub', 'workspace_ref.json'),
    );
    if (workspaceRef.existsSync()) {
      final workspaceRoot = _workspaceRootFromReference(
        workspaceRef,
        requestedRoot,
      );
      return CCProjectContext(
        requestedRoot: requestedRoot,
        resolutionRoot: workspaceRoot,
        isWorkspace: true,
      );
    }

    var current = requestedRoot.parent;
    while (true) {
      if (_isWorkspaceOwner(current, requestedRoot)) {
        return CCProjectContext(
          requestedRoot: requestedRoot,
          resolutionRoot: current.absolute,
          isWorkspace: true,
        );
      }
      final parent = current.parent;
      if (path.equals(parent.path, current.path)) break;
      current = parent;
    }
    throw CCProjectContextException(
      'Package "${requestedRoot.path}" declares `resolution: workspace` but '
      'no owning Pub Workspace was found.',
    );
  }
}

/// Reports an invalid Package request or inconsistent Pub Workspace identity.
final class CCProjectContextException implements Exception {
  /// Creates a project-context failure with an actionable [message].
  const CCProjectContextException(this.message);

  /// Human-readable reason project resolution could not be trusted.
  final String message;

  @override
  String toString() => message;
}

/// Finds the closest Package manifest at or above [start].
Directory _nearestPackageRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    if (File(path.join(current.path, 'pubspec.yaml')).existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (path.equals(parent.path, current.path)) break;
    current = parent;
  }
  throw CCProjectContextException(
    'No Package manifest was found at or above "${start.absolute.path}".',
  );
}

/// Reads one YAML document as a string-keyed mapping.
Map<String, Object?> _readYamlMap(File file) {
  try {
    final value = loadYaml(file.readAsStringSync());
    if (value is! YamlMap) {
      throw const FormatException('root document is not a mapping');
    }
    return <String, Object?>{
      for (final entry in value.entries) '${entry.key}': entry.value,
    };
  } on Object catch (error) {
    throw CCProjectContextException(
      'Unable to read Package manifest "${file.path}": $error',
    );
  }
}

/// Returns the relative members declared by one Workspace manifest.
List<String> _workspaceMembers(Map<String, Object?> manifest) {
  final value = manifest['workspace'];
  if (value is! Iterable) return const <String>[];
  return [
    for (final member in value)
      if (member is String) member,
  ];
}

/// Resolves and validates the Workspace referenced by Pub's local state.
Directory _workspaceRootFromReference(File reference, Directory requestedRoot) {
  try {
    final decoded = jsonDecode(reference.readAsStringSync());
    if (decoded is! Map || decoded['workspaceRoot'] is! String) {
      throw const FormatException('workspaceRoot is missing');
    }
    final value = decoded['workspaceRoot'] as String;
    if (value.isEmpty) throw const FormatException('workspaceRoot is empty');
    final candidate = Directory(
      path.normalize(path.join(reference.parent.path, value)),
    ).absolute;
    if (!_isWorkspaceOwner(candidate, requestedRoot)) {
      throw const FormatException(
        'referenced root does not declare this Package as a member',
      );
    }
    return candidate;
  } on Object catch (error) {
    throw CCProjectContextException(
      'Pub Workspace reference "${reference.path}" is invalid or stale: '
      '$error. Run Pub get from "${requestedRoot.path}".',
    );
  }
}

/// Whether [candidate] declares [requestedRoot] as an exact Workspace member.
bool _isWorkspaceOwner(Directory candidate, Directory requestedRoot) {
  final manifestFile = File(path.join(candidate.path, 'pubspec.yaml'));
  if (!manifestFile.existsSync()) return false;
  final manifest = _readYamlMap(manifestFile);
  final requestedIdentity = _directoryIdentity(requestedRoot);
  return _workspaceMembers(manifest).any((member) {
    final memberRoot = Directory(
      path.normalize(path.join(candidate.path, member)),
    );
    return path.equals(_directoryIdentity(memberRoot), requestedIdentity);
  });
}

/// Produces a stable comparison path while tolerating absent path segments.
String _directoryIdentity(Directory directory) {
  try {
    return path.normalize(directory.resolveSymbolicLinksSync());
  } on FileSystemException {
    return path.normalize(directory.absolute.path);
  }
}
