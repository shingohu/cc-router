@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('host aggregation includes a component without routes', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'ccrouter_host_aggregation_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final host = Directory(path.join(temporary.path, 'host'))
      ..createSync(recursive: true);
    File(path.join(host.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixture_host
environment:
  sdk: ^3.9.0
''');
    final component = Directory(path.join(host.path, 'modules', 'service'))
      ..createSync(recursive: true);
    File(path.join(component.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixture_service
environment:
  sdk: ^3.9.0
''');
    final metadata = File(
      path.join(
        component.path,
        'ccrouter_generated',
        'src',
        'fixture_service_component_registrar.component.json',
      ),
    )..createSync(recursive: true);
    metadata.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 2,
        'package': 'fixture_service',
        'source': 'lib/src/fixture_service_component_registrar.dart',
        'componentDeclarations': ['fixture_service_component'],
        'componentManifests': {'fixture_service_component': 'fixtureServiceComponentManifest'},
        'componentSymbols': {'fixture_service_component': 'fixtureServiceComponent'},
        'components': [
          {'id': 'fixture_service_component', 'version': '1.0.0', 'dependencies': <String>[], 'optionalDependencies': <String>[]},
        ],
        'routes': <Object>[],
      })}\n',
    );
    final contributionMetadata = File(
      path.join(
        component.path,
        'ccrouter_generated',
        'src',
        'fixture_service_registration.route.json',
      ),
    )..createSync(recursive: true);
    contributionMetadata.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 3,
        'package': 'fixture_service',
        'source': 'lib/src/fixture_service_registration.dart',
        'componentDeclarations': <String>[],
        'componentManifests': <String, String>{},
        'componentSymbols': <String, String>{},
        'components': <Object>[],
        'routes': <Object>[],
        'routeImplementations': <Object>[],
        'contributions': [
          {'id': 'fixture_service.services', 'componentId': null, 'package': 'fixture_service', 'source': 'lib/src/fixture_service_registration.dart', 'symbol': 'registerFixtureService'},
        ],
        'serviceImplementations': [
          {'id': 'fixture_service.summary', 'componentId': null, 'package': 'fixture_service', 'source': 'lib/src/fixture_summary_service.dart', 'registration': 'ccrouterRegisterFixtureSummaryService', 'registrationLibrary': 'lib/src/ccrouter_generated/service/fixture_summary_service.service.g.dart'},
        ],
      })}\n',
    );
    final obsoleteIndex = File(
      path.join(
        component.path,
        'lib',
        'src',
        'ccrouter_generated',
        'removed.routes.g.dart',
      ),
    )..createSync(recursive: true);
    obsoleteIndex.writeAsStringSync(
      '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
      '/// Generated registration index for component `removed`.\n',
    );
    final obsoleteStableApi =
        File(
          path.join(
            component.path,
            'lib',
            'src',
            'ccrouter_generated',
            'fixture_service_component.api.g.dart',
          ),
        )..writeAsStringSync(
          '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
          '/// Stable typed API entry point for component `fixture_service_component`.\n',
        );
    final obsoleteContractsApi =
        File(
          path.join(
            component.path,
            'lib',
            'src',
            'ccrouter_generated',
            'fixture_service.contracts.api.g.dart',
          ),
        )..writeAsStringSync(
          '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
          '/// Stable generated Contract API entry point for Package '
          '`fixture_service`.\n',
        );
    final handwrittenIndex = File(
      path.join(
        component.path,
        'lib',
        'src',
        'ccrouter_generated',
        'keep.routes.g.dart',
      ),
    )..writeAsStringSync('// Handwritten fixture.\n');
    final foreignGeneratedIndex = File(
      path.join(
        component.path,
        'lib',
        'src',
        'ccrouter_generated',
        'foreign.routes.g.dart',
      ),
    )..writeAsStringSync('// GENERATED CODE - DO NOT MODIFY BY HAND\n');

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'ccrouter_generator:ccrouter_generator',
      host.path,
      '--generate-component-registrars',
    ], workingDirectory: Directory.current.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final componentIndex = File(
      path.join(
        component.path,
        'lib',
        'src',
        'ccrouter_generated',
        'component',
        'fixture_service_component.component.g.dart',
      ),
    ).readAsStringSync();
    expect(componentIndex, contains('CCFlutterRouteCatalog([])'));
    expect(componentIndex, contains('.registerFixtureService('));
    expect(componentIndex, contains('      registry,'));
    expect(
      componentIndex,
      contains('.ccrouterRegisterFixtureSummaryService(registry);'),
    );
    expect(
      componentIndex,
      contains("import '../service/fixture_summary_service.service.g.dart'"),
    );

    final integration = File(
      path.join(
        component.path,
        'lib',
        'src',
        'ccrouter_generated',
        'host',
        'fixture_service_ccrouter.g.dart',
      ),
    ).readAsStringSync();
    expect(integration, contains('fixtureServiceComponentManifest'));
    expect(integration, contains('fixtureServiceComponentRouteCatalog'));

    final aggregate = File(
      path.join(
        host.path,
        'lib',
        'src',
        'ccrouter_generated',
        'host',
        'ccrouter_host.routes.g.dart',
      ),
    ).readAsStringSync();
    expect(aggregate, contains('ccrouterGeneratedHostAssembly'));
    expect(aggregate, contains('CCHostAssembly.fromComponents('));
    expect(aggregate, contains('fixtureServiceComponentManifest'));
    expect(aggregate, contains('fixtureServiceComponentRouteCatalog'));
    expect(aggregate, isNot(contains('ccrouterGeneratedComponentManifests')));
    expect(aggregate, isNot(contains('ccrouterGeneratedRouteCatalog')));
    expect(aggregate, isNot(contains('CCRouterGeneratedHost')));
    final hostApi = File(
      path.join(
        host.path,
        'lib',
        'src',
        'ccrouter_generated',
        'ccrouter_host.api.g.dart',
      ),
    ).readAsStringSync();
    expect(hostApi, contains('Stable Host-facing CCRouter API'));
    expect(hostApi, contains("export 'host/ccrouter_host.routes.g.dart'"));
    expect(hostApi, contains('ccrouterGeneratedHostAssembly'));
    expect(obsoleteIndex.existsSync(), isFalse);
    expect(obsoleteStableApi.existsSync(), isFalse);
    expect(obsoleteContractsApi.existsSync(), isFalse);
    expect(handwrittenIndex.existsSync(), isTrue);
    expect(foreignGeneratedIndex.existsSync(), isTrue);
  });

  test('host aggregation joins an external contract to its page binding', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'ccrouter_external_contract_aggregation_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final host = Directory(path.join(temporary.path, 'host'))
      ..createSync(recursive: true);
    File(path.join(host.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixture_host
environment:
  sdk: ^3.9.0
''');
    final contracts = Directory(
      path.join(host.path, 'modules', 'order_contracts'),
    )..createSync(recursive: true);
    File(path.join(contracts.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixture_order_contracts
environment:
  sdk: ^3.9.0
''');
    final generatedContract = File(
      path.join(
        contracts.path,
        'lib',
        'src',
        'ccrouter_generated',
        'contract',
        'detail.route.contract.g.dart',
      ),
    )..createSync(recursive: true);
    generatedContract.writeAsStringSync('''
final class DetailRouteArguments {}
abstract final class DetailRoute {}
''');
    File(
      path.join(contracts.path, 'lib', 'fixture_order_contracts.dart'),
    ).writeAsStringSync('''
export 'src/ccrouter_generated/contract/detail.route.contract.g.dart'
    show DetailRoute;
''');
    final contractMetadata = File(
      path.join(
        contracts.path,
        'ccrouter_generated',
        'src',
        'detail.route.json',
      ),
    )..createSync(recursive: true);
    contractMetadata.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 2,
        'package': 'fixture_order_contracts',
        'source': 'lib/src/detail.dart',
        'componentDeclarations': <String>[],
        'componentManifests': <String, String>{},
        'components': [
          {'id': 'order', 'version': '1.0.0', 'dependencies': <String>[], 'optionalDependencies': <String>[]},
        ],
        'routes': [
          {
            'id': 'order.detail',
            'componentId': 'order',
            'exposure': 'public',
            'deepLink': 'disabled',
            'description': 'Order detail.',
            'contracts': {'route': 'DetailRoute', 'arguments': 'DetailRouteArguments', 'package': 'fixture_order_contracts', 'library': 'lib/src/ccrouter_generated/contract/detail.route.contract.g.dart'},
            'patterns': [
              {'type': 'CCPathPattern', 'value': '/orders/:id', 'primary': true, 'constraints': <String, String>{}},
            ],
            'parameters': <Object>[],
            'resultType': 'void',
          },
        ],
        'routeImplementations': <Object>[],
      })}\n',
    );

    final implementation = Directory(path.join(host.path, 'modules', 'order'))
      ..createSync(recursive: true);
    File(path.join(implementation.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixture_order
environment:
  sdk: ^3.9.0
''');
    final componentMetadata = File(
      path.join(
        implementation.path,
        'ccrouter_generated',
        'src',
        'order_registrar.component.json',
      ),
    )..createSync(recursive: true);
    componentMetadata.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 2,
        'package': 'fixture_order',
        'source': 'lib/src/order_registrar.dart',
        'componentDeclarations': ['order'],
        'componentManifests': {'order': 'orderManifest'},
        'componentSymbols': {'order': 'orderComponent'},
        'components': [
          {'id': 'order', 'version': '1.0.0', 'dependencies': <String>[], 'optionalDependencies': <String>[]},
        ],
        'routes': <Object>[],
        'routeImplementations': <Object>[],
      })}\n',
    );
    final implementationMetadata = File(
      path.join(
        implementation.path,
        'ccrouter_generated',
        'src',
        'detail_page.route.json',
      ),
    )..createSync(recursive: true);
    implementationMetadata.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 2,
        'package': 'fixture_order',
        'source': 'lib/src/detail_page.dart',
        'componentDeclarations': <String>[],
        'componentManifests': <String, String>{},
        'components': [
          {'id': 'order', 'version': '1.0.0', 'dependencies': <String>[], 'optionalDependencies': <String>[]},
        ],
        'routes': <Object>[],
        'routeImplementations': [
          {
            'routeId': 'order.detail',
            'componentId': 'order',
            'registration': 'ccrouterRegisterDetailPageRoute',
            'registrationLibrary': 'lib/src/ccrouter_generated/binding/detail_page.route_binding.g.dart',
            'destination': {'descriptor': 'ccrouterDescribeDetailPageRoute', 'builder': 'ccrouterBuildDetailPageRoute', 'library': 'lib/src/ccrouter_generated/binding/detail_page.route_binding.g.dart', 'builderLibrary': 'lib/src/ccrouter_generated/binding/detail_page.route_binding.g.dart'},
          },
        ],
      })}\n',
    );

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'ccrouter_generator:ccrouter_generator',
      host.path,
      '--generate-component-registrars',
    ], workingDirectory: Directory.current.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final componentIndex = File(
      path.join(
        implementation.path,
        'lib',
        'src',
        'ccrouter_generated',
        'component',
        'order.component.g.dart',
      ),
    ).readAsStringSync();
    expect(
      componentIndex,
      contains("import '../binding/detail_page.route_binding.g.dart'"),
    );
    expect(componentIndex, contains('ccrouterRegisterDetailPageRoute'));
    expect(
      componentIndex,
      contains('CCFlutterRouteDestination.fromDefinition('),
    );
    expect(componentIndex, contains('definition:'));
    expect(
      componentIndex,
      isNot(contains('package:fixture_order_contracts/src/detail.dart')),
    );
    final stableContracts = File(
      path.join(
        contracts.path,
        'lib',
        'src',
        'ccrouter_generated',
        'fixture_order_contracts.contracts.api.g.dart',
      ),
    );
    expect(stableContracts.existsSync(), isTrue);
    expect(
      stableContracts.readAsStringSync(),
      allOf(
        contains("export 'contract/detail.route.contract.g.dart'"),
        contains('show DetailRoute;'),
        isNot(contains('DetailRouteArguments')),
      ),
    );
  });

  test('component Route API rejects colliding generated member names', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'ccrouter_route_api_collision_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final host = Directory(path.join(temporary.path, 'host'))
      ..createSync(recursive: true);
    File(path.join(host.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixture_host
environment:
  sdk: ^3.9.0
''');
    final component = Directory(path.join(host.path, 'modules', 'feature'))
      ..createSync(recursive: true);
    File(path.join(component.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixture_feature
environment:
  sdk: ^3.9.0
''');
    final metadata = File(
      path.join(
        component.path,
        'ccrouter_generated',
        'src',
        'feature_component.route.json',
      ),
    )..createSync(recursive: true);
    Map<String, Object?> route(String id, String page) => {
      'id': id,
      'componentId': 'feature_component',
      'exposure': 'internal',
      'contracts': {
        'route': '_${page}Route',
        'arguments': '_${page}RouteArguments',
        'intentFactory': 'CCGenerated${page}RouteFactory',
      },
      'registration': 'ccrouterRegister${page}Route',
      'registrationLibrary':
          'lib/src/ccrouter_generated/route/feature.route.g.dart',
      'destination': {
        'descriptor': 'ccrouterDescribe${page}Route',
        'builder': 'ccrouterBuild${page}Route',
        'library': 'lib/src/ccrouter_generated/route/feature.route.g.dart',
        'builderLibrary':
            'lib/src/ccrouter_generated/binding/feature.route_binding.g.dart',
      },
      'patterns': [
        {
          'type': 'CCPathPattern',
          'value': '/${id.split('.').last}',
          'primary': true,
          'constraints': <String, String>{},
        },
      ],
    };
    metadata.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 2,
        'package': 'fixture_feature',
        'source': 'lib/src/feature.dart',
        'componentDeclarations': ['feature_component'],
        'componentManifests': {'feature_component': 'featureManifest'},
        'componentSymbols': {'feature_component': 'featureComponent'},
        'components': [
          {'id': 'feature_component', 'version': '1.0.0', 'dependencies': <String>[], 'optionalDependencies': <String>[]},
        ],
        'routes': [route('feature.foo-bar', 'FooDashPage'), route('feature.foo_bar', 'FooUnderscorePage')],
        'routeImplementations': <Object>[],
      })}\n',
    );

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'ccrouter_generator:ccrouter_generator',
      host.path,
      '--generate-component-registrars',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('both generate'));
    expect('${result.stderr}', contains('fooBar'));
  });

  test('component contribution requires a Package component owner', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'ccrouter_orphan_contribution_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final host = Directory(path.join(temporary.path, 'host'))
      ..createSync(recursive: true);
    File(path.join(host.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixture_host
environment:
  sdk: ^3.9.0
''');
    final component = Directory(path.join(host.path, 'modules', 'feature'))
      ..createSync(recursive: true);
    File(path.join(component.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixture_feature
environment:
  sdk: ^3.9.0
''');
    final metadata = File(
      path.join(
        component.path,
        'ccrouter_generated',
        'src',
        'feature.route.json',
      ),
    )..createSync(recursive: true);
    metadata.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 3,
        'package': 'fixture_feature',
        'source': 'lib/src/feature.dart',
        'componentDeclarations': <String>[],
        'componentManifests': <String, String>{},
        'componentSymbols': <String, String>{},
        'components': <Object>[],
        'routes': <Object>[],
        'routeImplementations': <Object>[],
        'contributions': [
          {'id': 'fixture_feature.services', 'componentId': null, 'symbol': 'registerFixtureServices'},
        ],
      })}\n',
    );

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'ccrouter_generator:ccrouter_generator',
      host.path,
      '--generate-component-registrars',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('has no top-level const CCComponent'));
  });
}
