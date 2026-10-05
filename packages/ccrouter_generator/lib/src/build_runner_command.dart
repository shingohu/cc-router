import 'dart:io';

import 'package:path/path.dart' as path;

/// Diagnostic emitted when a cached Dart snapshot belongs to another SDK.
const ccWrongFullSnapshotVersionDiagnostic = 'Wrong full snapshot version';

/// Internal build_runner invocation selected for one generation process.
///
/// This type is intentionally kept below `lib/src` and is not exported from
/// the generator package. A missing cache uses `dart run` so Pub materializes
/// a compatible executable snapshot instead of repeatedly running source.
final class CCBuildRunnerCommand {
  /// Creates an immutable build_runner process invocation.
  CCBuildRunnerCommand({
    required this.executable,
    required List<String> arguments,
    required this.cachedSnapshot,
  }) : arguments = List<String>.unmodifiable(arguments);

  /// Dart executable used to launch build_runner.
  final String executable;

  /// Arguments preceding CCRouter's build filters and verbosity flags.
  final List<String> arguments;

  /// Cached Pub snapshot used by this invocation, or `null` while rebuilding.
  final File? cachedSnapshot;

  /// Removes an incompatible cached snapshot after the VM proves it is stale.
  ///
  /// Unknown failures preserve the cache so a Builder or configuration error
  /// cannot accidentally discard a valid executable snapshot.
  Future<bool> invalidateIfWrongSnapshotVersion(String diagnostics) async {
    final snapshot = cachedSnapshot;
    if (snapshot == null ||
        !diagnostics.contains(ccWrongFullSnapshotVersionDiagnostic)) {
      return false;
    }
    if (await snapshot.exists()) await snapshot.delete();
    return true;
  }
}

/// Resolves a cached build_runner snapshot or a self-healing Pub invocation.
///
/// [sdkVersion] is injectable so tests can model SDK switches without relying
/// on whichever Dart SDK happens to execute the test suite.
Future<CCBuildRunnerCommand> resolveCCBuildRunnerCommand({
  required Directory buildRoot,
  required String command,
  required String dartExecutable,
  String? sdkVersion,
}) async {
  final snapshotDirectory = Directory(
    path.join(buildRoot.path, '.dart_tool', 'pub', 'bin', 'build_runner'),
  );
  if (snapshotDirectory.existsSync()) {
    final effectiveSdkVersion = sdkVersion ?? Platform.version.split(' ').first;
    final snapshots = snapshotDirectory
        .listSync(followLinks: false)
        .whereType<File>()
        .where(
          (file) =>
              path.basename(file.path) ==
              'build_runner.dart-$effectiveSdkVersion.snapshot',
        )
        .toList();
    snapshots.sort(
      (left, right) =>
          right.lastModifiedSync().compareTo(left.lastModifiedSync()),
    );
    if (snapshots.isNotEmpty) {
      final snapshot = snapshots.first;
      return CCBuildRunnerCommand(
        executable: dartExecutable,
        arguments: [snapshot.path, command],
        cachedSnapshot: snapshot,
      );
    }
  }

  return CCBuildRunnerCommand(
    executable: dartExecutable,
    arguments: ['run', '--verbosity=error', 'build_runner', command],
    cachedSnapshot: null,
  );
}
