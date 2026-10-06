import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'pub_hook_watch_coordination.dart';

/// Publishes the latest terminal Host generation result for Analyzer tooling.
///
/// This snapshot is observational and fail-open at its call site. Consumers
/// must verify [resolutionFingerprint] against current Pub resolution inputs
/// before showing diagnostics from a previous process.
abstract final class CCOneShotGenerationDiagnosticsPublisher {
  /// Current schema for terminal one-shot diagnostic snapshots.
  static const int schemaVersion = 1;

  /// Returns the project-local snapshot file for [hostRoot].
  static File fileFor(Directory hostRoot) => File(
    path.join(
      hostRoot.path,
      '.dart_tool',
      'ccrouter',
      'v1',
      'generation',
      'diagnostics.json',
    ),
  );

  /// Atomically publishes one successful or failed terminal result.
  static Future<void> publish({
    required Directory hostRoot,
    required Directory buildRoot,
    required bool succeeded,
    required Iterable<Map<String, Object?>> structuredDiagnostics,
  }) async {
    final fingerprint = await CCPubResolutionFingerprint.capture(
      hostRoot: hostRoot,
      buildRoot: buildRoot,
    );
    final document = <String, Object?>{
      'schemaVersion': schemaVersion,
      'producer': 'oneShot',
      'hostRoot': hostRoot.absolute.path,
      'buildRoot': buildRoot.absolute.path,
      'outcome': succeeded ? 'succeeded' : 'failed',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'resolutionFingerprint': fingerprint,
      'diagnostics': succeeded
          ? const <Map<String, Object?>>[]
          : structuredDiagnostics.take(100).toList(growable: false),
    };
    final target = fileFor(hostRoot);
    await target.parent.create(recursive: true);
    final temporary = File(
      '${target.path}.ccrouter.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(document)}\n',
        flush: true,
      );
      try {
        await temporary.rename(target.path);
      } on FileSystemException {
        if (target.existsSync()) await target.delete();
        await temporary.rename(target.path);
      }
    } finally {
      if (temporary.existsSync()) await temporary.delete();
    }
  }
}
