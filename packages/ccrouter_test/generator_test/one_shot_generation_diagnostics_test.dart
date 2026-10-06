@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../ccrouter_generator/bin/src/one_shot_generation_diagnostics.dart';
import '../../ccrouter_generator/bin/src/pub_hook_watch_coordination.dart';

void main() {
  test('publishes failed and successful one-shot terminal snapshots', () async {
    final root = Directory.systemTemp.createTempSync(
      'ccrouter-one-shot-diagnostics-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    File(
      path.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: host\n');
    File(path.join(root.path, 'pubspec.lock')).writeAsStringSync('{}\n');
    File(path.join(root.path, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{}\n');
    File(
      path.join(root.path, '.dart_tool', 'package_graph.json'),
    ).writeAsStringSync('{}\n');

    await CCOneShotGenerationDiagnosticsPublisher.publish(
      hostRoot: root,
      buildRoot: root,
      succeeded: false,
      structuredDiagnostics: const [
        {'code': 'ccrouter_host_component_owner_missing', 'severity': 'error'},
      ],
    );
    final file = CCOneShotGenerationDiagnosticsPublisher.fileFor(root);
    final failed = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(failed['producer'], 'oneShot');
    expect(failed['outcome'], 'failed');
    expect(failed['diagnostics'], hasLength(1));
    expect(
      failed['resolutionFingerprint'],
      await CCPubResolutionFingerprint.capture(hostRoot: root, buildRoot: root),
    );

    await CCOneShotGenerationDiagnosticsPublisher.publish(
      hostRoot: root,
      buildRoot: root,
      succeeded: true,
      structuredDiagnostics: const [
        {'code': 'must_not_survive'},
      ],
    );
    final succeeded = jsonDecode(file.readAsStringSync()) as Map;
    expect(succeeded['outcome'], 'succeeded');
    expect(succeeded['diagnostics'], isEmpty);
  });
}
