@TestOn('vm')
@Timeout(Duration(minutes: 20))
library;

import 'dart:io';

import 'package:ccrouter_generator/src/component_dependency_preflight.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'support/real_workspace_test_lock.dart';

void main() {
  serializeRealWorkspaceTests();

  group('component dependency preflight', () {
    test('nested lib directories never alias another Library', () {
      for (final nestedPath in [
        'package:contracts/lib/src/lib/api.dart',
        '/workspace/contracts/lib/src/lib/api.dart',
      ]) {
        for (final includeDependency in [false, true]) {
          final issues = CCComponentDependencyPreflight.inspect([
            CCComponentDependencyPreflightSource(
              packageName: 'contracts',
              path: nestedPath,
              writable: false,
              contents: '''
@CCServiceContract(componentId: CCComponentId('hidden'), id: 'hidden.service')
abstract interface class SharedService {}
''',
            ),
            CCComponentDependencyPreflightSource(
              packageName: 'contracts',
              path: 'package:contracts/lib/api.dart',
              writable: false,
              contents: 'class SharedService {}',
            ),
            _source(
              package: 'consumer',
              file: 'component.dart',
              writable: true,
              contents:
                  '''
import 'package:contracts/${includeDependency ? 'src/lib/' : ''}api.dart';
const component = CCComponent(id: CCComponentId('consumer'), dependencies: [],
  serviceDependencies: [CCServiceDependency<SharedService>()]);
''',
            ),
          ]);
          expect(
            issues.length,
            includeDependency && nestedPath.startsWith('package:') ? 1 : 0,
          );
          if (issues.isNotEmpty)
            expect(issues.single.ownerComponentId, 'hidden');
        }
      }
    });

    test('does not use unrelated same-Package owner constants', () {
      final issues = CCComponentDependencyPreflight.inspect([
        _source(
          package: 'contracts',
          file: 'api.dart',
          contents: '''
const ownerId = CCComponentId('owner');
@CCServiceContract(componentId: ownerId, id: 'owner.service')
abstract interface class SharedService {}
''',
        ),
        _source(
          package: 'consumer',
          file: 'unrelated.dart',
          contents: "const ownerId = CCComponentId('unrelated');",
        ),
        _source(
          package: 'consumer',
          file: 'component.dart',
          writable: true,
          contents: '''
import 'package:contracts/api.dart';
const component = CCComponent(id: CCComponentId('consumer'),
  dependencies: [ownerId], serviceDependencies: [CCServiceDependency<SharedService>()]);
''',
        ),
      ]);
      expect(issues, isEmpty);
    });

    test(
      'unimported Contracts cannot be discovered through Package membership',
      () {
        final issues = CCComponentDependencyPreflight.inspect([
          _source(
            package: 'contracts',
            file: 'other.dart',
            contents: '''
@CCServiceContract(componentId: CCComponentId('owner'), id: 'owner.service')
abstract interface class SharedService {}
''',
          ),
          _source(
            package: 'contracts',
            file: 'api.dart',
            contents: 'class SharedService {}',
          ),
          _source(
            package: 'consumer',
            file: 'component.dart',
            writable: true,
            contents: '''
import 'package:contracts/api.dart';
const component = CCComponent(id: CCComponentId('consumer'), dependencies: [],
  serviceDependencies: [CCServiceDependency<SharedService>()]);
''',
          ),
        ]);
        expect(issues, isEmpty);
      },
    );

    test('follows exact relative barrels and preserves local shadowing', () {
      final contracts = _source(
        package: 'contracts',
        file: 'src/api.dart',
        contents: '''
const ownerId = CCComponentId('owner');
@CCServiceContract(componentId: ownerId, id: 'owner.service')
abstract interface class SharedService {}
''',
      );
      for (final declaration in [
        '',
        "const ownerId = CCComponentId('another');",
      ]) {
        final issues = CCComponentDependencyPreflight.inspect([
          contracts,
          _source(
            package: 'contracts',
            file: 'api.dart',
            contents: "export 'src/api.dart' show ownerId, SharedService;",
          ),
          _source(
            package: 'consumer',
            file: 'src/component.dart',
            writable: true,
            contents:
                '''
import 'package:contracts/api.dart';
$declaration
const component = CCComponent(id: CCComponentId('consumer'), dependencies: [ownerId],
  serviceDependencies: [CCServiceDependency<SharedService>()]);
''',
          ),
        ]);
        expect(issues.length, declaration.isEmpty ? 0 : 1);
        if (issues.isNotEmpty) expect(issues.single.ownerComponentId, 'owner');
      }
    });

    test('unknown and conditional namespaces defer to Builder', () {
      for (final import in [
        "import 'package:contracts/api.dart' if (dart.library.io) 'package:contracts/other.dart';",
        "import 'package:contracts/api.dart'; import 'package:unknown/api.dart';",
        "import 'package:contracts/api.dart' show SharedService hide SharedService;",
        "import 'package:contracts/api.dart'; part 'other.dart';",
      ]) {
        final issues = CCComponentDependencyPreflight.inspect([
          _source(
            package: 'contracts',
            file: 'api.dart',
            contents: '''
@CCServiceContract(componentId: CCComponentId('owner'), id: 'owner.service')
abstract interface class SharedService {}
''',
          ),
          _source(
            package: 'consumer',
            file: 'component.dart',
            writable: true,
            contents:
                '''
$import
const component = CCComponent(id: CCComponentId('consumer'), dependencies: [],
  serviceDependencies: [CCServiceDependency<SharedService>()]);
''',
          ),
        ]);
        expect(issues, isEmpty, reason: import);
      }
    });

    test('relative imports and CLI library paths use the same namespace', () {
      final issues = CCComponentDependencyPreflight.inspect([
        CCComponentDependencyPreflightSource(
          packageName: 'consumer',
          path: 'package:consumer/lib/src/service.dart',
          writable: true,
          contents: '''
@CCServiceContract(componentId: CCComponentId('owner'), id: 'owner.service')
abstract interface class SharedService {}
''',
        ),
        _source(
          package: 'consumer',
          file: 'src/component.dart',
          writable: true,
          contents: '''
import 'service.dart';
const component = CCComponent(id: CCComponentId('consumer'), dependencies: [],
  serviceDependencies: [CCServiceDependency<SharedService>()]);
''',
        ),
      ]);
      expect(issues.single.ownerComponentId, 'owner');
    });

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
    'generate reports proven missing owners before build_runner without writes',
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
      // Network's annotation library imports Dio, outside this AST index.
      // Do not guess that the unknown namespace cannot shadow its owner ID.
      expect(output, isNot(contains('demo_network_component')));
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
