import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:ccrouter_analyzer_plugin/src/contract_owner_index.dart';
import 'package:ccrouter_analyzer_plugin/src/quick_fixes.dart';
import 'package:ccrouter_analyzer_plugin/src/project_context.dart';
import 'package:ccrouter_analyzer_plugin/src/source_analyzer.dart'
    show CCRouterAnalyzerDiagnostic, CCRouterSourceAnalyzer;
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

  test(
    'UI Owner cache keeps distinct Libraries that share a named part',
    () async {
      for (final name in ['first', 'second']) {
        fixture.write('owner/lib/$name.dart', '''
library shared;
$_imports
part 'shared_marker.dart';
const ownerId = CCComponentId('orders');
const contractId = 'orders.$name';
''');
      }
      fixture.write('owner/lib/shared_marker.dart', '''
part of shared;
final class SharedProps { const SharedProps(); }
enum SharedAction { select }
@CCUIFragmentContract<SharedProps, SharedAction>(componentId: ownerId, id: contractId)
abstract final class Marker {}
''');
      fixture.write(
        'owner/lib/src/ccrouter_generated/metadata/ccrouter_package.json',
        jsonEncode({
          'schemaVersion': 3,
          'metadata': [
            {
              'package': 'owner_contracts',
              'uiSchemaVersion': 1,
              'uiContracts': [
                for (final name in ['first', 'second'])
                  {
                    'componentId': 'orders',
                    'id': 'orders.$name',
                    'declaration': {
                      'symbol': 'Marker',
                      'packageUri':
                          'package:owner_contracts/shared_marker.dart',
                      'libraryUri': 'package:owner_contracts/$name.dart',
                    },
                  },
              ],
            },
          ],
        }),
      );
      for (final name in ['first', 'second']) {
        final source = _consumer('CCUIFragmentDependency<owner.Marker>()')
            .replaceFirst(
              _imports,
              "$_imports\nimport 'package:owner_contracts/$name.dart' as owner;",
            )
            .replaceFirst(
              "dependencies: [CCComponentId('orders')]",
              'dependencies: []',
            );
        final result = await fixture.resolve(source);
        expect(result.diagnostics, isEmpty);
        final owners = CCRouterContractOwnerIndexCache().resolve(fixture.file);
        expect(
          _coreOwnerIssues(fixture, result, owners),
          hasLength(1),
          reason: name,
        );
      }
    },
  );

  for (final kind in ['Service', 'Command']) {
    test(
      '$kind part Owner metadata proves the defining Library separately from location',
      () async {
        fixture.write('owner/lib/core_root.dart', '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
part 'core_part.dart';
const ownerId = CCComponentId('orders');
''');
        fixture.write('owner/lib/core_part.dart', '''
part of 'core_root.dart';
@CC${kind}Contract(componentId: ownerId, id: 'orders.shared', alias: 'shared')
${kind == 'Service' ? 'abstract interface class Shared {}' : 'final class Shared implements CCCommand<void> { const Shared(); }'}
''');
        for (final library in <Object?>[
          'package:owner_contracts/core_root.dart',
          null,
          'package:owner_contracts/core_root.dart?query',
          'package:other/root.dart',
          123,
        ]) {
          fixture.write(
            'owner/lib/src/ccrouter_generated/metadata/ccrouter_package.json',
            jsonEncode({
              'capabilityCatalog': {
                'records': [
                  {
                    'kind': kind.toLowerCase(),
                    'componentId': 'orders',
                    'contract': {
                      'symbol': 'Shared',
                      'packageUri': 'package:owner_contracts/core_part.dart',
                      if (library != null) 'libraryUri': library,
                    },
                  },
                ],
              },
            }),
          );
          final source = _consumer('CCUIFragmentDependency<Summary>()')
              .replaceFirst(
                _imports,
                "$_imports\nimport 'package:owner_contracts/core_root.dart' as owner;",
              )
              .replaceFirst(
                "dependencies: [CCComponentId('orders')]",
                'dependencies: []',
              )
              .replaceFirst(
                'uiDependencies:',
                '${kind.toLowerCase()}Dependencies: [CC${kind}Dependency<owner.Shared>()], uiDependencies:',
              );
          final result = await fixture.resolve(source);
          expect(result.diagnostics, isEmpty);
          final owners = CCRouterContractOwnerIndexCache().resolve(
            fixture.file,
          );
          final expected = library == 'package:owner_contracts/core_root.dart'
              ? 1
              : 0;
          expect(
            _coreOwnerIssues(fixture, result, owners),
            hasLength(expected),
            reason: '$library',
          );
          final fixes = CCRouterQuickFixes.compute(
            source: source,
            filePath: fixture.file,
            offset: source.indexOf('CC${kind}Dependency<'),
            diagnosticCode: 'ccrouter_component_owner_dependency_missing',
            contractOwners: owners,
            sourcePackage: 'consumer',
            resolvedUnit: result.unit,
          );
          expect(fixes, hasLength(expected), reason: '$library');
        }
      },
    );
    test(
      '$kind Owner metadata rejects query and fragment source identities',
      () async {
        fixture.write('owner/lib/core.dart', '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
const ownerId = CCComponentId('orders');
@CC${kind}Contract(componentId: ownerId, id: 'orders.shared', alias: 'shared')
${kind == 'Service' ? 'abstract interface class Shared {}' : 'final class Shared implements CCCommand<void> { const Shared(); }'}
''');
        for (final suffix in ['', '?query', '#fragment']) {
          fixture.write(
            'owner/lib/src/ccrouter_generated/metadata/ccrouter_package.json',
            jsonEncode({
              'capabilityCatalog': {
                'records': [
                  {
                    'kind': kind.toLowerCase(),
                    'componentId': 'orders',
                    'contract': {
                      'symbol': 'Shared',
                      'packageUri': 'package:owner_contracts/core.dart$suffix',
                    },
                  },
                ],
              },
            }),
          );
          final source = _consumer('CCUIFragmentDependency<Summary>()')
              .replaceFirst(
                _imports,
                "$_imports\nimport 'package:owner_contracts/core.dart' as owner;",
              )
              .replaceFirst(
                "dependencies: [CCComponentId('orders')]",
                'dependencies: []',
              )
              .replaceFirst(
                'uiDependencies:',
                '${kind.toLowerCase()}Dependencies: [CC${kind}Dependency<owner.Shared>()], uiDependencies:',
              );
          final result = await fixture.resolve(source);
          expect(result.diagnostics, isEmpty);
          final owners = CCRouterContractOwnerIndexCache().resolve(
            fixture.file,
          );
          expect(
            _coreOwnerIssues(fixture, result, owners),
            hasLength(suffix.isEmpty ? 1 : 0),
            reason: suffix,
          );
        }
      },
    );
    test(
      '$kind Owner cache retains same-name Contracts from distinct Libraries',
      () async {
        for (final name in ['first', 'second']) {
          fixture.write('owner/lib/$name.dart', '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
const ownerId = CCComponentId('orders');
@CC${kind}Contract(componentId: ownerId, id: 'orders.$name', alias: '$name')
${kind == 'Service' ? 'abstract interface class Shared {}' : 'final class Shared implements CCCommand<void> { const Shared(); }'}
''');
        }
        fixture.write(
          'owner/lib/src/ccrouter_generated/metadata/ccrouter_package.json',
          jsonEncode({
            'capabilityCatalog': {
              'records': [
                for (final name in ['first', 'second'])
                  {
                    'kind': kind.toLowerCase(),
                    'componentId': 'orders',
                    'contract': {
                      'symbol': 'Shared',
                      'packageUri': 'package:owner_contracts/$name.dart',
                    },
                  },
              ],
            },
          }),
        );
        for (final name in ['first', 'second']) {
          final source = _consumer('CCUIFragmentDependency<Summary>()')
              .replaceFirst(
                _imports,
                "$_imports\nimport 'package:owner_contracts/$name.dart' as owner;",
              )
              .replaceFirst(
                "dependencies: [CCComponentId('orders')]",
                "dependencies: []",
              )
              .replaceFirst(
                'uiDependencies:',
                '${kind.toLowerCase()}Dependencies: [CC${kind}Dependency<owner.Shared>()], uiDependencies:',
              );
          final result = await fixture.resolve(source);
          expect(result.diagnostics, isEmpty);
          final owners = CCRouterContractOwnerIndexCache().resolve(
            fixture.file,
          );
          expect(
            _coreOwnerIssues(fixture, result, owners),
            hasLength(1),
            reason: name,
          );
          final fixes = CCRouterQuickFixes.compute(
            source: source,
            filePath: fixture.file,
            offset: source.indexOf('CC${kind}Dependency<'),
            diagnosticCode: 'ccrouter_component_owner_dependency_missing',
            contractOwners: owners,
            sourcePackage: 'consumer',
            resolvedUnit: result.unit,
          );
          expect(fixes, hasLength(1), reason: name);
          expect(fixes.single.replacement, contains('owner.ownerId'));
        }
      },
    );
  }

  test(
    'timeout checks prove SDK Duration identity and defer shadowed names',
    () async {
      for (final (declaration, timeout, invalid) in [
        (
          'class Duration { static const zero = core.Duration(seconds: 1); }',
          'Duration.zero',
          false,
        ),
        (
          'extension Duration on Object { static const zero = core.Duration(seconds: 1); }',
          'Duration.zero',
          false,
        ),
        ('typedef Delay = core.Duration;', 'Delay.zero', true),
        ('typedef Delay = core.Duration;', 'Delay(microseconds: 0)', true),
        ('', 'core.Duration.zero', true),
        ('', 'core.Duration(seconds: 1)', false),
      ]) {
        final source =
            _consumer(
              'CCUIFragmentDependency<Summary>()',
              extra:
                  '''
$declaration
@CCInitTask(id: 'startup.run', gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.optional, timeout: $timeout)
void run() {}
''',
            ).replaceFirst(
              _imports,
              "$_imports\nimport 'dart:core';\nimport 'dart:core' as core;",
            );
        final result = await fixture.resolve(source);
        expect(result.diagnostics, isEmpty);
        expect(
          fixture.codes(result).contains('ccrouter_timeout_invalid'),
          invalid,
          reason: timeout,
        );
        if (declaration.startsWith('class Duration') ||
            declaration.startsWith('extension Duration')) {
          final parsed = CCRouterSourceAnalyzer.analyze(
            source: source,
            filePath: fixture.file,
            packageRoot: fixture.root.path,
            packageName: 'consumer',
          );
          expect(
            parsed.map((issue) => issue.code),
            isNot(contains('ccrouter_timeout_invalid')),
          );
        }
      }
    },
  );

  test(
    'imported Duration holders cannot impersonate SDK zero in parser checks',
    () async {
      fixture.write(
        'lib/duration_holder.dart',
        "import 'dart:core' as core;\nclass Duration { static const zero = core.Duration(seconds: 1); }",
      );
      final source = _consumer(
        'CCUIFragmentDependency<Summary>()',
        extra: '''
@CCInitTask(id: 'startup.run', gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.optional, timeout: Duration.zero)
void run() {}
''',
      ).replaceFirst(_imports, "$_imports\nimport 'duration_holder.dart';");
      final result = await fixture.resolve(source);
      expect(result.diagnostics, isEmpty);
      expect(
        fixture.codes(result),
        isNot(contains('ccrouter_timeout_invalid')),
      );
      final parsed = CCRouterSourceAnalyzer.analyze(
        source: source,
        filePath: fixture.file,
        packageRoot: fixture.root.path,
        packageName: 'consumer',
      );
      expect(
        parsed.map((issue) => issue.code),
        isNot(contains('ccrouter_timeout_invalid')),
      );
    },
  );

  test(
    'Gate constructor aliases retain framework identity for literal validation',
    () async {
      final source = _consumer(
        'CCUIFragmentDependency<Summary>()',
        extra: '''
typedef OpenGate = CCInitTaskGate;
@CCInitTask(id: 'startup.run', gate: OpenGate('Bad Gate'), failurePolicy: CCInitTaskFailurePolicy.optional)
void run() {}
''',
      );
      final result = await fixture.resolve(source);
      expect(result.diagnostics, isEmpty);
      expect(fixture.codes(result), contains('ccrouter_identifier_invalid'));
    },
  );

  final argumentCases =
      (jsonDecode(
                File(
                  '../ccrouter_test/fixtures/annotation_argument_cases.json',
                ).readAsStringSync(),
              )
              as List)
          .cast<Map<String, dynamic>>();
  for (final entry in argumentCases) {
    test('IDE argument semantics: ${entry['name']}', () async {
      final annotation = switch (entry['kind']) {
        'routeContract' => '@CCRouteContract<void>',
        'route' => '@CCRoute<void>',
        _ => '@CCInitTask',
      };
      final declaration = switch (entry['kind']) {
        'routeContract' =>
          "$annotation(componentId: CCComponentId('owner'), id: 'probe.route', ${entry['arguments']})\nabstract class ProbeRouteContract { const ProbeRouteContract(); }",
        'route' =>
          "$annotation(id: 'probe.route', ${entry['arguments']})\nfinal class Probe { const Probe(); }",
        _ =>
          "$annotation(${entry['arguments']}, gate: CCInitTaskGate.appStarted, failurePolicy: CCInitTaskFailurePolicy.optional)\nvoid initialize() {}",
      };
      final source = _consumer(
        'CCUIFragmentDependency<Summary>()',
        extra:
            '''
const CCRoutePattern? absentPattern = null;
const CCInitTaskContract? absentTask = null;
const String? absentId = null;
const sharedTask = CCInitTaskContract(id: 'probe.shared');
$declaration
''',
      );
      final result = await fixture.resolve(source);
      expect(result.diagnostics, isEmpty);
      const code = 'ccrouter_annotation_arguments_conflict';
      expect(fixture.codes(result).contains(code), entry['conflict']);
      final fixes = CCRouterQuickFixes.compute(
        source: source,
        filePath: fixture.file,
        offset: source.indexOf(annotation),
        diagnosticCode: code,
        resolvedUnit: result.unit,
      );
      expect(fixes, hasLength(entry['fixes']));
      for (final fix in fixes) {
        final fixed = source.replaceRange(
          fix.offset,
          fix.offset + fix.length,
          fix.replacement,
        );
        final repaired = await fixture.resolve(fixed);
        expect(repaired.diagnostics, isEmpty);
        expect(fixture.codes(repaired), isNot(contains(code)));
      }
      final parsed = CCRouterSourceAnalyzer.analyze(
        source: source,
        filePath: fixture.file,
        packageRoot: fixture.root.path,
        packageName: 'consumer',
      );
      expect(
        parsed.any((issue) => issue.code == code),
        entry['parserConflict'],
      );
      final parsedFixes = CCRouterQuickFixes.compute(
        source: source,
        filePath: fixture.file,
        offset: source.indexOf(annotation),
        diagnosticCode: code,
      );
      expect(
        parsedFixes,
        hasLength(
          entry['parserConflict'] && entry['fixes'] > 0 ? entry['fixes'] : 0,
        ),
      );
    });
  }

  for (final kind in ['Service', 'Command']) {
    test('$kind self Owner cannot be repaired with a self dependency', () async {
      final owners = CCRouterContractOwnerIndex(
        owners: [
          CCRouterContractOwner(
            kind: kind == 'Service'
                ? CCRouterContractKind.service
                : CCRouterContractKind.command,
            contractSymbol: 'Shared',
            contractPackage: 'consumer',
            componentId: 'orders',
            componentIdSymbol: 'orderOwner',
            contractLibraryUri: 'package:consumer/probe.dart',
          ),
        ],
        packageRoots: {'consumer': fixture.root.path},
      );
      for (final consumer in [
        "CCComponentId('orders')",
        "Identity('orders')",
        'Identity(ownerName)',
        r"Identity('${'orders'}')",
        'orderOwner',
        "CCComponentId('consumer')",
      ]) {
        final source = _coreOwnerConsumer(kind)
            .replaceFirst("id: CCComponentId('consumer')", 'id: $consumer')
            .replaceFirst(
              'const computed',
              "typedef Identity = CCComponentId;\nconst ownerName = 'orders';\nconst orderOwner = CCComponentId('orders');\nconst computed",
            );
        final result = await fixture.resolve(source);
        expect(result.diagnostics, isEmpty);
        final external = consumer == "CCComponentId('consumer')";
        expect(
          _coreOwnerIssues(fixture, result, owners),
          hasLength(external ? 1 : 0),
        );
        final fixes = CCRouterQuickFixes.compute(
          source: source,
          filePath: fixture.file,
          offset: source.indexOf('CC${kind}Dependency<Shared>'),
          diagnosticCode: 'ccrouter_component_owner_dependency_missing',
          sourcePackage: 'consumer',
          contractOwners: owners,
          resolvedUnit: result.unit,
        );
        expect(fixes, hasLength(external ? 1 : 0));
      }
    });
    test(
      '$kind owner detection follows dependency and component typedefs',
      () async {
        final owners = _coreOwners(fixture, kind);
        for (final spelling in [
          'CC${kind}Dependency<Shared>',
          'Dependency',
          'cc.CC${kind}Dependency<Shared>',
        ]) {
          final source = _coreOwnerConsumer(kind)
              .replaceFirst(
                _imports,
                "$_imports\nimport 'package:ccrouter_contracts/ccrouter_contracts.dart' as cc;",
              )
              .replaceFirst(
                'const component',
                'typedef Dependency = cc.CC${kind}Dependency<Shared>;\ntypedef Descriptor = CCComponent;\nconst component',
              )
              .replaceFirst(
                'component = CCComponent(',
                'component = Descriptor(',
              )
              .replaceFirst('CC${kind}Dependency<Shared>(', '$spelling(');
          final result = await fixture.resolve(source);
          expect(result.diagnostics, isEmpty);
          expect(_coreOwnerIssues(fixture, result, owners), hasLength(1));
        }
      },
    );
    test('$kind owner detection ignores same-name functions', () async {
      final source = _coreOwnerConsumer(kind)
          .replaceFirst(
            _imports,
            "$_imports\nimport 'package:ccrouter_contracts/ccrouter_contracts.dart' as cc;",
          )
          .replaceFirst('const component', '''
@CC${kind}Contract(componentId: CCComponentId('other'), id: 'other.shared')
${kind == 'Service' ? 'abstract interface class Other {}' : 'final class Other implements CCCommand<void> { const Other(); }'}
cc.CC${kind}Dependency<Other> CC${kind}Dependency<T>({String? alias}) => cc.CC${kind}Dependency<Other>();
final component''')
          .replaceFirst(
            "dependencies: []",
            "dependencies: [CCComponentId('other')]",
          );
      final result = await fixture.resolve(source);
      expect(result.diagnostics, isEmpty);
      expect(
        _coreOwnerIssues(fixture, result, _coreOwners(fixture, kind)),
        isEmpty,
      );
    });
    for (final state in ['owner changed', 'removed', 'duplicated', 'foreign']) {
      test('$kind owner facts defer when current annotation is $state', () async {
        final source = _coreOwnerConsumer(kind);
        const annotation =
            "@CCContractPlaceholder(componentId: CCComponentId('orders'), id: 'orders.shared', alias: 'shared')";
        final actual = annotation.replaceFirst(
          'CCContractPlaceholder',
          'CC${kind}Contract',
        );
        final replacement = switch (state) {
          'owner changed' => actual.replaceFirst(
            "CCComponentId('orders')",
            "CCComponentId('changed')",
          ),
          'removed' => '',
          'duplicated' => '$actual\n$actual',
          _ => actual,
        };
        var edited = source.replaceFirst(actual, replacement);
        if (state == 'foreign')
          edited = edited.replaceFirst('const computed', '''
class CC${kind}Contract { const CC${kind}Contract({Object? componentId, Object? id, Object? alias}); }
const computed''');
        final result = await fixture.resolve(edited);
        expect(result.diagnostics, isEmpty);
        expect(
          _coreOwnerIssues(fixture, result, _coreOwners(fixture, kind)),
          isEmpty,
        );
      });
    }
  }

  for (final kind in ['Service', 'Command']) {
    for (final alias in ['bad-alias', 'class', 'hashCode']) {
      test('$kind dependency literal alias $alias is diagnosed', () async {
        final result = await fixture.resolve(_coreConsumer(kind, "'$alias'"));
        expect(result.diagnostics, isEmpty);
        final issues = fixture
            .issues(result)
            .where((issue) => issue.code == 'ccrouter_alias_invalid')
            .toList();
        expect(issues, hasLength(1));
        expect(
          result.content.substring(
            issues.single.offset,
            issues.single.offset + issues.single.length,
          ),
          "'$alias'",
        );
      });
    }
    test('$kind dependency valid and computed aliases defer', () async {
      for (final alias in ["'shared'", 'computed', 'null']) {
        final result = await fixture.resolve(_coreConsumer(kind, alias));
        expect(result.diagnostics, isEmpty);
        expect(
          fixture.codes(result),
          isNot(contains('ccrouter_alias_invalid')),
        );
      }
    });
    test('$kind dependency prefix and typedef retain constructor identity', () async {
      final source = _coreConsumer(kind, "'bad-alias'")
          .replaceFirst(
            _imports,
            "$_imports\nimport 'package:ccrouter_contracts/ccrouter_contracts.dart' as cc;",
          )
          .replaceAll('CC${kind}Dependency<Shared>', 'Dependency')
          .replaceFirst(
            'const computed',
            'typedef Dependency = cc.CC${kind}Dependency<Shared>;\nconst computed',
          );
      final result = await fixture.resolve(source);
      expect(result.diagnostics, isEmpty);
      expect(fixture.codes(result), contains('ccrouter_alias_invalid'));
      final prefixed = await fixture.resolve(
        _coreConsumer(kind, "'bad-alias'")
            .replaceFirst(
              _imports,
              "$_imports\nimport 'package:ccrouter_contracts/ccrouter_contracts.dart' as cc;",
            )
            .replaceAll(
              'CC${kind}Dependency<Shared>',
              'cc.CC${kind}Dependency<Shared>',
            ),
      );
      expect(prefixed.diagnostics, isEmpty);
      expect(fixture.codes(prefixed), contains('ccrouter_alias_invalid'));
    });
    test('$kind dependency same-name function is ignored', () async {
      final source = _coreConsumer(kind, "'bad-alias'")
          .replaceFirst(
            _imports,
            "$_imports\nimport 'package:ccrouter_contracts/ccrouter_contracts.dart' as cc;",
          )
          .replaceFirst('const component', '''
cc.CC${kind}Dependency<T> CC${kind}Dependency<T extends ${kind == 'Service' ? 'Object' : 'cc.CCCommand<Object?>'}>({String? alias}) =>
  cc.CC${kind}Dependency<T>(alias: 'shared');
final component''');
      final result = await fixture.resolve(source);
      expect(result.diagnostics, isEmpty);
      expect(fixture.codes(result), isNot(contains('ccrouter_alias_invalid')));
    });
    test('$kind dependency under foreign component is ignored', () async {
      final result = await fixture.resolve(
        _coreConsumer(kind, "'bad-alias'").replaceFirst('const component', '''
class CCComponent { const CCComponent({Object? id, Object? version,
  Object? dependencies, Object? uiDependencies, Object? ${kind.toLowerCase()}Dependencies}); }
const component'''),
      );
      expect(result.diagnostics, isEmpty);
      expect(fixture.codes(result), isNot(contains('ccrouter_alias_invalid')));
    });
  }

  for (final alias in ['build-card', 'class', 'toString']) {
    test('UI alias $alias is diagnosed with framework identity', () async {
      final result = await fixture.resolve(
        _consumer('''
CCUIFragmentDependency<Summary>(alias: '$alias')
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
CCUIFragmentDependency<Summary>(alias: 'card'),
CCUIFragmentDependency<Summary>(alias: 'card')
'''),
      );
      expect(fixture.codes(aliases), contains('ccrouter_ui_alias_duplicate'));
      final contracts = await fixture.resolve(
        _consumer('''
CCUIFragmentDependency<Summary>(alias: 'card'),
CCUIFragmentDependency<SummaryAlias>(alias: 'other')
''', extra: 'typedef SummaryAlias = Summary;'),
      );
      expect(
        fixture.codes(contracts),
        contains('ccrouter_ui_dependency_duplicate'),
      );
    },
  );
  test(
    'UI dependency defaults resolve without alias or version arguments',
    () async {
      final result = await fixture.resolve(
        _consumer('CCUIFragmentDependency<Summary>()'),
      );
      expect(result.diagnostics, isEmpty);
      expect(fixture.codes(result), isEmpty);
    },
  );
  test('UI inferred names and Contract aliases participate in collisions', () async {
    for (final annotation in [
      "@CCUIFragmentContract<Props, Action>(componentId: CCComponentId('orders'), id: 'orders.other')\nabstract final class SummaryFragmentContract {}",
      "@CCUIFragmentContract<Props, Action>(componentId: CCComponentId('orders'), id: 'orders.other', alias: 'summary')\nabstract final class Other {}",
    ]) {
      final marker = annotation.contains('class Other')
          ? 'Other'
          : 'SummaryFragmentContract';
      final result = await fixture.resolve(
        _consumer(
          'CCUIFragmentDependency<Summary>(), CCUIFragmentDependency<$marker>()',
          extra: annotation,
        ),
      );
      expect(result.diagnostics, isEmpty);
      expect(fixture.codes(result), contains('ccrouter_ui_alias_duplicate'));
    }
  });
  test('UI explicit aliases override Contract defaults', () async {
    final result = await fixture.resolve(
      _consumer(
        "CCUIFragmentDependency<Summary>(), CCUIFragmentDependency<Other>(alias: 'other')",
        extra:
            "@CCUIFragmentContract<Props, Action>(componentId: CCComponentId('orders'), id: 'orders.other', alias: 'summary')\nabstract final class Other {}",
      ),
    );
    expect(result.diagnostics, isEmpty);
    expect(fixture.codes(result), isEmpty);
  });
  test(
    'review subtype facts refresh after edits without retaining stale graphs',
    () async {
      const base =
          'final class Action { const Action(this.id); final String id; }';
      const derived =
          "final class Derived extends Action { const Derived(super.id); @override String get id => 'unmodeled'; }";
      final before = await fixture.resolve(
        '$_imports${_contract.replaceFirst('enum Action { select }', base)}',
      );
      expect(
        fixture.codes(before),
        isNot(contains('ccrouter_ui_action_invalid')),
      );
      final changed = await fixture.resolve(
        '$_imports${_contract.replaceFirst('enum Action { select }', '$base\n$derived')}',
      );
      expect(fixture.codes(changed), contains('ccrouter_ui_action_invalid'));
      final restored = await fixture.resolve(
        '$_imports${_contract.replaceFirst('enum Action { select }', base)}',
      );
      expect(
        fixture.codes(restored),
        isNot(contains('ccrouter_ui_action_invalid')),
      );
    },
  );

  test('review DTO subtype cannot add unmodeled behavior', () async {
    final result = await fixture.resolve(
      '$_imports${_contract.replaceFirst('enum Action { select }', '''
final class Action { const Action(this.id); final String id; }
final class Derived extends Action { const Derived(super.id); @override String get id => 'unmodeled'; }
''')}',
    );
    expect(result.diagnostics, isEmpty);
    expect(fixture.codes(result), contains('ccrouter_ui_action_invalid'));
  });
  test(
    'review same-name Object model is valid Dart but invalid UI data',
    () async {
      final result = await fixture.resolve(
        '$_imports${_contract.replaceFirst('enum Action { select }', '''
class Object { const Object(); String get id => 'unmodeled'; }
final class Action extends Object { const Action(); }
''')}',
      );
      expect(result.diagnostics, isEmpty);
      expect(fixture.codes(result), contains('ccrouter_ui_action_invalid'));
    },
  );
  test('review editor checks bound work for repeated DTO graphs', () async {
    final nodes = List.generate(24, (i) {
      final child = i == 23 ? 'String' : 'Node${i + 1}';
      return 'final class Node$i { const Node$i(this.left, this.right); final $child left; final $child right; }';
    }).join('\n');
    final result = await fixture.resolve(
      '$_imports${_contract.replaceFirst('enum Action { select }', 'final class Action { const Action(this.node); final Node0 node; }')}\n$nodes',
    );
    expect(result.diagnostics, isEmpty);
    final timer = Stopwatch()..start();
    expect(
      fixture.codes(result),
      isNot(contains('ccrouter_ui_action_invalid')),
    );
    timer.stop();
    expect(
      timer.elapsed,
      lessThan(const Duration(seconds: 2)),
      reason:
          'Only Plugin validation is timed, after Analyzer resolution. Excess work must defer to the Generator.',
    );
  });

  for (final removeAnnotation in [false, true]) {
    test(
      'review resolved UI Owner defers stale annotation facts removed=$removeAnnotation',
      () async {
        final file = File(p.join(fixture.root.path, 'owner/lib/contract.dart'));
        final original = file.readAsStringSync();
        file.writeAsStringSync(
          removeAnnotation
              ? original.replaceAll(
                  RegExp(r'@CCUIFragmentContract[^\n]*\n'),
                  '',
                )
              : original.replaceFirst(
                  "CCComponentId('orders')",
                  "CCComponentId('changed_owner')",
                ),
        );
        final result = await fixture.resolve(
          "$_imports import 'package:owner_contracts/owner_contracts.dart'; const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0', dependencies: [${removeAnnotation ? '' : 'orderOwner'}], uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'card')]);",
        );
        expect(result.diagnostics, isEmpty);
        final owners = CCRouterContractOwnerIndexCache().resolve(fixture.file);
        expect(
          fixture.issues(result, owners: owners).map((d) => d.code),
          isNot(contains('ccrouter_component_owner_dependency_missing')),
        );
      },
    );
  }

  const union = '''
sealed class Target { const Target(this.id); final String id; }
final class UserTarget extends Target { const UserTarget(super.id); }
final class ScoreTarget extends Target { const ScoreTarget(super.id); }
sealed class Action { const Action(); }
final class SettingsRequested extends Action { const SettingsRequested(); }
final class TargetSelected extends Action { const TargetSelected(this.target); final Target target; }
''';
  test(
    'legacy deep DTO defers at the IDE budget without false rejection',
    () async {
      final nodes = List.generate(
        40,
        (i) =>
            'final class Node$i { const Node$i(this.next); final ${i == 39 ? 'String' : 'Node${i + 1}'} next; }',
      ).join('\n');
      final result = await fixture.resolve(
        '$_imports${_contract.replaceFirst('enum Action { select }', 'final class Action { const Action(this.next); final Node0 next; }')}\n$nodes',
      );
      expect(result.diagnostics, isEmpty);
      expect(
        fixture.codes(result),
        isNot(contains('ccrouter_ui_action_invalid')),
      );
    },
  );
  test('sealed Action and nested const super data are accepted', () async {
    final result = await fixture.resolve(
      '$_imports${_contract.replaceFirst('enum Action { select }', union)}',
    );
    expect(result.diagnostics, isEmpty);
    expect(
      fixture.codes(result),
      isNot(contains('ccrouter_ui_action_invalid')),
    );
  });
  test(
    'sealed variants in parts are checked through the defining library',
    () async {
      fixture.write(
        'lib/variants.dart',
        "part of 'probe.dart'; final class Selected extends Action { const Selected(); }",
      );
      final result = await fixture.resolve(
        '$_imports\npart "variants.dart";\n${_contract.replaceFirst('enum Action { select }', 'sealed class Action { const Action(); }')}',
      );
      expect(result.diagnostics, isEmpty);
      expect(
        fixture.codes(result),
        isNot(contains('ccrouter_ui_action_invalid')),
      );
    },
  );
  for (final invalid in [
    '$union final class Grandchild extends SettingsRequested { const Grandchild(); }',
    '$union final class Impostor implements Action { const Impostor(); }',
    '$union final class _Private extends Action { const _Private(); }',
    '$union final class Generic<T> extends Action { const Generic(); }',
    union.replaceFirst('final Target target;', 'final Action target;'),
    union.replaceFirst('final Target target;', 'final Future<String> target;'),
    union.replaceFirst(
      'final Target target;',
      'final Target target; void run() {}',
    ),
    union.replaceFirst(
      'final class SettingsRequested',
      'class SettingsRequested',
    ),
  ]) {
    test('sealed invalid model is diagnosed: $invalid', () async {
      final result = await fixture.resolve(
        '$_imports${_contract.replaceFirst('enum Action { select }', invalid)}',
      );
      expect(fixture.codes(result), contains('ccrouter_ui_action_invalid'));
    });
  }

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
CCUIFragmentDependency<Summary>(alias: 'card')
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
const component = CCComponent(uiDependencies: [CCUIFragmentDependency<Marker>(alias: 'bad-alias')]);
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
 uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'card')]);
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
  for (final (documentVersion, recordVersion) in [(1.0, 1), (2, 3)]) {
    test(
      'review UI Owner facts defer malformed versions $documentVersion/$recordVersion',
      () async {
        final result = await fixture.resolve(
          "$_imports import 'package:owner_contracts/owner_contracts.dart'; const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0', uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'card')]);",
        );
        final metadataPath = p.join(
          fixture.root.path,
          'owner/lib/src/ccrouter_generated/metadata/ccrouter_package.json',
        );
        final metadata = jsonDecode(File(metadataPath).readAsStringSync());
        final cache = CCRouterContractOwnerIndexCache();
        expect(
          fixture
              .issues(result, owners: cache.resolve(fixture.file))
              .map((d) => d.code),
          contains('ccrouter_component_owner_dependency_missing'),
        );
        metadata['metadata'][0]['uiSchemaVersion'] = documentVersion;
        metadata['metadata'][0]['uiContracts'][0]['uiSchemaVersion'] =
            recordVersion;
        File(metadataPath).writeAsStringSync(jsonEncode(metadata));
        cache.invalidate(metadataPath);
        expect(
          fixture
              .issues(result, owners: cache.resolve(fixture.file))
              .map((d) => d.code),
          isNot(contains('ccrouter_component_owner_dependency_missing')),
        );
      },
    );
  }

  test('UI owner metadata removal and legacy records defer safely', () async {
    final result = await fixture.resolve(
      "$_imports import 'package:owner_contracts/owner_contracts.dart'; const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0', uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'card')]);",
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
    metadata['schemaVersion'] = 5;
    metadata['metadata'][0]['uiSchemaVersion'] = 3;
    metadata['metadata'][0]['uiContracts'][0]['uiSchemaVersion'] = 3;
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
        "$_imports $declaration const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0', uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'card')]);",
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
      "$_imports import 'package:owner_contracts/owner_contracts.dart'; const ids = <CCComponentId>[]; const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0', dependencies: [...ids], uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'card')]);",
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
        "import 'package:ccrouter_contracts/ccrouter_contracts.dart'; import 'barrel.dart' as ui; class Marker {} const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0', uiDependencies: [ui.CCUIFragmentDependency<Marker>(alias: 'bad-alias')]);",
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

  for (final form in [
    'fileHost',
    'queryHost',
    'fileGenerated',
    'queryGenerated',
    'typeAlias',
  ]) {
    test(
      'UI SPI $form paths keep their configured identity',
      () async {
        fixture.write(
          'ui/lib/src/ui_fragment.dart',
          'class CCUIHostAssembly {} class CCUIRenderer {}',
        );
        fixture.write(
          'ui/lib/ccrouter_ui_host.dart',
          "export 'src/ui_fragment.dart' show CCUIHostAssembly;",
        );
        fixture.write(
          'ui/lib/ccrouter_ui_generated.dart',
          "export 'src/ui_fragment.dart' show CCUIRenderer;",
        );
        Link(
          p.join(fixture.root.path, 'owner/lib/spi_alias.dart'),
        ).createSync(p.join(fixture.root.path, 'ui/lib/src/ui_fragment.dart'));
        final generated = form.endsWith('Generated');
        final library = generated
            ? 'ccrouter_ui_generated.dart'
            : 'ccrouter_ui_host.dart';
        final source = form == 'typeAlias'
            ? "import 'package:owner_contracts/spi_alias.dart' as ui; ui.CCUIHostAssembly? assembly; ui.CCUIRenderer? renderer;"
            : form.startsWith('file')
            ? "import '${File(p.join(fixture.root.path, 'ui/lib/$library')).uri}';"
            : "import 'package:ccrouter_ui/$library?query';";
        final result = await fixture.resolve(source);
        expect(
          result.diagnostics.where(
            (d) => d.diagnosticCode.severity.name == 'ERROR',
          ),
          isEmpty,
        );
        final issues = CCRouterSourceAnalyzer.analyze(
          source: source,
          filePath: fixture.file,
          packageRoot: fixture.root.path,
          packageName: 'consumer',
          resolvedUnit: result.unit,
          uriConverter: fixture.collection
              .contextFor(fixture.file)
              .currentSession
              .uriConverter,
        );
        expect(
          issues.where((d) => d.code == 'ccrouter_ui_spi_access'),
          isNotEmpty,
        );
      },
      skip: Platform.isWindows && form == 'typeAlias'
          ? 'POSIX symlink fixture'
          : false,
    );
  }

  test('hidden transitive UI SPI names do not count as uses', () async {
    fixture.write(
      'ui/lib/src/ui_fragment.dart',
      'class CCUIHostAssembly {} class CCUIRenderer {}',
    );
    fixture.write(
      'lib/spi_barrel.dart',
      "export 'package:ccrouter_ui/src/ui_fragment.dart';",
    );
    final result = await fixture.resolve(
      "import 'spi_barrel.dart' hide CCUIHostAssembly, CCUIRenderer;",
    );
    expect(
      result.diagnostics.where(
        (d) => d.diagnosticCode.severity.name == 'ERROR',
      ),
      isEmpty,
    );
    expect(
      fixture.codes(result).where((d) => d == 'ccrouter_ui_spi_access'),
      isEmpty,
    );
  });

  test('UI Host typedef static access keeps its reference location', () async {
    fixture.write(
      'ui/lib/src/ui_fragment.dart',
      'class CCUIHostAssembly { static int wrap() => 0; }',
    );
    fixture.write(
      'lib/spi_barrel.dart',
      "export 'package:ccrouter_ui/src/ui_fragment.dart';",
    );
    const source =
        "import 'spi_barrel.dart' as ui; typedef Host = ui.CCUIHostAssembly; final value = Host.wrap();";
    final result = await fixture.resolve(source);
    expect(
      result.diagnostics.where(
        (d) => d.diagnosticCode.severity.name == 'ERROR',
      ),
      isEmpty,
    );
    final issues = fixture
        .issues(result)
        .where((d) => d.code == 'ccrouter_ui_spi_access');
    expect(
      issues.map((d) => d.offset),
      contains(source.lastIndexOf('Host.wrap')),
    );
  });

  test(
    'transitive UI show lists keep only effectively exposed SPI names',
    () async {
      fixture.write(
        'ui/lib/src/ui_fragment.dart',
        'class CCUIHostAssembly {} class CCUIRenderer {}',
      );
      fixture.write(
        'lib/spi_barrel.dart',
        "export 'package:ccrouter_ui/src/ui_fragment.dart';",
      );
      for (final (selection, forbidden) in [
        ('show CCUIHostAssembly', true),
        ('show CCUIHostAssembly hide CCUIHostAssembly', false),
        ('show CCUIHostAssembly show CCUIRenderer', false),
      ]) {
        final result = await fixture.resolve(
          "import 'spi_barrel.dart' $selection;",
        );
        expect(
          result.diagnostics.where(
            (d) => d.diagnosticCode.severity.name == 'ERROR',
          ),
          isEmpty,
        );
        expect(
          fixture.codes(result).contains('ccrouter_ui_spi_access'),
          forbidden,
          reason: selection,
        );
      }
    },
  );

  test('a foreign UI SPI copy is not the configured framework library', () async {
    fixture.write(
      'owner/lib/src/ui_fragment.dart',
      'class CCUIHostAssembly {} class CCUIRenderer {}',
    );
    final result = await fixture.resolve(
      "import 'package:owner_contracts/src/ui_fragment.dart' as ui; ui.CCUIHostAssembly? assembly; ui.CCUIRenderer? renderer;",
    );
    expect(
      result.diagnostics.where(
        (d) => d.diagnosticCode.severity.name == 'ERROR',
      ),
      isEmpty,
    );
    final issues = CCRouterSourceAnalyzer.analyze(
      source: result.content,
      filePath: fixture.file,
      packageRoot: fixture.root.path,
      packageName: 'consumer',
      resolvedUnit: result.unit,
      uriConverter: fixture.collection
          .contextFor(fixture.file)
          .currentSession
          .uriConverter,
    );
    expect(issues.where((d) => d.code == 'ccrouter_ui_spi_access'), isEmpty);
  });

  test(
    'UI Host and Generated barrel aliases preserve their role matrix',
    () async {
      fixture.write(
        'ui/lib/src/ui_fragment.dart',
        'class CCUIHostAssembly {} class CCUIRenderer {}',
      );
      fixture.write(
        'ui/lib/ccrouter_ui_host.dart',
        "export 'src/ui_fragment.dart' show CCUIHostAssembly;",
      );
      fixture.write(
        'ui/lib/ccrouter_ui_generated.dart',
        "export 'src/ui_fragment.dart' show CCUIRenderer;",
      );
      for (final role in [
        CCRouterAnalyzerProjectRole.host,
        CCRouterAnalyzerProjectRole.package,
      ]) {
        for (final generated in [false, true]) {
          final library = generated
              ? 'ccrouter_ui_generated.dart'
              : 'ccrouter_ui_host.dart';
          final source =
              "import '${File(p.join(fixture.root.path, 'ui/lib/$library')).uri}';";
          final result = await fixture.resolve(source);
          expect(
            result.diagnostics.where(
              (d) => d.diagnosticCode.severity.name == 'ERROR',
            ),
            isEmpty,
          );
          final issues = CCRouterSourceAnalyzer.analyze(
            source: source,
            filePath: fixture.file,
            packageRoot: fixture.root.path,
            packageName: 'consumer',
            resolvedUnit: result.unit,
            projectRole: role,
            uriConverter: fixture.collection
                .contextFor(fixture.file)
                .currentSession
                .uriConverter,
          ).where((d) => d.code == 'ccrouter_ui_spi_access');
          expect(
            issues.isNotEmpty,
            generated || role == CCRouterAnalyzerProjectRole.package,
            reason: '$role/$library',
          );
        }
      }
    },
  );

  test(
    'business UI types in the same implementation library stay allowed',
    () async {
      fixture.write(
        'ui/lib/src/ui_fragment.dart',
        'class CCUIFragmentRenderInput<P,A> {} enum CCUIFragmentUpdatePolicy { always }',
      );
      final result = await fixture.resolve(
        "import 'package:ccrouter_ui/ccrouter_ui.dart'; CCUIFragmentRenderInput<Object,Object>? input; const policy = CCUIFragmentUpdatePolicy.always;",
      );
      expect(
        result.diagnostics.where(
          (d) => d.diagnosticCode.severity.name == 'ERROR',
        ),
        isEmpty,
      );
      final issues = CCRouterSourceAnalyzer.analyze(
        source: result.content,
        filePath: fixture.file,
        packageRoot: fixture.root.path,
        packageName: 'consumer',
        resolvedUnit: result.unit,
        uriConverter: fixture.collection
            .contextFor(fixture.file)
            .currentSession
            .uriConverter,
      );
      expect(issues.where((d) => d.code == 'ccrouter_ui_spi_access'), isEmpty);
    },
  );
  test(
    'foreign component constructors never inherit UI dependency semantics',
    () async {
      final result = await fixture.resolve(
        "$_imports import 'package:owner_contracts/owner_contracts.dart'; class CCComponent { const CCComponent({Object? uiDependencies}); } const component = CCComponent(uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'bad-alias')]);",
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
        "$_imports import 'package:owner_contracts/owner_contracts.dart'; const component = CCComponent(id: CCComponentId('orders'), version: '1.0.0', uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'card')]);",
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
  CCUIFragmentDependency<OrderFragment>(alias: 'bad-alias')]);
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
  required String alias,
}) => ui.CCUIFragmentDependency<T>(alias: 'card');
final component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0',
  uiDependencies: [CCUIFragmentDependency<OrderFragment>(
    alias: 'bad-alias',)]);
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
  uiDependencies: [Dependency<Marker>(alias: 'bad-alias')]);
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
  uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'card')]);
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
  uiDependencies: [$dependency<OrderFragment>(alias: 'card')]);
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
  uiDependencies: [CCUIFragmentDependency<OrderFragment>(alias: 'card')]);
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

CCRouterContractOwnerIndex _coreOwners(_UIFixture fixture, String kind) =>
    CCRouterContractOwnerIndex(
      owners: [
        CCRouterContractOwner(
          kind: kind == 'Service'
              ? CCRouterContractKind.service
              : CCRouterContractKind.command,
          contractSymbol: 'Shared',
          contractPackage: 'consumer',
          componentId: 'orders',
          componentIdSymbol: null,
          contractLibraryUri: 'package:consumer/probe.dart',
        ),
      ],
      packageRoots: {'consumer': fixture.root.path},
    );

String _coreOwnerConsumer(String kind) => _coreConsumer(
  kind,
  "'shared'",
).replaceFirst("dependencies: [CCComponentId('orders')]", 'dependencies: []');

List<CCRouterAnalyzerDiagnostic> _coreOwnerIssues(
  _UIFixture fixture,
  ResolvedUnitResult result,
  CCRouterContractOwnerIndex owners,
) => fixture
    .issues(result, owners: owners)
    .where(
      (issue) => issue.code == 'ccrouter_component_owner_dependency_missing',
    )
    .toList();

String _coreConsumer(String kind, String alias) =>
    _consumer(
      'CCUIFragmentDependency<Summary>()',
      extra:
          '''
const computed = 'bad-alias';
@CC${kind}Contract(componentId: CCComponentId('orders'), id: 'orders.shared', alias: 'shared')
${kind == 'Service' ? 'abstract interface class Shared {}' : 'final class Shared implements CCCommand<void> { const Shared(); }'}
''',
    ).replaceFirst(
      'uiDependencies:',
      '${kind.toLowerCase()}Dependencies: [CC${kind}Dependency<Shared>(alias: $alias)], uiDependencies:',
    );

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
