import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('pre-stage mode checks untracked evidence without printing values', () {
    final script = File('tool/release_sensitivity_check.dart').absolute.path;
    final fixture = Directory.systemTemp.createTempSync(
      'ccrouter-sensitivity-',
    );
    addTearDown(() => fixture.deleteSync(recursive: true));
    expect(
      Process.runSync('git', [
        'init',
        '-q',
      ], workingDirectory: fixture.path).exitCode,
      0,
    );
    final privatePath = ['/', 'Users', '/', 'synthetic', '/repo'].join();
    File('${fixture.path}/evidence.log').writeAsStringSync(privatePath);
    ProcessResult check(List<String> args) => Process.runSync(
      Platform.resolvedExecutable,
      [script, ...args],
      workingDirectory: fixture.path,
    );

    expect(check([]).exitCode, 0);
    final result = check(['--include-untracked']);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('evidence.log:1: macOS absolute home path'));
    expect('${result.stdout}${result.stderr}', isNot(contains(privatePath)));
    expect(check(['--unknown']).exitCode, 2);
  });
}
