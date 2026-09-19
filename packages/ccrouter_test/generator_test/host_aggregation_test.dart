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
        'metadata',
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
        'components': [
          {'id': 'fixture_service_component', 'version': '1.0.0', 'dependencies': <String>[], 'optionalDependencies': <String>[]},
        ],
        'routes': <Object>[],
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
        component.path,
        'lib',
        'src',
        'ccrouter_generated',
        'fixture_service_component.routes.g.dart',
      ),
    ).readAsStringSync();
    expect(componentIndex, contains('CCFlutterRouteCatalog([])'));

    final integration = File(
      path.join(component.path, 'lib', 'fixture_service_ccrouter.g.dart'),
    ).readAsStringSync();
    expect(integration, contains('fixtureServiceComponentManifest'));
    expect(integration, contains('fixtureServiceComponentRouteCatalog'));

    final aggregate = File(
      path.join(
        host.path,
        'lib',
        'ccrouter_generated',
        'ccrouter_host.routes.g.dart',
      ),
    ).readAsStringSync();
    expect(aggregate, contains('ccrouterGeneratedComponentManifests'));
    expect(aggregate, contains('fixtureServiceComponentManifest'));
    expect(aggregate, contains('fixtureServiceComponentRouteCatalog'));
    expect(aggregate, contains('componentVersions: {'));
    expect(aggregate, contains('manifest.id: manifest.version'));
    expect(aggregate, isNot(contains('CCRouterGeneratedHost')));
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
export 'src/ccrouter_generated/detail.route.contract.g.dart'
    show DetailRoute, DetailRouteArguments;
''');
    final contractMetadata = File(
      path.join(
        contracts.path,
        'ccrouter_generated',
        'metadata',
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
            'contracts': {'route': 'DetailRoute', 'arguments': 'DetailRouteArguments', 'package': 'fixture_order_contracts', 'library': 'lib/src/ccrouter_generated/detail.route.contract.g.dart'},
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
        'metadata',
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
        'metadata',
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
            'destination': {'descriptor': 'ccrouterDescribeDetailPageRoute', 'builder': 'ccrouterBuildDetailPageRoute'},
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
        'order.routes.g.dart',
      ),
    ).readAsStringSync();
    expect(
      componentIndex,
      contains('package:fixture_order/src/detail_page.dart'),
    );
    expect(componentIndex, contains('ccrouterRegisterDetailPageRoute'));
    expect(
      componentIndex,
      isNot(contains('package:fixture_order_contracts/src/detail.dart')),
    );
  });
}
