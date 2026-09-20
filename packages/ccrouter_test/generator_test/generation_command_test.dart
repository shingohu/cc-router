@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
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
        isTrue,
      );
      final hostBundle = File(
        path.join(
          Directory.current.path,
          'demo',
          'lib',
          'ccrouter_demo_ccrouter.g.dart',
        ),
      ).readAsStringSync();
      expect(
        hostBundle,
        contains('package:demo_order/demo_order_ccrouter.g.dart'),
      );
      expect(
        hostBundle,
        contains('package:demo_payment/demo_payment_ccrouter.g.dart'),
      );
      expect(hostBundle, isNot(contains('package:demo_order_contracts/')));
      final hostCatalog = File(
        path.join(
          Directory.current.path,
          'demo',
          'lib',
          'ccrouter_generated',
          'ccrouter_host.routes.g.dart',
        ),
      ).readAsStringSync();
      expect(
        hostCatalog,
        contains('package:ccrouter_demo/ccrouter_demo_ccrouter.g.dart'),
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
                    'ccrouter_generated',
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
      final hostSources = File(
        path.join(
          Directory.current.path,
          'demo',
          'ccrouter_generated',
          'cc_sources.md',
        ),
      ).readAsStringSync();
      expect(hostSources, contains('### Route `order.detail`'));
      expect(
        hostSources,
        contains('package:demo_order/src/order_detail_page.dart'),
      );
      final packageSources = File(
        path.join(
          Directory.current.path,
          'demo',
          'modules',
          'order',
          'ccrouter_generated',
          'cc_sources.md',
        ),
      ).readAsStringSync();
      expect(packageSources, contains('Scope: `package:demo_order`'));
      expect(packageSources, contains('### Route `order.detail`'));
      expect(
        File(
          path.join(
            Directory.current.path,
            'packages',
            'ccrouter_test',
            'lib',
            'ccrouter_generated',
            'ccrouter_package.json',
          ),
        ).existsSync(),
        isFalse,
      );

      final probe = Directory(
        path.join(
          Directory.current.path,
          'demo',
          'ccrouter_generated',
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
      expect(File(path.join(probe.path, 'cc_routes.md')).existsSync(), false);
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
