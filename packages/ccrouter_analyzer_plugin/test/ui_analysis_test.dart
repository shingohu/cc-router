import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:ccrouter_analyzer_plugin/src/contract_owner_index.dart';
import 'package:ccrouter_analyzer_plugin/src/quick_fixes.dart';
import 'package:ccrouter_analyzer_plugin/src/source_analyzer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _imports = '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_contracts/ccrouter_ui_contracts.dart';
''';
const _contract = '''
final class Props { const Props({required this.id}); final int id; }
enum Action { select }
@CCUIFragmentContract<Props, Action>(componentId: CCComponentId('orders'), id: 'orders.summary', version: '1.0.0')
abstract final class Summary {}
''';

void main() {
  late _UIFixture fixture;
  setUp(() => fixture = _UIFixture());
  tearDown(() => fixture.dispose());

  for (final alias in ['build-card', 'class', 'toString']) {
    test('UI alias $alias is diagnosed with framework identity', () async {
      final result = await fixture.resolve(
        _consumer('''
CCUIFragmentDependency<Summary>(alias: '$alias', versionRange: '^1.0.0')
'''),
      );
      expect(fixture.codes(result), contains('ccrouter_ui_alias_invalid'));
    });
  }
  test(
    'duplicate aliases and resolved contract aliases are distinguished',
    () async {
      final aliases = await fixture.resolve(
        _consumer('''
CCUIFragmentDependency<Summary>(alias: 'card', versionRange: '^1.0.0'),
CCUIFragmentDependency<Summary>(alias: 'card', versionRange: '^1.0.0')
'''),
      );
      expect(fixture.codes(aliases), contains('ccrouter_ui_alias_duplicate'));
      final contracts = await fixture.resolve(
        _consumer('''
CCUIFragmentDependency<Summary>(alias: 'card', versionRange: '^1.0.0'),
CCUIFragmentDependency<SummaryAlias>(alias: 'other', versionRange: '^1.0.0')
''', extra: 'typedef SummaryAlias = Summary;'),
      );
      expect(
        fixture.codes(contracts),
        contains('ccrouter_ui_dependency_duplicate'),
      );
    },
  );
  test('UI version ranges are checked without invoking generation', () async {
    final result = await fixture.resolve(
      _consumer('''
CCUIFragmentDependency<Summary>(alias: 'card', versionRange: 'latest')
'''),
    );
    expect(
      fixture.codes(result),
      contains('ccrouter_ui_version_range_invalid'),
    );
  });
  test(
    'invalid DTO and enhanced Action types have explicit diagnostics',
    () async {
      for (final action in [
        'class Action { const Action(this.id); final int id; }',
        'final class Action { const Action(this.id); final Object id; }',
        'final class Action { const Action(this.id); final List<int> id; }',
        'final class Action { Action(this.id); final int id; }',
        'sealed class Action { const Action(); }',
        'enum Action { select; String get label => "x"; }',
        'enum Action { select; static const label = "x"; }',
        'enum Action { select; const Action(); }',
      ]) {
        final result = await fixture.resolve(
          '$_imports${_contract.replaceFirst('enum Action { select }', action)}',
        );
        expect(fixture.codes(result), contains('ccrouter_ui_action_invalid'));
      }
    },
  );
  test(
    'immutable DTO Action and nested enum/DTO fields are accepted',
    () async {
      final result = await fixture.resolve(
        '$_imports${_contract.replaceFirst('enum Action { select }', '''
final class Action { const Action(this.id, this.detail); final String id; final Detail? detail; }
final class Detail { const Detail(this.kind); final Kind kind; }
enum Kind { recommendation, device }
''')}',
      );
      expect(
        fixture.codes(result),
        isNot(contains('ccrouter_ui_action_invalid')),
      );
    },
  );
  test(
    'plain enum and multiple keyed instances need no extra dependency',
    () async {
      final result = await fixture.resolve(
        _consumer('''
CCUIFragmentDependency<Summary>(alias: 'card', versionRange: '^1.0.0')
'''),
      );
      expect(
        fixture.codes(result).where((c) => c.startsWith('ccrouter_ui_')),
        isEmpty,
      );
    },
  );
  test(
    'foreign same-name UI annotations and constructors are ignored',
    () async {
      final result = await fixture.resolve('''
class CCUIFragmentContract<P,A> { const CCUIFragmentContract(); }
class CCUIFragmentDependency<T> { const CCUIFragmentDependency({String? alias, String? versionRange}); }
class CCComponent { const CCComponent({Object? uiDependencies}); }
@CCUIFragmentContract<int, String>()
class Marker {}
const component = CCComponent(uiDependencies: [CCUIFragmentDependency<Marker>(alias: 'bad-alias', versionRange: 'latest')]);
''');
      expect(fixture.codes(result), isEmpty);
    },
  );
  test('partial and ambiguous source buffers do not guess UI types', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source:
          "$_imports import 'unknown.dart'; const x = CCComponent(uiDependencies: [CCUIFragmentDependency<Missing>(alias: value,",
      filePath: fixture.file,
      packageRoot: fixture.root.path,
      packageName: 'consumer',
    );
    expect(
      diagnostics.where((d) => d.code.startsWith('ccrouter_ui_')),
      isEmpty,
    );
  });
  test('components cannot import UI Host or Generated SPI; tests are exempt', () {
    for (final barrel in [
      'ccrouter_ui_host.dart',
      'ccrouter_ui_generated.dart',
    ]) {
      final source =
          "export 'fallback.dart' if (dart.library.io) 'package:ccrouter_ui/$barrel';";
      final issues = CCRouterSourceAnalyzer.analyze(
        source: source,
        filePath: fixture.file,
        packageRoot: fixture.root.path,
        packageName: 'consumer',
      );
      expect(issues.map((d) => d.code), contains('ccrouter_ui_spi_access'));
      expect(
        CCRouterSourceAnalyzer.analyze(
          source: source,
          filePath: p.join(fixture.root.path, 'test/probe.dart'),
          packageRoot: fixture.root.path,
          packageName: 'consumer',
        ),
        isEmpty,
      );
    }
  });
  test(
    'Renderer signature compares exact contract types and ignores foreign inputs',
    () async {
      final result = await fixture.resolve('''
$_imports
import 'package:flutter/widgets.dart';
import 'package:ccrouter_ui/ccrouter_ui.dart';
$_contract
@CCUIFragmentRenderer(Summary)
Widget render(CCUIFragmentRenderInput<String, Action> input) => const Widget();
''');
      expect(fixture.codes(result), contains('ccrouter_ui_renderer_invalid'));
      final valid = await fixture.resolve(
        result.content.replaceFirst(
          'RenderInput<String,',
          'RenderInput<Props,',
        ),
      );
      expect(
        fixture.codes(valid).where((c) => c.startsWith('ccrouter_ui_')),
        isEmpty,
      );
    },
  );
  test(
    'metadata UI owner supports a safe imported-constant Quick Fix',
    () async {
      final result = await fixture.resolve('''
$_imports
import 'package:owner_contracts/owner_contracts.dart';
const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0',
 optionalDependencies: [orderOwner],
 uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'card', versionRange: '^1.0.0')]);
''');
      final owners = CCRouterContractOwnerIndexCache().resolve(fixture.file);
      final issues = fixture.issues(result, owners: owners);
      final issue = issues.singleWhere(
        (d) => d.code == 'ccrouter_component_owner_dependency_missing',
      );
      final fixes = CCRouterQuickFixes.compute(
        source: result.content,
        filePath: fixture.file,
        offset: issue.offset,
        diagnosticCode: issue.code,
        sourcePackage: 'consumer',
        contractOwners: owners,
        resolvedUnit: result.unit,
      );
      expect(fixes, isNotEmpty);
      final fix = fixes.first;
      final fixed = await fixture.resolve(
        result.content.replaceRange(
          fix.offset,
          fix.offset + fix.length,
          fix.replacement,
        ),
      );
      expect(
        fixture
            .issues(fixed, owners: owners)
            .where((d) => d.code == issue.code),
        isEmpty,
      );
    },
  );
  test('supported range literals defer to the authoritative grammar', () async {
    for (final range in [
      '',
      '*',
      '^1.0.0',
      '~1.0.0',
      '1.0.0',
      '=1.0.0',
      '>=1.0.0 <2.0.0',
      '^1.0.0-beta.1',
    ]) {
      final result = await fixture.resolve(
        _consumer(
          "CCUIFragmentDependency<Summary>(alias: 'card', versionRange: '$range')",
        ),
      );
      expect(
        fixture.codes(result),
        isNot(contains('ccrouter_ui_version_range_invalid')),
      );
    }
  });
  test('UI owner metadata removal and legacy records defer safely', () async {
    final result = await fixture.resolve(
      "$_imports import 'package:owner_contracts/owner_contracts.dart'; const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0', uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'card', versionRange: '*')]);",
    );
    final cache = CCRouterContractOwnerIndexCache();
    expect(
      fixture
          .issues(result, owners: cache.resolve(fixture.file))
          .map((d) => d.code),
      contains('ccrouter_component_owner_dependency_missing'),
    );
    final metadataPath = p.join(
      fixture.root.path,
      'owner/lib/src/ccrouter_generated/metadata/ccrouter_package.json',
    );
    final metadata = jsonDecode(File(metadataPath).readAsStringSync());
    metadata['schemaVersion'] = 4;
    metadata['metadata'][0]['uiSchemaVersion'] = 2;
    metadata['metadata'][0]['uiContracts'][0]['uiSchemaVersion'] = 2;
    File(metadataPath).writeAsStringSync(jsonEncode(metadata));
    cache.invalidate(metadataPath);
    expect(
      fixture
          .issues(result, owners: cache.resolve(fixture.file))
          .map((d) => d.code),
      contains('ccrouter_component_owner_dependency_missing'),
    );
    metadata['metadata'][0]['uiContracts'][0].remove('declaration');
    File(metadataPath).writeAsStringSync(jsonEncode(metadata));
    cache.invalidate(metadataPath);
    expect(
      fixture
          .issues(result, owners: cache.resolve(fixture.file))
          .map((d) => d.code),
      isNot(contains('ccrouter_component_owner_dependency_missing')),
    );
    File(metadataPath).deleteSync();
    cache.invalidate(metadataPath);
    expect(
      fixture
          .issues(result, owners: cache.resolve(fixture.file))
          .map((d) => d.code),
      isNot(contains('ccrouter_component_owner_dependency_missing')),
    );
    cache.clear();
  });
  test('UI Owner Quick Fix never guesses hidden constants or edits spreads', () async {
    for (final declaration in [
      "import 'package:owner_contracts/owner_contracts.dart' show OrderFragment;",
      "import 'package:owner_contracts/owner_contracts.dart' hide orderOwner;",
    ]) {
      final result = await fixture.resolve(
        "$_imports $declaration const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0', uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'card', versionRange: '*')]);",
      );
      final owners = CCRouterContractOwnerIndexCache().resolve(fixture.file);
      final issue = fixture
          .issues(result, owners: owners)
          .singleWhere(
            (d) => d.code == 'ccrouter_component_owner_dependency_missing',
          );
      expect(
        CCRouterQuickFixes.compute(
          source: result.content,
          filePath: fixture.file,
          offset: issue.offset,
          diagnosticCode: issue.code,
          sourcePackage: 'consumer',
          contractOwners: owners,
          resolvedUnit: result.unit,
        ),
        isEmpty,
      );
    }
    final result = await fixture.resolve(
      "$_imports import 'package:owner_contracts/owner_contracts.dart'; const ids = <CCComponentId>[]; const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0', dependencies: [...ids], uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'card', versionRange: '*')]);",
    );
    expect(
      fixture
          .issues(
            result,
            owners: CCRouterContractOwnerIndexCache().resolve(fixture.file),
          )
          .map((d) => d.code),
      isNot(contains('ccrouter_component_owner_dependency_missing')),
    );
  });
  test(
    'prefixed and transitive UI symbols preserve framework identity',
    () async {
      fixture.write(
        'lib/barrel.dart',
        "export 'package:ccrouter_contracts/ccrouter_ui_contracts.dart';",
      );
      final result = await fixture.resolve(
        "import 'package:ccrouter_contracts/ccrouter_contracts.dart'; import 'barrel.dart' as ui; class Marker {} const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0', uiDependencies: [ui.CCUIFragmentDependency<Marker>(alias: 'bad-alias', versionRange: '*')]);",
      );
      expect(fixture.codes(result), contains('ccrouter_ui_alias_invalid'));
    },
  );
  test(
    'UI SPI references through a public barrel use canonical identity',
    () async {
      fixture.write(
        'ui/lib/src/ui_fragment.dart',
        'class CCUIHostAssembly {} class CCUIRenderer {}',
      );
      fixture.write(
        'lib/barrel.dart',
        "export 'package:ccrouter_ui/src/ui_fragment.dart';",
      );
      final result = await fixture.resolve(
        "import 'barrel.dart' as ui; ui.CCUIHostAssembly? assembly; ui.CCUIRenderer? renderer;",
      );
      expect(
        fixture.codes(result).where((c) => c == 'ccrouter_ui_spi_access'),
        hasLength(2),
      );
    },
  );
  test(
    'foreign component constructors never inherit UI dependency semantics',
    () async {
      final result = await fixture.resolve(
        "$_imports import 'package:owner_contracts/owner_contracts.dart'; class CCComponent { const CCComponent({Object? uiDependencies}); } const component = CCComponent(uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'bad-alias', versionRange: '*')]);",
      );
      final owners = CCRouterContractOwnerIndexCache().resolve(fixture.file);
      expect(
        fixture
            .issues(result, owners: owners)
            .where(
              (d) =>
                  d.code.startsWith('ccrouter_ui_') ||
                  d.code == 'ccrouter_component_owner_dependency_missing',
            ),
        isEmpty,
      );
    },
  );
  test(
    'UI self-consumption cannot receive a cyclic Owner dependency fix',
    () async {
      final result = await fixture.resolve(
        "$_imports import 'package:owner_contracts/owner_contracts.dart'; const component = CCComponent(id: CCComponentId('orders'), version: '1.0.0', uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'card', versionRange: '*')]);",
      );
      final owners = CCRouterContractOwnerIndexCache().resolve(fixture.file);
      expect(
        fixture.issues(result, owners: owners).map((d) => d.code),
        isNot(contains('ccrouter_component_owner_dependency_missing')),
      );
      // The authoritative Generator rejects this declaration: use a local Widget.
    },
  );
  for (final name in ['CCComponent', 'wrapComponent']) {
    test('ordinary functions named $name cannot receive UI fixes', () async {
      final result = await fixture.resolve('''
import 'package:ccrouter_contracts/ccrouter_contracts.dart' as cc;
import 'package:ccrouter_contracts/ccrouter_ui_contracts.dart';
import 'package:owner_contracts/owner_contracts.dart';
cc.CCComponent $name({Object? uiDependencies}) => const cc.CCComponent(
  id: cc.CCComponentId('consumer'), version: '1.0.0');
final component = $name(uiDependencies: [
  CCUIFragmentDependency<OrderFragment>(alias: 'bad-alias', versionRange: 'latest')]);
''');
      expect(result.diagnostics, isEmpty);
      final owners = CCRouterContractOwnerIndexCache().resolve(fixture.file);
      expect(fixture.issues(result, owners: owners), isEmpty);
      expect(
        CCRouterQuickFixes.compute(
          source: result.content,
          filePath: fixture.file,
          offset: result.content.indexOf(
            'CCUIFragmentDependency<OrderFragment>',
          ),
          diagnosticCode: 'ccrouter_component_owner_dependency_missing',
          sourcePackage: 'consumer',
          contractOwners: owners,
          resolvedUnit: result.unit,
        ),
        isEmpty,
      );
    });
  }
  test(
    'UI dependency factories do not inherit constructor semantics',
    () async {
      final result = await fixture.resolve('''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_contracts/ccrouter_ui_contracts.dart' as ui;
import 'package:owner_contracts/owner_contracts.dart';
ui.CCUIFragmentDependency<T> CCUIFragmentDependency<T extends Object>({
  required String alias, required String versionRange,
}) => ui.CCUIFragmentDependency<T>(alias: 'card', versionRange: '*');
final component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0',
  uiDependencies: [CCUIFragmentDependency<OrderFragment>(
    alias: 'bad-alias', versionRange: 'latest')]);
''');
      expect(result.diagnostics, isEmpty);
      expect(
        fixture.issues(
          result,
          owners: CCRouterContractOwnerIndexCache().resolve(fixture.file),
        ),
        isEmpty,
      );
    },
  );
  test('UI typedef constructors retain canonical identity', () async {
    final result = await fixture.resolve('''
import 'package:ccrouter_contracts/ccrouter_contracts.dart' as cc;
import 'package:ccrouter_contracts/ccrouter_ui_contracts.dart' as ui;
typedef Component = cc.CCComponent;
typedef Dependency<T extends Object> = ui.CCUIFragmentDependency<T>;
class Marker {}
const component = Component(id: cc.CCComponentId('consumer'), version: '1.0.0',
  uiDependencies: [Dependency<Marker>(alias: 'bad-alias', versionRange: '*')]);
''');
    expect(result.diagnostics, isEmpty);
    expect(fixture.codes(result), contains('ccrouter_ui_alias_invalid'));
  });
  test(
    'same-name UI contracts in different libraries retain both Owners',
    () async {
      fixture.write(
        'owner/lib/second.dart',
        File(
          p.join(fixture.root.path, 'owner/lib/contract.dart'),
        ).readAsStringSync().replaceFirst('orders.card', 'orders.other'),
      );
      final metadataFile = File(
        p.join(
          fixture.root.path,
          'owner/lib/src/ccrouter_generated/metadata/ccrouter_package.json',
        ),
      );
      final metadata = jsonDecode(metadataFile.readAsStringSync()) as Map;
      (metadata['metadata'][0]['uiContracts'] as List).add({
        'componentId': 'orders',
        'id': 'orders.other',
        'declaration': {
          'packageUri': 'package:owner_contracts/second.dart',
          'symbol': 'OrderFragment',
        },
      });
      metadataFile.writeAsStringSync(jsonEncode(metadata));
      final owners = CCRouterContractOwnerIndexCache().resolve(fixture.file);
      for (final library in ['contract.dart', 'second.dart']) {
        final result = await fixture.resolve('''
$_imports
import 'package:owner_contracts/$library';
const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0',
  uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'card', versionRange: '*')]);
''');
        expect(result.diagnostics, isEmpty);
        final issue = fixture
            .issues(result, owners: owners)
            .singleWhere(
              (d) => d.code == 'ccrouter_component_owner_dependency_missing',
            );
        final fix = CCRouterQuickFixes.compute(
          source: result.content,
          filePath: fixture.file,
          offset: issue.offset,
          diagnosticCode: issue.code,
          sourcePackage: 'consumer',
          contractOwners: owners,
          resolvedUnit: result.unit,
        ).single;
        final fixed = await fixture.resolve(
          result.content.replaceRange(
            fix.offset,
            fix.offset + fix.length,
            fix.replacement,
          ),
        );
        expect(fixed.diagnostics, isEmpty);
        expect(fixture.issues(fixed, owners: owners), isEmpty);
      }
      // Package-only evidence cannot distinguish these declaration libraries.
      expect(
        owners.resolve(
          kind: CCRouterContractKind.uiFragment,
          contractSymbol: 'OrderFragment',
          prefix: null,
          importPrefixes: {
            '': {'owner_contracts'},
          },
          sourcePackage: 'consumer',
        ),
        isNull,
      );
    },
  );
  for (final variant in ['componentAlias', 'dependencyAlias', 'bothAliases']) {
    test('UI Owner fix round-trips with $variant', () async {
      final component = variant == 'dependencyAlias'
          ? 'CCComponent'
          : 'Component';
      final dependency = variant == 'componentAlias'
          ? 'CCUIFragmentDependency'
          : 'Dependency';
      final result = await fixture.resolve('''
$_imports
import 'package:owner_contracts/owner_contracts.dart';
typedef Component = CCComponent;
typedef Dependency<T extends Object> = CCUIFragmentDependency<T>;
const component = $component(id: CCComponentId('consumer'), version: '1.0.0',
  uiDependencies: [$dependency<OrderFragment>(alias: 'card', versionRange: '*')]);
''');
      final owners = CCRouterContractOwnerIndexCache().resolve(fixture.file);
      await _expectOwnerFix(fixture, result, owners);
    });
  }
  for (final libraryUri in <Object?>[
    'package:owner_contracts/contract.dart',
    null,
    'package:consumer/contract.dart',
    'package:owner_contracts/../contract.dart',
    'package:owner_contracts/contract.dart?invalid',
    'not a package URI',
    123,
  ]) {
    test('part UI Owner validates library identity $libraryUri', () async {
      final original = File(
        p.join(fixture.root.path, 'owner/lib/contract.dart'),
      ).readAsStringSync();
      fixture.write(
        'owner/lib/marker.dart',
        "part of 'contract.dart';\n${original.replaceFirst(_imports, '')}",
      );
      fixture.write(
        'owner/lib/contract.dart',
        "$_imports\npart 'marker.dart';",
      );
      final metadataFile = File(
        p.join(
          fixture.root.path,
          'owner/lib/src/ccrouter_generated/metadata/ccrouter_package.json',
        ),
      );
      final metadata = jsonDecode(metadataFile.readAsStringSync()) as Map;
      final declaration =
          metadata['metadata'][0]['uiContracts'][0]['declaration'] as Map;
      declaration['packageUri'] = 'package:owner_contracts/marker.dart';
      if (libraryUri != null) declaration['libraryUri'] = libraryUri;
      metadataFile.writeAsStringSync(jsonEncode(metadata));
      final result = await fixture.resolve('''
$_imports
import 'package:owner_contracts/owner_contracts.dart';
const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0',
  uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'card', versionRange: '*')]);
''');
      expect(result.diagnostics, isEmpty);
      final owners = CCRouterContractOwnerIndexCache().resolve(fixture.file);
      if (libraryUri == 'package:owner_contracts/contract.dart') {
        await _expectOwnerFix(fixture, result, owners);
      } else {
        expect(fixture.issues(result, owners: owners), isEmpty);
        if (libraryUri != null) {
          expect(
            owners.resolve(
              kind: CCRouterContractKind.uiFragment,
              contractSymbol: 'OrderFragment',
              prefix: null,
              importPrefixes: {
                '': {'owner_contracts'},
              },
              sourcePackage: 'consumer',
            ),
            isNull,
          );
        }
      }
    });
  }
  for (final inMethod in [false, true]) {
    test(
      'nested Renderer in ${inMethod ? 'method' : 'function'} is rejected',
      () async {
        final result = await fixture.resolve('''
$_imports
import 'package:flutter/widgets.dart';
import 'package:ccrouter_ui/ccrouter_ui.dart';
$_contract
${inMethod ? 'class View {' : ''}
void outer() {
  @CCUIFragmentRenderer(Summary)
  Widget render(CCUIFragmentRenderInput<Props, Action> input) => const Widget();
  render(const CCUIFragmentRenderInput<Props, Action>());
}
${inMethod ? '}' : ''}
''');
        expect(result.diagnostics, isEmpty);
        expect(fixture.codes(result), contains('ccrouter_ui_renderer_invalid'));
      },
    );
  }
}

Future<void> _expectOwnerFix(
  _UIFixture fixture,
  ResolvedUnitResult result,
  CCRouterContractOwnerIndex owners,
) async {
  expect(result.diagnostics, isEmpty);
  final issue = fixture
      .issues(result, owners: owners)
      .singleWhere(
        (d) => d.code == 'ccrouter_component_owner_dependency_missing',
      );
  final fix = CCRouterQuickFixes.compute(
    source: result.content,
    filePath: fixture.file,
    offset: issue.offset,
    diagnosticCode: issue.code,
    sourcePackage: 'consumer',
    contractOwners: owners,
    resolvedUnit: result.unit,
  ).single;
  expect(fix.replacement, contains('orderOwner'));
  final fixed = await fixture.resolve(
    result.content.replaceRange(
      fix.offset,
      fix.offset + fix.length,
      fix.replacement,
    ),
  );
  expect(fixed.diagnostics, isEmpty);
  expect(fixture.issues(fixed, owners: owners), isEmpty);
}

String _consumer(String dependencies, {String extra = ''}) =>
    '''
$_imports
$_contract
$extra
const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0',
 dependencies: [CCComponentId('orders')], uiDependencies: [$dependencies]);
''';

final class _UIFixture {
  _UIFixture() {
    write(
      'pubspec.yaml',
      'name: consumer\nenvironment:\n  sdk: ^3.10.0\ndependencies:\n  ccrouter: any\n',
    );
    write('lib/probe.dart', '');
    write('flutter/lib/widgets.dart', 'class Widget { const Widget(); }');
    write(
      'ui/lib/src/ui_fragment.dart',
      'class CCUIFragmentRenderInput<P,A> { const CCUIFragmentRenderInput(); }',
    );
    write('ui/lib/ccrouter_ui.dart', "export 'src/ui_fragment.dart';");
    write('owner/lib/contract.dart', '''
$_imports
const orderOwner = CCComponentId('orders');
final class Props { const Props(this.id); final int id; }
enum Action { select }
@CCUIFragmentContract<Props, Action>(componentId: orderOwner, id: 'orders.card', version: '1.0.0')
abstract final class OrderFragment {}
''');
    write('owner/lib/owner_contracts.dart', "export 'contract.dart';");
    write(
      'owner/lib/src/ccrouter_generated/metadata/ccrouter_package.json',
      jsonEncode({
        'metadata': [
          {
            'package': 'owner_contracts',
            'source': 'lib/contract.dart',
            'uiSchemaVersion': 1,
            'uiContracts': [
              {
                'componentId': 'orders',
                'id': 'orders.card',
                'declaration': {
                  'packageUri': 'package:owner_contracts/contract.dart',
                  'symbol': 'OrderFragment',
                },
              },
            ],
          },
        ],
        'capabilityCatalog': {'records': []},
      }),
    );
    write(
      '.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          for (final entry in {
            'consumer': root.path,
            'ccrouter_contracts': Directory(
              '../ccrouter_contracts',
            ).absolute.path,
            'owner_contracts': p.join(root.path, 'owner'),
            'ccrouter_ui': p.join(root.path, 'ui'),
            'flutter': p.join(root.path, 'flutter'),
          }.entries)
            {
              'name': entry.key,
              'rootUri': Directory(entry.value).uri.toString(),
              'packageUri': 'lib/',
              'languageVersion': '3.10',
            },
        ],
      }),
    );
    collection = AnalysisContextCollection(includedPaths: [root.path]);
  }
  final root = Directory.systemTemp.createTempSync('ccrouter-ui-plugin-');
  late final AnalysisContextCollection collection;
  String get file => p.join(root.path, 'lib/probe.dart');
  void write(String name, String source) => (File(
    p.join(root.path, name),
  )..createSync(recursive: true)).writeAsStringSync(source);
  Future<ResolvedUnitResult> resolve(String source) async {
    File(file).writeAsStringSync(source);
    final context = collection.contextFor(file);
    context.changeFile(file);
    await context.applyPendingFileChanges();
    return await context.currentSession.getResolvedUnit(file)
        as ResolvedUnitResult;
  }

  List<CCRouterAnalyzerDiagnostic> issues(
    ResolvedUnitResult result, {
    CCRouterContractOwnerIndex? owners,
  }) => CCRouterSourceAnalyzer.analyze(
    source: result.content,
    filePath: file,
    packageRoot: root.path,
    packageName: 'consumer',
    resolvedUnit: result.unit,
    contractOwners: owners,
  );
  List<String> codes(ResolvedUnitResult result) =>
      issues(result).map((d) => d.code).toList();
  Future<void> dispose() async {
    await collection.dispose();
    root.deleteSync(recursive: true);
  }
}
