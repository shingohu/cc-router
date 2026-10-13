@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../ccrouter_generator/bin/src/generation_file_reader.dart';
import '../../ccrouter_generator/bin/src/pub_hook_watch_coordination.dart';

void main() {
  test(
    'concurrent captures share a budget and preserve logical order',
    () async {
      final reader = CCGenerationFileReader(maxConcurrentReads: 4);
      final pending = <Completer<Uint8List>>[];
      var active = 0;
      var peak = 0;
      File file(int value) => _ControlledFile(() async {
        active++;
        if (active > peak) peak = active;
        final read = Completer<Uint8List>();
        pending.add(read);
        try {
          await read.future;
          return Uint8List.fromList([value]);
        } finally {
          active--;
        }
      });
      final first = reader.readAll({
        for (var i = 0; i < 12; i++) 'first/$i': file(i),
      });
      final second = reader.readAll({
        for (var i = 0; i < 7; i++) 'second/$i': file(100 + i),
      });
      await _flush();
      expect(active, 4);
      while (pending.length < 19 || active > 0) {
        // Deliberately finish later inputs first to test result ordering.
        for (final read in pending.reversed) {
          if (!read.isCompleted) read.complete(Uint8List(0));
        }
        await _flush();
      }
      final results = await Future.wait([first, second]);
      expect(peak, 4);
      expect(results[0].keys, [for (var i = 0; i < 12; i++) 'first/$i']);
      expect(results[0].values, [
        for (var i = 0; i < 12; i++) [i],
      ]);
      expect(results[1].values, [
        for (var i = 0; i < 7; i++) [100 + i],
      ]);
    },
  );

  test('failure drains in-flight reads and returns all permits', () async {
    final reader = CCGenerationFileReader(maxConcurrentReads: 4);
    final blocked = Completer<Uint8List>();
    final failed = Completer<Uint8List>();
    final error = FileSystemException('removed during capture', 'deleted.dart');
    var tailReads = 0;
    var settled = false;
    final capture = reader.readAll({
      'blocked': _ControlledFile(() => blocked.future),
      'failed': _ControlledFile(() => failed.future),
      'quick': _ControlledFile(() async => Uint8List.fromList([3])),
      for (var i = 0; i < 20; i++)
        'tail/$i': _ControlledFile(() async {
          tailReads++;
          return Uint8List(0);
        }),
    });
    final observation = capture.then<void>(
      (_) => fail('a partial capture must never succeed'),
      onError: (Object actual, StackTrace stack) {
        expect(actual, same(error));
        settled = true;
      },
    );
    failed.completeError(error);
    await _flush();
    expect(settled, isFalse);
    blocked.complete(Uint8List.fromList([1]));
    await observation;
    expect(settled, isTrue);
    expect(tailReads, lessThanOrEqualTo(1));
    final recoveryReads = List.generate(4, (_) => Completer<Uint8List>());
    var recoveryStarted = 0;
    final recovery = reader.readAll({
      for (var i = 0; i < 4; i++)
        'recovery/$i': _ControlledFile(() {
          recoveryStarted++;
          return recoveryReads[i].future;
        }),
    });
    await _flush();
    expect(
      recoveryStarted,
      4,
      reason: 'All read permits must be returned on failure.',
    );
    for (final read in recoveryReads) {
      read.complete(Uint8List.fromList([9]));
    }
    expect((await recovery).values, everyElement([9]));
  });

  test('multiple read failures report the first logical input', () async {
    final reader = CCGenerationFileReader(maxConcurrentReads: 4);
    final first = Completer<Uint8List>();
    final second = Completer<Uint8List>();
    final firstError = FileSystemException('first', 'first.dart');
    final capture = reader.readAll({
      'first': _ControlledFile(() => first.future),
      'second': _ControlledFile(() => second.future),
    });
    final check = expectLater(capture, throwsA(same(firstError)));
    await _flush();
    second.completeError(FileSystemException('second', 'second.dart'));
    await _flush();
    first.completeError(firstError);
    await check;
  });

  test('sequential reference stops before the next input on error', () async {
    var nextRead = false;
    final reader = CCGenerationFileReader(maxConcurrentReads: 1);
    await expectLater(
      reader.readAll({
        'missing': _ControlledFile(
          () async => throw FileSystemException('missing'),
        ),
        'next': _ControlledFile(() async {
          nextRead = true;
          return Uint8List(0);
        }),
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(nextRead, isFalse);
    expect(await reader.readAll({}), isEmpty);
  });

  test('concurrency is bounded to the supported range', () {
    for (final concurrency in [0, -1, 9]) {
      expect(
        () => CCGenerationFileReader(maxConcurrentReads: concurrency),
        throwsRangeError,
      );
    }
  });

  test(
    'real fingerprints observe add/edit/delete/rename and Package ownership',
    () async {
      final fixture = await Directory.systemTemp.createTemp(
        'ccrouter_read_mutations_',
      );
      addTearDown(() => fixture.delete(recursive: true));
      File write(String relative, List<int> bytes) {
        final file = File(path.join(fixture.path, relative));
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
        return file;
      }

      write('pubspec.yaml', utf8.encode('name: fixture\n'));
      write('build.yaml', utf8.encode('targets: {}\n'));
      write('lib/main.dart', utf8.encode('// 中文注释\nconst value = 1;\n'));
      final generated = write(
        'lib/src/ccrouter_generated/route/fixture.route.g.dart',
        [0, 255, 1, 2],
      );
      write('example/pubspec.yaml', utf8.encode('name: example\n'));
      write('example/lib/src/ccrouter_generated/route/example.route.g.dart', [
        9,
      ]);
      write('lib/src/ccrouter_generated/user.txt', [8]);

      Future<String> compare() async {
        final inputs = <String, List<int>>{};
        for (final file
            in fixture
                .listSync(recursive: true, followLinks: false)
                .whereType<File>()) {
          final relative = path
              .relative(file.path, from: fixture.path)
              .replaceAll(path.separator, '/');
          if ((relative.startsWith('lib/') &&
                  relative.endsWith('.dart') &&
                  !relative.contains('/ccrouter_generated/')) ||
              relative == 'pubspec.yaml' ||
              relative == 'build.yaml') {
            inputs['package/fixture/$relative'] = file.readAsBytesSync();
          }
        }
        final fingerprint =
            await CCPackageWatchFingerprint.captureAuthoredInput(
              packageName: 'fixture',
              packageRoot: fixture,
            );
        expect(fingerprint, CCPackageWatchFingerprint.digestEntries(inputs));
        final outputs =
            await CCPackageWatchFingerprint.captureManagedOutputFiles(fixture);
        expect(outputs, {
          'lib/src/ccrouter_generated/route/fixture.route.g.dart': generated
              .readAsBytesSync(),
        });
        return fingerprint;
      }

      final baseline = await compare();
      final added = write('lib/added.dart', utf8.encode('const added = 2;\n'));
      final afterAdd = await compare();
      expect(afterAdd, isNot(baseline));
      added.writeAsStringSync('const added = 3;\n');
      final afterEdit = await compare();
      expect(afterEdit, isNot(afterAdd));
      final renamed = added.renameSync(
        path.join(fixture.path, 'lib', 'renamed.dart'),
      );
      final afterRename = await compare();
      expect(afterRename, isNot(afterEdit));
      renamed.deleteSync();
      expect(await compare(), baseline);
      generated.writeAsBytesSync([0, 255, 1, 3]);
      expect(
        await compare(),
        baseline,
        reason: 'Generated edits are outputs, not authored inputs.',
      );
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _ControlledFile implements File {
  _ControlledFile(this._read);
  final Future<Uint8List> Function() _read;

  @override
  Future<Uint8List> readAsBytes() => _read();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
