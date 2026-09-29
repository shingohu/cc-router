import 'package:ccrouter_analyzer_plugin/src/quick_fixes.dart';
import 'package:test/test.dart';

void main() {
  test('offers explicit alternatives for Route pattern conflicts', () {
    const source = '''
@CCRoute<void>(
  id: 'sample.route',
  pattern: CCPathPattern('/sample'),
  patterns: [CCPathPattern('/legacy')],
)
class SamplePage {}
''';
    final fixes = CCRouterQuickFixes.compute(
      source: source,
      filePath: '/workspace/lib/src/sample_page.dart',
      offset: source.indexOf('@CCRoute'),
    );

    expect(fixes.map((item) => item.id), [
      'ccrouter.remove_conflicting_pattern',
      'ccrouter.remove_conflicting_patterns',
    ]);
    final withoutPattern = _apply(source, fixes.first);
    expect(
      withoutPattern,
      isNot(contains("pattern: CCPathPattern('/sample')")),
    );
    expect(withoutPattern, contains('patterns:'));
    final withoutPatterns = _apply(source, fixes.last);
    expect(withoutPatterns, contains('pattern:'));
    expect(withoutPatterns, isNot(contains('patterns:')));
  });

  test('offers explicit alternatives for InitTask identity conflicts', () {
    const source = '''
@CCInitTask(
  contract: startupTask,
  id: 'startup.task',
  gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.optional,
)
void initializeFeature() {}
''';
    final fixes = CCRouterQuickFixes.compute(
      source: source,
      filePath: '/workspace/lib/src/init_task.dart',
      offset: source.indexOf('@CCInitTask'),
    );

    expect(fixes, hasLength(2));
    expect(_apply(source, fixes.first), isNot(contains('contract:')));
    expect(_apply(source, fixes.last), isNot(contains("id: 'startup.task'")));
  });

  test('declines a deletion that would consume a source comment', () {
    const source = '''
@CCRoute<void>(
  id: 'sample.route',
  pattern: CCPathPattern('/sample'), // Keep this explanation.
  patterns: [CCPathPattern('/legacy')],
)
class SamplePage {}
''';
    final fixes = CCRouterQuickFixes.compute(
      source: source,
      filePath: '/workspace/lib/src/sample_page.dart',
      offset: source.indexOf('@CCRoute'),
    );

    expect(fixes, isEmpty);
  });

  test('does not offer guesses for non-conflict diagnostics', () {
    const source = '''
@CCServiceContract(id: 'Bad ID', alias: 'class')
abstract interface class InvalidService {}
''';
    final fixes = CCRouterQuickFixes.compute(
      source: source,
      filePath: '/workspace/lib/src/service.dart',
      offset: source.indexOf('@CCServiceContract'),
    );

    expect(fixes, isEmpty);
  });
}

String _apply(String source, CCRouterSourceFix fix) =>
    source.replaceRange(fix.offset, fix.offset + fix.length, fix.replacement);
