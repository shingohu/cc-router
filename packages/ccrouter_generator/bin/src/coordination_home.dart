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

/// Whether this invocation explicitly selects project-local V1 locks.
bool usesLegacyCCRouterCoordination({Map<String, String>? environment}) =>
    (environment ??
        Platform.environment)[ccrouterLegacyCoordinationEnvironment] ==
    '1';

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

  /// Stable authoritative session document for the shared Builder owner.
  File get builderSessionDocument =>
      File(path.join(projectDirectory.path, 'builder-session.json'));

  /// Stable lifecycle directory for Flutter runs owned by [hostRoot].
  Directory flutterRunLeaseDirectory(Directory hostRoot) => Directory(
    path.join(projectDirectory.path, 'leases', hostIdentity(hostRoot)),
  );

  /// Creates a unique stable lease path for one supervised Flutter run.
  ///
  /// The file is intentionally outside the project so `flutter clean` cannot
  /// silently turn a live run into an unrelated lease-expiry event.
  File newFlutterRunLease(
    Directory hostRoot, {
    required int ownerPid,
    required int nonce,
  }) => File(
    path.join(
      flutterRunLeaseDirectory(hostRoot).path,
      'flutter-run-$ownerPid-$nonce.lease',
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

/// Atomically publishes one Host watch session into stable V2 coordination.
Future<void> publishCCRouterHostSession({
  required Directory hostRoot,
  required Directory buildRoot,
  required Map<String, Object?> status,
  Map<String, String>? environment,
}) async {
  final paths = CCRouterCoordinationPaths.forBuildRoot(
    buildRoot,
    environment: environment,
  );
  await paths.prepare();
  await _writeCoordinationDocument(
    paths.sessionDocument(hostRoot),
    <String, Object?>{
      'schemaVersion': 2,
      'kind': 'host-session',
      'buildRoot': paths.canonicalBuildRoot,
      'hostRoot': canonicalDirectoryIdentity(hostRoot.path),
      'status': status,
    },
  );
}

/// Reads one exact Host watch session from stable V2 coordination.
Future<Map<String, Object?>?> readCCRouterHostSession({
  required Directory hostRoot,
  required Directory buildRoot,
  Map<String, String>? environment,
}) async {
  final paths = CCRouterCoordinationPaths.forBuildRoot(
    buildRoot,
    environment: environment,
  );
  final document = await _readCoordinationDocument(
    paths.sessionDocument(hostRoot),
  );
  if (document == null ||
      document['schemaVersion'] != 2 ||
      document['kind'] != 'host-session' ||
      document['buildRoot'] != paths.canonicalBuildRoot ||
      document['hostRoot'] != canonicalDirectoryIdentity(hostRoot.path) ||
      document['status'] is! Map) {
    return null;
  }
  return (document['status'] as Map).cast<String, Object?>();
}

/// Atomically publishes the shared Builder owner's V2 session.
Future<void> publishCCRouterBuilderSession({
  required Directory buildRoot,
  required Map<String, Object?> status,
  Map<String, String>? environment,
}) async {
  final paths = CCRouterCoordinationPaths.forBuildRoot(
    buildRoot,
    environment: environment,
  );
  await paths.prepare();
  await _writeCoordinationDocument(
    paths.builderSessionDocument,
    <String, Object?>{
      'schemaVersion': 2,
      'kind': 'builder-session',
      'buildRoot': paths.canonicalBuildRoot,
      'status': status,
    },
  );
}

/// Reads the shared Builder owner's session from stable V2 coordination.
Future<Map<String, Object?>?> readCCRouterBuilderSession({
  required Directory buildRoot,
  Map<String, String>? environment,
}) async {
  final paths = CCRouterCoordinationPaths.forBuildRoot(
    buildRoot,
    environment: environment,
  );
  final document = await _readCoordinationDocument(
    paths.builderSessionDocument,
  );
  if (document == null ||
      document['schemaVersion'] != 2 ||
      document['kind'] != 'builder-session' ||
      document['buildRoot'] != paths.canonicalBuildRoot ||
      document['status'] is! Map) {
    return null;
  }
  return (document['status'] as Map).cast<String, Object?>();
}

Future<Map<String, Object?>?> _readCoordinationDocument(File file) async {
  if (!file.existsSync()) return null;
  try {
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map ? decoded.cast<String, Object?>() : null;
  } on Object {
    return null;
  }
}

Future<void> _writeCoordinationDocument(
  File file,
  Map<String, Object?> document,
) async {
  final contents = '${const JsonEncoder.withIndent('  ').convert(document)}\n';
  if (file.existsSync() && await file.readAsString() == contents) return;
  await file.parent.create(recursive: true);
  final suffix = '$pid.${DateTime.now().microsecondsSinceEpoch}';
  final temporary = File('${file.path}.ccrouter.$suffix.tmp');
  final backup = File('${file.path}.ccrouter.$suffix.bak');
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
    } on Object {
      if (file.existsSync()) await file.delete();
      if (backup.existsSync()) await backup.rename(file.path);
      rethrow;
    }
  } finally {
    if (temporary.existsSync()) await temporary.delete();
    if (committed && backup.existsSync()) await backup.delete();
  }
}

/// Returns the owner lock selected for this invocation without creating it.
File ccrouterWatchOwnerLockFile(
  Directory buildRoot, {
  Map<String, String>? environment,
  String? operatingSystem,
}) {
  if (usesLegacyCCRouterCoordination(environment: environment)) {
    return legacyCCRouterWatchOwnerLockFile(buildRoot);
  }
  return CCRouterCoordinationPaths.forBuildRoot(
    buildRoot,
    environment: environment,
    operatingSystem: operatingSystem,
  ).ownerLock;
}

/// Project-local owner lock used by the pre-V2 implementation.
File legacyCCRouterWatchOwnerLockFile(Directory buildRoot) => File(
  path.join(
    buildRoot.path,
    '.dart_tool',
    'ccrouter',
    'v1',
    'watch',
    'owner.lock',
  ),
);

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
