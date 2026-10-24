import 'package:test/test.dart';

import '../markdown_links.dart';

void main() {
  final source = Uri.parse('file:///bundle/skill/SKILL.md');

  for (final entry in {
    'guide.md?plain=1#heading': 'file:///bundle/skill/guide.md',
    'guide%20(v2)%23中文.md': 'file:///bundle/skill/guide%20(v2)%23中文.md',
    'literal%2520name.md': 'file:///bundle/skill/literal%2520name.md',
    '%252e%252e/guide.md': 'file:///bundle/skill/%252e%252e/guide.md',
    '%2e%2e/%2e%2e/outside.md': 'file:///outside.md',
    'a+b.md': 'file:///bundle/skill/a+b.md',
  }.entries) {
    test('local destination ${entry.key} resolves without double decoding', () {
      expect(localMarkdownTarget(entry.key, source), Uri.parse(entry.value));
    });
  }

  test('external and fragment-only links do not become local paths', () {
    for (final target in [
      'https://example.invalid/guide.md',
      '//example.invalid/guide.md',
      'mailto:example@example.invalid',
      '#heading',
      '?plain=1#heading',
    ]) {
      expect(localMarkdownTarget(target, source), isNull, reason: target);
    }
  });

  test('unused definitions do not create rendered links', () {
    expect(markdownReferences('[unused]: missing.md\n'), isEmpty);
  });

  test('rendered links and images retain distinct index semantics', () {
    final links = markdownReferences('''
[Guide][detail]
![Preview](image.png)

[detail]: guide.md
''');
    expect(links.map((link) => link.target), ['guide.md', 'image.png']);
    expect(links.map((link) => link.isImage), [false, true]);
  });
}
