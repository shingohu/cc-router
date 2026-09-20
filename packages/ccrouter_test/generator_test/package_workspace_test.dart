@TestOn('vm')
library;

// Package discovery is generator-internal rather than a framework public API.
// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:io';

import 'package:ccrouter_generator/src/package_workspace.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('discovers only the Host runtime dependency closure', () async {
    final fixture = await PackageResolutionFixture.create();
    addTearDown(fixture.dispose);

    final workspace = await CCPackageWorkspace.load(
      buildRoot: fixture.root,
      hostRoot: fixture.packageRoot('host'),
      workspace: true,
    );

    expect(workspace.host.name, 'host');
    expect(
      workspace.packages.keys,
      unorderedEquals(['host', 'path_feature', 'git_feature', 'pub_feature']),
    );
    expect(workspace.packages['host']!.writable, isTrue);
    expect(workspace.packages['path_feature']!.writable, isTrue);
    expect(workspace.packages['git_feature']!.writable, isFalse);
    expect(workspace.packages['pub_feature']!.writable, isFalse);
    expect(workspace.packages, isNot(contains('unrelated_workspace')));
    expect(workspace.packages, isNot(contains('dev_only')));
  });

  test(
    'requires resolved Package graph instead of scanning the repository',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ccrouter_missing_graph_',
      );
      addTearDown(() => root.delete(recursive: true));
      final host = Directory(path.join(root.path, 'host'))..createSync();

      await expectLater(
        CCPackageWorkspace.load(
          buildRoot: root,
          hostRoot: host,
          workspace: true,
        ),
        throwsA(
          isA<CCPackageWorkspaceException>().having(
            (error) => error.message,
            'message',
            contains('pub get'),
          ),
        ),
      );
    },
  );

  test('rejects corrupted and incompatible Package indexes', () async {
    final root = await Directory.systemTemp.createTemp('ccrouter_bad_index_');
    addTearDown(() => root.delete(recursive: true));
    final packageRoot = Directory(path.join(root.path, 'dependency'))
      ..createSync(recursive: true);
    final package = CCResolvedPackage(
      name: 'dependency',
      version: '1.0.0',
      root: packageRoot,
      dependencies: const [],
      devDependencies: const [],
      writable: false,
    );
    package.indexFile
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'package': {'name': 'dependency', 'version': '1.0.0'},
          'contentFingerprint': 'invalid',
          'bundle': null,
          'dependencies': <Object>[],
          'metadata': <Object>[],
        }),
      );

    await expectLater(
      CCPackageIndex.read(package),
      throwsA(
        isA<CCPackageWorkspaceException>().having(
          (error) => error.message,
          'message',
          contains('fingerprint mismatch'),
        ),
      ),
    );

    package.indexFile.writeAsStringSync(
      jsonEncode({
        'schemaVersion': 999,
        'package': {'name': 'dependency', 'version': '1.0.0'},
      }),
    );
    await expectLater(
      CCPackageIndex.read(package),
      throwsA(
        isA<CCPackageWorkspaceException>().having(
          (error) => error.message,
          'message',
          contains('Unsupported CCRouter Package index schema'),
        ),
      ),
    );
  });

  test('non-framework CCRouter dependencies require a published index', () {
    final root = Directory.systemTemp;
    final component = CCResolvedPackage(
      name: 'remote_component',
      version: '1.0.0',
      root: root,
      dependencies: const ['ccrouter'],
      devDependencies: const [],
      writable: false,
    );
    final contracts = CCResolvedPackage(
      name: 'remote_contracts',
      version: '1.0.0',
      root: root,
      dependencies: const ['ccrouter_contracts'],
      devDependencies: const [],
      writable: false,
    );
    final framework = CCResolvedPackage(
      name: 'ccrouter_go_router',
      version: '1.0.0',
      root: root,
      dependencies: const ['ccrouter'],
      devDependencies: const [],
      writable: false,
    );

    expect(component.requiresPackageIndex, isTrue);
    expect(contracts.requiresPackageIndex, isTrue);
    expect(framework.requiresPackageIndex, isFalse);
  });

  test(
    'Package index fingerprint is canonical and detects metadata changes',
    () {
      String fingerprint(Map<String, Object?> metadata) =>
          computeCCPackageFingerprint(
            packageName: 'feature',
            packageVersion: '1.0.0',
            bundleLibrary: null,
            bundleSymbol: null,
            dependencies: const [],
            metadata: [metadata],
          );

      final first = fingerprint({
        'package': 'feature',
        'routes': [
          {'id': 'feature.detail', 'description': 'first'},
        ],
      });
      final reordered = fingerprint({
        'routes': [
          {'description': 'first', 'id': 'feature.detail'},
        ],
        'package': 'feature',
      });
      final changed = fingerprint({
        'package': 'feature',
        'routes': [
          {'id': 'feature.detail', 'description': 'second'},
        ],
      });

      expect(reordered, first);
      expect(changed, isNot(first));
    },
  );

  test('capability catalog merges route contract and implementation sources', () {
    final catalog = CCCapabilitySourceCatalog.fromMetadata([
      {
        'package': 'orders_contracts',
        'source': 'lib/src/order_route.dart',
        'routes': [
          {
            'id': 'orders.detail',
            'componentId': 'orders',
            'declaration': {
              'package': 'orders_contracts',
              'library': 'lib/src/order_route.dart',
              'kind': 'contract',
              'symbol': 'OrderDetailRouteContract',
              'packageUri': 'package:orders_contracts/src/order_route.dart',
              'line': 12,
              'column': 16,
            },
            'generatedArtifacts': [
              {
                'role': 'routeContract',
                'symbol': 'OrderDetailRoute',
                'packageUri':
                    'package:orders_contracts/src/ccrouter_generated/order_route.route.contract.g.dart',
              },
            ],
          },
        ],
        'routeImplementations': <Object>[],
      },
      {
        'package': 'orders',
        'source': 'lib/src/order_page.dart',
        'routes': <Object>[],
        'routeImplementations': [
          {
            'routeId': 'orders.detail',
            'componentId': 'orders',
            'package': 'orders',
            'source': 'lib/src/order_page.dart',
            'contract': {
              'symbol': 'OrderDetailRouteContract',
              'packageUri': 'package:orders_contracts/src/order_route.dart',
              'line': 12,
              'column': 16,
            },
            'implementation': {
              'symbol': 'OrderDetailPage',
              'packageUri': 'package:orders/src/order_page.dart',
              'line': 20,
              'column': 13,
            },
            'generatedArtifacts': [
              {
                'role': 'routeBinding',
                'symbol': 'ccrouterRegisterOrderDetailPageRoute',
                'packageUri':
                    'package:orders/src/ccrouter_generated/order_page.route_binding.g.dart',
              },
            ],
          },
        ],
      },
    ]);

    expect(catalog.records, hasLength(1));
    final route = catalog.records.single;
    expect(route.id, 'orders.detail');
    expect(route.packageName, 'orders_contracts');
    expect(route.contract!.line, 12);
    expect(route.implementation!.symbol, 'OrderDetailPage');
    expect(route.generatedArtifacts, hasLength(2));
    expect(
      catalog.toMarkdown(scope: 'host:shop'),
      allOf(
        contains('## `orders`'),
        contains('### Route `orders.detail`'),
        contains('package:orders/src/order_page.dart:20:13'),
      ),
    );
  });

  test('capability catalog retains schema-v2 file-only locations', () {
    final catalog = CCCapabilitySourceCatalog.fromMetadata([
      {
        'package': 'legacy_orders',
        'source': 'lib/detail.dart',
        'routes': [
          {
            'id': 'legacy.detail',
            'componentId': 'legacy',
            'declaration': {
              'package': 'legacy_orders',
              'library': 'lib/detail.dart',
              'kind': 'page',
            },
          },
        ],
        'routeImplementations': <Object>[],
      },
    ]);

    final reference = catalog.records.single.contract!;
    expect(reference.packageUri, 'package:legacy_orders/detail.dart');
    expect(reference.line, isNull);
    expect(reference.column, isNull);
  });

  test('legacy route implementation does not invent a contract location', () {
    final catalog = CCCapabilitySourceCatalog.fromMetadata([
      {
        'package': 'legacy_orders',
        'source': 'lib/detail_page.dart',
        'routes': <Object>[],
        'routeImplementations': [
          {
            'routeId': 'legacy.detail',
            'componentId': 'legacy',
            'package': 'legacy_orders',
            'source': 'lib/detail_page.dart',
          },
        ],
      },
    ]);

    final route = catalog.records.single;
    expect(route.contract, isNull);
    expect(
      route.implementation!.packageUri,
      'package:legacy_orders/detail_page.dart',
    );
  });

  test(
    'metadata cache detects add change rename and delete by exact bytes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ccrouter_metadata_cache_',
      );
      addTearDown(() => root.delete(recursive: true));
      final package = CCResolvedPackage(
        name: 'feature',
        version: '1.0.0',
        root: root,
        dependencies: const [],
        devDependencies: const ['ccrouter_generator'],
        writable: true,
      );
      final generatedDirectory = package.generatedDirectory
        ..createSync(recursive: true);
      final firstFile = File(
        path.join(generatedDirectory.path, 'first.route.json'),
      );
      firstFile.writeAsStringSync(
        jsonEncode({'package': 'feature', 'source': 'lib/first.dart'}),
      );
      final first = await readCCPackageMetadata(package);
      final legacyFile =
          File(
              path.join(
                generatedDirectory.path,
                'metadata',
                'legacy.route.json',
              ),
            )
            ..createSync(recursive: true)
            ..writeAsStringSync(
              jsonEncode({'package': 'feature', 'source': 'lib/legacy.dart'}),
            );
      final ignoresLegacy = await readCCPackageMetadata(package);
      expect(ignoresLegacy.fingerprint, first.fingerprint);
      expect(ignoresLegacy.documents, first.documents);
      expect(legacyFile.existsSync(), isTrue);
      final hit = await readCCPackageMetadata(
        package,
        cachedFingerprint: first.fingerprint,
        cachedDocuments: first.documents,
      );
      expect(hit.cacheHit, isTrue);

      final originalModified = firstFile.lastModifiedSync();
      firstFile.writeAsStringSync(
        jsonEncode({'package': 'feature', 'source': 'lib/other.dart'}),
      );
      firstFile.setLastModifiedSync(originalModified);
      final changed = await readCCPackageMetadata(
        package,
        cachedFingerprint: first.fingerprint,
        cachedDocuments: first.documents,
      );
      expect(changed.cacheHit, isFalse);
      expect(changed.fingerprint, isNot(first.fingerprint));

      final addedFile = File(
        path.join(generatedDirectory.path, 'second.route.json'),
      );
      addedFile.writeAsStringSync(
        jsonEncode({'package': 'feature', 'source': 'lib/second.dart'}),
      );
      final added = await readCCPackageMetadata(package);
      expect(added.fingerprint, isNot(changed.fingerprint));

      final renamedFile = File(
        path.join(generatedDirectory.path, 'renamed.route.json'),
      );
      addedFile.renameSync(renamedFile.path);
      final renamed = await readCCPackageMetadata(package);
      expect(renamed.fingerprint, isNot(added.fingerprint));

      renamedFile.deleteSync();
      final deleted = await readCCPackageMetadata(package);
      expect(deleted.fingerprint, isNot(renamed.fingerprint));
    },
  );
}

final class PackageResolutionFixture {
  PackageResolutionFixture._(this.root, this._roots);

  final Directory root;
  final Map<String, Directory> _roots;

  static Future<PackageResolutionFixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'ccrouter_package_workspace_',
    );
    final external = await Directory.systemTemp.createTemp(
      'ccrouter_package_cache_',
    );
    final roots = <String, Directory>{
      'host': Directory(path.join(root.path, 'host')),
      'path_feature': Directory(
        path.join(root.path, 'modules', 'path_feature'),
      ),
      'unrelated_workspace': Directory(
        path.join(root.path, 'modules', 'unrelated'),
      ),
      'dev_only': Directory(path.join(root.path, 'tools', 'dev_only')),
      'git_feature': Directory(path.join(external.path, 'git_feature')),
      'pub_feature': Directory(path.join(external.path, 'pub_feature')),
    };
    for (final entry in roots.entries) {
      entry.value.createSync(recursive: true);
      File(path.join(entry.value.path, 'pubspec.yaml')).writeAsStringSync('''
name: ${entry.key}
version: 1.0.0
${entry.key == 'host' || entry.key == 'path_feature' || entry.key == 'unrelated_workspace' ? 'resolution: workspace' : ''}
environment:
  sdk: ^3.9.0
''');
    }
    final dartTool = Directory(path.join(root.path, '.dart_tool'))
      ..createSync(recursive: true);
    File(path.join(dartTool.path, 'package_graph.json')).writeAsStringSync(
      jsonEncode({
        'packages': [
          package('host', ['path_feature'], ['dev_only']),
          package('path_feature', ['git_feature']),
          package('git_feature', ['pub_feature']),
          package('pub_feature', const []),
          package('unrelated_workspace', const []),
          package('dev_only', const []),
        ],
      }),
    );
    File(path.join(dartTool.path, 'package_config.json')).writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          for (final entry in roots.entries)
            {
              'name': entry.key,
              'rootUri': entry.value.uri.toString(),
              'packageUri': 'lib/',
              'languageVersion': '3.9',
            },
        ],
      }),
    );
    return PackageResolutionFixture._(root, roots);
  }

  static Map<String, Object?> package(
    String name,
    List<String> dependencies, [
    List<String> devDependencies = const [],
  ]) => {
    'name': name,
    'version': '1.0.0',
    'dependencies': dependencies,
    'devDependencies': devDependencies,
  };

  Directory packageRoot(String name) => _roots[name]!;

  Future<void> dispose() async {
    final externalRoot = _roots['git_feature']!.parent;
    await root.delete(recursive: true);
    await externalRoot.delete(recursive: true);
  }
}
