@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

const _gitRef = '0123456789abcdef0123456789abcdef01234567';

void main() {
  test('status distinguishes missing Host and missing plugin setup', () async {
    final root = await Directory.systemTemp.createTemp('ccrouter-analyzer-');
    addTearDown(() => root.delete(recursive: true));

    final plain = await _run(['analyzer', 'status', root.path]);
    expect(plain.exitCode, 1);
    expect('${plain.stdout}', contains('state: notInstalled'));

    _writeHost(root, enablePlugin: false);
    final missingPlugin = await _run(['analyzer', 'status', root.path]);
    expect(missingPlugin.exitCode, 1);
    expect('${missingPlugin.stdout}', contains('state: notInstalled'));
  });

  test('status resolves a plugin from an enclosing workspace config', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'ccrouter-analyzer-workspace-',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final host = Directory(path.join(workspace.path, 'apps', 'demo'))
      ..createSync(recursive: true);
    final plugin = Directory(path.join(workspace.path, 'tooling', 'plugin'))
      ..createSync(recursive: true);
    _writeHost(host);
    _writePackageConfig(workspace, plugin);
    _writeBootstrap(plugin);

    final result = await _run(['analyzer', 'status', host.path]);

    expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
    expect('${result.stdout}', contains('state: healthy'));
    expect('${result.stdout}', contains('source: git'));
    expect('${result.stdout}', contains('ref: $_gitRef'));
    expect('${result.stdout}', contains('loadability is unchecked'));
  });

  test('status reports incomplete resolved state', () async {
    final root = await Directory.systemTemp.createTemp('ccrouter-analyzer-');
    addTearDown(() => root.delete(recursive: true));
    _writeHost(root);

    final result = await _run(['analyzer', 'status', root.path]);

    expect(result.exitCode, 1);
    expect('${result.stdout}', contains('state: incomplete'));
    expect('${result.stdout}', contains('package configuration'));
  });

  test('status rejects path and floating Git dependencies', () async {
    final fixture = await _createFixture();
    addTearDown(() => fixture.root.delete(recursive: true));

    _writeBootstrap(fixture.plugin, dependency: 'path: ../../plugin');
    final pathDependency = await _run([
      'analyzer',
      'status',
      fixture.root.path,
    ]);
    expect(pathDependency.exitCode, 1);
    expect('${pathDependency.stdout}', contains('state: modified'));

    _writeBootstrap(
      fixture.plugin,
      dependency: '''git:
      url: https://example.com/cc-router.git
      path: packages/ccrouter_analyzer_plugin
      ref: main''',
    );
    final floatingGit = await _run(['analyzer', 'status', fixture.root.path]);
    expect(floatingGit.exitCode, 1);
    expect('${floatingGit.stdout}', contains('state: modified'));
  });

  test('status detects stale dependency identity', () async {
    final fixture = await _createFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    _writeBootstrap(
      fixture.plugin,
      resolvedRef: 'fedcba9876543210fedcba9876543210fedcba98',
    );

    final result = await _run(['analyzer', 'status', fixture.root.path]);

    expect(result.exitCode, 1);
    expect('${result.stdout}', contains('state: stale'));
  });

  test('status detects incompatible locked versions', () async {
    final fixture = await _createFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    _writeBootstrap(fixture.plugin, analyzerConstraint: '^9.0.0');

    final result = await _run(['analyzer', 'status', fixture.root.path]);

    expect(result.exitCode, 1);
    expect('${result.stdout}', contains('state: incompatible'));
  });

  test('status validates Hosted version constraints', () async {
    final fixture = await _createFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    _writeBootstrap(
      fixture.plugin,
      dependency: '^0.2.0',
      lockedPluginSource: 'hosted',
      lockedPluginVersion: '0.1.0',
    );

    final result = await _run(['analyzer', 'status', fixture.root.path]);

    expect(result.exitCode, 1);
    expect('${result.stdout}', contains('state: incompatible'));
  });

  test(
    'doctor stops before subprocess checks when status is unhealthy',
    () async {
      final root = await Directory.systemTemp.createTemp('ccrouter-analyzer-');
      addTearDown(() => root.delete(recursive: true));
      _writeHost(root);

      final result = await _run(['analyzer', 'doctor', root.path]);

      expect(result.exitCode, 1);
      expect('${result.stdout}', isNot(contains('Analyzer doctor:')));
    },
  );

  test(
    'doctor treats a stale Analysis Server plugin-manager copy as advisory',
    () async {
      final fixture = await _createFixture();
      final home = await Directory.systemTemp.createTemp(
        'ccrouter-analyzer-home-',
      );
      addTearDown(() async {
        await fixture.root.delete(recursive: true);
        await home.delete(recursive: true);
      });
      final cached = Directory(
        path.join(
          home.path,
          '.dartServer',
          '.plugin_manager',
          md5
              .convert(
                path
                    .join(fixture.plugin.path, 'tools', 'analyzer_plugin')
                    .codeUnits,
              )
              .toString(),
          'analyzer_plugin',
        ),
      )..createSync(recursive: true);
      File(path.join(cached.path, 'pubspec.yaml')).writeAsStringSync('''
name: analyzer_test_bootstrap
dependencies:
  ccrouter_analyzer_plugin: 0.0.1
''');

      final result = await _run(
        ['analyzer', 'doctor', fixture.root.path],
        environment: {...Platform.environment, 'HOME': home.path},
      );

      expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
      expect(
        '${result.stderr}',
        contains('stale Analysis Server plugin cache'),
      );
      expect('${result.stderr}', contains(cached.parent.path));
      expect('${result.stderr}', contains('not authoritative cross-SDK gate'));
      expect('${result.stdout}', contains('Analyzer doctor:'));
    },
  );

  for (final damage in [
    'missing child',
    'missing entrypoint',
    'changed entrypoint',
  ]) {
    test(
      'doctor reports $damage without changing or blaming other caches',
      () async {
        final fixture = await _createFixture();
        final home = await Directory.systemTemp.createTemp(
          'ccrouter-analyzer-home-',
        );
        addTearDown(() async {
          await fixture.root.delete(recursive: true);
          await home.delete(recursive: true);
        });
        final bootstrap = Directory(
          path.join(fixture.plugin.path, 'tools', 'analyzer_plugin'),
        );
        final manager = Directory(
          path.join(home.path, '.dartServer', '.plugin_manager'),
        );
        final entry = Directory(
          path.join(
            manager.path,
            md5.convert(bootstrap.path.codeUnits).toString(),
          ),
        )..createSync(recursive: true);
        if (damage != 'missing child') {
          final cached = Directory(path.join(entry.path, 'analyzer_plugin'))
            ..createSync();
          File(
            path.join(bootstrap.path, 'pubspec.yaml'),
          ).copySync(path.join(cached.path, 'pubspec.yaml'));
          if (damage == 'changed entrypoint') {
            Directory(path.join(cached.path, 'bin')).createSync();
            File(
              path.join(cached.path, 'bin', 'plugin.dart'),
            ).writeAsStringSync('void outdated() {}');
          }
        }
        final unrelated = Directory(
          path.join(manager.path, 'another-host', 'analyzer_plugin'),
        )..createSync(recursive: true);
        final unrelatedManifest = File(
          path.join(unrelated.path, 'pubspec.yaml'),
        )..writeAsStringSync('name: analyzer_test_bootstrap\n');

        final result = await _run(
          ['analyzer', 'doctor', fixture.root.path],
          environment: {...Platform.environment, 'HOME': home.path},
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stderr}\n${result.stdout}',
        );
        expect('${result.stderr}', contains(entry.path));
        expect('${result.stderr}', isNot(contains(unrelated.parent.path)));
        expect('${result.stdout}', contains('Analyzer doctor:'));
        expect(entry.existsSync(), isTrue);
        expect(
          unrelatedManifest.readAsStringSync(),
          'name: analyzer_test_bootstrap\n',
        );
      },
    );
  }

  test('analyzer rejects unsupported actions and excess arguments', () async {
    final unsupported = await _run(['analyzer', 'unknown']);
    expect(unsupported.exitCode, 2);
    expect('${unsupported.stderr}', contains('requires status, doctor'));

    final excess = await _run(['analyzer', 'status', '.', 'extra']);
    expect(excess.exitCode, 2);
    expect('${excess.stderr}', contains('one optional Host root'));
  });

  test('write command parser rejects ambiguous or unsupported flags', () async {
    for (final args in [
      ['install', '--version', '1.0.0', '--version', '2.0.0'],
      ['install', '--url'],
      ['status', '--dry-run'],
      ['upgrade', '--source', 'git'],
      ['uninstall', '--version', '1.0.0'],
      ['install', '--unknown'],
    ]) {
      final result = await _run(['analyzer', ...args]);
      expect(result.exitCode, 2, reason: '$args: ${result.stderr}');
    }
  });

  test(
    'install dry-run parses explicit Git source without touching Host',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ccrouter-analyzer-dry-',
      );
      addTearDown(() => root.delete(recursive: true));
      _writeHost(root, enablePlugin: false);
      final manifest = File(path.join(root.path, 'pubspec.yaml'));
      manifest.writeAsStringSync(
        '${manifest.readAsStringSync()}  flutter:\n    sdk: flutter\n',
      );
      File(
        path.join(root.path, '.metadata'),
      ).writeAsStringSync('project_type: app\n');
      final before = manifest.readAsStringSync();
      final result = await _run([
        'analyzer',
        'install',
        root.path,
        '--source',
        'git',
        '--url',
        'https://example.com/router.git',
        '--ref',
        _gitRef,
        '--dry-run',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}', contains('(dry-run)'));
      expect(manifest.readAsStringSync(), before);
      expect(Directory(path.join(root.path, 'tools')).existsSync(), isFalse);
    },
  );
}

Future<({Directory root, Directory plugin})> _createFixture() async {
  final root = await Directory.systemTemp.createTemp('ccrouter-analyzer-');
  final plugin = Directory(path.join(root.path, 'plugin'))..createSync();
  _writeHost(root);
  _writePackageConfig(root, plugin);
  _writeBootstrap(plugin);
  return (root: root, plugin: plugin);
}

void _writeHost(Directory host, {bool enablePlugin = true}) {
  File(path.join(host.path, 'pubspec.yaml')).writeAsStringSync('''
name: analyzer_test_host
environment:
  sdk: ^3.10.0
dependencies:
  ccrouter: ^0.1.0
''');
  File(path.join(host.path, 'analysis_options.yaml')).writeAsStringSync('''
analyzer:
  plugins:${enablePlugin ? '\n    - ccrouter_test_analyzer_plugin' : ' []'}
''');
}

void _writePackageConfig(Directory workspace, Directory plugin) {
  final tool = Directory(path.join(workspace.path, '.dart_tool'))..createSync();
  final rootUri = tool.uri.resolveUri(plugin.uri).toString();
  File(path.join(tool.path, 'package_config.json')).writeAsStringSync(
    jsonEncode({
      'configVersion': 2,
      'packages': [
        {
          'name': 'ccrouter_test_analyzer_plugin',
          'rootUri': rootUri,
          'packageUri': 'lib/',
          'languageVersion': '3.10',
        },
      ],
    }),
  );
}

void _writeBootstrap(
  Directory plugin, {
  String? dependency,
  String analyzerConstraint = '8.4.0',
  String resolvedRef = _gitRef,
  String lockedPluginSource = 'git',
  String lockedPluginVersion = '0.1.0',
}) {
  final bootstrap = Directory(
    path.join(plugin.path, 'tools', 'analyzer_plugin'),
  )..createSync(recursive: true);
  final bin = Directory(path.join(bootstrap.path, 'bin'))..createSync();
  File(
    path.join(bin.path, 'plugin.dart'),
  ).writeAsStringSync('void main() {}\n');
  final dependencyYaml =
      dependency ??
      '''git:
      url: https://example.com/cc-router.git
      path: packages/ccrouter_analyzer_plugin
      ref: $_gitRef''';
  File(path.join(bootstrap.path, 'pubspec.yaml')).writeAsStringSync('''
name: analyzer_test_bootstrap
environment:
  sdk: ^3.10.0
dependencies:
  analyzer: $analyzerConstraint
  analyzer_plugin: 0.13.10
  ccrouter_analyzer_plugin:
    $dependencyYaml
''');
  final pluginDescription = lockedPluginSource == 'git'
      ? '''      path: packages/ccrouter_analyzer_plugin
      ref: $_gitRef
      resolved-ref: $resolvedRef
      url: https://example.com/cc-router.git'''
      : '''      name: ccrouter_analyzer_plugin
      url: https://pub.dev''';
  File(path.join(bootstrap.path, 'pubspec.lock')).writeAsStringSync('''
packages:
  analyzer:
    source: hosted
    version: "8.4.0"
  analyzer_plugin:
    source: hosted
    version: "0.13.10"
  ccrouter_analyzer_plugin:
    description:
$pluginDescription
    source: $lockedPluginSource
    version: "$lockedPluginVersion"
''');
}

Future<ProcessResult> _run(
  List<String> arguments, {
  Map<String, String>? environment,
}) => Process.run(
  Platform.resolvedExecutable,
  [
    '--packages=${path.absolute('.dart_tool/package_config.json')}',
    path.absolute('packages/ccrouter_generator/bin/ccrouter.dart'),
    ...arguments,
  ],
  workingDirectory: Directory.current.path,
  environment: environment,
);
