import 'dart:io';

import 'package:ccrouter_analyzer_plugin/src/diagnostics.dart';
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
    final diagnostics = CCRouterAnalyzerDiagnostics.analyze(
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
    final diagnostics = CCRouterAnalyzerDiagnostics.analyze(
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
    final diagnostics = CCRouterAnalyzerDiagnostics.analyze(
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
      CCRouterAnalyzerDiagnostics.authoredRoutePathForGenerated(generated),
      path.join(packageRoot, 'lib', 'src', 'pages', 'network_page.dart'),
    );
  });

  test('ignores unrelated generated files for source refresh', () {
    expect(
      CCRouterAnalyzerDiagnostics.authoredRoutePathForGenerated(
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
      () => CCRouterAnalyzerDiagnostics.analyze(
        source: 'class HomePage {',
        filePath: path.join(packageRoot, 'lib', 'src', 'home_page.dart'),
        packageRoot: packageRoot,
        packageName: 'sample_component',
      ),
      returnsNormally,
    );
  });

  test('does not flag generated implementation imports', () {
    final diagnostics = CCRouterAnalyzerDiagnostics.analyze(
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
}
