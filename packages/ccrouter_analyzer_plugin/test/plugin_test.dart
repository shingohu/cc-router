import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:ccrouter_analyzer_plugin/src/plugin.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  test('advertises a stable name and supported server boundary', () {
    final plugin = CCRouterAnalyzerPlugin(
      PhysicalResourceProvider.INSTANCE,
    );

    expect(plugin.name, 'CCRouter Analysis Server Plugin');
    expect(plugin.version, '1.0.0');
    expect(plugin.isCompatibleWith(Version(1, 0, 0)), isTrue);
    expect(plugin.isCompatibleWith(Version(1, 0, 1)), isFalse);
    expect(plugin.isCompatibleWith(Version(2, 0, 0)), isFalse);
  });
}
