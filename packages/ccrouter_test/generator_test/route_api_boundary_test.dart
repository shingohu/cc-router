@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('another Package reports internal use and hides the public Route API', () async {
    final root = _workspaceRoot();
    final probeDirectory = Directory(
      path.join(root.path, 'demo', 'test', '_ccrouter_route_api_probe'),
    );
    expect(probeDirectory.existsSync(), isFalse);
    final probe = File(
      path.join(probeDirectory.path, 'probe.dart'),
    );
    addTearDown(() {
      if (probeDirectory.existsSync()) {
        probeDirectory.deleteSync(recursive: true);
      }
    });

    // ccrouter_demo is a separate Package with a declared dependency on
    // demo_navigation_lab, so its Analyzer uses the real workspace graph.
    probeDirectory.createSync(recursive: true);
    probe.writeAsStringSync('''
import 'package:demo_navigation_lab/src/ccrouter_generated/component/demo_navigation_lab_component.route_api.g.dart';

void probe() {
  DemoNavigationLabRoutes.detail(id: 1);
}
''');
    final defaultAnalysis = await _analyze(probe);
    expect(defaultAnalysis.stdout, contains('invalid_use_of_internal_member'));
    expect(defaultAnalysis.exitCode, isNonZero);

    probe.writeAsStringSync('''
import 'package:demo_navigation_lab/src/ccrouter_generated/component/demo_navigation_lab_component.route_api.g.dart';

void probe() {
  // ignore: invalid_use_of_internal_member
  DemoNavigationLabRoutes.detail(id: 1);
}
''');
    final ignored = await _analyze(probe);
    expect(ignored.stdout, contains('No issues found!'));

    probe.writeAsStringSync('''
import 'package:demo_navigation_lab/demo_navigation_lab.dart';

void probe() {
  DemoNavigationLabRoutes.detail(id: 1);
}
''');
    final public = await _analyze(probe);
    expect(public.stdout, contains('undefined_identifier'));
    expect(public.stdout, isNot(contains('implementation_imports')));
  });
}

Future<ProcessResult> _analyze(File source) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'analyze',
    source.absolute.path,
  ], workingDirectory: _workspaceRoot().path);
  expect(result.stderr, isEmpty, reason: '${result.stderr}');
  return result;
}

Directory _workspaceRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (File(path.join(current.path, 'demo', 'pubspec.yaml')).existsSync() &&
        File(path.join(current.path, 'pubspec.yaml')).existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('CCRouter workspace root was not found.');
    }
    current = parent;
  }
}
