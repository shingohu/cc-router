@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  final nodeAvailable = _nodeAvailable();

  test('Hvigor preflight is ordered before the Flutter task', () {
    final source = File(
      path.join(Directory.current.path, 'demo', 'ohos', 'hvigorfile.ts'),
    ).readAsStringSync();

    expect(source, contains(r'name: `${targetName}@CCRouterPreflight`'));
    expect(
      source,
      contains(r'postDependencies: [`${targetName}@FlutterTask`]'),
    );
  });

  test(
    'Hvigor preflight uses the resolved SDK Dart and propagates failure',
    () async {
      final fixture = await _createFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      final trace = File(path.join(fixture.root.path, 'trace.txt'));

      final succeeded = await _runHelper(fixture, trace);
      expect(succeeded.exitCode, 0, reason: '${succeeded.stderr}');
      expect(trace.readAsLinesSync(), [
        'run',
        '--verbosity=error',
        'ccrouter_generator:ccrouter',
        'pub-hook',
        'run',
        '--project-root',
        fixture.project.absolute.path,
        '--pub-command',
        'build',
      ]);

      fixture.dartExecutable.writeAsStringSync('''#!/usr/bin/env bash
exit 7
''');
      final failed = await _runHelper(fixture, trace);
      expect(failed.exitCode, isNot(0));
      expect('${failed.stderr}', contains('exit 7'));
    },
    skip: nodeAvailable ? false : 'Node.js is required for Hvigor glue tests.',
  );

  test(
    'Hvigor preflight has an isolated bypass',
    () async {
      final fixture = await _createFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      final trace = File(path.join(fixture.root.path, 'trace.txt'));

      final result = await _runHelper(
        fixture,
        trace,
        environment: {'CCROUTER_DISABLE_HVIGOR_PREFLIGHT': '1'},
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}', contains('Hvigor preflight disabled'));
      expect(trace.existsSync(), isFalse);
    },
    skip: nodeAvailable ? false : 'Node.js is required for Hvigor glue tests.',
  );
}

bool _nodeAvailable() {
  try {
    return Process.runSync('node', const ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

final class _HvigorFixture {
  const _HvigorFixture({
    required this.root,
    required this.project,
    required this.dartExecutable,
    required this.runner,
  });

  final Directory root;
  final Directory project;
  final File dartExecutable;
  final File runner;
}

Future<_HvigorFixture> _createFixture() async {
  final root = await Directory.systemTemp.createTemp(
    'ccrouter_hvigor_preflight_',
  );
  final project = Directory(path.join(root.path, 'project with spaces'))
    ..createSync();
  final sdk = Directory(path.join(root.path, 'sdk with spaces'))..createSync();
  final dartExecutable = File(
    path.join(sdk.path, 'bin', 'cache', 'dart-sdk', 'bin', 'dart'),
  )..parent.createSync(recursive: true);
  dartExecutable.writeAsStringSync('''#!/usr/bin/env bash
printf '%s\\n' "\$@" > "\$CCROUTER_TEST_TRACE"
''');
  await Process.run('chmod', ['+x', dartExecutable.path]);
  final ohos = Directory(path.join(project.path, 'ohos'))..createSync();
  File(
    path.join(ohos.path, 'local.properties'),
  ).writeAsStringSync('flutter.sdk=${sdk.path.replaceAll(' ', r'\ ')}\n');
  final helper = path.join(
    Directory.current.path,
    'demo',
    'ohos',
    'ccrouter-preflight.js',
  );
  final runner = File(path.join(root.path, 'runner.js'))
    ..writeAsStringSync('''
const { ccrouterBuildPreflight } = require(${jsonEncode(helper)})
ccrouterBuildPreflight(process.argv[2])
''');
  return _HvigorFixture(
    root: root,
    project: project,
    dartExecutable: dartExecutable,
    runner: runner,
  );
}

Future<ProcessResult> _runHelper(
  _HvigorFixture fixture,
  File trace, {
  Map<String, String>? environment,
}) => Process.run(
  'node',
  [fixture.runner.path, fixture.project.path],
  environment: {
    ...Platform.environment,
    'CCROUTER_TEST_TRACE': trace.path,
    ...?environment,
  },
);
