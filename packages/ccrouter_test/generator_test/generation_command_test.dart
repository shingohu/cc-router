@TestOn('vm')
@Timeout(Duration(minutes: 20))
library;

import 'dart:convert';
import 'dart:io';

import 'package:ccrouter_generator/src/package_workspace.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'support/real_workspace_test_lock.dart';

void main() {
  serializeRealWorkspaceTests();

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
      expect(hostCatalog, contains('show CCHostAssembly;'));
      expect(hostCatalog, contains('CCHostAssembly.fromPackageBundles('));
      expect(
        hostCatalog,
        contains("package:ccrouter_devtools/ccrouter_devtools.dart"),
      );
      expect(hostCatalog, contains('ccrouterGeneratedDevToolsCatalog'));
      expect(hostCatalog, contains('CCDevToolsHostIntegration('));
      expect(hostCatalog, contains('hostToolIntegrations: ['));
      expect(hostCatalog, contains('kind: "route"'));
      expect(hostCatalog, contains('kind: "service"'));
      expect(hostCatalog, contains('kind: "command"'));
      expect(hostCatalog, contains('kind: "event"'));
      expect(hostCatalog, contains('kind: "initTask"'));
      expect(hostCatalog, contains('id: "demo_navigation_lab.detail"'));
      expect(hostCatalog, contains('id: "demo.network.client"'));
      expect(hostCatalog, contains('kind: "subscribes"'));
      expect(hostCatalog, isNot(contains('demo.analytics.order-completed')));
      expect(hostCatalog, isNot(contains('DateTime.now')));
      expect(hostCatalog, isNot(contains("import 'package:demo_order/")));
      final hostApi = File(
        path.join(
          Directory.current.path,
          'demo',
          'lib',
          'src',
          'ccrouter_generated',
          'ccrouter_host.api.g.dart',
        ),
      ).readAsStringSync();
      expect(hostApi, contains('Stable Host-facing CCRouter API'));
      expect(hostApi, contains("export 'host/ccrouter_host.routes.g.dart'"));
      expect(hostApi, contains('ccrouterGeneratedHostAssembly'));
      expect(hostApi, isNot(contains('ccrouterGeneratedComponentManifests')));
      expect(hostApi, isNot(contains('ccrouterGeneratedRouteCatalog')));
      expect(hostApi, isNot(contains('ccrouterGeneratedPackageBundle')));
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
      expect(
        contractCapabilities.where(
          (record) =>
              (record as Map)['kind'] == 'route' &&
              record['id'] == 'order.detail',
        ),
        hasLength(1),
      );
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
      final paymentCatalogDocument = File(
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
      ).readAsStringSync();
      expect(paymentCatalogDocument, contains('Scope: `package:demo_payment`'));
      expect(
        paymentCatalogDocument,
        contains('### Service `demo_order.summary`'),
      );
      expect(
        paymentCatalogDocument,
        contains('`DemoPaymentServices.orderSummary`'),
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
      final eventApi = File(
        path.join(
          navigationPackage,
          'lib',
          'src',
          'ccrouter_generated',
          'component',
          'demo_navigation_lab_component.event_api.g.dart',
        ),
      ).readAsStringSync();
      expect(
        eventApi,
        contains('abstract final class DemoNavigationLabEvents'),
      );
      expect(eventApi, contains('publishDemoOrderCompleted'));
      expect(
        eventApi,
        contains('eventId: "demo_navigation_lab.order_completed"'),
      );
      final componentApi = File(
        path.join(
          navigationPackage,
          'lib',
          'src',
          'ccrouter_generated',
          'demo_navigation_lab_component.api.g.dart',
        ),
      ).readAsStringSync();
      expect(
        componentApi,
        contains('Stable typed API entry point for component'),
      );
      expect(
        componentApi,
        contains(
          "export 'component/demo_navigation_lab_component.route_api.g.dart'",
        ),
      );
      expect(
        componentApi,
        contains(
          "export 'component/navigation_lab_component.service_api.g.dart'",
        ),
      );
      expect(
        componentApi,
        contains(
          "export 'component/demo_navigation_lab_component.event_api.g.dart'",
        ),
      );
      expect(componentApi, isNot(contains('.component.g.dart')));
      expect(componentApi, isNot(contains('ccrouterGeneratedComponent')));
      final componentAssembly = File(
        path.join(
          navigationPackage,
          'lib',
          'src',
          'ccrouter_generated',
          'component',
          'demo_navigation_lab_component.component.g.dart',
        ),
      ).readAsStringSync();
      expect(
        componentAssembly,
        matches(
          RegExp(
            r'subscriberId:\s*"demo_navigation_lab_component\.demo_navigation_lab\.slow"',
          ),
        ),
      );
      expect(
        componentAssembly,
        contains('ccrouterRegisterInitializeDemoFoundationInitTask(registry)'),
      );
      final initTaskBridge = File(
        path.join(
          navigationPackage,
          'lib',
          'src',
          'ccrouter_generated',
          'init_task',
          'navigation_lab_component_registrar.init_task.g.dart',
        ),
      ).readAsStringSync();
      expect(initTaskBridge, contains('id: "demo.startup.foundation"'));
      expect(
        initTaskBridge,
        contains('dependsOn: const ["demo_order.startup.foundation"]'),
      );
      final navigationCatalog = File(
        path.join(
          navigationPackage,
          'lib',
          'src',
          'ccrouter_generated',
          'metadata',
          'cc_catalog.md',
        ),
      ).readAsStringSync();
      expect(
        navigationCatalog,
        contains('### Event `demo_navigation_lab.order_completed`'),
      );
      expect(
        navigationCatalog,
        contains('### Event `demo.analytics.order-completed`'),
      );
      expect(navigationCatalog, contains('## Initialization DAG'));
      expect(navigationCatalog, contains('`demo_order.startup.foundation`'));
      expect(hostCatalogDocument, contains('## Initialization DAG'));
      expect(hostCatalogDocument, contains('`demo_order.startup.foundation`'));
      final navigationBarrel = File(
        path.join(navigationPackage, 'lib', 'demo_navigation_lab.dart'),
      ).readAsStringSync();
      expect(
        navigationBarrel,
        isNot(contains('demo_navigation_lab_component.route_api.g.dart')),
      );
      expect(
        navigationBarrel,
        isNot(contains('demo_navigation_lab_component.event_api.g.dart')),
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
    'generation rejects authored input changed after build_runner',
    () async {
      final source = File(
        path.join(
          Directory.current.path,
          'demo',
          'modules',
          'navigation_lab',
          'lib',
          'src',
          'detail_page.dart',
        ),
      );
      final original = source.readAsBytesSync();
      final seeded = await _generateDemo(['--no-cache']);
      expect(seeded.exitCode, 0, reason: '${seeded.stderr}');
      try {
        source.writeAsBytesSync([
          ...original,
          ...'\n// CCRouter pre-build input-barrier probe.\n'.codeUnits,
        ], flush: true);
        final result = await _generateDemo(
          ['--profile'],
          environment: {
            'CCROUTER_TEST_MUTATE_INPUT_AFTER_BUILDER': source.path,
          },
        );
        expect(result.exitCode, 1);
        expect(
          '${result.stderr}',
          contains('generation input changed during before-aggregation'),
        );
        expect('${result.stderr}', contains('generated output was discarded'));
        final trace = _profileDelta(result, 'trace');
        expect(trace['outcome'], 'failed');
        final spans = (trace['spans'] as List).cast<Map<String, dynamic>>();
        expect(
          spans.firstWhere(
            (span) => span['name'] == 'before-aggregation-input-barrier',
          )['status'],
          'failed',
        );
        expect(
          spans.map((span) => span['name']),
          contains('artifact-snapshot-restore'),
        );
      } finally {
        source.writeAsBytesSync(original, flush: true);
        final restored = await _generateDemo(['--no-cache']);
        expect(restored.exitCode, 0, reason: '${restored.stderr}');
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'generation removes only obsolete source-tree metadata',
    () async {
      final legacyGeneratedRoot = Directory(
        path.join(
          Directory.current.path,
          'demo',
          'modules',
          'payment',
          'ccrouter_generated',
        ),
      );
      final rootExistedBeforeTest = legacyGeneratedRoot.existsSync();
      final generatedDirectory = Directory(
        path.join(legacyGeneratedRoot.path, '.migration_probe_$pid'),
      )..createSync(recursive: true);
      addTearDown(() {
        if (generatedDirectory.existsSync()) {
          generatedDirectory.deleteSync(recursive: true);
        }
        if (!rootExistedBeforeTest &&
            legacyGeneratedRoot.existsSync() &&
            legacyGeneratedRoot.listSync().isEmpty) {
          legacyGeneratedRoot.deleteSync();
        }
        if (!rootExistedBeforeTest) {
          expect(legacyGeneratedRoot.existsSync(), isFalse);
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
      final portableStates = <String, String>{};
      await for (final entity in Directory.current.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File ||
            path.basename(entity.path) != 'ccrouter_generation_state.json' ||
            entity.path.contains(
              '${path.separator}.dart_tool${path.separator}',
            )) {
          continue;
        }
        portableStates[path.relative(
          entity.path,
          from: Directory.current.path,
        )] = await entity
            .readAsString();
      }
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
      final generatedInitTask = File(
        path.join(
          demoRoot.path,
          'modules',
          'navigation_lab',
          'lib',
          'src',
          'ccrouter_generated',
          'init_task',
          'navigation_lab_component_registrar.init_task.g.dart',
        ),
      );
      final generatedOrderContractsApi = File(
        path.join(
          demoRoot.path,
          'modules',
          'order_contracts',
          'lib',
          'src',
          'ccrouter_generated',
          'demo_order_contracts.contracts.api.g.dart',
        ),
      );
      final paymentGeneratedRoot = Directory(
        path.join(
          demoRoot.path,
          'modules',
          'payment',
          'lib',
          'src',
          'ccrouter_generated',
        ),
      );
      expect(generatedRouteApi.existsSync(), isTrue);
      expect(generatedInitTask.existsSync(), isTrue);
      expect(generatedOrderContractsApi.existsSync(), isTrue);
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
        expect(generatedInitTask.existsSync(), isFalse);
        expect(generatedOrderContractsApi.existsSync(), isFalse);
        expect(sentinel.readAsStringSync(), 'user-owned');
        expect(
          paymentGeneratedRoot.existsSync(),
          isFalse,
          reason: 'clean must remove an empty generated root.',
        );
      } finally {
        final regenerated = await Process.run(Platform.resolvedExecutable, [
          'run',
          'ccrouter_generator:ccrouter',
          'generate',
          'demo',
        ], workingDirectory: Directory.current.path);
        expect(regenerated.exitCode, 0, reason: '${regenerated.stderr}');
        for (final entry in portableStates.entries) {
          final state = File(path.join(Directory.current.path, entry.key));
          state.parent.createSync(recursive: true);
          state.writeAsStringSync(entry.value, flush: true);
        }
        if (sentinel.existsSync()) sentinel.deleteSync();
      }
      expect(generatedRouteApi.existsSync(), isTrue);
      expect(generatedInitTask.existsSync(), isTrue);
      expect(generatedOrderContractsApi.existsSync(), isTrue);
      expect(
        generatedOrderContractsApi.readAsStringSync(),
        allOf(
          contains(
            "export 'contract/order_detail_route_contract.route.contract.g.dart'",
          ),
          contains('show OrderDetailRoute, OrderDetailRouteArguments'),
          isNot(contains('placeholder')),
        ),
      );
      final converged = await Process.run(Platform.resolvedExecutable, [
        'run',
        'ccrouter_generator:ccrouter',
        'generate',
        'demo',
        '--no-cache',
        '--check',
        '--profile',
      ], workingDirectory: Directory.current.path);
      expect(converged.exitCode, 0, reason: '${converged.stderr}');
      expect('${converged.stdout}', contains('wrote 0 outputs'));
      expect(
        '${converged.stdout}',
        contains('generated artifacts are up to date'),
      );
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
    'profile emits a structured trace and atomically persists the latest run',
    () async {
      Future<ProcessResult> generate() =>
          Process.run(Platform.resolvedExecutable, [
            'run',
            'ccrouter_generator:ccrouter',
            'generate',
            'demo',
            '--check',
            '--profile',
          ], workingDirectory: Directory.current.path);

      final seeded = await generate();
      expect(seeded.exitCode, 0, reason: '${seeded.stderr}');
      final result = await generate();
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}', contains('fast-path=hit'));

      final trace = _profileDelta(result, 'trace');
      expect(trace['schemaVersion'], 1);
      expect(trace['command'], 'generate');
      expect(trace['outcome'], 'success');
      expect(trace['totalUs'], isA<int>());
      expect(trace['totalUs'], greaterThanOrEqualTo(0));
      final spans = (trace['spans'] as List).cast<Map<String, dynamic>>();
      expect(
        spans.map((span) => span['name']),
        containsAll(<String>[
          'argument-resolution',
          'build-context-resolution',
          'generation-lock-wait',
          'workspace-load',
          'fast-path-inspection',
          'build-runner-process',
          'workspace-aggregation',
          'generation-lock-release',
        ]),
      );
      for (final span in spans) {
        expect(span['startUs'], isA<int>());
        expect(span['durationUs'], isA<int>());
        expect(span['durationUs'], greaterThanOrEqualTo(0));
        expect(span['status'], anyOf('ok', 'failed', 'skipped'));
      }
      expect(
        jsonEncode(trace),
        isNot(contains(Directory.current.absolute.path)),
      );
      final reportMatch = RegExp(
        r'CCRouter profile report=([^\n]+)',
      ).firstMatch('${result.stdout}');
      expect(reportMatch, isNotNull, reason: '${result.stdout}');
      final reportPath = reportMatch!.group(1)!;
      expect(path.isAbsolute(reportPath), isFalse);
      final reportFile = File(path.join(Directory.current.path, reportPath));
      expect(reportFile.existsSync(), isTrue);
      expect(jsonDecode(reportFile.readAsStringSync()), trace);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'no-cache profile traces the full generator and Builder phases',
    () async {
      final result = await _generateDemo([
        '--no-cache',
        '--check',
        '--profile',
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}', contains('ccrouter_generator:routes'));
      expect('${result.stdout}', contains('Built with build_runner'));
      final trace = _profileDelta(result, 'trace');
      final spans = (trace['spans'] as List).cast<Map<String, dynamic>>();
      expect(
        spans.map((span) => span['name']),
        containsAll(<String>[
          'input-fingerprint-capture',
          'portable-state-readonly-verification',
          'component-dependency-preflight',
          'artifact-snapshot-capture',
          'build-runner-process-start',
          'build-runner-execution',
          'build-runner-protection-restore',
          'aggregation-workspace-reload',
          'before-aggregation-input-barrier',
          'metadata-and-package-index-load',
          'package-graph-and-index-construction',
          'aggregation-input-fingerprint',
          'workspace-validation',
          'component-index-generation',
          'package-bundle-generation',
          'host-artifact-write',
          'after-aggregation-input-barrier',
          'output-delta-scan',
          'check-restore',
          'planning-snapshot-capture',
          'fast-path-manifest-write',
          'build-plan-state-write',
        ]),
      );
      expect(
        spans.firstWhere(
          (span) => span['name'] == 'build-runner-execution',
        )['status'],
        'ok',
      );
      final aggregationInput = spans.singleWhere(
        (span) => span['name'] == 'aggregation-input-fingerprint',
      );
      expect(aggregationInput['status'], 'ok');
      expect(
        (aggregationInput['attributes'] as Map)['fingerprint'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect(trace['outcome'], 'success');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'shared planning snapshot matches legacy state bytes',
    () async {
      final before = await _readDemoGeneratedArtifacts();
      final optimized = await _generateDemo([
        '--no-cache',
        '--check',
        '--profile',
      ]);
      expect(optimized.exitCode, 0, reason: '${optimized.stderr}');
      final optimizedSpans =
          (_profileDelta(optimized, 'trace')['spans'] as List)
              .cast<Map<String, dynamic>>();
      expect(
        optimizedSpans.singleWhere(
          (span) => span['name'] == 'planning-snapshot-capture',
        )['status'],
        'ok',
      );
      final optimizedManifest = _demoFastPathManifest().readAsBytesSync();
      final optimizedPlan = _demoBuildPlanState().readAsBytesSync();

      final reference = await _generateDemo(
        ['--no-cache', '--check', '--profile'],
        environment: {
          ...Platform.environment,
          'CCROUTER_DISABLE_SHARED_PLANNING_SNAPSHOT': '1',
        },
      );
      expect(reference.exitCode, 0, reason: '${reference.stderr}');
      final referenceSpans =
          (_profileDelta(reference, 'trace')['spans'] as List)
              .cast<Map<String, dynamic>>();
      expect(
        referenceSpans.singleWhere(
          (span) => span['name'] == 'planning-snapshot-capture',
        )['status'],
        'skipped',
      );
      expect(
        _demoFastPathManifest().readAsBytesSync(),
        orderedEquals(optimizedManifest),
      );
      expect(
        _demoBuildPlanState().readAsBytesSync(),
        orderedEquals(optimizedPlan),
      );
      expect(await _readDemoGeneratedArtifacts(), before);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'post-Builder aggregation reuse matches the kill-switch reference',
    () async {
      final source = File(
        path.join(
          Directory.current.path,
          'demo',
          'modules',
          'navigation_lab',
          'lib',
          'src',
          'stack_page.dart',
        ),
      );
      final original = source.readAsStringSync();
      final before = await _readDemoGeneratedArtifacts();
      try {
        source.writeAsStringSync(
          '$original\n// Aggregation reuse seed.\n',
          flush: true,
        );
        final seed = await _generateDemo(['--profile']);
        expect(seed.exitCode, 0, reason: '${seed.stderr}');

        source.writeAsStringSync(
          '$original\n// Aggregation reuse hit.\n',
          flush: true,
        );
        final optimized = await _generateDemo(['--profile']);
        expect(optimized.exitCode, 0, reason: '${optimized.stderr}');
        expect(
          '${optimized.stdout}',
          contains('aggregation-reuse=hit reason=verified'),
        );
        final optimizedSpans =
            (_profileDelta(optimized, 'trace')['spans'] as List)
                .cast<Map<String, dynamic>>();
        for (final name in const [
          'dirty-package-computation',
          'component-index-generation',
          'metadata-cache-persist',
        ]) {
          expect(
            optimizedSpans.singleWhere(
              (span) => span['name'] == name,
            )['status'],
            'skipped',
          );
        }
        expect(await _readDemoGeneratedArtifacts(), before);

        source.writeAsStringSync(
          '$original\n// Aggregation reuse reference.\n',
          flush: true,
        );
        final reference = await _generateDemo(
          ['--profile'],
          environment: {
            ...Platform.environment,
            'CCROUTER_DISABLE_AGGREGATION_REUSE': '1',
          },
        );
        expect(reference.exitCode, 0, reason: '${reference.stderr}');
        expect(
          '${reference.stdout}',
          contains('aggregation-reuse=miss reason=disabled'),
        );
        expect(await _readDemoGeneratedArtifacts(), before);
      } finally {
        source.writeAsStringSync(original, flush: true);
        final restored = await _generateDemo(const []);
        expect(restored.exitCode, 0, reason: '${restored.stderr}');
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'shared planning snapshot isolates Build Plan state failures',
    () async {
      final before = await _readDemoGeneratedArtifacts();
      final stateDirectory = _demoBuildPlanState().parent;
      final backup = Directory('${stateDirectory.path}.failure-test-$pid');
      expect(backup.existsSync(), isFalse);
      stateDirectory.renameSync(backup.path);
      final blocker = File(stateDirectory.path)
        ..writeAsStringSync('Build Plan directory failure probe.\n');
      try {
        final result = await _generateDemo(['--no-cache', '--profile']);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect('${result.stdout}', contains('build-plan-state=write-failed'));
        final spans = (_profileDelta(result, 'trace')['spans'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          spans.singleWhere(
            (span) => span['name'] == 'fast-path-manifest-write',
          )['status'],
          'ok',
        );
        expect(
          spans.singleWhere(
            (span) => span['name'] == 'build-plan-state-write',
          )['status'],
          'failed',
        );
        expect(await _readDemoGeneratedArtifacts(), before);
      } finally {
        if (blocker.existsSync()) blocker.deleteSync();
        if (backup.existsSync()) backup.renameSync(stateDirectory.path);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'fast path requires exact authored inputs and managed outputs',
    () async {
      Future<ProcessResult> generate({bool check = false}) =>
          Process.run(Platform.resolvedExecutable, [
            'run',
            'ccrouter_generator:ccrouter',
            'generate',
            'demo',
            if (check) '--check',
            '--profile',
          ], workingDirectory: Directory.current.path);

      final seeded = await generate();
      expect(seeded.exitCode, 0, reason: '${seeded.stderr}');
      final unchanged = await generate(check: true);
      expect(unchanged.exitCode, 0, reason: '${unchanged.stderr}');
      expect('${unchanged.stdout}', contains('fast-path=hit'));
      expect(_profileDelta(unchanged, 'output-delta')['files'], 0);
      expect('${unchanged.stdout}', contains('input-delta=unchanged'));

      final sourceProbe = File(
        path.join(
          Directory.current.path,
          'demo',
          'lib',
          '_ccrouter_fast_path_probe.dart',
        ),
      );
      final generatedProbe = File(
        path.join(
          Directory.current.path,
          'demo',
          'lib',
          'src',
          'ccrouter_generated',
          'metadata',
          'cc_routes.json',
        ),
      );
      final originalGenerated = generatedProbe.readAsBytesSync();
      final portableState = File(
        path.join(
          Directory.current.path,
          'demo',
          'lib',
          'src',
          'ccrouter_generated',
          'metadata',
          'ccrouter_generation_state.json',
        ),
      );
      final originalPortableState = portableState.readAsBytesSync();
      addTearDown(() {
        if (sourceProbe.existsSync()) sourceProbe.deleteSync();
        generatedProbe.writeAsBytesSync(originalGenerated, flush: true);
        portableState.writeAsBytesSync(originalPortableState, flush: true);
      });

      sourceProbe.writeAsStringSync('const fastPathProbe = true;\n');
      final changedSource = await generate(check: true);
      expect(changedSource.exitCode, 0, reason: '${changedSource.stderr}');
      expect('${changedSource.stdout}', contains('fast-path=miss'));
      expect('${changedSource.stdout}', contains('CCRouter profile build='));
      expect(
        '${changedSource.stdout}',
        contains('CCRouter profile build-targets='),
      );
      expect(
        '${changedSource.stdout}',
        contains('aggregation-reuse=hit reason=verified'),
      );
      expect(
        '${changedSource.stdout}',
        contains('dirty-packages=reused-aggregation-outputs'),
      );
      final inputs = _profileDelta(changedSource, 'input-delta');
      expect(inputs['status'], 'compared');
      expect((inputs['authored'] as Map)['packages'], ['ccrouter_demo']);
      final outputs = _profileDelta(changedSource, 'output-delta');
      expect(outputs['files'], 0);
      expect((outputs['artifacts'] as Map)['dart'], {
        'added': 0,
        'removed': 0,
        'modified': 0,
      });
      expect('${changedSource.stdout}', isNot(contains('const fastPathProbe')));
      expect(
        '${changedSource.stderr}',
        isNot(contains('ccrouter_generation_state.json')),
      );

      final generatedWithSource = await generate();
      expect(
        generatedWithSource.exitCode,
        0,
        reason: '${generatedWithSource.stderr}',
      );
      expect('${generatedWithSource.stdout}', contains('fast-path=hit'));
      expect(portableState.readAsBytesSync(), originalPortableState);

      sourceProbe.deleteSync();
      final reseeded = await generate();
      expect(reseeded.exitCode, 0, reason: '${reseeded.stderr}');
      expect('${reseeded.stdout}', contains('fast-path=miss'));

      generatedProbe.writeAsStringSync(
        '${generatedProbe.readAsStringSync()}\n',
        flush: true,
      );
      final tamperedGenerated = generatedProbe.readAsBytesSync();
      final changedOutput = await generate(check: true);
      expect(changedOutput.exitCode, 1);
      expect('${changedOutput.stdout}', contains('fast-path=miss'));
      expect(
        '${changedOutput.stderr}',
        contains('generated artifacts are stale'),
      );
      expect(generatedProbe.readAsBytesSync(), tamperedGenerated);
      final repaired = _profileDelta(changedOutput, 'output-delta');
      expect(
        ((repaired['artifacts'] as Map)['metadata'] as Map)['modified'],
        greaterThan(0),
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test('generation without profile does not emit a timing trace', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'ccrouter_generator:ccrouter',
      'generate',
      'demo',
      '--check',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}', isNot(contains('CCRouter profile trace=')));
    expect('${result.stdout}', isNot(contains('CCRouter profile report=')));
  });

  test(
    'P1 build plan diagnoses Host-only changes without skipping Builder',
    () async {
      final before = await _readDemoGeneratedArtifacts();
      final seeded = await _generateDemo(['--no-cache', '--profile']);
      expect(seeded.exitCode, 0, reason: '${seeded.stderr}');
      expect(_profileDelta(seeded, 'input-delta')['status'], 'unavailable');
      expect(
        '${seeded.stdout}',
        contains(
          'build-plan suggested=runBuilder actual=runBuilder '
          'reasons=no-cache-reference',
        ),
      );
      final state = _demoBuildPlanState();
      final stateContents = state.readAsStringSync();
      expect(stateContents, isNot(contains(Directory.current.absolute.path)));
      expect(stateContents, isNot(contains('rootUri')));

      final probe =
          File(
            path.join(
              Directory.current.path,
              'demo',
              'lib',
              '_ccrouter_build_plan_host_probe.dart',
            ),
          )..writeAsStringSync(
            'const ccrouterBuildPlanHostProbe = '
            '${DateTime.now().microsecondsSinceEpoch};\n',
            flush: true,
          );
      try {
        final result = await _generateDemo(['--check', '--profile']);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect('${result.stdout}', contains('fast-path=miss'));
        expect(
          '${result.stdout}',
          contains(
            'build-plan suggested=runBuilder actual=runBuilder '
            'reasons=authored-input-changed:ccrouter_demo,'
            'resolution-changed:ccrouter_demo',
          ),
        );
        expect('${result.stdout}', contains('CCRouter profile build-targets='));
        expect('${result.stdout}', contains('CCRouter profile build='));
        expect(
          '${result.stderr}',
          isNot(contains('ccrouter_generation_state')),
        );
        expect(_profileDelta(result, 'output-delta')['files'], 0);
        expect(await _readDemoGeneratedArtifacts(), before);
      } finally {
        if (probe.existsSync()) probe.deleteSync();
        final restored = await _generateDemo(const []);
        expect(restored.exitCode, 0, reason: '${restored.stderr}');
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'P1 build plan reports changed source and repairs local planning state',
    () async {
      final seeded = await _generateDemo(['--no-cache']);
      expect(seeded.exitCode, 0, reason: '${seeded.stderr}');
      final component = File(
        path.join(
          Directory.current.path,
          'demo',
          'modules',
          'payment',
          'lib',
          'src',
          'demo_payment_component.dart',
        ),
      );
      final originalComponent = component.readAsBytesSync();
      try {
        component.writeAsStringSync(
          '${component.readAsStringSync()}\n// Build plan source probe.\n',
          flush: true,
        );
        final changed = await _generateDemo(['--check', '--profile']);
        expect(changed.exitCode, 0, reason: '${changed.stderr}');
        expect(
          '${changed.stdout}',
          contains('suggested=runBuilder actual=runBuilder'),
        );
        expect(
          '${changed.stdout}',
          contains('authored-input-changed:demo_payment'),
        );
        final inputs = _profileDelta(changed, 'input-delta');
        expect((inputs['authored'] as Map)['packages'], ['demo_payment']);
        expect(
          (inputs['resolutionOnly'] as Map)['packages'],
          contains('ccrouter_demo'),
        );
        expect(
          '${changed.stderr}',
          isNot(contains('ccrouter_generation_state')),
        );
        expect(_profileDelta(changed, 'output-delta')['files'], 0);
      } finally {
        component.writeAsBytesSync(originalComponent, flush: true);
      }

      final restored = await _generateDemo(const []);
      expect(restored.exitCode, 0, reason: '${restored.stderr}');
      final state = _demoBuildPlanState();
      final hostProbe = File(
        path.join(
          Directory.current.path,
          'demo',
          'lib',
          '_ccrouter_invalid_plan_probe.dart',
        ),
      )..writeAsStringSync('const ccrouterInvalidPlanProbe = true;\n');
      try {
        final unprovenDocument =
            (jsonDecode(state.readAsStringSync()) as Map)
                .cast<String, Object?>()
              ..remove('contentFingerprint');
        final packageStates = (unprovenDocument['packages']! as Map)
            .cast<String, Object?>();
        final paymentState = (packageStates['demo_payment']! as Map)
            .cast<String, Object?>();
        paymentState['resolutionPortable'] = false;
        paymentState['authoredInputFingerprint'] = null;
        paymentState['resolutionFingerprint'] = 'unknown-previous-resolution';
        unprovenDocument['contentFingerprint'] =
            computeCCCanonicalJsonFingerprint(unprovenDocument);
        state.writeAsStringSync(jsonEncode(unprovenDocument), flush: true);

        final unproven = await _generateDemo(['--check', '--profile']);
        expect(unproven.exitCode, 0, reason: '${unproven.stderr}');
        final attribution = _profileDelta(unproven, 'input-delta');
        expect(
          (attribution['authoredUnavailable'] as Map)['packages'],
          contains('demo_payment'),
        );
        expect(
          (attribution['resolutionOnly'] as Map)['packages'],
          isNot(contains('demo_payment')),
        );
        expect(
          '${unproven.stdout}',
          contains('resolution-unproven:demo_payment'),
        );
        expect(
          '${unproven.stderr}',
          isNot(contains('ccrouter_generation_state')),
        );
        expect(_profileDelta(unproven, 'output-delta')['files'], 0);

        state.writeAsStringSync('{invalid planning state', flush: true);
        hostProbe.writeAsStringSync(
          'const ccrouterInvalidPlanProbe = false;\n',
          flush: true,
        );
        final invalid = await _generateDemo(['--check', '--profile']);
        expect(invalid.exitCode, 0, reason: '${invalid.stderr}');
        expect(
          '${invalid.stdout}',
          contains(
            'build-plan suggested=runBuilder actual=runBuilder '
            'reasons=planning-state-invalid',
          ),
        );
        expect(
          '${invalid.stderr}',
          isNot(contains('ccrouter_generation_state')),
        );
        expect(_profileDelta(invalid, 'output-delta')['files'], 0);
        expect(jsonDecode(state.readAsStringSync()), isA<Map>());
      } finally {
        if (hostProbe.existsSync()) hostProbe.deleteSync();
        final converged = await _generateDemo(const []);
        expect(converged.exitCode, 0, reason: '${converged.stderr}');
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'P6 tool identity changes force the full Builder path',
    () async {
      final seeded = await _generateDemo(['--no-cache']);
      expect(seeded.exitCode, 0, reason: '${seeded.stderr}');
      final state = _demoBuildPlanState();
      final original = state.readAsBytesSync();
      final probe = File(
        path.join(
          Directory.current.path,
          'demo',
          'lib',
          '_ccrouter_tool_identity_probe.dart',
        ),
      );
      try {
        probe.writeAsStringSync('const ccrouterToolIdentityProbe = true;\n');
        final document =
            (jsonDecode(state.readAsStringSync()) as Map)
                .cast<String, Object?>()
              ..remove('contentFingerprint');
        document['toolFingerprint'] = 'p6-tool-identity-probe';
        document['contentFingerprint'] = computeCCCanonicalJsonFingerprint(
          document,
        );
        state.writeAsStringSync(jsonEncode(document), flush: true);

        final result = await _generateDemo(['--check', '--profile']);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(
          '${result.stdout}',
          contains('build-plan suggested=runBuilder actual=runBuilder'),
        );
        expect('${result.stdout}', contains('tool-input-changed'));
        expect(_profileDelta(result, 'output-delta')['files'], 0);
        expect(
          '${result.stderr}',
          isNot(contains('ccrouter_generation_state')),
        );
      } finally {
        if (probe.existsSync()) probe.deleteSync();
        state.writeAsBytesSync(original, flush: true);
        final restored = await _generateDemo(const []);
        expect(restored.exitCode, 0, reason: '${restored.stderr}');
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'CLI integration edits do not change the generation tool identity',
    () async {
      final seeded = await _generateDemo(['--no-cache']);
      expect(seeded.exitCode, 0, reason: '${seeded.stderr}');
      final probe = File(
        path.join(
          Directory.current.path,
          'packages',
          'ccrouter_generator',
          'bin',
          'src',
          'scaffold.dart',
        ),
      );
      final original = probe.readAsBytesSync();
      try {
        await probe.writeAsBytes(<int>[...original, 10], flush: true);
        final result = await _generateDemo(['--check', '--profile']);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect('${result.stdout}', isNot(contains('tool-input-changed')));
        expect(_profileDelta(result, 'output-delta')['files'], 0);
        expect(
          '${result.stderr}',
          isNot(contains('ccrouter_generation_state')),
        );
      } finally {
        await probe.writeAsBytes(original, flush: true);
        final restored = await _generateDemo(const []);
        expect(restored.exitCode, 0, reason: '${restored.stderr}');
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'generation-cycle kernel edits invalidate the generation tool identity',
    () async {
      final seeded = await _generateDemo(['--no-cache']);
      expect(seeded.exitCode, 0, reason: '${seeded.stderr}');
      final probe = File(
        path.join(
          Directory.current.path,
          'packages',
          'ccrouter_generator',
          'bin',
          'src',
          'generation_watch.dart',
        ),
      );
      final original = probe.readAsBytesSync();
      try {
        await probe.writeAsBytes(<int>[...original, 10], flush: true);
        final result = await _generateDemo(['--check', '--profile']);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect('${result.stdout}', contains('tool-input-changed'));
        expect(_profileDelta(result, 'output-delta')['files'], 0);
        expect(
          '${result.stderr}',
          isNot(contains('ccrouter_generation_state')),
        );
      } finally {
        await probe.writeAsBytes(original, flush: true);
        final restored = await _generateDemo(const []);
        expect(restored.exitCode, 0, reason: '${restored.stderr}');
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'P2 full Builder fallback matches a Host component removal reference',
    () async {
      final before = await _readDemoGeneratedArtifacts();
      final seeded = await _generateDemo(['--no-cache']);
      expect(seeded.exitCode, 0, reason: '${seeded.stderr}');
      final graph = File(
        path.join(Directory.current.path, '.dart_tool', 'package_graph.json'),
      );
      final originalGraph = graph.readAsBytesSync();
      try {
        final document = jsonDecode(graph.readAsStringSync()) as Map;
        final packages = document['packages'] as List;
        final host = packages.cast<Map>().singleWhere(
          (package) => package['name'] == 'ccrouter_demo',
        );
        (host['dependencies'] as List).remove('demo_payment');
        graph.writeAsStringSync(jsonEncode(document), flush: true);

        final disabled = await _generateDemo(
          ['--check', '--profile'],
          environment: const {'CCROUTER_DISABLE_AGGREGATE_ONLY': '1'},
        );
        expect(disabled.exitCode, 1);
        expect(
          '${disabled.stdout}',
          contains(
            'build-plan suggested=runBuilder actual=runBuilder '
            'reasons=resolution-changed:ccrouter_demo',
          ),
        );
        expect(
          '${disabled.stdout}',
          contains('CCRouter profile build-targets=8'),
        );

        final generated = await _generateDemo(['--profile']);
        expect(generated.exitCode, 0, reason: '${generated.stderr}');
        expect(
          '${generated.stdout}',
          contains(
            'build-plan suggested=runBuilder actual=runBuilder '
            'reasons=resolution-changed:ccrouter_demo',
          ),
        );
        expect(
          '${generated.stdout}',
          contains('CCRouter profile build-targets=8'),
        );
        final generatedArtifacts = await _readDemoGeneratedArtifacts();
        expect(generatedArtifacts, isNot(before));

        final reference = await _generateDemo([
          '--check',
          '--no-cache',
          '--profile',
        ]);
        expect(reference.exitCode, 0, reason: '${reference.stderr}');
        expect('${reference.stdout}', contains('reasons=no-cache-reference'));
        expect(await _readDemoGeneratedArtifacts(), generatedArtifacts);
      } finally {
        graph.writeAsBytesSync(originalGraph, flush: true);
        final restored = await _generateDemo(const []);
        expect(restored.exitCode, 0, reason: '${restored.stderr}');
        expect(await _readDemoGeneratedArtifacts(), before);
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  test(
    'portable prepare bypasses a matching manifest and repairs state',
    () async {
      final portableState = File(
        path.join(
          Directory.current.path,
          'demo',
          'modules',
          'payment',
          'lib',
          'src',
          'ccrouter_generated',
          'metadata',
          'ccrouter_generation_state.json',
        ),
      );
      final original = portableState.readAsBytesSync();
      try {
        portableState.deleteSync();
        final missingBaseline = await _generateDemo(['--no-cache']);
        expect(
          missingBaseline.exitCode,
          0,
          reason: '${missingBaseline.stderr}',
        );
        expect(portableState.existsSync(), isFalse);

        final missingFastPath = await _generateDemo(const []);
        expect(
          missingFastPath.exitCode,
          0,
          reason: '${missingFastPath.stderr}',
        );
        expect('${missingFastPath.stdout}', contains('fast path hit'));
        expect(portableState.existsSync(), isFalse);

        final repairedMissing = await _preparePortableDemo();
        expect(
          repairedMissing.exitCode,
          0,
          reason: '${repairedMissing.stderr}',
        );
        expect('${repairedMissing.stdout}', contains('Prepared Portable'));
        expect('${repairedMissing.stdout}', isNot(contains('fast path hit')));
        expect(portableState.existsSync(), isTrue);

        final staleDocument =
            (jsonDecode(portableState.readAsStringSync()) as Map)
                .cast<String, Object?>()
              ..remove('contentFingerprint');
        staleDocument['toolFingerprint'] = 'stale-portable-tool';
        staleDocument['contentFingerprint'] = computeCCCanonicalJsonFingerprint(
          staleDocument,
        );
        final staleContents = jsonEncode(staleDocument);
        portableState.writeAsStringSync(staleContents, flush: true);

        final staleBaseline = await _generateDemo(['--no-cache']);
        expect(staleBaseline.exitCode, 0, reason: '${staleBaseline.stderr}');
        expect(portableState.readAsStringSync(), staleContents);

        final staleFastPath = await _generateDemo(const []);
        expect(staleFastPath.exitCode, 0, reason: '${staleFastPath.stderr}');
        expect('${staleFastPath.stdout}', contains('fast path hit'));
        expect(portableState.readAsStringSync(), staleContents);

        final repairedStale = await _preparePortableDemo();
        expect(repairedStale.exitCode, 0, reason: '${repairedStale.stderr}');
        expect('${repairedStale.stdout}', contains('Prepared Portable'));
        expect('${repairedStale.stdout}', isNot(contains('fast path hit')));
        expect(
          jsonDecode(portableState.readAsStringSync()),
          isNot(containsPair('toolFingerprint', 'stale-portable-tool')),
        );
      } finally {
        portableState.writeAsBytesSync(original, flush: true);
        final restored = await _generateDemo(['--no-cache']);
        expect(restored.exitCode, 0, reason: '${restored.stderr}');
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  test(
    'P3 falls back to Builder when a Portable Package changes resolution',
    () async {
      final seeded = await _preparePortableDemo();
      expect(seeded.exitCode, 0, reason: '${seeded.stderr}');
      final before = await _readDemoGeneratedArtifacts();
      final portableState = File(
        path.join(
          Directory.current.path,
          'demo',
          'modules',
          'payment',
          'lib',
          'src',
          'ccrouter_generated',
          'metadata',
          'ccrouter_generation_state.json',
        ),
      );
      expect(portableState.existsSync(), isTrue);
      final portableContents = portableState.readAsStringSync();
      expect(portableContents, isNot(contains(Directory.current.path)));
      expect(portableContents, isNot(contains('rootUri')));
      expect(portableContents, isNot(contains('.dart_tool')));

      final graph = File(
        path.join(Directory.current.path, '.dart_tool', 'package_graph.json'),
      );
      final originalGraph = graph.readAsBytesSync();
      final metadataDirectory = Directory(
        path.join(
          Directory.current.path,
          '.dart_tool',
          'build',
          'generated',
          'demo_payment',
        ),
      );
      try {
        final document = jsonDecode(graph.readAsStringSync()) as Map;
        final packages = document['packages'] as List;
        final host = packages.cast<Map>().singleWhere(
          (package) => package['name'] == 'ccrouter_demo',
        );
        (host['dependencies'] as List).remove('demo_payment');
        graph.writeAsStringSync(jsonEncode(document), flush: true);

        final removed = await _generateDemo(['--profile']);
        expect(removed.exitCode, 0, reason: '${removed.stderr}');
        expect(
          '${removed.stdout}',
          contains(
            'build-plan suggested=runBuilder actual=runBuilder '
            'reasons=resolution-changed:ccrouter_demo',
          ),
        );

        graph.writeAsBytesSync(originalGraph, flush: true);
        if (metadataDirectory.existsSync()) {
          metadataDirectory.deleteSync(recursive: true);
        }
        final restored = await _generateDemo(['--profile']);
        expect(restored.exitCode, 0, reason: '${restored.stderr}');
        expect(
          '${restored.stdout}',
          contains(
            'build-plan suggested=runBuilder actual=runBuilder '
            'reasons=resolution-changed:ccrouter_demo',
          ),
        );
        expect(
          '${restored.stdout}',
          contains('CCRouter profile build-targets='),
        );
        expect(await _readDemoGeneratedArtifacts(), before);

        final reference = await _generateDemo([
          '--check',
          '--no-cache',
          '--profile',
        ]);
        expect(reference.exitCode, 0, reason: '${reference.stderr}');
        expect('${reference.stdout}', contains('reasons=no-cache-reference'));
        expect(await _readDemoGeneratedArtifacts(), before);
      } finally {
        graph.writeAsBytesSync(originalGraph, flush: true);
        final restored = await _generateDemo(['--no-cache']);
        expect(restored.exitCode, 0, reason: '${restored.stderr}');
        expect(await _readDemoGeneratedArtifacts(), before);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  test(
    'P3 rejects a read-only Package without valid Portable Generation State',
    () async {
      final seeded = await _preparePortableDemo();
      expect(seeded.exitCode, 0, reason: '${seeded.stderr}');
      final packageConfig = File(
        path.join(Directory.current.path, '.dart_tool', 'package_config.json'),
      );
      final originalConfig = packageConfig.readAsBytesSync();
      final externalRoot = await Directory.systemTemp.createTemp(
        'ccrouter_external_payment_',
      );
      await _copyDirectory(
        Directory(
          path.join(Directory.current.path, 'demo', 'modules', 'payment'),
        ),
        externalRoot,
      );
      try {
        final document = jsonDecode(packageConfig.readAsStringSync()) as Map;
        final packages = document['packages'] as List;
        final payment = packages.cast<Map>().singleWhere(
          (package) => package['name'] == 'demo_payment',
        );
        payment['rootUri'] = externalRoot.uri.toString();
        packageConfig.writeAsStringSync(jsonEncode(document), flush: true);

        final valid = await _generateDemo(['--check', '--profile']);
        expect(valid.exitCode, 0, reason: '${valid.stderr}');
        expect('${valid.stdout}', contains('build-targets=8'));
        expect(
          '${valid.stdout}',
          contains('builder-package-disabled:demo_payment'),
        );

        final externalState = File(
          path.join(
            externalRoot.path,
            'lib',
            'src',
            'ccrouter_generated',
            'metadata',
            'ccrouter_generation_state.json',
          ),
        );
        final originalState = externalState.readAsStringSync();
        final tamperedDocument =
            jsonDecode(originalState) as Map<String, Object?>;
        tamperedDocument['contentFingerprint'] = 'tampered';
        externalState.writeAsStringSync(
          jsonEncode(tamperedDocument),
          flush: true,
        );
        final tampered = await _generateDemo(['--check', '--profile']);
        expect(tampered.exitCode, 1);
        expect(
          '${tampered.stderr}',
          contains(
            'Read-only CCRouter Package "demo_payment" has an invalid '
            'Portable Generation State (invalid)',
          ),
        );

        externalState.writeAsStringSync(originalState, flush: true);
        externalState.deleteSync();
        final missing = await _generateDemo(['--check', '--profile']);
        expect(missing.exitCode, 1);
        expect(
          '${missing.stderr}',
          contains(
            'Read-only CCRouter Package "demo_payment" has an invalid '
            'Portable Generation State (missing)',
          ),
        );
      } finally {
        packageConfig.writeAsBytesSync(originalConfig, flush: true);
        if (externalRoot.existsSync()) {
          externalRoot.deleteSync(recursive: true);
        }
        final restored = await _generateDemo(['--no-cache']);
        expect(restored.exitCode, 0, reason: '${restored.stderr}');
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
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
      expect('${result.stdout}', contains('cache-missing'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'corrupted generation manifest fails closed to full generation',
    () async {
      final seeded = await Process.run(Platform.resolvedExecutable, [
        'run',
        'ccrouter_generator:ccrouter',
        'generate',
        'demo',
      ], workingDirectory: Directory.current.path);
      expect(seeded.exitCode, 0, reason: '${seeded.stderr}');

      final manifestDirectory = Directory(
        path.join(
          Directory.current.path,
          '.dart_tool',
          'ccrouter',
          'v1',
          'manifests',
        ),
      );
      final manifest = manifestDirectory
          .listSync()
          .whereType<File>()
          .firstWhere((file) {
            final decoded = jsonDecode(file.readAsStringSync());
            return decoded is Map && decoded['hostPackage'] == 'ccrouter_demo';
          });
      manifest.writeAsStringSync('{invalid manifest', flush: true);

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'ccrouter_generator:ccrouter',
        'generate',
        'demo',
        '--check',
        '--profile',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}', contains('fast-path=miss'));
      expect('${result.stdout}', contains('CCRouter profile build='));
      expect(
        '${result.stdout}',
        contains('generated artifacts are up to date'),
      );
      expect(jsonDecode(manifest.readAsStringSync()), isA<Map>());
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

Future<ProcessResult> _generateDemo(
  List<String> arguments, {
  Map<String, String>? environment,
}) => Process.run(
  Platform.resolvedExecutable,
  ['run', 'ccrouter_generator:ccrouter', 'generate', 'demo', ...arguments],
  workingDirectory: Directory.current.path,
  environment: environment,
);

Future<ProcessResult> _preparePortableDemo() => Process.run(
  Platform.resolvedExecutable,
  ['run', 'ccrouter_generator:ccrouter', 'portable', 'prepare', 'demo'],
  workingDirectory: Directory.current.path,
);

File _demoBuildPlanState() {
  final directory = Directory(
    path.join(
      Directory.current.path,
      '.dart_tool',
      'ccrouter',
      'v1',
      'build_plans',
    ),
  );
  return directory.listSync().whereType<File>().firstWhere((file) {
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map && decoded['hostPackage'] == 'ccrouter_demo';
    } on FormatException {
      return false;
    }
  });
}

File _demoFastPathManifest() {
  final directory = Directory(
    path.join(
      Directory.current.path,
      '.dart_tool',
      'ccrouter',
      'v1',
      'manifests',
    ),
  );
  return directory.listSync().whereType<File>().firstWhere((file) {
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map && decoded['hostPackage'] == 'ccrouter_demo';
    } on FormatException {
      return false;
    }
  });
}

Map<String, dynamic> _profileDelta(ProcessResult result, String name) {
  final match = RegExp(
    'CCRouter profile $name=([^\\n]+)',
  ).firstMatch('${result.stdout}');
  expect(match, isNotNull, reason: '${result.stdout}');
  return jsonDecode(match!.group(1)!) as Map<String, dynamic>;
}

Future<void> _copyDirectory(Directory source, Directory target) async {
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = path.relative(entity.path, from: source.path);
    final destination = path.join(target.path, relative);
    if (entity is Directory) {
      Directory(destination).createSync(recursive: true);
    } else if (entity is File) {
      final file = File(destination);
      file.parent.createSync(recursive: true);
      await entity.copy(file.path);
    }
  }
}
