import 'dart:io';

import 'package:ccrouter_analyzer_plugin/src/contract_owner_index.dart';
import 'package:ccrouter_analyzer_plugin/src/quick_fixes.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('offers explicit alternatives for Route pattern conflicts', () {
    const source = '''
@CCRoute<void>(
  id: 'sample.route',
  pattern: CCPathPattern('/sample'),
  patterns: [CCPathPattern('/legacy')],
)
class SamplePage {}
''';
    final fixes = CCRouterQuickFixes.compute(
      source: source,
      filePath: '/workspace/lib/src/sample_page.dart',
      offset: source.indexOf('@CCRoute'),
    );

    expect(fixes.map((item) => item.id), [
      'ccrouter.remove_conflicting_pattern',
      'ccrouter.remove_conflicting_patterns',
    ]);
    final withoutPattern = _apply(source, fixes.first);
    expect(
      withoutPattern,
      isNot(contains("pattern: CCPathPattern('/sample')")),
    );
    expect(withoutPattern, contains('patterns:'));
    final withoutPatterns = _apply(source, fixes.last);
    expect(withoutPatterns, contains('pattern:'));
    expect(withoutPatterns, isNot(contains('patterns:')));
  });

  test('offers explicit alternatives for InitTask identity conflicts', () {
    const source = '''
@CCInitTask(
  contract: startupTask,
  id: 'startup.task',
  gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.optional,
)
void initializeFeature() {}
''';
    final fixes = CCRouterQuickFixes.compute(
      source: source,
      filePath: '/workspace/lib/src/init_task.dart',
      offset: source.indexOf('@CCInitTask'),
    );

    expect(fixes, hasLength(2));
    expect(_apply(source, fixes.first), isNot(contains('contract:')));
    expect(_apply(source, fixes.last), isNot(contains("id: 'startup.task'")));
  });

  test('declines a deletion that would consume a source comment', () {
    const source = '''
@CCRoute<void>(
  id: 'sample.route',
  pattern: CCPathPattern('/sample'), // Keep this explanation.
  patterns: [CCPathPattern('/legacy')],
)
class SamplePage {}
''';
    final fixes = CCRouterQuickFixes.compute(
      source: source,
      filePath: '/workspace/lib/src/sample_page.dart',
      offset: source.indexOf('@CCRoute'),
    );

    expect(fixes, isEmpty);
  });

  test('does not offer guesses for non-conflict diagnostics', () {
    const source = '''
@CCServiceContract(id: 'Bad ID', alias: 'class')
abstract interface class InvalidService {}
''';
    final fixes = CCRouterQuickFixes.compute(
      source: source,
      filePath: '/workspace/lib/src/service.dart',
      offset: source.indexOf('@CCServiceContract'),
    );

    expect(fixes, isEmpty);
  });

  test('adds a proven owner to an existing required dependency list', () {
    final fixture = _QuickFixFixture.create();
    addTearDown(fixture.dispose);
    const source = '''
import 'package:owner_contracts/owner_contracts.dart';
const existingComponentId = CCComponentId('existing.component');

const consumerComponent = CCComponent(
  id: consumerComponentId,
  version: '1.0.0',
  dependencies: [
    existingComponentId,
  ],
  serviceDependencies: [CCServiceDependency<SharedService>()],
);
''';
    final fixes = CCRouterQuickFixes.compute(
      source: source,
      filePath: fixture.consumerSource.path,
      offset: source.indexOf('CCServiceDependency'),
      diagnosticCode: 'ccrouter_component_owner_dependency_missing',
      contractOwners: fixture.index,
      sourcePackage: 'consumer',
    );

    expect(fixes, hasLength(1));
    expect(
      _apply(source, fixes.single),
      contains('''
  dependencies: [
    existingComponentId,
    ownerComponentId,
  ],'''),
    );
  });

  test('creates a required dependency list before the consuming field', () {
    final fixture = _QuickFixFixture.create();
    addTearDown(fixture.dispose);
    const source = '''
import 'package:owner_contracts/owner_contracts.dart' as owner;

const consumerComponent = CCComponent(
  id: consumerComponentId,
  version: '1.0.0',
  commandDependencies: [CCCommandDependency<owner.RunCommand>()],
);
''';
    final fixes = CCRouterQuickFixes.compute(
      source: source,
      filePath: fixture.consumerSource.path,
      offset: source.indexOf('CCCommandDependency'),
      diagnosticCode: 'ccrouter_component_owner_dependency_missing',
      contractOwners: fixture.index,
      sourcePackage: 'consumer',
    );

    expect(fixes, hasLength(1));
    expect(
      _apply(source, fixes.single),
      contains('''
  dependencies: [owner.ownerComponentId],
  commandDependencies:'''),
    );
  });

  test('offers one edit for all uniquely proven missing owners', () {
    final fixture = _QuickFixFixture.create();
    addTearDown(fixture.dispose);
    const source = '''
import 'package:owner_contracts/owner_contracts.dart';

const consumerComponent = CCComponent(
  id: consumerComponentId,
  version: '1.0.0',
  dependencies: [],
  serviceDependencies: [
    CCServiceDependency<SharedService>(),
    CCServiceDependency<SecondaryService>(),
  ],
);
''';
    final fixes = CCRouterQuickFixes.compute(
      source: source,
      filePath: fixture.consumerSource.path,
      offset: source.indexOf('CCServiceDependency'),
      diagnosticCode: 'ccrouter_component_owner_dependency_missing',
      contractOwners: fixture.index,
      sourcePackage: 'consumer',
    );

    expect(fixes.map((item) => item.id), [
      'ccrouter.add_required_component_dependency',
      'ccrouter.add_all_required_component_dependencies',
    ]);
    expect(
      _apply(source, fixes.last),
      contains('dependencies: [ownerComponentId, secondaryComponentId]'),
    );
  });

  test('declines owner edit when the public import hides the ID constant', () {
    final fixture = _QuickFixFixture.create();
    addTearDown(fixture.dispose);
    const source = '''
import 'package:owner_contracts/owner_contracts.dart'
    hide ownerComponentId;

const consumerComponent = CCComponent(
  id: consumerComponentId,
  version: '1.0.0',
  serviceDependencies: [CCServiceDependency<SharedService>()],
);
''';
    final fixes = CCRouterQuickFixes.compute(
      source: source,
      filePath: fixture.consumerSource.path,
      offset: source.indexOf('CCServiceDependency'),
      diagnosticCode: 'ccrouter_component_owner_dependency_missing',
      contractOwners: fixture.index,
      sourcePackage: 'consumer',
    );

    expect(fixes, isEmpty);
  });
}

String _apply(String source, CCRouterSourceFix fix) =>
    source.replaceRange(fix.offset, fix.offset + fix.length, fix.replacement);

final class _QuickFixFixture {
  const _QuickFixFixture({
    required this.root,
    required this.consumerSource,
    required this.index,
  });

  final Directory root;
  final File consumerSource;
  final CCRouterContractOwnerIndex index;

  static _QuickFixFixture create() {
    final root = Directory.systemTemp.createTempSync('ccrouter-owner-fix-');
    final ownerRoot = Directory(path.join(root.path, 'owner_contracts'))
      ..createSync(recursive: true);
    final ownerSource = File(
      path.join(ownerRoot.path, 'lib', 'src', 'owner.dart'),
    )..createSync(recursive: true);
    ownerSource.writeAsStringSync('''
const ownerComponentId = CCComponentId('owner.component');
const secondaryComponentId = CCComponentId('secondary.component');
abstract interface class SharedService {}
abstract interface class SecondaryService {}
final class RunCommand {}
''');
    File(path.join(ownerRoot.path, 'lib', 'owner_contracts.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "export 'src/owner.dart' show ownerComponentId, secondaryComponentId, SharedService, SecondaryService, RunCommand;\n",
      );
    final consumerSource = File(
      path.join(root.path, 'consumer', 'lib', 'src', 'component.dart'),
    )..createSync(recursive: true);
    return _QuickFixFixture(
      root: root,
      consumerSource: consumerSource,
      index: CCRouterContractOwnerIndex(
        owners: const [
          CCRouterContractOwner(
            kind: CCRouterContractKind.service,
            contractSymbol: 'SharedService',
            contractPackage: 'owner_contracts',
            componentId: 'owner.component',
            componentIdSymbol: 'ownerComponentId',
          ),
          CCRouterContractOwner(
            kind: CCRouterContractKind.service,
            contractSymbol: 'SecondaryService',
            contractPackage: 'owner_contracts',
            componentId: 'secondary.component',
            componentIdSymbol: 'secondaryComponentId',
          ),
          CCRouterContractOwner(
            kind: CCRouterContractKind.command,
            contractSymbol: 'RunCommand',
            contractPackage: 'owner_contracts',
            componentId: 'owner.component',
            componentIdSymbol: 'ownerComponentId',
          ),
        ],
        packageRoots: {'owner_contracts': ownerRoot.path},
      ),
    );
  }

  void dispose() => root.deleteSync(recursive: true);
}
