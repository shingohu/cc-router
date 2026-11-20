import 'dart:convert';
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

  test('malformed import URIs do not crash source analysis', () {
    for (final uri in [
      'package:other/%FF.dart',
      'package:other/src/ccrouter_generated/%FF.dart',
      'package:other/src/ccrouter_generated/%00.dart',
      'local%FF.dart',
      'local.dart?query',
      'package:/other/public.dart',
    ]) {
      final issues = CCRouterSourceAnalyzer.analyze(
        source: "import '$uri';",
        filePath: path.join(packageRoot, 'lib/src/probe.dart'),
        packageRoot: packageRoot,
        packageName: 'sample_component',
      );
      expect(issues, isEmpty, reason: uri);
    }
  });

  test(
    'invalid Package URI evidence cannot supply a parsed Contract namespace',
    () {
      for (final (uri, expected) in [
        ('package:sample_component/api.dart', true),
        ('package:sample_component/api.dart?query', false),
        ('package:sample_component/api.dart#fragment', false),
        ('package:/sample_component/api.dart', false),
        ('package:sample_component/dir%2Ffile.dart', false),
      ]) {
        final issues = CCRouterSourceAnalyzer.analyze(
          source:
              '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import '$uri' as api;
const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0',
  serviceDependencies: [CCServiceDependency<api.SharedService>()]);
''',
          filePath: path.join(packageRoot, 'lib/src/probe.dart'),
          packageRoot: packageRoot,
          packageName: 'consumer',
          contractOwners: _localOwnerIndex(),
        );
        expect(
          issues.any(
            (issue) =>
                issue.code == 'ccrouter_component_owner_dependency_missing',
          ),
          expected,
          reason: uri,
        );
      }
    },
  );

  test(
    'parser-only dependency aliases require proven constructors and literal lists',
    () {
      for (final kind in ['Service', 'Command']) {
        for (final (declaration, collection, expected) in [
          ('', "[CC${kind}Dependency<Shared>(alias: 'hashCode')]", true),
          ('', "[CC${kind}Dependency<Shared>(alias: computed)]", false),
          (
            '',
            "[...other, CC${kind}Dependency<Shared>(alias: 'hashCode')]",
            false,
          ),
          ('', 'other', false),
          (
            "Object CC${kind}Dependency<T>({String? alias}) => Object();",
            "[CC${kind}Dependency<Shared>(alias: 'hashCode')]",
            false,
          ),
          (
            'class CCComponent { const CCComponent({Object? ${kind.toLowerCase()}Dependencies}); }',
            "[CC${kind}Dependency<Shared>(alias: 'hashCode')]",
            false,
          ),
          (
            'extension CCComponent on Object {}',
            "[CC${kind}Dependency<Shared>(alias: 'hashCode')]",
            false,
          ),
          (
            'extension CC${kind}Dependency on Object {}',
            "[CC${kind}Dependency<Shared>(alias: 'hashCode')]",
            false,
          ),
        ]) {
          final issues = CCRouterSourceAnalyzer.analyze(
            source:
                "import 'package:ccrouter_contracts/ccrouter_contracts.dart';\n"
                '$declaration\nconst component = CCComponent(${kind.toLowerCase()}Dependencies: $collection);',
            filePath: path.join(packageRoot, 'lib/src/probe.dart'),
            packageRoot: packageRoot,
            packageName: 'sample_component',
          );
          expect(
            issues.any((issue) => issue.code == 'ccrouter_alias_invalid'),
            expected,
            reason: '$kind: $declaration $collection',
          );
        }
      }
    },
  );

  for (final (label, imports, declaration, type) in [
    (
      'local type shadows an imported Contract',
      "import 'package:owner_contracts/owner_contracts.dart' show SharedService;",
      'class SharedService {}',
      'SharedService',
    ),
    (
      'hidden Contract is not an imported type',
      "import 'package:owner_contracts/owner_contracts.dart' as api hide SharedService;\nimport 'package:other/other.dart' as api show SharedService;",
      '',
      'api.SharedService',
    ),
    (
      'conditional Contract namespace is unknown',
      "import 'package:owner_contracts/owner_contracts.dart' if (dart.library.io) 'package:other/other.dart' as api show SharedService;",
      '',
      'api.SharedService',
    ),
    (
      'conditional competing namespace is unknown',
      "import 'package:owner_contracts/owner_contracts.dart' as api show SharedService;\nimport 'package:other/empty.dart' if (dart.library.io) 'package:other/other.dart' as api show SharedService;",
      '',
      'api.SharedService',
    ),
  ]) {
    test('parser-only Owner checks defer when $label', () {
      final issues = CCRouterSourceAnalyzer.analyze(
        source:
            '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
$imports
$declaration
const component = CCComponent(id: CCComponentId('consumer'), version: '1.0.0',
  serviceDependencies: [CCServiceDependency<$type>()]);
''',
        filePath: path.join(packageRoot, 'lib/src/probe.dart'),
        packageRoot: packageRoot,
        packageName: 'consumer',
        contractOwners: _ownerIndex(),
      );
      expect(
        issues.map((issue) => issue.code),
        isNot(contains('ccrouter_component_owner_dependency_missing')),
      );
    });
  }

  test('parser-only Owner checks defer shadowed or ambiguous constructors', () {
    for (final extra in [
      "import 'unknown.dart';",
      'class CCComponent { const CCComponent({Object? serviceDependencies}); }',
      'Object CCServiceDependency<T>() => Object();',
    ]) {
      final issues = CCRouterSourceAnalyzer.analyze(
        source:
            '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
$extra
const component = CCComponent(serviceDependencies: [CCServiceDependency<SharedService>()]);
''',
        filePath: path.join(packageRoot, 'lib/src/component.dart'),
        packageRoot: packageRoot,
        packageName: 'sample_component',
        contractOwners: _localOwnerIndex(),
      );
      expect(
        issues.map((issue) => issue.code),
        isNot(contains('ccrouter_component_owner_dependency_missing')),
      );
    }
  });

  final routeCases =
      jsonDecode(
            File(
              '../ccrouter_test/fixtures/route_configuration_cases.json',
            ).readAsStringSync(),
          )
          as List;
  for (final entry in routeCases.cast<Map<String, dynamic>>()) {
    test('shared Generator configuration: ${entry['name']}', () {
      final diagnostics = CCRouterSourceAnalyzer.analyze(
        source:
            "import 'package:ccrouter_contracts/ccrouter_contracts.dart';\n"
            "@CCRoute<void>(id: 'sample.home', pattern: CCPathPattern('/'), ${entry['arguments']}) class Home {}",
        filePath: path.join(packageRoot, 'lib/src/home.dart'),
        packageRoot: packageRoot,
        packageName: 'sample_component',
      );
      expect(
        diagnostics
            .where((d) => d.code.startsWith('ccrouter_route_'))
            .map((d) => d.code),
        unorderedEquals(entry['codes'] as List),
      );
    });
  }

  test('component cannot explicitly import or re-export Host lifecycle', () {
    File(path.join(packageRoot, 'pubspec.yaml')).writeAsStringSync(
      'name: sample_component\ndependencies:\n  ccrouter: any\n',
    );
    for (final source in [
      "import 'package:ccrouter/ccrouter_host.dart';",
      "import 'package:ccrouter/ccrouter_host.dart' show CCRouterHost;",
      "export 'package:ccrouter/ccrouter_host.dart';",
      "export 'safe.dart' if (dart.library.io) 'package:ccrouter/ccrouter_host.dart';",
    ]) {
      final diagnostics = CCRouterSourceAnalyzer.analyze(
        source: source,
        filePath: path.join(packageRoot, 'lib/src/component.dart'),
        packageRoot: packageRoot,
        packageName: 'sample_component',
      );
      expect(
        diagnostics.map((d) => d.code),
        contains('ccrouter_host_lifecycle_access'),
      );
    }
  });

  test(
    'narrow Adapter SPI and unavailable roles do not trigger lifecycle errors',
    () {
      File(path.join(packageRoot, 'pubspec.yaml')).writeAsStringSync(
        'name: sample_component\ndependencies:\n  ccrouter: any\n',
      );
      for (final source in [
        "import 'package:ccrouter/ccrouter_host.dart' hide CCRouterHost;",
        "import 'package:ccrouter/ccrouter_host.dart' show CCRouterHostBinding;",
        "export 'package:ccrouter/ccrouter_host.dart' hide CCRouterHost;",
      ]) {
        expect(
          CCRouterSourceAnalyzer.analyze(
            source: source,
            filePath: path.join(packageRoot, 'lib/src/adapter.dart'),
            packageRoot: packageRoot,
            packageName: 'sample_component',
          ),
          isEmpty,
        );
      }
      File(
        path.join(packageRoot, 'ccrouter.yaml'),
      ).writeAsStringSync('host:\n  enabled: unknown\n');
      expect(
        CCRouterSourceAnalyzer.analyze(
          source: "import 'package:ccrouter/ccrouter_host.dart';",
          filePath: path.join(packageRoot, 'lib/src/unknown.dart'),
          packageRoot: packageRoot,
          packageName: 'sample_component',
        ),
        isEmpty,
      );
    },
  );

  test('Host role and test sources may import lifecycle', () {
    File(path.join(packageRoot, 'pubspec.yaml')).writeAsStringSync(
      'name: sample_component\ndependencies:\n  ccrouter: any\n',
    );
    const source =
        "import 'package:ccrouter/ccrouter_host.dart' show CCRouterHost;";
    List<String> codes(String file) => CCRouterSourceAnalyzer.analyze(
      source: source,
      filePath: path.join(packageRoot, file),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    ).map((d) => d.code).toList();
    expect(codes('test/lifecycle_test.dart'), isEmpty);
    File(
      path.join(packageRoot, 'ccrouter.yaml'),
    ).writeAsStringSync('host:\n  enabled: true\n');
    expect(codes('lib/main.dart'), isEmpty);
    File(
      path.join(packageRoot, 'ccrouter.yaml'),
    ).writeAsStringSync('host:\n  enabled: false\n');
    expect(codes('lib/main.dart'), contains('ccrouter_host_lifecycle_access'));
  });

  test('unresolved foreign hidden and ambiguous annotations are ignored', () {
    for (final source in [
      '@CCInitTask(id: "bad id", contract: 1) void start() {}',
      "import 'package:other/other.dart';\n@CCInitTask() void start() {}",
      "import 'package:ccrouter_contracts/ccrouter_contracts.dart' hide CCInitTask;\n@CCInitTask() void start() {}",
      "import 'package:ccrouter_contracts/ccrouter_contracts.dart';\nclass CCInitTask { const CCInitTask(); }\n@CCInitTask() void start() {}",
      "import 'package:ccrouter_contracts/ccrouter_contracts.dart';\nimport 'package:other/other.dart';\n@CCInitTask() void start() {}",
      "import 'package:ccrouter_contracts/ccrouter_contracts.dart' if (dart.library.io) 'package:other/other.dart';\n@CCInitTask() void start() {}",
    ]) {
      expect(
        CCRouterSourceAnalyzer.analyze(
          source: source,
          filePath: path.join(packageRoot, 'lib/src/foreign.dart'),
          packageRoot: packageRoot,
          packageName: 'sample_component',
        ),
        isEmpty,
        reason: source,
      );
    }
  });

  test('unresolved exact prefixed framework imports still diagnose', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source:
          "import 'package:ccrouter_contracts/ccrouter_contracts.dart' as cc show CCInitTask;\n@cc.CCInitTask() void start() {}",
      filePath: path.join(packageRoot, 'lib/src/init.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );
    expect(
      diagnostics.map((d) => d.code),
      contains('ccrouter_generated_output_missing'),
    );
    expect(
      diagnostics.map((d) => d.code),
      contains('ccrouter_annotation_arguments_conflict'),
    );
  });

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

  test('file URI namespaces respect generated Package boundaries', () {
    final foreign = File(
      path.join(root.path, 'other/lib/src/ccrouter_generated/hidden.dart'),
    ).uri;
    final own = File(
      path.join(packageRoot, 'lib/src/ccrouter_generated/own.dart'),
    ).uri;
    final public = File(path.join(root.path, 'other/lib/other.dart')).uri;
    for (final (uri, forbidden) in [
      (foreign.toString(), true),
      if (!Platform.isWindows)
        (foreign.replace(host: 'localhost').toString(), true),
      (own.toString(), false),
      (public.toString(), false),
      (foreign.replace(query: 'query').toString(), true),
      (foreign.replace(fragment: 'fragment').toString(), false),
      (foreign.resolve('%FF.dart').toString(), false),
      (foreign.resolve('%00.dart').toString(), false),
    ]) {
      for (final source in [
        "import '$uri';",
        "export '$uri';",
        "import 'public.dart' if (dart.library.io) '$uri';",
      ]) {
        final issues = CCRouterSourceAnalyzer.analyze(
          source: source,
          filePath: path.join(packageRoot, 'lib/src/page.dart'),
          packageRoot: packageRoot,
          packageName: 'sample_component',
        ).where((d) => d.code == 'ccrouter_cross_package_generated_import');
        expect(issues, hasLength(forbidden ? 1 : 0), reason: source);
        for (final issue in issues) {
          expect(
            source.substring(issue.offset, issue.offset + issue.length),
            "'$uri'",
          );
        }
      }
    }
  });

  test(
    'native aliases preserve own and foreign generated boundaries',
    () {
      final aliases = Directory.systemTemp.createTempSync(
        'ccrouter_source_alias_',
      );
      addTearDown(() => aliases.deleteSync(recursive: true));
      final own = File(
        path.join(packageRoot, 'lib/src/ccrouter_generated/own.dart'),
      )..createSync(recursive: true);
      final foreign = File(
        path.join(root.path, 'other/lib/src/ccrouter_generated/hidden.dart'),
      )..createSync(recursive: true);
      own.writeAsStringSync('const own = 1;');
      foreign.writeAsStringSync('const hidden = 1;');
      final ownAlias = Link(path.join(aliases.path, 'own'))
        ..createSync(packageRoot);
      final hiddenAlias = Link(path.join(packageRoot, 'lib/public_alias.dart'))
        ..createSync(foreign.path);
      for (final (uri, forbidden) in [
        (
          File(
            path.join(ownAlias.path, 'lib/src/ccrouter_generated/own.dart'),
          ).uri.toString(),
          false,
        ),
        (hiddenAlias.uri.toString(), true),
        ('package:sample_component/public_alias.dart', true),
        ('../public_alias.dart', true),
      ]) {
        final issues = CCRouterSourceAnalyzer.analyze(
          source: "import '$uri';",
          filePath: path.join(packageRoot, 'lib/src/page.dart'),
          packageRoot: packageRoot,
          packageName: 'sample_component',
        ).where((d) => d.code == 'ccrouter_cross_package_generated_import');
        expect(issues, hasLength(forbidden ? 1 : 0), reason: uri);
      }
    },
    skip: Platform.isWindows ? 'POSIX symlink fixture' : false,
  );

  test('checks every conditional import and export at its exact URI', () {
    const foreign = 'package:other/src/ccrouter_generated/host/x.dart';
    for (final directive in ['import', 'export']) {
      final source =
          "$directive 'safe.dart' if (dart.library.io) '$foreign' "
          "if (dart.library.html) '$foreign';";
      final issues = CCRouterSourceAnalyzer.analyze(
        source: source,
        filePath: path.join(packageRoot, 'lib/src/page.dart'),
        packageRoot: packageRoot,
        packageName: 'sample_component',
      ).where((d) => d.code == 'ccrouter_cross_package_generated_import');
      expect(issues, hasLength(2));
      for (final issue in issues) {
        expect(
          source.substring(issue.offset, issue.offset + issue.length),
          "'$foreign'",
        );
      }
    }
  });

  test('own generated and public conditional barrels remain allowed', () {
    final issues = CCRouterSourceAnalyzer.analyze(
      source:
          "export 'public.dart' if (dart.library.io) "
          "'package:sample_component/src/ccrouter_generated/route/x.dart';",
      filePath: path.join(packageRoot, 'lib/src/page.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );
    expect(issues, isEmpty);
  });

  test('route placement and policy literals fail before generation', () {
    const source = '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart' as cc;
@cc.CCRoute<void>(id: 'sample.home', pattern: cc.CCPathPattern('/'),
  placement: cc.CCRoutePlacement(hostId: 'Bad Host', navigatorOutlet: '',
    shellId: 'bad..shell', parentRouteId: 'sample.home'),
  interceptors: ['auth.check', 'auth.check', 'bad id'],
  popGuards: ['dirty.check', 'dirty.check'])
class Home {}
''';
    final issues = CCRouterSourceAnalyzer.analyze(
      source: source,
      filePath: path.join(packageRoot, 'lib/src/page.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );
    expect(
      issues.where((d) => d.code == 'ccrouter_route_placement_invalid'),
      hasLength(3),
    );
    expect(
      issues.where((d) => d.code == 'ccrouter_route_parent_self'),
      hasLength(1),
    );
    expect(
      issues.where((d) => d.code == 'ccrouter_route_policy_duplicate'),
      hasLength(2),
    );
    expect(
      issues.where((d) => d.code == 'ccrouter_route_policy_invalid'),
      hasLength(1),
    );
    final invalidHost = issues.firstWhere(
      (d) => d.code == 'ccrouter_route_placement_invalid',
    );
    expect(
      source.substring(
        invalidHost.offset,
        invalidHost.offset + invalidHost.length,
      ),
      "'Bad Host'",
    );
  });

  test('unknown route configuration expressions and constructors defer', () {
    for (final placement in [
      'placementValue',
      'makePlacement()',
      'foreign.CCRoutePlacement(hostId: "Bad Host")',
    ]) {
      final issues = CCRouterSourceAnalyzer.analyze(
        source:
            "import 'package:ccrouter_contracts/ccrouter_contracts.dart' as cc;\n"
            "@cc.CCRoute<void>(id: 'sample.home', placement: $placement, "
            'interceptors: policies, popGuards: [unknownId]) class Home {}',
        filePath: path.join(packageRoot, 'lib/src/page.dart'),
        packageRoot: packageRoot,
        packageName: 'sample_component',
      );
      expect(
        issues.where((d) => d.code.startsWith('ccrouter_route_')),
        isEmpty,
      );
    }
  });

  test('warns when a route output is missing', () {
    final source = '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
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

  test('reports exact generated outputs for bounded filesystem polling', () {
    final sourcePath = path.join(packageRoot, 'lib', 'src', 'home_page.dart');
    final analysis = CCRouterSourceAnalyzer.analyzeWithLineInfo(
      source:
          "import 'package:ccrouter_contracts/ccrouter_contracts.dart';\n@CCRoute<void>()\nclass HomePage {}",
      filePath: sourcePath,
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );

    expect(analysis.generatedOutputPaths, {
      path.join(
        packageRoot,
        'lib',
        'src',
        'ccrouter_generated',
        'route',
        'home_page.route.g.dart',
      ),
      path.join(
        packageRoot,
        'lib',
        'src',
        'ccrouter_generated',
        'binding',
        'home_page.route_binding.g.dart',
      ),
    });
  });

  test('does not warn after the route output exists', () {
    _writeGenerated(packageRoot, 'route/home_page.route.g.dart');
    _writeGenerated(packageRoot, 'binding/home_page.route_binding.g.dart');
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source:
          "import 'package:ccrouter_contracts/ccrouter_contracts.dart';\n@CCRoute<void>()\nclass HomePage {}",
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
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
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
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
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
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/owner_contracts.dart' show SharedService, RunCommand, ownerComponentId;

const consumerComponentId = CCComponentId('consumer.component');
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
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/owner_contracts.dart' show SharedService, RunCommand, ownerComponentId;

const consumerComponentId = CCComponentId('consumer.component');
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
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/owner_contracts.dart' show SharedService, RunCommand, ownerComponentId;

const sharedOwner = ownerComponentId;
const consumerComponentId = CCComponentId('consumer.component');
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

  test('accepts a reverse-ordered local owner alias chain', () {
    const aliasCount = 200;
    final aliases = StringBuffer();
    for (var index = aliasCount; index >= 1; index--) {
      aliases.writeln('const alias$index = alias${index - 1};');
    }
    aliases.writeln('const alias0 = ownerComponentId;');
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source:
          '''
const ownerComponentId = CCComponentId('owner.component');
$aliases
const consumerComponentId = CCComponentId('consumer.component');
const consumerComponent = CCComponent(
  id: CCComponentId('consumer.component'),
  version: '1.0.0',
  dependencies: [alias$aliasCount],
  serviceDependencies: [
    ${List.filled(20, 'CCServiceDependency<SharedService>()').join(',\n    ')},
  ],
);
''',
      filePath: path.join(packageRoot, 'lib', 'src', 'component.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
      contractOwners: _localOwnerIndex(),
    );

    expect(
      diagnostics.map((item) => item.code),
      isNot(contains('ccrouter_component_owner_dependency_missing')),
    );
  });

  test(
    'preserves conservative cycles and rejects known wrong owner aliases',
    () {
      final cycleDiagnostics = CCRouterSourceAnalyzer.analyze(
        source: '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
const ownerComponentId = CCComponentId('owner.component');
const cycleA = cycleB;
const cycleB = cycleA;
const consumerComponentId = CCComponentId('consumer.component');
const consumerComponent = CCComponent(
  id: CCComponentId('consumer.component'),
  version: '1.0.0',
  dependencies: [cycleA],
  serviceDependencies: [CCServiceDependency<SharedService>()],
);
''',
        filePath: path.join(packageRoot, 'lib', 'src', 'component.dart'),
        packageRoot: packageRoot,
        packageName: 'sample_component',
        contractOwners: _localOwnerIndex(),
      );
      expect(
        cycleDiagnostics.map((item) => item.code),
        isNot(contains('ccrouter_component_owner_dependency_missing')),
      );

      final wrongOwnerDiagnostics = CCRouterSourceAnalyzer.analyze(
        source: '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
const ownerComponentId = CCComponentId('owner.component');
const wrongOwner = CCComponentId('wrong.component');
const consumerComponentId = CCComponentId('consumer.component');
const consumerComponent = CCComponent(
  id: CCComponentId('consumer.component'),
  version: '1.0.0',
  dependencies: [wrongOwner],
  serviceDependencies: [CCServiceDependency<SharedService>()],
);
''',
        filePath: path.join(packageRoot, 'lib', 'src', 'component.dart'),
        packageRoot: packageRoot,
        packageName: 'sample_component',
        contractOwners: _localOwnerIndex(),
      );
      expect(
        wrongOwnerDiagnostics
            .where(
              (item) =>
                  item.code == 'ccrouter_component_owner_dependency_missing',
            )
            .length,
        1,
      );
    },
  );

  test('does not let an optional dependency satisfy a Service consumer', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/owner_contracts.dart' show SharedService, RunCommand, ownerComponentId;

const consumerComponentId = CCComponentId('consumer.component');
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
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:owner_contracts/owner_contracts.dart' show SharedService, RunCommand, ownerComponentId;

const baseDependencies = <CCComponentId>[];
const consumerComponentId = CCComponentId('consumer.component');
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
        source:
            "import 'package:ccrouter_contracts/ccrouter_contracts.dart';\n${generatedCase.annotation}\n${generatedCase.declaration}\n",
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
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
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
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
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
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
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

  test('reports Route conflict and defers unresolved InitTask arguments', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
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
      hasLength(1),
    );
  });

  test('reports missing InitTask identity after a complete annotation', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
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
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
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

  test('Contract aliases reject Object members before Client generation', () {
    for (final contract in [
      'CCServiceContract',
      'CCCommandContract',
      'CCEventContract',
      'CCUIFragmentContract',
    ]) {
      for (final alias in [
        'hashCode',
        'runtimeType',
        'toString',
        'noSuchMethod',
      ]) {
        final diagnostics = CCRouterSourceAnalyzer.analyze(
          source:
              '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_contracts/ccrouter_ui_contracts.dart';
@$contract(componentId: CCComponentId('owner'), id: 'owner.probe', alias: '$alias')
abstract interface class Probe {}
''',
          filePath: path.join(packageRoot, 'lib', 'src', 'reserved_alias.dart'),
          packageRoot: packageRoot,
          packageName: 'sample_component',
        );
        expect(
          diagnostics.where((item) => item.code == 'ccrouter_alias_invalid'),
          hasLength(1),
          reason: '$contract: $alias',
        );
      }
    }
  });

  test('adjacent Contract literal strings use the same ID and alias rules', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
@CCServiceContract(componentId: CCComponentId('owner'), id: 'Bad' ' ID', alias: 'hash' 'Code')
abstract interface class Probe {}
''',
      filePath: path.join(packageRoot, 'lib/src/adjacent.dart'),
      packageRoot: packageRoot,
      packageName: 'sample_component',
    );
    expect(
      diagnostics.map((issue) => issue.code),
      containsAll(['ccrouter_identifier_invalid', 'ccrouter_alias_invalid']),
    );
  });

  test(
    'Owner Command inferred aliases are checked without guessing computed overrides',
    () {
      for (final override in [
        '',
        ", alias: 'formatOrder'",
        ', alias: localAlias',
      ]) {
        final diagnostics = CCRouterSourceAnalyzer.analyze(
          source:
              '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
@CCCommandContract(id: 'owner.format'$override)
final class ToStringCommand implements CCCommand<void> {
  const ToStringCommand();
}
''',
          filePath: path.join(packageRoot, 'lib', 'src', 'inferred_alias.dart'),
          packageRoot: packageRoot,
          packageName: 'sample_component',
        );
        expect(
          diagnostics.where((item) => item.code == 'ccrouter_alias_invalid'),
          hasLength(override.isEmpty ? 1 : 0),
          reason: override,
        );
      }
    },
  );

  test('reports Handler arity and defers unresolved imported return types', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
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
      hasLength(2),
    );
  });

  test('does not guess non-literal identifiers aliases or timeouts', () {
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
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

CCRouterContractOwnerIndex _localOwnerIndex() => CCRouterContractOwnerIndex(
  owners: const [
    CCRouterContractOwner(
      kind: CCRouterContractKind.service,
      contractSymbol: 'SharedService',
      contractPackage: 'sample_component',
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
