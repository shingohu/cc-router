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
        'schemaVersion': 1,
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
  });
}
