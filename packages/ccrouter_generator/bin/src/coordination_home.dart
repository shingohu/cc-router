import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import 'canonical_directory_identity.dart';

/// Overrides the user-level directory that owns CCRouter coordination state.
const ccrouterHomeEnvironment = 'CCROUTER_HOME';

/// Temporarily selects the project-local V1 coordination implementation.
const ccrouterLegacyCoordinationEnvironment =
    'CCROUTER_USE_LEGACY_DART_TOOL_LOCKS';

/// User-level, project-isolated paths for CCRouter's coordination plane.
///
/// Generated output, planning state, profiles, and build_runner data do not
/// belong here. They remain disposable project-local data under `.dart_tool`.
final class CCRouterCoordinationPaths {
  CCRouterCoordinationPaths._({
    required this.home,
    required this.canonicalBuildRoot,
    required this.projectIdentity,
  }) : coordinationRoot = Directory(path.join(home.path, 'coordination', 'v2')),
       projectDirectory = Directory(
         path.join(
           home.path,
           'coordination',
           'v2',
           'projects',
           projectIdentity,
         ),
       );

  /// Resolves V2 paths for one canonical Pub/build root.
  factory CCRouterCoordinationPaths.forBuildRoot(
    Directory buildRoot, {
    Map<String, String>? environment,
    String? operatingSystem,
  }) {
    final canonicalBuildRoot = canonicalDirectoryIdentity(buildRoot.path);
    return CCRouterCoordinationPaths._(
      home: resolveCCRouterHome(
        environment: environment,
        operatingSystem: operatingSystem,
      ),
      canonicalBuildRoot: canonicalBuildRoot,
      projectIdentity: _identity(canonicalBuildRoot),
    );
  }

  /// Root selected by [ccrouterHomeEnvironment] or the platform default.
  final Directory home;

  /// Versioned coordination root shared by all projects for this user.
  final Directory coordinationRoot;

  /// Canonical absolute spelling used to identify the Pub/build root.
  final String canonicalBuildRoot;

  /// Full SHA-256 identity of [canonicalBuildRoot].
  final String projectIdentity;

  /// Isolated coordination directory for this Pub/build root.
  final Directory projectDirectory;

  /// Human-readable identity record used to diagnose hashed project paths.
  File get projectDocument =>
      File(path.join(projectDirectory.path, 'project.json'));

  /// Stable watch ownership lock for this build root.
  File get ownerLock => File(path.join(projectDirectory.path, 'owner.lock'));

  /// Stable one-shot/watch generation serialization lock.
  File get generationLock =>
      File(path.join(projectDirectory.path, 'generation.lock'));

  /// Stable cross-Host aggregation serialization lock.
  File get aggregationLock =>
      File(path.join(projectDirectory.path, 'aggregation.lock'));

  /// Stable registration document for [hostRoot].
  File registrationDocument(Directory hostRoot) => File(
    path.join(
      projectDirectory.path,
      'registrations',
      '${hostIdentity(hostRoot)}.json',
    ),
  );

  /// Stable registration lock for [hostRoot].
  File registrationLock(Directory hostRoot) => File(
    path.join(
      projectDirectory.path,
      'registrations',
      '${hostIdentity(hostRoot)}.lock',
    ),
  );

  /// Stable authoritative session document for [hostRoot].
  File sessionDocument(Directory hostRoot) => File(
    path.join(
      projectDirectory.path,
      'sessions',
      '${hostIdentity(hostRoot)}.json',
    ),
  );

  /// Full SHA-256 identity of one canonical Host root.
  String hostIdentity(Directory hostRoot) =>
      _identity(canonicalDirectoryIdentity(hostRoot.path));

  /// Creates and validates this project's coordination directory.
  Future<void> prepare() async {
    await projectDirectory.create(recursive: true);
    final expected = <String, Object?>{
      'schemaVersion': 2,
      'buildRoot': canonicalBuildRoot,
      'projectIdentity': projectIdentity,
    };
    if (projectDocument.existsSync()) {
      await _validateProjectDocument(expected);
      return;
    }
    final temporary = File(
      '${projectDocument.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(expected)}\n',
        flush: true,
      );
      try {
        await temporary.rename(projectDocument.path);
      } on FileSystemException {
        if (!projectDocument.existsSync()) rethrow;
      }
      await _validateProjectDocument(expected);
    } finally {
      if (temporary.existsSync()) await temporary.delete();
    }
  }

  Future<void> _validateProjectDocument(Map<String, Object?> expected) async {
    try {
      final decoded = jsonDecode(await projectDocument.readAsString());
      if (decoded is Map &&
          decoded['schemaVersion'] == expected['schemaVersion'] &&
          decoded['buildRoot'] == expected['buildRoot'] &&
          decoded['projectIdentity'] == expected['projectIdentity']) {
        return;
      }
    } on FormatException {
      // Report the same bounded identity error as every other invalid record.
    }
    throw FileSystemException(
      'CCRouter coordination identity does not match the requested build root',
      projectDocument.path,
    );
  }

  static String _identity(String value) =>
      sha256.convert(utf8.encode(value)).toString();
}

/// Resolves the CCRouter user home without creating it.
Directory resolveCCRouterHome({
  Map<String, String>? environment,
  String? operatingSystem,
}) {
  final values = environment ?? Platform.environment;
  final override = values[ccrouterHomeEnvironment]?.trim();
  if (override != null && override.isNotEmpty) {
    return Directory(override).absolute;
  }
  final os = operatingSystem ?? Platform.operatingSystem;
  if (os == 'windows') {
    final localAppData = values['LOCALAPPDATA']?.trim();
    if (localAppData != null && localAppData.isNotEmpty) {
      return Directory(path.join(localAppData, 'CCRouter')).absolute;
    }
    final userProfile = values['USERPROFILE']?.trim();
    if (userProfile != null && userProfile.isNotEmpty) {
      return Directory(path.join(userProfile, '.ccrouter')).absolute;
    }
  } else {
    final home = values['HOME']?.trim();
    if (home != null && home.isNotEmpty) {
      return Directory(path.join(home, '.ccrouter')).absolute;
    }
  }
  throw StateError(
    'Cannot resolve CCRouter home. Set $ccrouterHomeEnvironment to an '
    'absolute writable directory.',
  );
}
