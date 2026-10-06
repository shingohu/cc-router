import 'dart:convert';
import 'dart:io';

import 'package:ccrouter_analyzer_plugin/src/generator_diagnostics_bridge.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('accepts only the current failed watch identity', () {
    final fixture = _BridgeFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeStatus(eventRevision: 7);
    fixture.writeDiagnostics(eventRevision: 7);

    final accepted = fixture.bridge.diagnosticsFor(fixture.source.path);
    expect(accepted, hasLength(1));
    expect(accepted.single.code, 'ccrouter_host_component_owner_missing');
    expect(accepted.single.path, fixture.source.path);
    expect(fixture.bridge.affectedDartPaths(fixture.diagnostics.path), {
      fixture.source.path,
    });

    fixture.writeStatus(eventRevision: 8);
    expect(fixture.bridge.diagnosticsFor(fixture.source.path), isEmpty);
    expect(fixture.bridge.affectedDartPaths(fixture.diagnostics.path), {
      fixture.source.path,
    });
    expect(fixture.bridge.affectedDartPaths(fixture.diagnostics.path), isEmpty);
  });

  test('clears diagnostics published during initial source analysis', () {
    final fixture = _BridgeFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeStatus(eventRevision: 7);
    fixture.writeDiagnostics(eventRevision: 7);

    expect(fixture.bridge.diagnosticsFor(fixture.source.path), hasLength(1));
    fixture.writeStatus(eventRevision: 8);
    expect(fixture.bridge.affectedDartPaths(fixture.status.path), {
      fixture.source.path,
    });

    fixture.bridge.clear();
    expect(fixture.bridge.affectedDartPaths(fixture.status.path), isEmpty);
  });

  test('accepts a current failed one-shot snapshot without watch', () {
    final fixture = _BridgeFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeOneShotDiagnostics(succeeded: false);

    final accepted = fixture.bridge.diagnosticsFor(fixture.source.path);

    expect(accepted, hasLength(1));
    expect(accepted.single.code, 'ccrouter_host_component_owner_missing');
    expect(fixture.bridge.affectedDartPaths(fixture.oneShotDiagnostics.path), {
      fixture.source.path,
    });
  });

  test('invalidates one-shot diagnostics when resolution inputs change', () {
    final fixture = _BridgeFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeOneShotDiagnostics(succeeded: false);

    expect(fixture.bridge.pollAffectedDartPaths(fixture.root), {
      fixture.source.path,
    });
    fixture.pubspec.writeAsStringSync('''
name: bridge_host
dependencies:
  ccrouter: any
  changed_dependency: any
''');

    expect(fixture.bridge.pollAffectedDartPaths(fixture.root), {
      fixture.source.path,
    });
    expect(fixture.bridge.diagnosticsFor(fixture.source.path), isEmpty);
  });

  test('successful one-shot clears a previously published failure', () {
    final fixture = _BridgeFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeOneShotDiagnostics(succeeded: false);
    expect(fixture.bridge.diagnosticsFor(fixture.source.path), hasLength(1));

    fixture.writeOneShotDiagnostics(succeeded: true);

    expect(fixture.bridge.affectedDartPaths(fixture.oneShotDiagnostics.path), {
      fixture.source.path,
    });
    expect(fixture.bridge.diagnosticsFor(fixture.source.path), isEmpty);
  });

  test('active successful watch suppresses an older failed one-shot', () {
    final fixture = _BridgeFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeOneShotDiagnostics(succeeded: false);
    fixture.writeStatus(eventRevision: 8, lastEvent: 'aggregationSucceeded');
    fixture.writeDiagnostics(
      eventRevision: 8,
      lastEvent: 'aggregationSucceeded',
      includeDiagnostic: false,
    );

    expect(fixture.bridge.diagnosticsFor(fixture.source.path), isEmpty);
  });

  test('reports only saved manifest versus resolved graph drift', () {
    final fixture = _BridgeFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeStatus(eventRevision: 1);
    fixture.pubspec.writeAsStringSync('''
name: bridge_host
dependencies:
  ccrouter: any
#  demo_order: any
''');
    fixture.writePackageGraph(['ccrouter', 'demo_order']);

    final stale = fixture.bridge.pubResolutionHint(fixture.pubspec);
    expect(stale, isNotNull);
    expect(stale!.message, contains('still resolved: demo_order'));
    expect(stale.message, contains('ownership conclusions are suspended'));

    fixture.writePackageGraph(['ccrouter']);
    expect(fixture.bridge.pubResolutionHint(fixture.pubspec), isNull);
  });

  test('compares an unsaved manifest overlay with the resolved graph', () {
    final fixture = _BridgeFixture.create();
    addTearDown(fixture.dispose);
    fixture.pubspec.writeAsStringSync('''
name: bridge_host
dependencies:
  ccrouter: any
  demo_order: any
''');
    fixture.writePackageGraph(['ccrouter', 'demo_order']);

    final stale = fixture.bridge.pubResolutionHint(
      fixture.pubspec,
      contents: '''
name: bridge_host
dependencies:
  ccrouter: any
#  demo_order: any
''',
    );

    expect(stale, isNotNull);
    expect(stale!.message, contains('still resolved: demo_order'));
    expect(
      fixture.bridge.pubResolutionHint(
        fixture.pubspec,
        contents: fixture.pubspec.readAsStringSync(),
      ),
      isNull,
    );
  });

  test(
    'uses role-specific stale resolution guidance without an active watch',
    () {
      final host = _BridgeFixture.create();
      final flutterPackage = _BridgeFixture.create();
      final dartPackage = _BridgeFixture.create();
      addTearDown(host.dispose);
      addTearDown(flutterPackage.dispose);
      addTearDown(dartPackage.dispose);
      host.writeProject(
        dependency: 'ccrouter',
        projectType: 'app',
        hostEnabled: null,
      );
      flutterPackage.writeProject(
        dependency: 'ccrouter',
        projectType: 'package',
        hostEnabled: null,
      );
      dartPackage.writeProject(
        dependency: 'ccrouter_contracts',
        projectType: null,
        hostEnabled: null,
      );
      host.writePackageGraph(['ccrouter', 'stale_dependency']);
      flutterPackage.writePackageGraph(['ccrouter', 'stale_dependency']);
      dartPackage.writePackageGraph(['ccrouter_contracts', 'stale_dependency']);

      final hostHint = host.bridge.pubResolutionHint(host.pubspec)!;
      final flutterHint = flutterPackage.bridge.pubResolutionHint(
        flutterPackage.pubspec,
      )!;
      final dartHint = dartPackage.bridge.pubResolutionHint(
        dartPackage.pubspec,
      )!;

      expect(hostHint.message, contains('Saved Host dependencies'));
      expect(hostHint.correction, contains('flutter pub get'));
      expect(flutterHint.message, contains('Saved Package dependencies'));
      expect(flutterHint.correction, contains('flutter pub get'));
      expect(dartHint.message, contains('Saved Package dependencies'));
      expect(dartHint.correction, contains('dart pub get'));
      expect(dartHint.correction, isNot(contains('flutter pub get')));
    },
  );

  test('treats role and Workspace reference files as bridge inputs', () {
    final fixture = _BridgeFixture.create();
    addTearDown(fixture.dispose);

    for (final relativePath in const [
      '.metadata',
      'ccrouter.yaml',
      '.dart_tool/pub/workspace_ref.json',
    ]) {
      expect(
        fixture.bridge.isBridgeInput(
          path.join(fixture.root.path, relativePath),
        ),
        isTrue,
        reason: relativePath,
      );
    }
  });

  test('accepts watch identity through a symlinked Host path', () {
    if (Platform.isWindows) return;
    final fixture = _BridgeFixture.create();
    final aliases = Directory.systemTemp.createTempSync(
      'ccrouter-bridge-alias-',
    );
    final alias = Directory(path.join(aliases.path, 'host'));
    Link(alias.path).createSync(fixture.root.path);
    addTearDown(() => aliases.deleteSync(recursive: true));
    addTearDown(fixture.dispose);
    fixture.writeStatus(eventRevision: 7);
    fixture.writeDiagnostics(eventRevision: 7);
    fixture.pubspec.writeAsStringSync('''
name: bridge_host
dependencies:
  ccrouter: any
#  demo_order: any
''');
    fixture.writePackageGraph(['ccrouter', 'demo_order']);

    final aliasedSource = path.join(alias.path, 'lib', 'src', 'component.dart');
    final diagnostics = fixture.bridge.diagnosticsFor(aliasedSource);
    final hint = fixture.bridge.pubResolutionHint(
      File(path.join(alias.path, 'pubspec.yaml')),
    );

    expect(diagnostics, hasLength(1));
    expect(hint, isNotNull);
    expect(hint!.message, contains('still resolved: demo_order'));
  });

  test('kill switch disables snapshots and Pub resolution hints', () {
    final fixture = _BridgeFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeStatus(eventRevision: 7);
    fixture.writeDiagnostics(eventRevision: 7);
    fixture.pubspec.writeAsStringSync('''
name: bridge_host
dependencies:
  ccrouter: any
''');
    fixture.writePackageGraph(['ccrouter', 'demo_order']);
    final bridge = CCRouterGeneratorDiagnosticsBridge(
      environment: {ccrouterAnalyzerWatchBridgeKillSwitch: '1'},
    );

    expect(bridge.enabled, isFalse);
    expect(bridge.diagnosticsFor(fixture.source.path), isEmpty);
    expect(bridge.affectedDartPaths(fixture.status.path), isEmpty);
    fixture.writeOneShotDiagnostics(succeeded: false);
    expect(bridge.affectedDartPaths(fixture.oneShotDiagnostics.path), isEmpty);
    expect(bridge.pubResolutionHint(fixture.pubspec), isNull);
  });
}

final class _BridgeFixture {
  _BridgeFixture._({
    required this.root,
    required this.source,
    required this.pubspec,
    required this.status,
    required this.diagnostics,
    required this.oneShotDiagnostics,
  });

  final Directory root;
  final File source;
  final File pubspec;
  final File status;
  final File diagnostics;
  final File oneShotDiagnostics;
  final CCRouterGeneratorDiagnosticsBridge bridge =
      CCRouterGeneratorDiagnosticsBridge();

  static _BridgeFixture create() {
    final root = Directory.systemTemp.createTempSync('ccrouter-bridge-test-');
    final source = File(path.join(root.path, 'lib', 'src', 'component.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('const component = 1;\n');
    final pubspec = File(path.join(root.path, 'pubspec.yaml'))
      ..writeAsStringSync('name: bridge_host\n');
    final watch = Directory(
      path.join(root.path, '.dart_tool', 'ccrouter', 'v1', 'watch'),
    )..createSync(recursive: true);
    final status = File(path.join(watch.path, 'status.json'));
    final diagnostics = File(path.join(watch.path, 'diagnostics.json'));
    final oneShotDiagnostics = File(
      path.join(
        root.path,
        '.dart_tool',
        'ccrouter',
        'v1',
        'generation',
        'diagnostics.json',
      ),
    );
    File(path.join(root.path, '.dart_tool', 'package_config.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {'name': 'bridge_host', 'rootUri': '../', 'packageUri': 'lib/'},
          ],
        }),
      );
    return _BridgeFixture._(
      root: root,
      source: source,
      pubspec: pubspec,
      status: status,
      diagnostics: diagnostics,
      oneShotDiagnostics: oneShotDiagnostics,
    );
  }

  void writeStatus({required int eventRevision, String lastEvent = 'failed'}) {
    status.writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'active': true,
        'lastEvent': lastEvent,
        'hostRoot': root.path,
        'buildRoot': root.path,
        'sessionId': 'session-1',
        'eventRevision': eventRevision,
        'cycle': 2,
        'resolutionFingerprint': 'resolution-1',
      }),
    );
  }

  void writeDiagnostics({
    required int eventRevision,
    String lastEvent = 'failed',
    bool includeDiagnostic = true,
  }) {
    diagnostics.writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'hostRoot': root.path,
        'buildRoot': root.path,
        'sessionId': 'session-1',
        'eventRevision': eventRevision,
        'cycle': 2,
        'lastEvent': lastEvent,
        'resolutionFingerprint': 'resolution-1',
        'cycleResolutionState': 'matched',
        'diagnostics': [
          if (includeDiagnostic)
            {
              'code': 'ccrouter_host_component_owner_missing',
              'severity': 'error',
              'message': 'Host closure is missing an owner.',
              'correction': 'Run Pub get.',
              'rootCauseGroup': 'missing-owner:orders',
              'primaryLocation': {
                'uri': 'package:bridge_host/src/component.dart',
                'line': 1,
                'column': 7,
                'length': 9,
              },
            },
        ],
      }),
    );
  }

  void writeOneShotDiagnostics({required bool succeeded}) {
    oneShotDiagnostics
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'producer': 'oneShot',
          'hostRoot': root.path,
          'buildRoot': root.path,
          'outcome': succeeded ? 'succeeded' : 'failed',
          'resolutionFingerprint': _resolutionFingerprint(),
          'diagnostics': [
            if (!succeeded)
              {
                'code': 'ccrouter_host_component_owner_missing',
                'severity': 'error',
                'message': 'Host closure is missing an owner.',
                'correction': 'Run Pub get.',
                'rootCauseGroup': 'missing-owner:orders',
                'primaryLocation': {
                  'uri': 'package:bridge_host/src/component.dart',
                  'line': 1,
                  'column': 7,
                  'length': 9,
                },
              },
          ],
        }),
      );
  }

  String _resolutionFingerprint() {
    final files = <String, File>{
      'host/pubspec.yaml': pubspec,
      'build/pubspec.yaml': pubspec,
      'build/pubspec.lock': File(path.join(root.path, 'pubspec.lock')),
      'build/.dart_tool/package_config.json': File(
        path.join(root.path, '.dart_tool', 'package_config.json'),
      ),
      'build/.dart_tool/package_graph.json': File(
        path.join(root.path, '.dart_tool', 'package_graph.json'),
      ),
    };
    final contents = <String, String?>{};
    for (final entry in files.entries) {
      contents[entry.key] = entry.value.existsSync()
          ? base64Encode(entry.value.readAsBytesSync())
          : null;
    }
    return sha256.convert(utf8.encode(jsonEncode(contents))).toString();
  }

  void writePackageGraph(List<String> dependencies) {
    File(path.join(root.path, '.dart_tool', 'package_graph.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'packages': [
            {
              'name': 'bridge_host',
              'version': '1.0.0',
              'dependencies': dependencies,
            },
          ],
        }),
      );
  }

  void writeProject({
    required String dependency,
    required String? projectType,
    required bool? hostEnabled,
  }) {
    pubspec.writeAsStringSync('''
name: bridge_host
dependencies:
  $dependency: any
''');
    if (projectType != null) {
      File(
        path.join(root.path, '.metadata'),
      ).writeAsStringSync('project_type: $projectType\n');
    }
    if (hostEnabled != null) {
      File(
        path.join(root.path, 'ccrouter.yaml'),
      ).writeAsStringSync('host:\n  enabled: $hostEnabled\n');
    }
  }

  void dispose() => root.deleteSync(recursive: true);
}
