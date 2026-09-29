import 'dart:io';

import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer_plugin/protocol/protocol_generated.dart';
import 'package:ccrouter_analyzer_plugin/src/plugin.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  test('advertises a stable name and supported server boundary', () {
    final plugin = CCRouterAnalyzerPlugin(PhysicalResourceProvider.INSTANCE);

    expect(plugin.name, 'CCRouter Analysis Server Plugin');
    expect(plugin.version, '1.0.0');
    expect(plugin.isCompatibleWith(Version(1, 0, 0)), isTrue);
    expect(plugin.isCompatibleWith(Version(1, 0, 1)), isFalse);
    expect(plugin.isCompatibleWith(Version(2, 0, 0)), isFalse);
  });

  test('returns protocol Quick Fixes for one conflict diagnostic', () async {
    final root = Directory.systemTemp.createTempSync('ccrouter-plugin-fix-');
    addTearDown(() => root.deleteSync(recursive: true));
    File(
      path.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: plugin_fix_test\n');
    const source = '''
@CCRoute<void>(
  id: 'sample.route',
  pattern: CCPathPattern('/sample'),
  patterns: [CCPathPattern('/legacy')],
)
class SamplePage {}
''';
    final sourceFile = File(
      path.join(root.path, 'lib', 'src', 'sample_page.dart'),
    )..createSync(recursive: true);
    sourceFile.writeAsStringSync(source);
    final plugin = CCRouterAnalyzerPlugin(PhysicalResourceProvider.INSTANCE);

    final result = await plugin.handleEditGetFixes(
      EditGetFixesParams(sourceFile.path, source.indexOf('@CCRoute')),
    );

    expect(result.fixes, hasLength(1));
    expect(
      result.fixes.single.error.code,
      'ccrouter_annotation_arguments_conflict',
    );
    expect(result.fixes.single.fixes, hasLength(2));
  });
}
