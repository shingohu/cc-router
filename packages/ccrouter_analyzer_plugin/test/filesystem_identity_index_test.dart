import 'dart:io';
import 'dart:math';

import 'package:ccrouter_analyzer_plugin/src/filesystem_identity_index.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('deduplicates shared paths without changing affected sources', () {
    final fixture = _Fixture.create(3);
    addTearDown(fixture.dispose);
    final index = CCRouterFilesystemIdentityIndex()
      ..replace(
        'first',
        watchedPaths: [fixture.paths[0], fixture.paths[1]],
        affectedPaths: [fixture.source('first')],
      )
      ..replace(
        'second',
        watchedPaths: [fixture.paths[1], fixture.paths[2]],
        affectedPaths: [fixture.source('second')],
      );

    fixture.change(1);
    final result = index.pollAll();

    expect(result.changedRegistrations, {'first', 'second'});
    expect(result.affectedPaths, {
      fixture.source('first'),
      fixture.source('second'),
    });
    expect(result.inspectedPathCount, 3);
    expect(index.watchedPathCount, 3);
  });

  test('matches the per-registration full scan across filesystem churn', () {
    final fixture = _Fixture.create(100);
    addTearDown(fixture.dispose);
    final candidate = CCRouterFilesystemIdentityIndex();
    final reference = _PerRegistrationReference();
    for (var registration = 0; registration < 40; registration++) {
      final watched = <String>[
        for (var offset = 0; offset < 5; offset++)
          fixture.paths[(registration * 3 + offset) % fixture.paths.length],
      ];
      final affected = [fixture.source('$registration')];
      candidate.replace(
        '$registration',
        watchedPaths: watched,
        affectedPaths: affected,
      );
      reference.replace(
        '$registration',
        watchedPaths: watched,
        affectedPaths: affected,
      );
    }

    final random = Random(731);
    for (var operation = 0; operation < 120; operation++) {
      final index = random.nextInt(fixture.paths.length);
      switch (operation % 4) {
        case 0:
          fixture.change(index);
        case 1:
          fixture.delete(index);
        case 2:
          fixture.recreate(index);
        case 3:
          fixture.change(index);
      }
      final expected = reference.pollAll();
      final actual = candidate.pollAll();
      expect(
        actual.changedRegistrations,
        expected.changedRegistrations,
        reason: 'changed registrations after operation $operation',
      );
      expect(
        actual.affectedPaths,
        expected.affectedPaths,
        reason: 'affected sources after operation $operation',
      );
    }
  });

  test('event polling updates only exact paths before the fallback scan', () {
    final fixture = _Fixture.create(10);
    addTearDown(fixture.dispose);
    final index = CCRouterFilesystemIdentityIndex()
      ..replace(
        'route',
        watchedPaths: fixture.paths,
        affectedPaths: [fixture.source('route')],
      );

    fixture.change(4);
    final event = index.pollPaths([
      fixture.paths[4],
      fixture.paths[4],
      path.join(fixture.root.path, 'untracked.dart'),
    ]);

    expect(event.changedRegistrations, {'route'});
    expect(event.affectedPaths, {fixture.source('route')});
    expect(event.inspectedPathCount, 1);
    expect(index.pollAll().affectedPaths, isEmpty);
  });

  test('replacement and removal release unused path identities', () {
    final fixture = _Fixture.create(3);
    addTearDown(fixture.dispose);
    final index = CCRouterFilesystemIdentityIndex()
      ..replace(
        'route',
        watchedPaths: [fixture.paths[0], fixture.paths[1]],
        affectedPaths: [fixture.source('route')],
      );

    index.replace(
      'route',
      watchedPaths: [fixture.paths[2]],
      affectedPaths: [fixture.source('route')],
    );
    expect(index.watchedPathCount, 1);
    fixture.change(0);
    expect(index.pollAll().affectedPaths, isEmpty);
    fixture.change(2);
    expect(index.pollAll().affectedPaths, {fixture.source('route')});

    index.remove('route');
    expect(index.watchedPathCount, 0);
  });

  test('all deterministic shards equal one full scan', () {
    final fixture = _Fixture.create(101);
    addTearDown(fixture.dispose);
    final full = CCRouterFilesystemIdentityIndex();
    final sharded = CCRouterFilesystemIdentityIndex();
    for (
      var registration = 0;
      registration < fixture.paths.length;
      registration++
    ) {
      final watched = [fixture.paths[registration]];
      final affected = [fixture.source('$registration')];
      full.replace(
        '$registration',
        watchedPaths: watched,
        affectedPaths: affected,
      );
      sharded.replace(
        '$registration',
        watchedPaths: watched,
        affectedPaths: affected,
      );
      fixture.change(registration);
    }

    final expected = full.pollAll();
    final changed = <String>{};
    final affected = <String>{};
    var inspected = 0;
    for (var shard = 0; shard < 10; shard++) {
      final result = sharded.pollShard(shardIndex: shard, shardCount: 10);
      changed.addAll(result.changedRegistrations);
      affected.addAll(result.affectedPaths);
      inspected += result.inspectedPathCount;
    }

    expect(changed, expected.changedRegistrations);
    expect(affected, expected.affectedPaths);
    expect(inspected, fixture.paths.length);
    expect(
      () => sharded.pollShard(shardIndex: 10, shardCount: 10),
      throwsRangeError,
    );
  });
}

final class _PerRegistrationReference {
  final Map<String, _ReferenceRegistration> _registrations = {};

  void replace(
    String registration, {
    required Iterable<String> watchedPaths,
    required Iterable<String> affectedPaths,
  }) {
    _registrations[registration] = _ReferenceRegistration(
      identities: {
        for (final watchedPath in watchedPaths)
          path.normalize(File(watchedPath).absolute.path): _identity(
            watchedPath,
          ),
      },
      affectedPaths: affectedPaths
          .map((item) => path.normalize(File(item).absolute.path))
          .toSet(),
    );
  }

  CCRouterFilesystemPollResult pollAll() {
    final changed = <String>{};
    final affected = <String>{};
    var inspected = 0;
    for (final entry in _registrations.entries) {
      var registrationChanged = false;
      for (final watchedPath in entry.value.identities.keys) {
        inspected++;
        final current = _identity(watchedPath);
        if (current == entry.value.identities[watchedPath]) continue;
        entry.value.identities[watchedPath] = current;
        registrationChanged = true;
      }
      if (!registrationChanged) continue;
      changed.add(entry.key);
      affected.addAll(entry.value.affectedPaths);
    }
    return CCRouterFilesystemPollResult(
      changedRegistrations: changed,
      affectedPaths: affected,
      inspectedPathCount: inspected,
    );
  }
}

final class _ReferenceRegistration {
  _ReferenceRegistration({
    required this.identities,
    required this.affectedPaths,
  });

  final Map<String, String> identities;
  final Set<String> affectedPaths;
}

final class _Fixture {
  factory _Fixture.create(int count) {
    final root = Directory.systemTemp.createTempSync(
      'ccrouter-filesystem-index-',
    );
    final paths = <String>[];
    for (var index = 0; index < count; index++) {
      final file = File(path.join(root.path, 'generated', '$index.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{"revision":0}\n');
      paths.add(file.path);
    }
    return _Fixture._(root, paths);
  }

  const _Fixture._(this.root, this.paths);

  final Directory root;
  final List<String> paths;

  String source(String name) => path.join(root.path, 'lib', '$name.dart');

  void change(int index) {
    File(paths[index]).writeAsStringSync('// changed\n', mode: FileMode.append);
  }

  void delete(int index) {
    final file = File(paths[index]);
    if (file.existsSync()) file.deleteSync();
  }

  void recreate(int index) {
    File(paths[index])
      ..createSync(recursive: true)
      ..writeAsStringSync('// recreated\n');
  }

  void dispose() => root.deleteSync(recursive: true);
}

String _identity(String filePath) {
  try {
    final stat = File(filePath).statSync();
    return '${stat.type}:${stat.size}:${stat.modified.microsecondsSinceEpoch}:'
        '${stat.changed.microsecondsSinceEpoch}';
  } on Object {
    return 'missing';
  }
}
