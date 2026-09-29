import 'dart:io';

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
    final output = File(
      path.join(
        packageRoot,
        'lib',
        'src',
        'ccrouter_generated',
        'route',
        'home_page.route.g.dart',
      ),
    )..createSync(recursive: true);
    addTearDown(() => output.deleteSync());
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
      CCRouterSourceAnalyzer.authoredRoutePathForGenerated(generated),
      path.join(packageRoot, 'lib', 'src', 'pages', 'network_page.dart'),
    );
  });

  test('ignores unrelated generated files for source refresh', () {
    expect(
      CCRouterSourceAnalyzer.authoredRoutePathForGenerated(
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
}
