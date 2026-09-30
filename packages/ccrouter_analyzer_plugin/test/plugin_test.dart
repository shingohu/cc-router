import 'dart:convert';
import 'dart:io';

import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer_plugin/channel/channel.dart';
import 'package:analyzer_plugin/protocol/protocol.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
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

  test('reports diagnostics from the latest unsaved overlay', () async {
    final root = Directory.systemTemp.createTempSync('ccrouter-overlay-');
    addTearDown(() => root.deleteSync(recursive: true));
    File(
      path.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: overlay_test\n');
    final sourceFile = File(
      path.join(root.path, 'lib', 'src', 'sample_page.dart'),
    )..createSync(recursive: true);
    sourceFile.writeAsStringSync('''
@CCRoute<void>(
  id: 'sample.route',
  pattern: CCPathPattern('/sample'),
)
class SamplePage {}
''');
    final plugin = CCRouterAnalyzerPlugin(PhysicalResourceProvider.INSTANCE);
    final channel = _RecordingChannel();
    plugin.start(channel);

    await plugin.handleAnalysisUpdateContent(
      AnalysisUpdateContentParams({
        sourceFile.path: AddContentOverlay('''
@CCRoute<void>(
  id: 'sample.route',
  pattern: CCPathPattern('/sample'),
  patterns: [CCPathPattern('/legacy')],
)
class SamplePage {}
'''),
      }),
    );

    final errors = AnalysisErrorsParams.fromNotification(
      channel.notifications.single,
    ).errors;
    expect(
      errors.map((error) => error.code),
      contains('ccrouter_annotation_arguments_conflict'),
    );
  });

  test('returns a protocol Quick Fix for one proven missing owner', () async {
    final root = Directory.systemTemp.createTempSync('ccrouter-plugin-owner-');
    addTearDown(() => root.deleteSync(recursive: true));
    final consumer = Directory(path.join(root.path, 'consumer'))
      ..createSync(recursive: true);
    final owner = Directory(path.join(root.path, 'owner_contracts'))
      ..createSync(recursive: true);
    File(
      path.join(consumer.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: consumer\n');
    File(
      path.join(owner.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: owner_contracts\n');
    File(path.join(owner.path, 'lib', 'src', 'contracts.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('''
const ownerComponentId = CCComponentId('owner.component');
@CCServiceContract(componentId: ownerComponentId, id: 'owner.service')
abstract interface class SharedService {}
''');
    File(path.join(owner.path, 'lib', 'owner_contracts.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "export 'src/contracts.dart' show SharedService, ownerComponentId;\n",
      );
    File(
        path.join(
          owner.path,
          'lib',
          'src',
          'ccrouter_generated',
          'metadata',
          'ccrouter_package.json',
        ),
      )
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'capabilityCatalog': {
            'records': [
              {
                'kind': 'service',
                'componentId': 'owner.component',
                'contract': {
                  'symbol': 'SharedService',
                  'packageUri': 'package:owner_contracts/src/contracts.dart',
                },
              },
            ],
          },
        }),
      );
    File(path.join(root.path, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'consumer',
              'rootUri': '../consumer',
              'packageUri': 'lib/',
            },
            {
              'name': 'owner_contracts',
              'rootUri': '../owner_contracts',
              'packageUri': 'lib/',
            },
          ],
        }),
      );
    const source = '''
import 'package:owner_contracts/owner_contracts.dart';
const consumerComponent = CCComponent(
  id: consumerComponentId,
  version: '1.0.0',
  serviceDependencies: [CCServiceDependency<SharedService>()],
);
''';
    final sourceFile = File(
      path.join(consumer.path, 'lib', 'src', 'component.dart'),
    )..createSync(recursive: true);
    sourceFile.writeAsStringSync(source);
    final plugin = CCRouterAnalyzerPlugin(PhysicalResourceProvider.INSTANCE);

    final result = await plugin.handleEditGetFixes(
      EditGetFixesParams(
        sourceFile.path,
        source.indexOf('CCServiceDependency'),
      ),
    );

    expect(result.fixes, hasLength(1));
    expect(
      result.fixes.single.error.code,
      'ccrouter_component_owner_dependency_missing',
    );
    expect(result.fixes.single.fixes, hasLength(1));
    expect(
      result
          .fixes
          .single
          .fixes
          .single
          .change
          .edits
          .single
          .edits
          .single
          .replacement,
      contains('dependencies: [ownerComponentId]'),
    );
  });
}

/// Minimal channel that captures diagnostics emitted by a direct plugin test.
final class _RecordingChannel implements PluginCommunicationChannel {
  /// Notifications emitted by the plugin under test.
  final List<Notification> notifications = <Notification>[];

  @override
  void close() {}

  @override
  void listen(
    void Function(Request request)? onRequest, {
    void Function()? onDone,
    Function? onError,
    Function(Notification)? onNotification,
  }) {}

  @override
  void sendNotification(Notification notification) {
    notifications.add(notification);
  }

  @override
  void sendResponse(Response response) {}
}
