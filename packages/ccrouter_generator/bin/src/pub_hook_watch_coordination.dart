import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

/// Exact identity of the Pub resolution inputs coordinated by Hook and watch.
abstract final class CCPubResolutionFingerprint {
  /// Hashes the current Host manifest and build-root resolution files.
  static Future<String> capture({
    required Directory hostRoot,
    required Directory buildRoot,
  }) async {
    final files = <String, File>{
      'host/pubspec.yaml': File(path.join(hostRoot.path, 'pubspec.yaml')),
      'build/pubspec.yaml': File(path.join(buildRoot.path, 'pubspec.yaml')),
      'build/pubspec.lock': File(path.join(buildRoot.path, 'pubspec.lock')),
      'build/.dart_tool/package_config.json': File(
        path.join(buildRoot.path, '.dart_tool', 'package_config.json'),
      ),
      'build/.dart_tool/package_graph.json': File(
        path.join(buildRoot.path, '.dart_tool', 'package_graph.json'),
      ),
    };
    final contents = <String, String?>{};
    for (final entry in files.entries) {
      contents[entry.key] = await entry.value.exists()
          ? base64Encode(await entry.value.readAsBytes())
          : null;
    }
    return sha256.convert(utf8.encode(jsonEncode(contents))).toString();
  }
}
