import 'dart:io';

import 'package:test/test.dart';

void main() {
  final checker = File('tool/documentation_check.dart').absolute.path;
  late Directory repository;

  void write(String path, String contents) {
    File('${repository.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);
  }

  Future<void> git(List<String> arguments) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: repository.path,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
  }

  Future<ProcessResult> check() => Process.run(Platform.resolvedExecutable, [
    checker,
  ], workingDirectory: repository.path);

  setUp(() async {
    repository = Directory.systemTemp.createTempSync('ccrouter-doc-check-');
    await git(['init', '-q']);
    write('README.md', '# Fixture\n');
    write('docs/README.md', '# Documents\n');
    write('demo/README.md', '# Demo\n');
    Directory('${repository.path}/demo/docs').createSync(recursive: true);
    await git(['add', '--', 'README.md', 'docs/README.md', 'demo/README.md']);
  });

  tearDown(() => repository.deleteSync(recursive: true));

  test('rejects a broken link in an untracked nested document', () async {
    // A nested file is outside top-level index coverage, so only enumerating
    // current Markdown files can find this error before staging.
    write('docs/drafts/new guide.md', '[missing](missing.md)\n');

    final result = await check();

    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('docs/drafts/new guide.md:'));
    expect('${result.stderr}', contains('missing.md'));
  });

  test('checks a new staged document against its current bytes', () async {
    write('docs/drafts/guide.md', '# Valid when staged\n');
    await git(['add', '--', 'docs/drafts/guide.md']);
    write('docs/drafts/guide.md', '[missing](missing.md)\n');

    final result = await check();

    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('docs/drafts/guide.md:'));
  });

  test('excludes ignored untracked Markdown', () async {
    write('.gitignore', 'docs/drafts/\n');
    write('docs/drafts/ignored.md', '[missing](missing.md)\n');

    final result = await check();

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}', contains('3 Markdown files'));
  });

  test('does not count deleted tracked documents as checked', () async {
    write('docs/drafts/retired.md', '# Old document\n');
    await git(['add', '--', 'docs/drafts/retired.md']);
    File('${repository.path}/docs/drafts/retired.md').deleteSync();

    final result = await check();

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}', contains('3 Markdown files'));
  });

  test('a filename mention does not satisfy index coverage', () async {
    write('docs/guide.md', '# Guide\n');
    write('docs/README.md', '# Documents\nRead guide.md for details.\n');

    final result = await check();

    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('does not reference docs/guide.md'));
  });

  test('a remote link does not satisfy local index coverage', () async {
    write('docs/guide.md', '# Guide\n');
    write(
      'docs/README.md',
      '# Documents\n[Guide](https://example.invalid/guide.md)\n',
    );

    final result = await check();

    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('does not reference docs/guide.md'));
  });

  test('resolves index links by target, including encoded names', () async {
    write('docs/new guide.md', '# Guide\n');
    write('docs/README.md', '# Documents\n[Guide](./new%20guide.md#guide)\n');

    final result = await check();

    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('does not require ignored untracked documents in indexes', () async {
    write('.gitignore', 'docs/scratch.md\n');
    write('docs/scratch.md', '[missing](missing.md)\n');

    final result = await check();

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}', contains('3 Markdown files'));
  });

  test('code and comments do not provide index navigation', () async {
    write('docs/guide.md', '# Guide\n');
    for (final example in [
      '```md\n[Guide](guide.md)\n```',
      '~~~~md\n[Guide](guide.md)\n~~~~',
      '`[Guide](guide.md)`',
      '``[Guide](guide.md) with a ` character``',
      '<!-- [Guide](guide.md) -->',
    ]) {
      write('docs/README.md', '# Documents\n$example\n');

      final result = await check();

      expect(result.exitCode, 1, reason: example);
      expect('${result.stderr}', contains('does not reference docs/guide.md'));
    }
  });

  test('does not validate illustrative links in code or comments', () async {
    write('README.md', '''
# Fixture
```md
[Example](missing.md)
```
`[Example](missing.md)`
<!-- [Example](missing.md) -->
''');

    final result = await check();

    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test(
    'keeps real links after code fences and code-formatted labels',
    () async {
      write('docs/guide.md', '# Guide\n');
      write('docs/README.md', '''
# Documents
````md
```
[Example](missing.md)
```
````
[`guide.md`](guide.md)
''');

      final result = await check();

      expect(result.exitCode, 0, reason: '${result.stderr}');
    },
  );

  test('reports only the rendered broken target after code examples', () async {
    write('README.md', '''
# Fixture
```md
[Example](not-checked.md)
```
`[Example](also-not-checked.md)`
[Broken](missing.md)
''');

    final result = await check();

    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('README.md: missing local link'));
    expect('${result.stderr}', isNot(contains('not-checked.md')));
  });

  test('unmatched backticks cannot hide links in later blocks', () async {
    write('README.md', '''
# Fixture
A literal ` character.

```dart
final example = `value`;
```
[Broken](missing.md)
''');

    final result = await check();

    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('README.md: missing local link'));
  });

  for (final entry in {
    'reference links': '[Broken][detail]\n\n[detail]: missing.md\n',
    'angle paths with parentheses': '[Broken](<missing (v2).md>)\n',
    'nested link labels': '[Broken [detail]](missing.md)\n',
    'escaped backticks': r'\` [Broken](missing.md) \`',
  }.entries) {
    test('validates ${entry.key}', () async {
      write('README.md', entry.value);

      final result = await check();

      expect(result.exitCode, 1, reason: entry.value);
      expect('${result.stderr}', contains('missing'));
    });
  }

  for (final entry in {
    'indented code': '    [Example](missing.md)\n',
    'escaped link syntax': r'\[Example](missing.md)',
  }.entries) {
    test('ignores ${entry.key}', () async {
      write('README.md', entry.value);

      final result = await check();

      expect(result.exitCode, 0, reason: '${result.stderr}');
    });
  }

  test('reference links provide real index navigation', () async {
    write('docs/guide.md', '# Guide\n');
    write('docs/README.md', '[Guide][detail]\n\n[detail]: guide.md\n');

    final result = await check();

    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('resolves balanced paths, encoded names, query and fragment', () async {
    write('docs/Guide (v2) #中文.md', '# Guide\n');
    write('docs/README.md', '[Guide](<Guide (v2) %23中文.md?plain=1#guide>)\n');

    final result = await check();

    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('image targets do not substitute for index navigation', () async {
    write('docs/guide.md', '# Guide\n');
    write('docs/README.md', '![Guide](guide.md)\n');

    final result = await check();

    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('does not reference docs/guide.md'));
  });
}
