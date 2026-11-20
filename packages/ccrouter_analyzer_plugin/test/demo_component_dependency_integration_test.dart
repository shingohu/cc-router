import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:ccrouter_analyzer_plugin/src/contract_owner_index.dart';
import 'package:ccrouter_analyzer_plugin/src/package_context_cache.dart';
import 'package:ccrouter_analyzer_plugin/src/quick_fixes.dart';
import 'package:ccrouter_analyzer_plugin/src/source_analyzer.dart'
    show CCRouterSourceAnalyzer;
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test(
    'reports missing component owners from the resolved Demo graph',
    () async {
      final workspaceRoot = _findWorkspaceRoot();
      final sourceFile = File(
        path.join(
          workspaceRoot.path,
          'demo',
          'modules',
          'navigation_lab',
          'lib',
          'src',
          'navigation_lab_component.dart',
        ),
      );
      final source = sourceFile.readAsStringSync().replaceFirst(
        RegExp(r'  dependencies: \[.*?\],\n', dotAll: true),
        '  dependencies: [],\n',
      );
      final packageContext = CCRouterPackageContextCache().resolve(
        sourceFile.path,
      );

      expect(packageContext?.name, 'demo_navigation_lab');
      final resources = OverlayResourceProvider(
        PhysicalResourceProvider.INSTANCE,
      )..setOverlay(sourceFile.path, content: source, modificationStamp: 1);
      final collection = AnalysisContextCollection(
        includedPaths: [sourceFile.path],
        resourceProvider: resources,
      );
      addTearDown(collection.dispose);
      final resolved =
          await collection
                  .contextFor(sourceFile.path)
                  .currentSession
                  .getResolvedUnit(sourceFile.path)
              as ResolvedUnitResult;
      final diagnostics = CCRouterSourceAnalyzer.analyze(
        source: source,
        filePath: sourceFile.path,
        packageRoot: packageContext?.root,
        packageName: packageContext?.name,
        resolvedUnit: resolved.unit,
        contractOwners: CCRouterContractOwnerIndexCache().resolve(
          sourceFile.path,
        ),
      );

      final ownerDiagnostics = diagnostics
          .where(
            (diagnostic) =>
                diagnostic.code ==
                'ccrouter_component_owner_dependency_missing',
          )
          .map((diagnostic) => diagnostic.message)
          .toList(growable: false);
      expect(ownerDiagnostics, hasLength(3));
      expect(ownerDiagnostics, contains(contains('demo_order_component')));
      expect(ownerDiagnostics, contains(contains('demo_network_component')));
      expect(ownerDiagnostics, contains(contains('demo_kv_storage_component')));
    },
  );
  test(
    'Analyzer 8 Plugin consumes Analyzer 13 metadata and fixes Owner',
    () async {
      final workspaceRoot = _findWorkspaceRoot();
      final generatorConfig = File(
        path.join(workspaceRoot.path, '.dart_tool', 'package_config.json'),
      );
      expect(_analyzerVersion(generatorConfig), startsWith('13.'));
      expect(_analyzerVersion(File('.dart_tool/package_config.json')), '8.4.0');
      // A successful reference check proves disk metadata matches the current
      // producer, without borrowing its Analyzer objects or writing a fixture.
      final generated = await Process.run(Platform.resolvedExecutable, [
        '--packages=${generatorConfig.path}',
        path.join(
          workspaceRoot.path,
          'packages',
          'ccrouter_generator',
          'bin',
          'ccrouter.dart',
        ),
        'generate',
        'demo',
        '--no-cache',
        '--check',
      ], workingDirectory: workspaceRoot.path);
      expect(
        generated.exitCode,
        0,
        reason: '${generated.stdout}\n${generated.stderr}',
      );
      final index =
          jsonDecode(
                File(
                  path.join(
                    workspaceRoot.path,
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
              as Map;
      expect(index['schemaVersion'], 5);
      expect(
        (index['metadata'] as List).whereType<Map>(),
        contains(containsPair('uiSchemaVersion', 3)),
      );

      final sourceFile = File(
        path.join(
          workspaceRoot.path,
          'demo',
          'modules',
          'navigation_lab',
          'lib',
          'src',
          'navigation_lab_component.dart',
        ),
      );
      final original = sourceFile.readAsStringSync();
      final source = original.replaceFirst(
        RegExp(r'  dependencies: \[.*?\],\n', dotAll: true),
        '  dependencies: [],\n',
      );
      final owners = CCRouterContractOwnerIndexCache().resolve(sourceFile.path);
      final context = CCRouterPackageContextCache().resolve(sourceFile.path)!;
      final uiOwner = owners.resolve(
        kind: CCRouterContractKind.uiFragment,
        contractSymbol: 'OrderPanelFragmentContract',
        prefix: null,
        importPrefixes: {
          '': {'demo_order_contracts'},
        },
        sourcePackage: context.name,
      );
      expect(uiOwner?.componentId, 'demo_order_component');
      expect(
        uiOwner?.contractLibraryUri,
        'package:demo_order_contracts/src/order_panel_fragment.dart',
      );
      final resources = OverlayResourceProvider(
        PhysicalResourceProvider.INSTANCE,
      )..setOverlay(sourceFile.path, content: source, modificationStamp: 1);
      final collection = AnalysisContextCollection(
        includedPaths: [sourceFile.path],
        resourceProvider: resources,
      );
      addTearDown(collection.dispose);
      final analysisContext = collection.contextFor(sourceFile.path);
      final resolved =
          await analysisContext.currentSession.getResolvedUnit(sourceFile.path)
              as ResolvedUnitResult;
      final errors = CCRouterSourceAnalyzer.analyze(
        source: source,
        filePath: sourceFile.path,
        packageRoot: context.root,
        packageName: context.name,
        contractOwners: owners,
        resolvedUnit: resolved.unit,
      );
      final error = errors.singleWhere(
        (error) =>
            error.message.startsWith('Service Contract OrderSummaryService '),
      );
      expect(error.code, 'ccrouter_component_owner_dependency_missing');
      expect(error.message, contains('demo_order_component'));
      expect(
        source.substring(error.offset, error.offset + error.length),
        contains('CCServiceDependency<OrderSummaryService>'),
      );
      final fixes = CCRouterQuickFixes.compute(
        source: source,
        filePath: sourceFile.path,
        offset: error.offset,
        diagnosticCode: error.code,
        sourcePackage: context.name,
        contractOwners: owners,
        resolvedUnit: resolved.unit,
      );
      expect(fixes, isNotEmpty);
      final fix = fixes.first;
      expect(fix.replacement, contains('demoOrderComponentId'));
      final repaired = source.replaceRange(
        fix.offset,
        fix.offset + fix.length,
        fix.replacement,
      );
      resources.setOverlay(
        sourceFile.path,
        content: repaired,
        modificationStamp: 2,
      );
      analysisContext.changeFile(sourceFile.path);
      await analysisContext.applyPendingFileChanges();
      final repairedResult =
          await analysisContext.currentSession.getResolvedUnit(sourceFile.path)
              as ResolvedUnitResult;
      final remaining = CCRouterSourceAnalyzer.analyze(
        source: repaired,
        filePath: sourceFile.path,
        packageRoot: context.root,
        packageName: context.name,
        contractOwners: owners,
        resolvedUnit: repairedResult.unit,
      );
      expect(
        remaining.where(
          (error) =>
              error.code == 'ccrouter_component_owner_dependency_missing' &&
              error.message.contains('demo_order_component'),
        ),
        isEmpty,
      );
      expect(sourceFile.readAsStringSync(), original);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

String _analyzerVersion(File config) {
  final packages = jsonDecode(config.readAsStringSync())['packages'] as List;
  final analyzer = packages.singleWhere((entry) => entry['name'] == 'analyzer');
  final manifest = File.fromUri(
    Directory.fromUri(
      config.absolute.uri.resolve(analyzer['rootUri'] as String),
    ).uri.resolve('pubspec.yaml'),
  );
  return loadYaml(manifest.readAsStringSync())['version'] as String;
}

/// Finds this repository without embedding a machine-specific absolute path.
Directory _findWorkspaceRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (File(path.join(current.path, 'pubspec.yaml')).existsSync() &&
        Directory(
          path.join(current.path, 'packages', 'ccrouter_analyzer_plugin'),
        ).existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('CCRouter workspace root was not found.');
    }
    current = parent;
  }
}
