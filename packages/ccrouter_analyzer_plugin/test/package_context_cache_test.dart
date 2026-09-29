import 'dart:io';

import 'package:ccrouter_analyzer_plugin/src/package_context_cache.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('caches Package identity and invalidates on pubspec change', () {
    final root = Directory.systemTemp.createTempSync('ccrouter-cache-');
    addTearDown(() => root.deleteSync(recursive: true));
    final manifest = File(path.join(root.path, 'pubspec.yaml'))
      ..writeAsStringSync('name: first_package\n');
    final source = File(path.join(root.path, 'lib', 'src', 'feature.dart'))
      ..createSync(recursive: true);
    final cache = CCRouterPackageContextCache(maximumEntries: 4);

    final first = cache.resolve(source.path);
    final cached = cache.resolve(source.path);

    expect(first?.name, 'first_package');
    expect(identical(first, cached), isTrue);
    expect(cache.entryCount, 1);

    manifest.writeAsStringSync('name: other_package\n');
    cache.invalidate(manifest.path);
    expect(cache.resolve(source.path)?.name, 'other_package');
  });

  test('evicts least recently used source directories at the bound', () {
    final root = Directory.systemTemp.createTempSync('ccrouter-cache-');
    addTearDown(() => root.deleteSync(recursive: true));
    File(
      path.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: bounded_package\n');
    final cache = CCRouterPackageContextCache(maximumEntries: 2);

    for (final directory in const ['first', 'second', 'third']) {
      final source = File(
        path.join(root.path, 'lib', directory, 'feature.dart'),
      )..createSync(recursive: true);
      expect(cache.resolve(source.path)?.name, 'bounded_package');
    }

    expect(cache.entryCount, 2);
    cache.clear();
    expect(cache.entryCount, 0);
  });

  test('does not cache malformed or missing manifests', () {
    final root = Directory.systemTemp.createTempSync('ccrouter-cache-');
    addTearDown(() => root.deleteSync(recursive: true));
    final source = File(path.join(root.path, 'lib', 'feature.dart'))
      ..createSync(recursive: true);
    final cache = CCRouterPackageContextCache();

    expect(cache.resolve(source.path), isNull);
    File(path.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: [');
    expect(cache.resolve(source.path), isNull);
    expect(cache.entryCount, 0);
  });
}
