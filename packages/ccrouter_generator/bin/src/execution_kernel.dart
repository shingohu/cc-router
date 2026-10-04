import 'dart:io';

import 'package:path/path.dart' as path;

/// Owns the source boundary that can change generated artifacts.
///
/// Analyzer installation, scaffold templates, and the Pub hook are CLI
/// integrations. They are deliberately outside this boundary: changing one
/// must not invalidate a Host's generation planning state. The kernel list is
/// explicit and reviewable so a new generation dependency cannot silently
/// expand the tool fingerprint by scanning every file under `bin/`.
abstract final class CCGeneratorExecutionKernel {
  /// Returns the generator files whose bytes affect generation semantics.
  static Future<List<File>> files(Directory packageRoot) async {
    final result = <File>[];
    final lib = Directory(path.join(packageRoot.path, 'lib'));
    if (lib.existsSync()) {
      await for (final entity in lib.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File && entity.path.endsWith('.dart')) result.add(entity);
      }
    }
    for (final relative in const [
      'bin/ccrouter_generator.dart',
      'bin/src/build_plan.dart',
      'bin/src/execution_kernel.dart',
      'bin/src/portable_generation_state.dart',
    ]) {
      final file = File(
        path.joinAll([packageRoot.path, ...relative.split('/')]),
      );
      if (file.existsSync()) result.add(file);
    }
    result.sort((left, right) => left.path.compareTo(right.path));
    return result;
  }
}
