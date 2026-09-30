@TestOn('vm')
library;

import 'dart:io';

import 'package:ccrouter_generator/src/component_dependency_preflight.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('component dependency preflight', () {
    test('aggregates capabilities by uniquely proven owner', () {
      final issues = CCComponentDependencyPreflight.inspect([
        _source(
          package: 'owner_contracts',
          file: 'contracts.dart',
          contents: '''
const ownerComponentId = CCComponentId('owner.component');
const otherComponentId = CCComponentId('other.component');

@CCServiceContract(componentId: ownerComponentId, id: 'owner.service')
abstract interface class SharedService {}

@CCCommandContract(componentId: ownerComponentId, id: 'owner.command')
final class RunCommand {}

@CCServiceContract(componentId: otherComponentId, id: 'other.service')
abstract interface class OtherService {}
''',
        ),
        _source(
          package: 'consumer',
          file: 'component.dart',
          writable: true,
          contents: '''
import 'package:owner_contracts/contracts.dart';

const consumerComponentId = CCComponentId('consumer.component');
const consumerComponent = CCComponent(
  id: consumerComponentId,
  version: '1.0.0',
  dependencies: [],
  serviceDependencies: [
    CCServiceDependency<SharedService>(),
    CCServiceDependency<OtherService>(),
  ],
  commandDependencies: [CCCommandDependency<RunCommand>()],
);
''',
        ),
      ]);

      expect(issues, hasLength(2));
      expect(issues.first.ownerComponentId, 'other.component');
      expect(issues.first.capabilities.map((item) => item.id), [
        'other.service',
      ]);
      expect(issues.last.ownerComponentId, 'owner.component');
      expect(
        issues.last.capabilities.map((item) => '${item.kind}:${item.id}'),
        ['Command:owner.command', 'Service:owner.service'],
      );
    });

    test('resolves prefixed imports and respects show and hide', () {
      final contract = _source(
        package: 'owner_contracts',
        file: 'contracts.dart',
        contents: '''
const ownerComponentId = CCComponentId('owner.component');
@CCServiceContract(componentId: ownerComponentId, id: 'owner.service')
abstract interface class SharedService {}
''',
      );
      final prefixed = CCComponentDependencyPreflight.inspect([
        contract,
        _source(
          package: 'consumer',
          file: 'prefixed.dart',
          writable: true,
          contents: '''
import 'package:owner_contracts/contracts.dart' as contracts;
const consumerComponent = CCComponent(
  id: CCComponentId('consumer.component'),
  version: '1.0.0',
  dependencies: [],
  serviceDependencies: [
    CCServiceDependency<contracts.SharedService>(),
  ],
);
''',
        ),
      ]);
      expect(prefixed.single.ownerComponentId, 'owner.component');

      for (final combinator in [
        'show ownerComponentId',
        'hide SharedService',
      ]) {
        final hidden = CCComponentDependencyPreflight.inspect([
          contract,
          _source(
            package: 'consumer',
            file: 'hidden.dart',
            writable: true,
            contents:
                '''
import 'package:owner_contracts/contracts.dart' $combinator;
const consumerComponent = CCComponent(
  id: CCComponentId('consumer.component'),
  version: '1.0.0',
  dependencies: [],
  serviceDependencies: [CCServiceDependency<SharedService>()],
);
''',
          ),
        ]);
        expect(hidden, isEmpty, reason: combinator);
      }
    });

    test('declines computed and ambiguous declarations', () {
      final contractA = _source(
        package: 'owner_a',
        file: 'contracts.dart',
        contents: '''
const ownerA = CCComponentId('owner.a');
@CCServiceContract(componentId: ownerA, id: 'owner.a.service')
abstract interface class SharedService {}
''',
      );
      final contractB = _source(
        package: 'owner_b',
        file: 'contracts.dart',
        contents: '''
const ownerB = CCComponentId('owner.a');
@CCServiceContract(componentId: ownerB, id: 'owner.a.service')
abstract interface class SharedService {}
''',
      );
      for (final contents in [
        '''
import 'package:owner_a/contracts.dart';
const inherited = <CCComponentId>[];
const consumerComponent = CCComponent(
  id: CCComponentId('consumer.component'),
  version: '1.0.0',
  dependencies: [...inherited],
  serviceDependencies: [CCServiceDependency<SharedService>()],
);
''',
        '''
import 'package:owner_a/contracts.dart';
const inherited = <CCComponentId>[];
const consumerComponent = CCComponent(
  id: CCComponentId('consumer.component'),
  version: '1.0.0',
  dependencies: inherited,
  serviceDependencies: [CCServiceDependency<SharedService>()],
);
''',
        '''
import 'package:owner_a/contracts.dart';
import 'package:owner_b/contracts.dart';
const consumerComponent = CCComponent(
  id: CCComponentId('consumer.component'),
  version: '1.0.0',
  dependencies: [],
  serviceDependencies: [CCServiceDependency<SharedService>()],
);
''',
      ]) {
        final issues = CCComponentDependencyPreflight.inspect([
          contractA,
          contractB,
          _source(
            package: 'consumer',
            file: 'component.dart',
            writable: true,
            contents: contents,
          ),
        ]);
        expect(issues, isEmpty);
      }
    });
  });

  test(
    'generate reports all missing owners before build_runner without writes',
    () async {
      final root = _workspaceRoot();
      final componentSource = File(
        path.join(
          root.path,
          'demo',
          'modules',
          'navigation_lab',
          'lib',
          'src',
          'navigation_lab_component.dart',
        ),
      );
      final generatedApi = File(
        path.join(
          root.path,
          'demo',
          'lib',
          'src',
          'ccrouter_generated',
          'ccrouter_host.api.g.dart',
        ),
      );
      final originalSource = componentSource.readAsBytesSync();
      final originalGenerated = generatedApi.readAsBytesSync();
      addTearDown(() {
        componentSource.writeAsBytesSync(originalSource, flush: true);
        generatedApi
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(originalGenerated, flush: true);
      });

      final source = String.fromCharCodes(originalSource);
      final dependencies = RegExp(
        r'  dependencies: \[\n(?:    .*\n)+?  \],\n  serviceDependencies:',
      );
      expect(source, matches(dependencies));
      componentSource.writeAsStringSync(
        source.replaceFirst(
          dependencies,
          '  dependencies: [],\n  serviceDependencies:',
        ),
        flush: true,
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'ccrouter_generator:ccrouter',
        'generate',
        'demo',
        '--profile',
      ], workingDirectory: root.path);
      final output = '${result.stdout}\n${result.stderr}';

      expect(result.exitCode, 1, reason: output);
      expect(output, contains('component dependency preflight failed'));
      expect(output, contains('demo_order_component'));
      expect(output, contains('demo_network_component'));
      expect(output, contains('demo_kv_storage_component'));
      expect(output, contains('Service "demo_order.summary"'));
      expect(output, contains('Command "demo_order.reserve"'));
      expect(output, isNot(contains('Generating Package artifacts')));
      expect(output, isNot(contains('ccrouter_generator:service_contracts')));
      expect(generatedApi.readAsBytesSync(), originalGenerated);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

CCComponentDependencyPreflightSource _source({
  required String package,
  required String file,
  required String contents,
  bool writable = false,
}) => CCComponentDependencyPreflightSource(
  packageName: package,
  path: '/workspace/$package/lib/$file',
  contents: contents,
  writable: writable,
);

Directory _workspaceRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (Directory(path.join(current.path, '.git')).existsSync()) return current;
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('CCRouter workspace root was not found.');
    }
    current = parent;
  }
}
