import 'dart:io';

import 'package:ccrouter_analyzer_plugin/src/contract_owner_index.dart';
import 'package:ccrouter_analyzer_plugin/src/source_analyzer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late String packageRoot;

  setUp(() {
    root = Directory.systemTemp.createTempSync('ccrouter-analyzer-');
    packageRoot = root.path;
    File(
      path.join(packageRoot, 'pubspec.yaml'),
    ).writeAsStringSync('name: sample_component\n');
    Directory(path.join(packageRoot, 'lib', 'src')).createSync(recursive: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('does not reject prefixed Future or unresolved return aliases', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
import 'dart:async' as async;
typedef Completion = async.Future<void>;
@CCEventSubscription()
async.Future<void> receive(Object event) async {}
@CCEventSubscription()
Completion receiveAlias(Object event) async {}
''',
      filePath: path.join(packageRoot, 'lib', 'src', 'handlers.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );
    expect(
      diagnostics.where(
        (item) => item.code == 'ccrouter_handler_signature_invalid',
      ),
      isEmpty,
    );
  });

  test('rejects a foreign generated library import', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source:
          "import 'package:other_component/src/ccrouter_generated/route/x.dart';",
      filePath: path.join(packageRoot, 'lib', 'src', 'page.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );
    expect(
      diagnostics.map((item) => item.code),
      contains('ccrouter_cross_package_generated_import'),
    );
  });

  test('warns when a route output is missing', () {
    final source = '''
class CCRoute<T> {
  const CCRoute();
}

@CCRoute<void>()
class HomePage {}
''';
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: source,
      filePath: path.join(packageRoot, 'lib', 'src', 'home_page.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );
    expect(
      diagnostics.map((item) => item.code),
      contains('ccrouter_generated_output_missing'),
    );
  });

  test('does not warn after the route output exists', () {
    _writeGenerated(packageRoot, 'route/home_page.route.g.dart');
    _writeGenerated(packageRoot, 'binding/home_page.route_binding.g.dart');
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '@CCRoute<void>()\nclass HomePage {}',
      filePath: path.join(packageRoot, 'lib', 'src', 'home_page.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );
    expect(
      diagnostics.map((item) => item.code),
      isNot(contains('ccrouter_generated_output_missing')),
    );
  });

  test('maps generated route output changes back to the authored source', () {
    final generated = path.join(
      packageRoot,
      'lib',
      'src',
      'ccrouter_generated',
      'route',
      'pages',
      'network_page.route.g.dart',
    );
    expect(
      CCRouterSourceAnalyzer.authoredPathForGenerated(generated),
      path.join(packageRoot, 'lib', 'src', 'pages', 'network_page.dart'),
    );
  });

  test('ignores unrelated generated files for source refresh', () {
    expect(
      CCRouterSourceAnalyzer.authoredPathForGenerated(
        path.join(
          packageRoot,
          'lib',
          'src',
          'ccrouter_generated',
          'component',
          'component.g.dart',
        ),
      ),
      isNull,
    );
  });

  test('ignores an incomplete editor buffer without throwing', () {
    expect(
      () => CCRouterSourceAnalyzer.analyze(
        source: 'class HomePage {',
        filePath: path.join(packageRoot, 'lib', 'src', 'home_page.dart'),
        packageRoot: packageRoot,
        packageName: 'sample_component',
      ),
      returnsNormally,
    );
  });

  test('does not flag generated implementation imports', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source:
          "import 'package:other_component/src/ccrouter_generated/route/x.dart';",
      filePath: path.join(
        packageRoot,
        'lib',
        'src',
        'ccrouter_generated',
        'host',
        'host.g.dart',
      ),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );
    expect(diagnostics, isEmpty);
  });

  test('reports required InitTask without Contract or timeout', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
@CCInitTask(
  id: 'startup.required',
  gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.required,
)
Future<void> initializeRequired() async {}
''',
      filePath: path.join(packageRoot, 'lib', 'src', 'init_tasks.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );

    expect(
      diagnostics.map((item) => item.code),
      containsAll([
        'ccrouter_required_init_task_contract_missing',
        'ccrouter_required_init_task_timeout_missing',
      ]),
    );
  });

  test('accepts a bounded required InitTask Contract Handler', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
@CCInitTask(
  contract: startupRequired,
  gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.required,
  timeout: Duration(seconds: 3),
)
Future<void> initializeRequired() async {}
''',
      filePath: path.join(packageRoot, 'lib', 'src', 'init_tasks.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );

    expect(
      diagnostics.map((item) => item.code),
      isNot(contains(startsWith('ccrouter_required_init_task_'))),
    );
  });

  test(
    'reports one missing required owner for Service and Command consumers',
    () {
      final diagnostics = CCRouterSourceAnalyzer.analyze(
        source: '''
import 'package:owner_contracts/owner_contracts.dart';

const consumerComponent = CCComponent(
  id: consumerComponentId,
  version: '1.0.0',
  serviceDependencies: [CCServiceDependency<SharedService>()],
  commandDependencies: [CCCommandDependency<RunCommand>()],
);
''',
        filePath: path.join(packageRoot, 'lib', 'src', 'component.dart'),
        packageRoot: packageRoot,
        packageName: 'sample_component',
        contractOwners: _ownerIndex(),
      );

      expect(
        diagnostics.where(
          (item) => item.code == 'ccrouter_component_owner_dependency_missing',
        ),
        hasLength(1),
      );
      expect(
        diagnostics
            .singleWhere(
              (item) =>
                  item.code == 'ccrouter_component_owner_dependency_missing',
            )
            .message,
        contains('owner.component'),
      );
    },
  );

  test('accepts the exact required owner dependency', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
import 'package:owner_contracts/owner_contracts.dart';

const consumerComponent = CCComponent(
  id: consumerComponentId,
  version: '1.0.0',
  dependencies: [ownerComponentId],
  serviceDependencies: [CCServiceDependency<SharedService>()],
);
''',
      filePath: path.join(packageRoot, 'lib', 'src', 'component.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
      contractOwners: _ownerIndex(),
    );

    expect(
      diagnostics.map((item) => item.code),
      isNot(contains('ccrouter_component_owner_dependency_missing')),
    );
  });

  test('accepts a local const alias of the required owner', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
import 'package:owner_contracts/owner_contracts.dart';

const sharedOwner = ownerComponentId;
const consumerComponent = CCComponent(
  id: consumerComponentId,
  version: '1.0.0',
  dependencies: [sharedOwner],
  serviceDependencies: [CCServiceDependency<SharedService>()],
);
''',
      filePath: path.join(packageRoot, 'lib', 'src', 'component.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
      contractOwners: _ownerIndex(),
    );

    expect(
      diagnostics.map((item) => item.code),
      isNot(contains('ccrouter_component_owner_dependency_missing')),
    );
  });

  test('does not let an optional dependency satisfy a Service consumer', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
import 'package:owner_contracts/owner_contracts.dart';

const consumerComponent = CCComponent(
  id: consumerComponentId,
  version: '1.0.0',
  optionalDependencies: [ownerComponentId],
  serviceDependencies: [CCServiceDependency<SharedService>()],
);
''',
      filePath: path.join(packageRoot, 'lib', 'src', 'component.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
      contractOwners: _ownerIndex(),
    );

    expect(
      diagnostics.map((item) => item.code),
      contains('ccrouter_component_owner_dependency_missing'),
    );
  });

  test('declines dependency inference for a spread list', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
import 'package:owner_contracts/owner_contracts.dart';

const baseDependencies = <CCComponentId>[];
const consumerComponent = CCComponent(
  id: consumerComponentId,
  version: '1.0.0',
  dependencies: [...baseDependencies],
  serviceDependencies: [CCServiceDependency<SharedService>()],
);
''',
      filePath: path.join(packageRoot, 'lib', 'src', 'component.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
      contractOwners: _ownerIndex(),
    );

    expect(
      diagnostics.map((item) => item.code),
      isNot(contains('ccrouter_component_owner_dependency_missing')),
    );
  });

  final generatedCases =
      <({String annotation, String declaration, String label})>[
        (
          annotation: '@CCRouteContract<void>()',
          declaration: 'class RouteSchema {}',
          label: 'Route Contract',
        ),
        (
          annotation: '@CCRouteImplementation(routeContract)',
          declaration: 'class RoutePage {}',
          label: 'Route implementation',
        ),
        (
          annotation: '@CCService()',
          declaration: 'class SampleService {}',
          label: 'Service',
        ),
        (
          annotation: '@CCServiceContract()',
          declaration: 'class SampleServiceContract {}',
          label: 'Service Contract',
        ),
        (
          annotation: '@CCCommandHandler()',
          declaration: 'void handleCommand() {}',
          label: 'Command Handler',
        ),
        (
          annotation: '@CCEventSubscription()',
          declaration: 'void handleEvent() {}',
          label: 'Event Subscription',
        ),
        (
          annotation: '@CCInitTask()',
          declaration: 'void initializeFeature() {}',
          label: 'InitTask',
        ),
      ];
  for (final generatedCase in generatedCases) {
    test('warns for missing ${generatedCase.label} output', () {
      final diagnostics = CCRouterSourceAnalyzer.analyze(
        source: '${generatedCase.annotation}\n${generatedCase.declaration}\n',
        filePath: path.join(packageRoot, 'lib', 'src', 'capability.dart'),
        packageRoot: packageRoot,
        packageName: 'sample_component',
      );

      expect(
        diagnostics,
        contains(
          isA<CCRouterAnalyzerDiagnostic>()
              .having(
                (item) => item.code,
                'code',
                'ccrouter_generated_output_missing',
              )
              .having(
                (item) => item.message,
                'message',
                contains(generatedCase.label),
              ),
        ),
      );
    });
  }

  test('accepts complete source-preserving capability outputs', () {
    for (final output in const [
      'contract/capability.route.contract.g.dart',
      'binding/capability.route_binding.g.dart',
      'contract/capability.service.contract.g.dart',
      'service/capability.service.g.dart',
      'command/capability.command.g.dart',
      'event/capability.event.g.dart',
      'init_task/capability.init_task.g.dart',
    ]) {
      _writeGenerated(packageRoot, output);
    }
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
@CCRouteContract<void>()
class RouteSchema {}
@CCRouteImplementation(routeContract)
class RoutePage {}
@CCServiceContract()
class SampleServiceContract {}
@CCService()
class SampleService {}
@CCCommandHandler()
void handleCommand() {}
@CCEventSubscription()
void handleEvent() {}
@CCInitTask()
void initializeFeature() {}
''',
      filePath: path.join(packageRoot, 'lib', 'src', 'capability.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );

    expect(
      diagnostics.map((item) => item.code),
      isNot(contains('ccrouter_generated_output_missing')),
    );
  });

  test('does not invent direct output for metadata-only Contracts', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
@CCCommandContract()
class SampleCommand {}
@CCEventContract()
class SampleEvent {}
const startupTask = CCInitTaskContract(id: 'startup.task');
''',
      filePath: path.join(packageRoot, 'lib', 'src', 'contracts.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );

    expect(
      diagnostics.map((item) => item.code),
      isNot(contains('ccrouter_generated_output_missing')),
    );
  });

  test('maps every source-preserving generated kind back to source', () {
    for (final generated in const [
      'route/pages/capability.route.g.dart',
      'binding/pages/capability.route_binding.g.dart',
      'contract/pages/capability.route.contract.g.dart',
      'contract/pages/capability.service.contract.g.dart',
      'service/pages/capability.service.g.dart',
      'command/pages/capability.command.g.dart',
      'event/pages/capability.event.g.dart',
      'init_task/pages/capability.init_task.g.dart',
    ]) {
      expect(
        CCRouterSourceAnalyzer.authoredPathForGenerated(
          path.join(packageRoot, 'lib', 'src', 'ccrouter_generated', generated),
        ),
        path.join(packageRoot, 'lib', 'src', 'pages', 'capability.dart'),
        reason: generated,
      );
    }
  });

  test('reports non-public generic and method Handlers', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
@CCCommandHandler()
void _handleCommand<T>(T command) {}
class Owner {
  @CCEventSubscription()
  void handleEvent(Object event) {}
}
''',
      filePath: path.join(packageRoot, 'lib', 'src', 'handlers.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );

    expect(
      diagnostics.where(
        (item) => item.code == 'ccrouter_handler_declaration_invalid',
      ),
      hasLength(2),
    );
  });

  test('reports mutually exclusive Route and InitTask arguments', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
@CCRoute<void>(
  id: 'sample.route',
  pattern: CCPathPattern('/sample'),
  patterns: [CCPathPattern('/legacy')],
)
class SamplePage {}
@CCInitTask(
  contract: startupTask,
  id: 'startup.task',
  gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.optional,
)
void initializeFeature() {}
''',
      filePath: path.join(packageRoot, 'lib', 'src', 'conflicts.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );

    expect(
      diagnostics.where(
        (item) => item.code == 'ccrouter_annotation_arguments_conflict',
      ),
      hasLength(2),
    );
  });

  test('reports missing InitTask identity after a complete annotation', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
@CCInitTask(
  gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.optional,
)
void initializeFeature() {}
''',
      filePath: path.join(packageRoot, 'lib', 'src', 'init_task.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );

    expect(
      diagnostics.map((item) => item.code),
      contains('ccrouter_annotation_arguments_conflict'),
    );
  });

  test('reports invalid literal IDs aliases Gates and timeouts', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
@CCServiceContract(id: 'Bad ID', alias: 'class')
abstract interface class InvalidService {}
@CCInitTask(
  id: 'startup.task',
  gate: CCInitTaskGate('Privacy Gate'),
  failurePolicy: CCInitTaskFailurePolicy.optional,
  timeout: Duration.zero,
)
void initializeFeature() {}
''',
      filePath: path.join(packageRoot, 'lib', 'src', 'invalid_values.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );

    expect(
      diagnostics.map((item) => item.code),
      containsAll([
        'ccrouter_identifier_invalid',
        'ccrouter_alias_invalid',
        'ccrouter_timeout_invalid',
      ]),
    );
    expect(
      diagnostics.where((item) => item.code == 'ccrouter_identifier_invalid'),
      hasLength(2),
    );
  });

  test('reports obvious Handler arity and return violations', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
@CCCommandHandler()
void handleCommand() {}
@CCEventSubscription()
int handleEvent(Object event) => 1;
@CCInitTask(
  id: 'startup.task',
  gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.optional,
)
String initializeFeature([Object? context]) => '';
''',
      filePath: path.join(packageRoot, 'lib', 'src', 'signatures.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );

    expect(
      diagnostics.where(
        (item) => item.code == 'ccrouter_handler_signature_invalid',
      ),
      hasLength(4),
    );
  });

  test('does not guess non-literal identifiers aliases or timeouts', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
@CCServiceContract(id: serviceId, alias: serviceAlias)
abstract interface class DeferredService {}
@CCInitTask(
  id: taskId,
  gate: customGate,
  failurePolicy: CCInitTaskFailurePolicy.optional,
  timeout: configuredTimeout,
)
void initializeFeature() {}
''',
      filePath: path.join(packageRoot, 'lib', 'src', 'deferred_values.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );

    expect(
      diagnostics.map((item) => item.code),
      isNot(
        contains(
          anyOf(
            'ccrouter_identifier_invalid',
            'ccrouter_alias_invalid',
            'ccrouter_timeout_invalid',
          ),
        ),
      ),
    );
  });
}

CCRouterContractOwnerIndex _ownerIndex() => CCRouterContractOwnerIndex(
  owners: const [
    CCRouterContractOwner(
      kind: CCRouterContractKind.service,
      contractSymbol: 'SharedService',
      contractPackage: 'owner_contracts',
      componentId: 'owner.component',
      componentIdSymbol: 'ownerComponentId',
    ),
    CCRouterContractOwner(
      kind: CCRouterContractKind.command,
      contractSymbol: 'RunCommand',
      contractPackage: 'owner_contracts',
      componentId: 'owner.component',
      componentIdSymbol: 'ownerComponentId',
    ),
  ],
  packageRoots: const {},
);

void _writeGenerated(String packageRoot, String relative) {
  File(
    path.join(packageRoot, 'lib', 'src', 'ccrouter_generated', relative),
  ).createSync(recursive: true);
}
