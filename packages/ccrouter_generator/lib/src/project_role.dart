import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import 'project_context.dart';

/// Execution role selected for one requested Package.
enum CCProjectRole {
  /// A Flutter application composition root that owns Host aggregation and
  /// cross-Package validation.
  host,

  /// A participating component or contracts Package that owns only its local
  /// generated artifacts.
  package,

  /// A Package that does not directly participate in CCRouter generation.
  skip,
}

/// Direct CCRouter dependency surface declared by one Package.
enum CCProjectParticipation {
  /// The Package has no direct CCRouter runtime or contracts dependency.
  none,

  /// The Package directly consumes only Pure Dart CCRouter contracts.
  contracts,

  /// The Package directly consumes the Flutter-facing CCRouter runtime.
  runtime,
}

/// Immutable role evidence shared by generator entrypoints.
final class CCProjectRoleResolution {
  /// Creates a validated role decision for [context].
  const CCProjectRoleResolution({
    required this.context,
    required this.role,
    required this.participation,
    required this.flutterProjectType,
    required this.explicitHostEnabled,
  });

  /// Requested Package and Pub resolution ownership.
  final CCProjectContext context;

  /// Generation behavior selected for the requested Package.
  final CCProjectRole role;

  /// Direct dependency evidence proving CCRouter participation.
  final CCProjectParticipation participation;

  /// Flutter `.metadata` project type, when the Package has one.
  final String? flutterProjectType;

  /// Explicit `ccrouter.yaml` Host override, when declared.
  final bool? explicitHostEnabled;
}

/// Resolves Host, package-local, or skipped behavior from authored Package
/// configuration rather than from the complete resolved dependency graph.
final class CCProjectRoleResolver {
  /// Prevents construction; role resolution is stateless.
  const CCProjectRoleResolver._();

  /// Resolves the role for [context].
  ///
  /// `ccrouter.yaml` `host.enabled` has highest precedence. Otherwise only
  /// Flutter `project_type: app` defaults to Host, and only when the Package
  /// directly depends on `ccrouter`. Every other participating project type is
  /// package-local. Workspace aggregators and unrelated Packages are skipped.
  static CCProjectRoleResolution resolve(CCProjectContext context) {
    final root = context.requestedRoot;
    final manifest = _readYamlMap(
      File(path.join(root.path, 'pubspec.yaml')),
      required: true,
    )!;
    final dependencies = _stringMapKeys(manifest['dependencies']);
    final participation = dependencies.contains('ccrouter')
        ? CCProjectParticipation.runtime
        : dependencies.contains('ccrouter_contracts')
        ? CCProjectParticipation.contracts
        : CCProjectParticipation.none;
    final metadata = _readYamlMap(
      File(path.join(root.path, '.metadata')),
      required: false,
    );
    final projectType = switch (metadata?['project_type']) {
      final String value when value.trim().isNotEmpty => value.trim(),
      _ => null,
    };
    final configuration = _readYamlMap(
      File(path.join(root.path, 'ccrouter.yaml')),
      required: false,
    );
    final explicitHost = _readHostOverride(configuration, root);

    if (participation == CCProjectParticipation.none) {
      if (explicitHost == true) {
        throw CCProjectRoleException(
          'Package "${root.path}" enables CCRouter Host generation but does '
          'not directly depend on `ccrouter`.',
        );
      }
      return CCProjectRoleResolution(
        context: context,
        role: CCProjectRole.skip,
        participation: participation,
        flutterProjectType: projectType,
        explicitHostEnabled: explicitHost,
      );
    }

    final role = switch (explicitHost) {
      true when participation != CCProjectParticipation.runtime =>
        throw CCProjectRoleException(
          'Package "${root.path}" enables CCRouter Host generation but only '
          'depends on `ccrouter_contracts`; add a direct `ccrouter` dependency.',
        ),
      true => CCProjectRole.host,
      false => CCProjectRole.package,
      null
          when projectType == 'app' &&
              participation == CCProjectParticipation.runtime =>
        CCProjectRole.host,
      null => CCProjectRole.package,
    };
    return CCProjectRoleResolution(
      context: context,
      role: role,
      participation: participation,
      flutterProjectType: projectType,
      explicitHostEnabled: explicitHost,
    );
  }
}

/// Reports invalid or contradictory project-role declarations.
final class CCProjectRoleException implements Exception {
  /// Creates a role-resolution failure with an actionable [message].
  const CCProjectRoleException(this.message);

  /// Human-readable reason the requested role could not be selected.
  final String message;

  @override
  String toString() => message;
}

/// Reads a YAML mapping, optionally tolerating an absent [file].
Map<String, Object?>? _readYamlMap(File file, {required bool required}) {
  if (!file.existsSync()) {
    if (!required) return null;
    throw CCProjectRoleException('Required manifest is missing: ${file.path}');
  }
  try {
    final value = loadYaml(file.readAsStringSync());
    if (value == null && !required) return <String, Object?>{};
    if (value is! YamlMap) {
      throw const FormatException('root document is not a mapping');
    }
    return <String, Object?>{
      for (final entry in value.entries) '${entry.key}': entry.value,
    };
  } on Object catch (error) {
    throw CCProjectRoleException(
      'Unable to read project configuration "${file.path}": $error',
    );
  }
}

/// Returns string keys from a YAML dependency mapping.
Set<String> _stringMapKeys(Object? value) {
  if (value is! YamlMap && value is! Map) return const <String>{};
  final entries = value is YamlMap ? value.keys : (value as Map).keys;
  return {
    for (final key in entries)
      if (key is String) key,
  };
}

/// Reads the optional `host.enabled` override and rejects ambiguous values.
bool? _readHostOverride(Map<String, Object?>? configuration, Directory root) {
  if (configuration == null || !configuration.containsKey('host')) return null;
  final host = configuration['host'];
  if (host is! YamlMap && host is! Map) {
    throw CCProjectRoleException(
      '`host` in "${path.join(root.path, 'ccrouter.yaml')}" must be a mapping.',
    );
  }
  final enabled = host is YamlMap ? host['enabled'] : (host as Map)['enabled'];
  if (enabled == null) return null;
  if (enabled is bool) return enabled;
  throw CCProjectRoleException(
    '`host.enabled` in "${path.join(root.path, 'ccrouter.yaml')}" must be true '
    'or false.',
  );
}
