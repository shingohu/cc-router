@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test(
    'generate check rejects cross-Package internal imports despite ignores',
    () async {
      final probe = File(
        path.join(
          Directory.current.path,
          'demo',
          'lib',
          '_ccrouter_internal_api_probe.dart',
        ),
      );
      expect(probe.existsSync(), isFalse);
      addTearDown(() {
        if (probe.existsSync()) probe.deleteSync();
      });
      probe.writeAsStringSync('''
import 'package:demo_navigation_lab/src/ccrouter_generated/component/demo_navigation_lab_component.route_api.g.dart';

void probe() {
  // ignore: invalid_use_of_internal_member
  DemoNavigationLabRoutes.detail(id: 1);
}
''');
      final rejected = await Process.run(Platform.resolvedExecutable, [
        'run',
        'ccrouter_generator:ccrouter',
        'generate',
        'demo',
        '--check',
      ], workingDirectory: Directory.current.path);
      expect(rejected.exitCode, 1);
      expect(
        '${rejected.stderr}',
        contains('ccrouter_demo:lib/_ccrouter_internal_api_probe.dart:1'),
      );
      expect('${rejected.stderr}', contains('public Contract or Host barrel'));
      expect(probe.existsSync(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'unified generation checks workspace outputs and restores stale probes',
    () async {
      final outsideOutput = path.join(
        Directory.systemTemp.path,
        'ccrouter_outside_check_$pid',
      );
      final rejectedOutside = await Process.run(Platform.resolvedExecutable, [
        'run',
        'ccrouter_generator:ccrouter',
        'generate',
        'demo',
        '--check',
        '--output-dir',
        outsideOutput,
      ], workingDirectory: Directory.current.path);
      expect(rejectedOutside.exitCode, 2);
      expect(
        '${rejectedOutside.stderr}',
        contains('--output-dir to remain inside'),
      );
      expect(Directory(outsideOutput).existsSync(), false);

      final current = await Process.run(Platform.resolvedExecutable, [
        'run',
        'ccrouter_generator:ccrouter',
        'generate',
        'demo',
        '--check',
      ], workingDirectory: Directory.current.path);
      expect(current.exitCode, 0, reason: '${current.stderr}');
      expect(
        '${current.stdout}',
        contains('CCRouter generated artifacts are up to date.'),
      );
      expect(
        Directory(
          path.join(
            Directory.current.path,
            'demo',
            'ccrouter_generated',
            'metadata',
          ),
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          path.join(
            Directory.current.path,
            'demo',
            'modules',
            'order',
            'ccrouter_generated',
            'src',
            'order_detail_page.route.json',
          ),
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          path.join(
            Directory.current.path,
            '.dart_tool',
            'build',
            'generated',
            'demo_order',
            'lib',
            'src',
            'ccrouter_generated',
            'metadata',
            'src',
            'order_detail_page.route.json',
          ),
        ).existsSync(),
        isTrue,
      );
      final hostBundle = File(
        path.join(
          Directory.current.path,
          'demo',
          'lib',
          'src',
          'ccrouter_generated',
          'host',
          'ccrouter_demo_ccrouter.g.dart',
        ),
      ).readAsStringSync();
      expect(
        hostBundle,
        contains(
          'package:demo_order/src/ccrouter_generated/host/demo_order_ccrouter.g.dart',
        ),
      );
      expect(
        hostBundle,
        contains(
          'package:demo_payment/src/ccrouter_generated/host/demo_payment_ccrouter.g.dart',
        ),
      );
      expect(hostBundle, isNot(contains('package:demo_order_contracts/')));
      final hostCatalog = File(
        path.join(
          Directory.current.path,
          'demo',
          'lib',
          'src',
          'ccrouter_generated',
          'host',
          'ccrouter_host.routes.g.dart',
        ),
      ).readAsStringSync();
      expect(
        hostCatalog,
        contains(
          'package:ccrouter_demo/src/ccrouter_generated/host/ccrouter_demo_ccrouter.g.dart',
        ),
      );
      expect(hostCatalog, isNot(contains('package:demo_order/')));
      final contractIndex =
          jsonDecode(
                File(
                  path.join(
                    Directory.current.path,
                    'demo',
                    'modules',
                    'order_contracts',
                    'lib',
                    'src',
                    'ccrouter_generated',
                    'metadata',
                    'ccrouter_package.json',
                  ),
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(contractIndex['bundle'], isNull);
      final contractCapabilities =
          (contractIndex['capabilityCatalog']
                  as Map<String, Object?>)['records']
              as List;
      expect(contractCapabilities, isNotEmpty);
      expect((contractCapabilities.single as Map)['id'], 'order.detail');
      final hostCatalogDocument = File(
        path.join(
          Directory.current.path,
          'demo',
          'lib',
          'src',
          'ccrouter_generated',
          'metadata',
          'cc_catalog.md',
        ),
      ).readAsStringSync();
      expect(hostCatalogDocument, contains('## Route Definitions'));
      expect(hostCatalogDocument, contains('## Capability Sources'));
      expect(hostCatalogDocument, contains('### Route `order.detail`'));
      expect(
        hostCatalogDocument,
        contains('package:demo_order/src/order_detail_page.dart'),
      );
      final packageCatalogDocument = File(
        path.join(
          Directory.current.path,
          'demo',
          'modules',
          'order',
          'lib',
          'src',
          'ccrouter_generated',
          'metadata',
          'cc_catalog.md',
        ),
      ).readAsStringSync();
      expect(packageCatalogDocument, contains('Scope: `package:demo_order`'));
      expect(packageCatalogDocument, contains('### Route `order.detail`'));
      expect(
        File(
          path.join(
            Directory.current.path,
            'demo',
            'modules',
            'payment',
            'lib',
            'src',
            'ccrouter_generated',
            'metadata',
            'cc_catalog.md',
          ),
        ).existsSync(),
        isFalse,
      );
      for (final legacyName in ['cc_routes.md', 'cc_sources.md']) {
        expect(
          File(
            path.join(
              Directory.current.path,
              'demo',
              'ccrouter_generated',
              legacyName,
            ),
          ).existsSync(),
          isFalse,
        );
      }
      final navigationPackage = path.join(
        Directory.current.path,
        'demo',
        'modules',
        'navigation_lab',
      );
      final routeApi = File(
        path.join(
          navigationPackage,
          'lib',
          'src',
          'ccrouter_generated',
          'component',
          'demo_navigation_lab_component.route_api.g.dart',
        ),
      ).readAsStringSync();
      expect(
        routeApi,
        contains('abstract final class DemoNavigationLabRoutes'),
      );
      expect(
        routeApi,
        contains("import 'package:flutter/foundation.dart' show internal;"),
      );
      expect(
        routeApi,
        contains('@internal\nabstract final class DemoNavigationLabRoutes'),
      );
      expect(routeApi, contains('static const detail ='));
      expect(routeApi, contains('static const presentationBottomPage ='));
      expect(routeApi, isNot(contains('route_binding.g.dart')));
      final navigationBarrel = File(
        path.join(navigationPackage, 'lib', 'demo_navigation_lab.dart'),
      ).readAsStringSync();
      expect(
        navigationBarrel,
        isNot(contains('demo_navigation_lab_component.route_api.g.dart')),
      );
      for (final package in ['order', 'payment', 'web']) {
        final component = package == 'order'
            ? 'demo_order_component'
            : package == 'payment'
            ? 'demo_payment_component'
            : 'demo_web_component';
        expect(
          File(
            path.join(
              Directory.current.path,
              'demo',
              'modules',
              package,
              'lib',
              'src',
              'ccrouter_generated',
              'component',
              '$component.route_api.g.dart',
            ),
          ).existsSync(),
          isFalse,
          reason: '$package must not retain an empty component Route API.',
        );
      }
      expect(
        File(
          path.join(
            Directory.current.path,
            'packages',
            'ccrouter_test',
            'lib',
            'src',
            'ccrouter_generated',
            'metadata',
            'ccrouter_package.json',
          ),
        ).existsSync(),
        isFalse,
      );

      final probe = Directory(
        path.join(
          Directory.current.path,
          'demo',
          'lib',
          'src',
          'ccrouter_generated',
          'metadata',
          '.command_check_probe_$pid',
        ),
      );
      addTearDown(() {
        if (probe.existsSync()) probe.deleteSync(recursive: true);
      });
      final stale = await Process.run(Platform.resolvedExecutable, [
        'run',
        'ccrouter_generator:ccrouter',
        'generate',
        'demo',
        '--check',
        '--output-dir',
        probe.path,
      ], workingDirectory: Directory.current.path);

      expect(stale.exitCode, 1);
      expect('${stale.stderr}', contains('generated artifacts are stale'));
      expect('${stale.stderr}', contains('added:'));
      expect(File(path.join(probe.path, 'cc_routes.json')).existsSync(), false);
      expect(File(path.join(probe.path, 'cc_catalog.md')).existsSync(), false);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'concurrent generation is serialized by the workspace lock',
    () async {
      Future<ProcessResult> generate() => Process.run(
        Platform.resolvedExecutable,
        ['run', 'ccrouter_generator:ccrouter', 'generate', 'demo', '--check'],
        workingDirectory: Directory.current.path,
      );

      final results = await Future.wait([generate(), generate()]);

      for (final result in results) {
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(
          '${result.stdout}',
          contains('CCRouter generated artifacts are up to date.'),
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'generation removes only obsolete source-tree metadata',
    () async {
      final generatedDirectory = Directory(
        path.join(
          Directory.current.path,
          'demo',
          'modules',
          'payment',
          'ccrouter_generated',
          '.migration_probe_$pid',
        ),
      )..createSync(recursive: true);
      addTearDown(() {
        if (generatedDirectory.existsSync()) {
          generatedDirectory.deleteSync(recursive: true);
        }
      });
      final obsoleteJson = File(
        path.join(generatedDirectory.path, 'probe.route.json'),
      )..writeAsStringSync('{}');
      final obsoleteMarkdown = File(
        path.join(generatedDirectory.path, 'probe.component.md'),
      )..writeAsStringSync('# generated');
      final unknown = File(path.join(generatedDirectory.path, 'keep.txt'))
        ..writeAsStringSync('user-owned');

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'ccrouter_generator:ccrouter',
        'generate',
        'demo',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(obsoleteJson.existsSync(), isFalse);
      expect(obsoleteMarkdown.existsSync(), isFalse);
      expect(unknown.readAsStringSync(), 'user-owned');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'clean removes managed outputs but preserves user files and rebuilds',
    () async {
      final demoRoot = Directory(path.join(Directory.current.path, 'demo'));
      final sentinel = File(
        path.join(
          demoRoot.path,
          'modules',
          'navigation_lab',
          'lib',
          'src',
          'ccrouter_generated',
          'clean_probe.txt',
        ),
      )..writeAsStringSync('user-owned');
      final generatedRouteApi = File(
        path.join(
          demoRoot.path,
          'modules',
          'navigation_lab',
          'lib',
          'src',
          'ccrouter_generated',
          'component',
          'demo_navigation_lab_component.route_api.g.dart',
        ),
      );
      expect(generatedRouteApi.existsSync(), isTrue);
      try {
        final cleaned = await Process.run(Platform.resolvedExecutable, [
          'run',
          'ccrouter_generator:ccrouter',
          'clean',
          'demo',
        ], workingDirectory: Directory.current.path);
        expect(cleaned.exitCode, 0, reason: '${cleaned.stderr}');
        expect('${cleaned.stdout}', contains('Removed '));
        expect(generatedRouteApi.existsSync(), isFalse);
        expect(sentinel.readAsStringSync(), 'user-owned');
      } finally {
        final regenerated = await Process.run(Platform.resolvedExecutable, [
          'run',
          'ccrouter_generator:ccrouter',
          'generate',
          'demo',
        ], workingDirectory: Directory.current.path);
        expect(regenerated.exitCode, 0, reason: '${regenerated.stderr}');
        if (sentinel.existsSync()) sentinel.deleteSync();
      }
      expect(generatedRouteApi.existsSync(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'cached and no-cache generation produce identical artifacts',
    () async {
      final before = await _readDemoGeneratedArtifacts();
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'ccrouter_generator:ccrouter',
        'generate',
        'demo',
        '--no-cache',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(await _readDemoGeneratedArtifacts(), before);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'corrupted generation cache falls back to a full parse',
    () async {
      final cache = File(
        path.join(
          Directory.current.path,
          '.dart_tool',
          'ccrouter',
          'v1',
          'cache.json',
        ),
      );
      final original = cache.existsSync() ? cache.readAsBytesSync() : null;
      addTearDown(() {
        if (original == null) {
          if (cache.existsSync()) cache.deleteSync();
        } else {
          cache
            ..createSync(recursive: true)
            ..writeAsBytesSync(original, flush: true);
        }
      });
      cache
        ..createSync(recursive: true)
        ..writeAsStringSync('{invalid cache', flush: true);

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'ccrouter_generator:ccrouter',
        'generate',
        'demo',
        '--profile',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        '${result.stdout}',
        contains('cache was invalid and has been ignored'),
      );
      expect('${result.stdout}', contains('cache=0/'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<Map<String, String>> _readDemoGeneratedArtifacts() async {
  final root = Directory(path.join(Directory.current.path, 'demo'));
  final artifacts = <String, String>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = path
        .relative(entity.path, from: root.path)
        .replaceAll(path.separator, '/');
    final segments = relative.split('/');
    final name = segments.last;
    if (!segments.contains('ccrouter_generated') &&
        !name.endsWith('_ccrouter.g.dart')) {
      continue;
    }
    if (name == '.DS_Store') continue;
    artifacts[relative] = await entity.readAsString();
  }
  return Map.unmodifiable(artifacts);
}
