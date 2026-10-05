import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Serializes test suites that run generation against the repository Demo.
///
/// The production generation lock protects generator writes, but these tests
/// also edit authored inputs before starting the generator. Holding a separate
/// suite-level lock keeps those probes isolated without weakening production
/// watch conflict handling or serializing unrelated unit tests.
void serializeRealWorkspaceTests() {
  File? isolateOwner;
  var ownsIsolateMarker = false;
  RandomAccessFile? lock;

  setUpAll(() async {
    final lockDirectory = Directory(
      path.join(Directory.current.path, '.dart_tool', 'ccrouter', 'test-locks'),
    );
    await lockDirectory.create(recursive: true);
    isolateOwner = File(
      path.join(lockDirectory.path, 'real-workspace.$pid.owner'),
    );
    try {
      while (true) {
        try {
          isolateOwner!.createSync(exclusive: true);
          ownsIsolateMarker = true;
          break;
        } on PathExistsException {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
      lock = await File(
        path.join(lockDirectory.path, 'real-workspace.lock'),
      ).open(mode: FileMode.append);
      await lock!.lock(FileLock.blockingExclusive);
    } catch (_) {
      await lock?.close();
      lock = null;
      if (ownsIsolateMarker) isolateOwner?.deleteSync();
      isolateOwner = null;
      ownsIsolateMarker = false;
      rethrow;
    }
  });

  tearDownAll(() async {
    final acquiredLock = lock;
    if (acquiredLock == null) return;
    await acquiredLock.unlock();
    await acquiredLock.close();
    lock = null;
    isolateOwner!.deleteSync();
    isolateOwner = null;
    ownsIsolateMarker = false;
  });
}
