@TestOn('vm')
library;

import 'dart:io';

import 'package:ccrouter_generator/src/build_runner_command.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ccrouter_build_runner_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'wrong full snapshot version invalidates and selects Pub rebuild',
    () async {
      final snapshot = await _createSnapshot(root, '3.11.5');
      final cached = await resolveCCBuildRunnerCommand(
        buildRoot: root,
        command: 'build',
        dartExecutable: '/sdk/bin/dart',
        sdkVersion: '3.11.5',
      );

      expect(cached.cachedSnapshot?.path, snapshot.path);
      expect(cached.arguments, [snapshot.path, 'build']);
      expect(
        await cached.invalidateIfWrongSnapshotVersion(
          'Wrong full snapshot version, expected current SDK.',
        ),
        isTrue,
      );
      expect(await snapshot.exists(), isFalse);

      final rebuilding = await resolveCCBuildRunnerCommand(
        buildRoot: root,
        command: 'build',
        dartExecutable: '/sdk/bin/dart',
        sdkVersion: '3.11.5',
      );
      expect(rebuilding.cachedSnapshot, isNull);
      expect(rebuilding.executable, '/sdk/bin/dart');
      expect(rebuilding.arguments, [
        'run',
        '--verbosity=error',
        'build_runner',
        'build',
      ]);
    },
  );

  test('unrelated Builder failure preserves the cached snapshot', () async {
    final snapshot = await _createSnapshot(root, '3.11.5');
    final cached = await resolveCCBuildRunnerCommand(
      buildRoot: root,
      command: 'watch',
      dartExecutable: '/sdk/bin/dart',
      sdkVersion: '3.11.5',
    );

    expect(
      await cached.invalidateIfWrongSnapshotVersion(
        'Failed to build with build_runner because a Builder threw.',
      ),
      isFalse,
    );
    expect(await snapshot.exists(), isTrue);
  });
}

Future<File> _createSnapshot(Directory root, String sdkVersion) async {
  final snapshot = File(
    path.join(
      root.path,
      '.dart_tool',
      'pub',
      'bin',
      'build_runner',
      'build_runner.dart-$sdkVersion.snapshot',
    ),
  );
  await snapshot.parent.create(recursive: true);
  await snapshot.writeAsString('cached snapshot');
  return snapshot;
}
