import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:ccrouter_analyzer_plugin/src/contract_owner_index.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('reads exact Service and Command owners from resolved metadata', () {
    final fixture = _OwnerFixture.create();
    addTearDown(fixture.dispose);
    final cache = CCRouterContractOwnerIndexCache();
    final index = cache.resolve(fixture.consumerSource.path);

    final service = index.resolve(
      kind: CCRouterContractKind.service,
      contractSymbol: 'SharedService',
      prefix: null,
      importPrefixes: const {
        '': {'owner_contracts'},
      },
      sourcePackage: 'consumer',
    );
    final command = index.resolve(
      kind: CCRouterContractKind.command,
      contractSymbol: 'RunCommand',
      prefix: 'contracts',
      importPrefixes: const {
        'contracts': {'owner_contracts'},
      },
      sourcePackage: 'consumer',
    );

    expect(service?.componentId, 'owner.component');
    expect(service?.componentIdSymbol, 'ownerComponentId');
    expect(command?.componentId, 'owner.component');
    expect(command?.componentIdSymbol, 'ownerComponentId');
  });

  test('proves component ID visibility through public exports and prefixes', () {
    final fixture = _OwnerFixture.create();
    addTearDown(fixture.dispose);
    final index = CCRouterContractOwnerIndexCache().resolve(
      fixture.consumerSource.path,
    );
    final owner = index.resolve(
      kind: CCRouterContractKind.service,
      contractSymbol: 'SharedService',
      prefix: null,
      importPrefixes: const {
        '': {'owner_contracts'},
      },
      sourcePackage: 'consumer',
    )!;

    final unprefixed = parseString(
      content: "import 'package:owner_contracts/owner_contracts.dart';",
      path: fixture.consumerSource.path,
    ).unit;
    final prefixed = parseString(
      content:
          "import 'package:owner_contracts/owner_contracts.dart' as owner;",
      path: fixture.consumerSource.path,
    ).unit;
    final hidden = parseString(
      content:
          "import 'package:owner_contracts/owner_contracts.dart' hide ownerComponentId;",
      path: fixture.consumerSource.path,
    ).unit;

    expect(
      index.visibleComponentIdReference(
        unit: unprefixed,
        sourcePath: fixture.consumerSource.path,
        owner: owner,
      ),
      'ownerComponentId',
    );
    expect(
      index.visibleComponentIdReference(
        unit: prefixed,
        sourcePath: fixture.consumerSource.path,
        owner: owner,
      ),
      'owner.ownerComponentId',
    );
    expect(
      index.visibleComponentIdReference(
        unit: hidden,
        sourcePath: fixture.consumerSource.path,
        owner: owner,
      ),
      isNull,
    );
  });

  test('invalidates an owner index when its Contract source changes', () {
    final fixture = _OwnerFixture.create();
    addTearDown(fixture.dispose);
    final cache = CCRouterContractOwnerIndexCache();
    final first = cache
        .resolve(fixture.consumerSource.path)
        .resolve(
          kind: CCRouterContractKind.service,
          contractSymbol: 'SharedService',
          prefix: null,
          importPrefixes: const {
            '': {'owner_contracts'},
          },
          sourcePackage: 'consumer',
        );
    expect(first?.componentIdSymbol, 'ownerComponentId');

    fixture.contractSource.writeAsStringSync(
      fixture.contractSource.readAsStringSync().replaceAll(
        'ownerComponentId',
        'renamedOwnerComponentId',
      ),
    );
    final affected = cache.invalidate(fixture.contractSource.path);
    final refreshed = cache
        .resolve(fixture.consumerSource.path)
        .resolve(
          kind: CCRouterContractKind.service,
          contractSymbol: 'SharedService',
          prefix: null,
          importPrefixes: const {
            '': {'owner_contracts'},
          },
          sourcePackage: 'consumer',
        );

    expect(refreshed?.componentIdSymbol, 'renamedOwnerComponentId');
    expect(affected, contains(path.normalize(fixture.consumerSource.path)));
    expect(cache.entryCount, 1);
  });
}

final class _OwnerFixture {
  const _OwnerFixture({
    required this.root,
    required this.consumerSource,
    required this.contractSource,
  });

  final Directory root;
  final File consumerSource;
  final File contractSource;

  static _OwnerFixture create() {
    final root = Directory.systemTemp.createTempSync('ccrouter-owner-index-');
    final consumer = Directory(path.join(root.path, 'consumer'))
      ..createSync(recursive: true);
    final contracts = Directory(path.join(root.path, 'owner_contracts'))
      ..createSync(recursive: true);
    File(path.join(consumer.path, 'pubspec.yaml')).writeAsStringSync('''
name: consumer
dependencies:
  owner_contracts: any
''');
    File(
      path.join(contracts.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: owner_contracts\n');
    final consumerSource = File(
      path.join(consumer.path, 'lib', 'src', 'component.dart'),
    )..createSync(recursive: true);
    consumerSource.writeAsStringSync('');
    final contractSource = File(
      path.join(contracts.path, 'lib', 'src', 'contracts.dart'),
    )..createSync(recursive: true);
    contractSource.writeAsStringSync('''
const ownerComponentId = CCComponentId('owner.component');

@CCServiceContract(
  componentId: ownerComponentId,
  id: 'owner.service',
)
abstract interface class SharedService {}

@CCCommandContract(
  componentId: ownerComponentId,
  id: 'owner.run',
)
final class RunCommand {}
''');
    File(path.join(contracts.path, 'lib', 'owner_contracts.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "export 'src/contracts.dart' show SharedService, RunCommand, ownerComponentId;\n",
      );
    final metadata = File(
      path.join(
        contracts.path,
        'lib',
        'src',
        'ccrouter_generated',
        'metadata',
        'ccrouter_package.json',
      ),
    )..createSync(recursive: true);
    metadata.writeAsStringSync(
      jsonEncode({
        'capabilityCatalog': {
          'records': [
            {
              'kind': 'service',
              'componentId': 'owner.component',
              'contract': {
                'symbol': 'SharedService',
                'packageUri': 'package:owner_contracts/src/contracts.dart',
              },
            },
            {
              'kind': 'command',
              'componentId': 'owner.component',
              'contract': {
                'symbol': 'RunCommand',
                'packageUri': 'package:owner_contracts/src/contracts.dart',
              },
            },
          ],
        },
      }),
    );
    File(
        path.join(
          consumer.path,
          'lib',
          'src',
          'ccrouter_generated',
          'metadata',
          'ccrouter_package.json',
        ),
      )
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'metadata': [
            {
              'package': 'consumer',
              'source': 'lib/src/component.dart',
              'components': [
                {'id': 'consumer.component'},
              ],
            },
          ],
          'capabilityCatalog': {'records': <Object>[]},
        }),
      );
    final packageConfig = File(
      path.join(root.path, '.dart_tool', 'package_config.json'),
    )..createSync(recursive: true);
    packageConfig.writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'consumer', 'rootUri': '../consumer', 'packageUri': 'lib/'},
          {
            'name': 'owner_contracts',
            'rootUri': '../owner_contracts',
            'packageUri': 'lib/',
          },
        ],
      }),
    );
    return _OwnerFixture(
      root: root,
      consumerSource: consumerSource,
      contractSource: contractSource,
    );
  }

  void dispose() => root.deleteSync(recursive: true);
}
