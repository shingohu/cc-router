import 'dart:io';

import 'package:ccrouter_analyzer_plugin/src/contract_owner_index.dart';
import 'package:ccrouter_analyzer_plugin/src/quick_fixes.dart';
import 'package:ccrouter_analyzer_plugin/src/source_analyzer.dart'
    show CCRouterSourceAnalyzer;
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('parser-only Owner edits respect named extension shadowing', () {
    final fixture = _QuickFixFixture.create();
    addTearDown(fixture.dispose);
    const source = '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/owner_contracts.dart' show SharedService, ownerComponentId;
extension ownerComponentId on Object {}
const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0',
  serviceDependencies: [CCServiceDependency<SharedService>()]);
''';
    final fixes = CCRouterQuickFixes.compute(
      source: source,
      filePath: fixture.consumerSource.path,
      offset: source.indexOf('CCServiceDependency<'),
      diagnosticCode: 'ccrouter_component_owner_dependency_missing',
      sourcePackage: 'consumer',
      contractOwners: fixture.index,
    );
    expect(fixes, isEmpty);
  });
  for (final mode in [
    'conditionalExport',
    'hiddenConditionalExport',
    'missingExport',
    'brokenExport',
    'packageQuery',
    'packageAbsolute',
    'packageInvalidEncoding',
    'relativeInvalidEncoding',
    'relativeQuery',
  ]) {
    test('parser-only Owner edits defer unproven $mode namespaces', () {
      final fixture = _QuickFixFixture.create();
      addTearDown(fixture.dispose);
      File(
        path.join(fixture.root.path, 'owner_contracts/lib/conditional.dart'),
      ).writeAsStringSync(
        mode == 'missingExport'
            ? "export 'src/owner.dart' show ownerComponentId;\nexport 'src/missing.dart' show ownerComponentId;"
            : mode == 'brokenExport'
            ? "export 'src/owner.dart' show ownerComponentId;\nclass Unfinished {"
            : '''
export 'src/owner.dart' show ownerComponentId;
export 'src/empty.dart' if (dart.library.io) 'src/other.dart' ${mode == 'hiddenConditionalExport' ? 'hide' : 'show'} ownerComponentId;
''',
      );
      File(
        path.join(fixture.root.path, 'owner_contracts/lib/src/empty.dart'),
      ).writeAsStringSync('');
      File(
        path.join(fixture.root.path, 'owner_contracts/lib/src/other.dart'),
      ).writeAsStringSync('''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
const ownerComponentId = CCComponentId('wrong');
''');
      final uri = switch (mode) {
        'conditionalExport' ||
        'hiddenConditionalExport' ||
        'missingExport' ||
        'brokenExport' => 'package:owner_contracts/conditional.dart',
        'packageQuery' => 'package:owner_contracts/owner_contracts.dart?query',
        'packageAbsolute' => 'package:/owner_contracts/owner_contracts.dart',
        'packageInvalidEncoding' => 'package:owner_contracts/%FF.dart',
        'relativeInvalidEncoding' => 'owner%FF.dart',
        _ => 'owner.dart?query',
      };
      File(
        path.join(fixture.consumerSource.parent.path, 'owner.dart'),
      ).writeAsStringSync(
        "export 'package:owner_contracts/owner_contracts.dart' show ownerComponentId;",
      );
      final source =
          '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/owner_contracts.dart' as api show SharedService;
import '$uri' as owner;
const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0',
  serviceDependencies: [CCServiceDependency<api.SharedService>()]);
''';
      final fixes = CCRouterQuickFixes.compute(
        source: source,
        filePath: fixture.consumerSource.path,
        offset: source.indexOf('CCServiceDependency<'),
        diagnosticCode: 'ccrouter_component_owner_dependency_missing',
        sourcePackage: 'consumer',
        contractOwners: fixture.index,
      );
      expect(fixes, hasLength(mode == 'hiddenConditionalExport' ? 1 : 0));
    });
  }

  for (final (label, declaration, expected) in [
    (
      'prefixed ID',
      "import 'package:ccrouter_contracts/ccrouter_contracts.dart' as cc;\nconst ownerComponentId = cc.CCComponentId('owner.component');",
      1,
    ),
    (
      'foreign ID',
      "class CCComponentId { const CCComponentId(this.value); final String value; }\nconst ownerComponentId = CCComponentId('owner.component');",
      0,
    ),
  ]) {
    test('parser-only Owner constant proves $label before editing', () {
      final fixture = _QuickFixFixture.create();
      addTearDown(fixture.dispose);
      File(
        path.join(fixture.root.path, 'owner_contracts/lib/src/owner.dart'),
      ).writeAsStringSync(
        '$declaration\nabstract interface class SharedService {}',
      );
      const source = '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/owner_contracts.dart' show SharedService, ownerComponentId;
const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0',
  serviceDependencies: [CCServiceDependency<SharedService>()]);
''';
      final fixes = CCRouterQuickFixes.compute(
        source: source,
        filePath: fixture.consumerSource.path,
        offset: source.indexOf('CCServiceDependency<'),
        diagnosticCode: 'ccrouter_component_owner_dependency_missing',
        sourcePackage: 'consumer',
        contractOwners: fixture.index,
      );
      expect(fixes, hasLength(expected));
    });
  }

  for (final (field, dependency) in [
    ('serviceDependencies', 'CCServiceDependency<SharedService>'),
    ('commandDependencies', 'CCCommandDependency<RunCommand>'),
  ]) {
    test('parser-only $field cannot add its own Owner', () {
      final fixture = _QuickFixFixture.create();
      addTearDown(fixture.dispose);
      for (final id in [
        "CCComponentId('owner.component')",
        'localOwner',
        'ownerComponentId',
      ]) {
        final source =
            '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/owner_contracts.dart' show SharedService, RunCommand, ownerComponentId;
const localOwner = CCComponentId('owner.component');
const component = CCComponent(id: $id, version: '1.0.0', $field: [$dependency()]);
''';
        const code = 'ccrouter_component_owner_dependency_missing';
        final issues = CCRouterSourceAnalyzer.analyze(
          source: source,
          filePath: fixture.consumerSource.path,
          packageRoot: fixture.root.path,
          packageName: 'consumer',
          contractOwners: fixture.index,
        );
        expect(
          issues.map((issue) => issue.code),
          isNot(contains(code)),
          reason: id,
        );
        final fixes = CCRouterQuickFixes.compute(
          source: source,
          filePath: fixture.consumerSource.path,
          offset: source.indexOf('$dependency('),
          diagnosticCode: code,
          sourcePackage: 'consumer',
          contractOwners: fixture.index,
        );
        expect(fixes, isEmpty, reason: id);
      }
    });
  }

  for (final constructor in [
    'CCComponent',
    'cc.CCComponent',
    'const cc.CCComponent',
  ]) {
    test('parser-only Component $constructor keeps the Owner fix', () {
      final fixture = _QuickFixFixture.create();
      addTearDown(fixture.dispose);
      final source =
          '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart' as cc;
import 'package:owner_contracts/owner_contracts.dart' show SharedService, ownerComponentId;
const component = $constructor(id: CCComponentId('consumer'), version: '1.0.0',
  serviceDependencies: [CCServiceDependency<SharedService>()]);
''';
      List<String> codes(String text) => CCRouterSourceAnalyzer.analyze(
        source: text,
        filePath: fixture.consumerSource.path,
        packageRoot: fixture.root.path,
        packageName: 'consumer',
        contractOwners: fixture.index,
      ).map((issue) => issue.code).toList();
      const code = 'ccrouter_component_owner_dependency_missing';
      expect(codes(source), contains(code));
      final fixes = CCRouterQuickFixes.compute(
        source: source,
        filePath: fixture.consumerSource.path,
        offset: source.indexOf('CCServiceDependency<'),
        diagnosticCode: code,
        sourcePackage: 'consumer',
        contractOwners: fixture.index,
      );
      expect(fixes, hasLength(1));
      final fixed = _apply(source, fixes.single);
      expect(fixed, contains('dependencies: [ownerComponentId]'));
      expect(codes(fixed), isNot(contains(code)));
    });
  }

  test('offers explicit alternatives for Route pattern conflicts', () {
    const source = '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
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

  test('defers InitTask identity fixes for unresolved nullable references', () {
    const source = '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
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

    expect(fixes, isEmpty);
  });

  test('declines a deletion that would consume a source comment', () {
    const source = '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
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
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
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
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/owner_contracts.dart' show SharedService, SecondaryService, ownerComponentId, secondaryComponentId;
const existingComponentId = CCComponentId('existing.component');

const consumerComponentId = CCComponentId('consumer.component');
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
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/owner_contracts.dart' as owner;

const consumerComponentId = CCComponentId('consumer.component');
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
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/owner_contracts.dart' show SharedService, SecondaryService, ownerComponentId, secondaryComponentId;

const consumerComponentId = CCComponentId('consumer.component');
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
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/owner_contracts.dart'
    hide ownerComponentId;

const consumerComponentId = CCComponentId('consumer.component');
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
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
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
        packageRoots: {
          'owner_contracts': ownerRoot.path,
          'ccrouter_contracts': Directory(
            '../ccrouter_contracts',
          ).absolute.path,
        },
      ),
    );
  }

  void dispose() => root.deleteSync(recursive: true);
}
