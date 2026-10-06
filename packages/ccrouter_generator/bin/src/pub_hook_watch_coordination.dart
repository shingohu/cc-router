import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

/// Exact identity of the Pub resolution inputs coordinated by Hook and watch.
abstract final class CCPubResolutionFingerprint {
  /// Hashes the current Host manifest and build-root resolution files.
  static Future<String> capture({
    required Directory hostRoot,
    required Directory buildRoot,
  }) async => (await captureMany(
    requestedRoots: <String, Directory>{'requested': hostRoot},
    buildRoot: buildRoot,
  ))['requested']!;

  /// Hashes multiple requested manifests while reading shared Pub state once.
  static Future<Map<String, String>> captureMany({
    required Map<String, Directory> requestedRoots,
    required Directory buildRoot,
  }) async {
    final sharedFiles = <String, File>{
      'build/pubspec.yaml': File(path.join(buildRoot.path, 'pubspec.yaml')),
      'build/pubspec.lock': File(path.join(buildRoot.path, 'pubspec.lock')),
      'build/.dart_tool/package_config.json': File(
        path.join(buildRoot.path, '.dart_tool', 'package_config.json'),
      ),
      'build/.dart_tool/package_graph.json': File(
        path.join(buildRoot.path, '.dart_tool', 'package_graph.json'),
      ),
    };
    final sharedContents = <String, String?>{};
    for (final entry in sharedFiles.entries) {
      sharedContents[entry.key] = await entry.value.exists()
          ? base64Encode(await entry.value.readAsBytes())
          : null;
    }
    final fingerprints = <String, String>{};
    for (final entry in requestedRoots.entries) {
      final manifest = File(path.join(entry.value.path, 'pubspec.yaml'));
      final contents = <String, String?>{
        'host/pubspec.yaml': await manifest.exists()
            ? base64Encode(await manifest.readAsBytes())
            : null,
        ...sharedContents,
      };
      fingerprints[entry.key] = sha256
          .convert(utf8.encode(jsonEncode(contents)))
          .toString();
    }
    return Map<String, String>.unmodifiable(fingerprints);
  }
}

/// Exact Package source and generated-output identities shared by watch/Hook.
abstract final class CCPackageWatchFingerprint {
  /// Hashes authored Dart, `pubspec.yaml`, and `build.yaml` bytes.
  static Future<String> captureAuthoredInput({
    required String packageName,
    required Directory packageRoot,
  }) async {
    final inputs = <String, List<int>>{};
    final lib = Directory(path.join(packageRoot.path, 'lib'));
    if (lib.existsSync()) {
      final files = <File>[];
      await for (final entity in lib.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final relative = _relativePath(packageRoot, entity);
        if (relative.split('/').contains('ccrouter_generated')) continue;
        files.add(entity);
      }
      files.sort((left, right) => left.path.compareTo(right.path));
      for (final file in files) {
        inputs['package/$packageName/${_relativePath(packageRoot, file)}'] =
            await file.readAsBytes();
      }
    }
    for (final name in const <String>['pubspec.yaml', 'build.yaml']) {
      final file = File(path.join(packageRoot.path, name));
      if (file.existsSync()) {
        inputs['package/$packageName/$name'] = await file.readAsBytes();
      }
    }
    return digestEntries(inputs);
  }

  /// Reads exact CCRouter-owned source-tree artifacts below one Package.
  static Future<Map<String, List<int>>> captureManagedOutputFiles(
    Directory packageRoot, {
    bool Function(String relative)? include,
  }) async {
    final files = <String, List<int>>{};
    final normalizedRoot = path.normalize(packageRoot.absolute.path);
    final pending = <Directory>[packageRoot.absolute];
    while (pending.isNotEmpty) {
      final directory = pending.removeLast();
      final entities = await directory.list(followLinks: false).toList()
        ..sort((left, right) => left.path.compareTo(right.path));
      for (final entity in entities) {
        if (entity is Directory) {
          final name = path.basename(entity.path);
          if (name == '.dart_tool' || name == 'build') continue;
          if (!path.equals(
                path.normalize(entity.absolute.path),
                normalizedRoot,
              ) &&
              File(path.join(entity.path, 'pubspec.yaml')).existsSync()) {
            continue;
          }
          pending.add(entity);
          continue;
        }
        if (entity is! File) continue;
        final relative = _relativePath(packageRoot, entity);
        final segments = relative.split('/');
        if (!_isManagedGeneratedArtifact(segments, segments.last)) continue;
        if (include != null && !include(relative)) continue;
        files[relative] = await entity.readAsBytes();
      }
    }
    return files;
  }

  /// Hashes every currently managed source-tree artifact for one Package.
  static Future<String> captureManagedOutput(Directory packageRoot) async =>
      digestEntries(await captureManagedOutputFiles(packageRoot));

  /// Hashes logical file names and exact bytes in deterministic order.
  static String digestEntries(Map<String, List<int>> entries) {
    final names = entries.keys.toList()..sort();
    final bytes = BytesBuilder(copy: false);
    for (final name in names) {
      bytes
        ..add(utf8.encode(name))
        ..addByte(0)
        ..add(entries[name]!)
        ..addByte(0);
    }
    return sha256.convert(bytes.takeBytes()).toString();
  }

  /// Whether one source-tree file is owned by CCRouter generation.
  static bool _isManagedGeneratedArtifact(List<String> segments, String name) {
    if (name.endsWith('_ccrouter.g.dart')) return true;
    if (!segments.contains('ccrouter_generated')) return false;
    return name.endsWith('.g.dart') ||
        name == 'ccrouter_package.json' ||
        name == 'ccrouter_generation_state.json' ||
        name == 'cc_routes.json' ||
        name == 'cc_catalog.md' ||
        name == 'cc_routes.md' ||
        name == 'cc_sources.md' ||
        name.endsWith('.route.json') ||
        name.endsWith('.service.json') ||
        name.endsWith('.command.json') ||
        name.endsWith('.event.json') ||
        name.endsWith('.init_task.json') ||
        name.endsWith('.route.md') ||
        name.endsWith('.component.json') ||
        name.endsWith('.component.md');
  }

  /// Returns one slash-separated path relative to [root].
  static String _relativePath(Directory root, File file) => path
      .relative(file.absolute.path, from: root.absolute.path)
      .replaceAll(path.separator, '/');
}
