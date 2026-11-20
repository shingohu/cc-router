import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:ccrouter_analyzer_plugin/src/contract_owner_index.dart';
import 'package:ccrouter_analyzer_plugin/src/package_context_cache.dart';
import 'package:ccrouter_analyzer_plugin/src/source_analyzer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

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
