@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../ccrouter_generator/bin/src/analyzer_bootstrap.dart';

const _ref = 'a275d1d46ddfdded6678ecbf1d2d23818cdbdfdc';

void main() {
  late _Host host;
  setUp(() => host = _Host());
  tearDown(() => host.root.deleteSync(recursive: true));

  test(
    'dry-run validates source and Host without files or processes',
    () async {
      final before = host.snapshot();
      expect(await host.run(dryRun: true), isTrue);
      expect(host.snapshot(), before);
      expect(host.calls, isEmpty);
    },
  );

  test(
    'Hosted install, idempotency and uninstall preserve unrelated YAML',
    () async {
      expect(await host.run(), isTrue);
      expect(
        host.file('analysis_options.yaml').readAsStringSync(),
        contains('# keep this comment'),
      );
      expect(
        host.file('analysis_options.yaml').readAsStringSync(),
        contains('unused_local_variable: warning'),
      );
      expect(
        host.file('pubspec.yaml').readAsStringSync(),
        contains('test: any'),
      );
      final installed = host.snapshot();
      final calls = host.calls.length;
      final stamp = host
          .file('$wrapper/tools/analyzer_plugin/pubspec.lock')
          .lastModifiedSync();
      expect(await host.run(), isTrue);
      expect(host.snapshot(), installed);
      expect(host.calls, hasLength(calls));
      expect(
        host
            .file('$wrapper/tools/analyzer_plugin/pubspec.lock')
            .lastModifiedSync(),
        stamp,
      );

      // New unrelated user config survives removal of the CLI-owned leaf.
      host
          .file('analysis_options.yaml')
          .writeAsStringSync(
            '${host.file('analysis_options.yaml').readAsStringSync()}\nlinter:\n  rules:\n    - avoid_print\n',
          );
      expect(
        await host.run(action: CCAnalyzerBootstrapAction.uninstall),
        isTrue,
      );
      expect(
        host.file('analysis_options.yaml').readAsStringSync(),
        contains('avoid_print'),
      );
      expect(
        host.file('analysis_options.yaml').readAsStringSync(),
        isNot(contains('plugins:')),
      );
      expect(
        host.file('pubspec.yaml').readAsStringSync(),
        isNot(contains('sample_ccrouter_analyzer')),
      );
      expect(Directory(host.file(wrapper).path).existsSync(), isFalse);
      expect(
        await host.run(),
        isTrue,
        reason: 'Reinstall must work after a normal uninstall',
      );
    },
  );

  test(
    'Git source verifies a remotely fetchable full commit before Pub',
    () async {
      expect(
        await host.run(
          source: 'git',
          url: 'https://example.com/router.git',
          ref: _ref,
        ),
        isTrue,
      );
      expect(host.calls[0], startsWith('git init'));
      expect(
        host.calls[1],
        contains(
          'fetch --quiet --no-tags --depth=1 https://example.com/router.git $_ref',
        ),
      );
      expect(
        host
            .file('$wrapper/tools/analyzer_plugin/pubspec.yaml')
            .readAsStringSync(),
        contains(_ref),
      );
      expect(
        host.file('$wrapper/.ccrouter-analyzer.json').readAsStringSync(),
        isNot(contains(host.root.path)),
      );
    },
  );

  for (final source in [
    (
      kind: 'git',
      version: null,
      url: 'https://example.com/router.git',
      ref: 'main',
    ),
    (
      kind: 'git',
      version: null,
      url: 'https://example.com/router.git',
      ref: 'a275d1d',
    ),
    (kind: 'git', version: null, url: '/tmp/local-repository', ref: _ref),
    (kind: 'git', version: null, url: 'file:///tmp/repo', ref: _ref),
    (
      kind: 'git',
      version: '2.0.0',
      url: 'https://example.com/router.git',
      ref: _ref,
    ),
    (kind: 'hosted', version: 'any', url: null, ref: null),
    (kind: 'hosted', version: null, url: null, ref: null),
  ]) {
    test(
      'reject invalid source ${source.kind}/${source.version}/${source.url}/${source.ref}',
      () async {
        final before = host.snapshot();
        expect(
          await host.run(
            source: source.kind,
            version: source.version,
            url: source.url,
            ref: source.ref,
          ),
          isFalse,
        );
        expect(host.snapshot(), before);
        expect(host.calls, isEmpty);
      },
    );
  }

  for (final failure in [
    'fetch',
    'pub get',
    'analyze',
    'compile',
    'Host pub',
  ]) {
    test('failure in $failure preserves source and resolution bytes', () async {
      host.failAt = failure;
      final before = host.snapshot();
      expect(
        await host.run(
          source: 'git',
          url: 'https://example.com/router.git',
          ref: _ref,
        ),
        isFalse,
      );
      expect(host.snapshot(), before);
      host.failAt = null;
      expect(
        await host.run(),
        isTrue,
        reason: 'Rollback must not leave an empty conflicting bootstrap',
      );
    });
  }

  test(
    'upgrade verifies before and after; failed candidate keeps old installation',
    () async {
      expect(await host.run(), isTrue);
      final before = host.snapshot();
      host.failVersion = '1.1.0';
      expect(
        await host.run(
          action: CCAnalyzerBootstrapAction.upgrade,
          version: '1.1.0',
        ),
        isFalse,
      );
      expect(host.snapshot(), before);
      host.failVersion = null;
      expect(
        await host.run(
          action: CCAnalyzerBootstrapAction.upgrade,
          version: '1.1.0',
        ),
        isTrue,
      );
      expect(
        host
            .file('$wrapper/tools/analyzer_plugin/pubspec.lock')
            .readAsStringSync(),
        contains('"1.1.0"'),
      );
    },
  );

  test(
    'failed uninstall restores enabled bootstrap and Pub resolution',
    () async {
      expect(await host.run(), isTrue);
      final before = host.snapshot();
      host.failAt = 'Host pub';
      expect(
        await host.run(action: CCAnalyzerBootstrapAction.uninstall),
        isFalse,
      );
      expect(host.snapshot(), before);
    },
  );

  for (final target in [
    '$wrapper/tools/analyzer_plugin/bin/plugin.dart',
    'analysis_options.yaml',
    'pubspec.yaml',
  ]) {
    test('modified owned entry is refused: $target', () async {
      expect(await host.run(), isTrue);
      final file = host.file(target);
      final original = file.readAsStringSync();
      file.writeAsStringSync(
        target.endsWith('plugin.dart')
            ? '$original// user edit\n'
            : original.replaceAll('sample_ccrouter_analyzer', 'another_plugin'),
      );
      final before = host.snapshot();
      expect(
        await host.run(action: CCAnalyzerBootstrapAction.uninstall),
        isFalse,
      );
      expect(host.snapshot(), before);
    });
  }

  test('uninstall preserves unknown wrapper files', () async {
    expect(await host.run(), isTrue);
    host.write('$wrapper/notes.txt', 'owned by the developer');
    expect(await host.run(action: CCAnalyzerBootstrapAction.uninstall), isTrue);
    expect(
      host.file('$wrapper/notes.txt').readAsStringSync(),
      'owned by the developer',
    );
  });

  test(
    'rejects existing and inherited Analyzer plugins without modification',
    () async {
      host.write('parent.yaml', 'analyzer:\n  plugins: [another_plugin]\n');
      host.write('analysis_options.yaml', 'include: parent.yaml\n');
      final before = host.snapshot();
      expect(await host.run(), isFalse);
      expect(host.snapshot(), before);
      expect(host.calls, isEmpty);
    },
  );

  test('rejects a component or aggregator without an App identity', () async {
    host.write('.metadata', 'project_type: package\n');
    final before = host.snapshot();
    expect(await host.run(), isFalse);
    expect(host.snapshot(), before);
  });

  test(
    'supports explicit module Host and initially absent options/dev dependencies',
    () async {
      host.write('.metadata', 'project_type: module\n');
      host.write('ccrouter.yaml', 'host:\n  enabled: true\n');
      host.file('analysis_options.yaml').deleteSync();
      host
          .file('pubspec.yaml')
          .writeAsStringSync(
            host
                .file('pubspec.yaml')
                .readAsStringSync()
                .replaceFirst('dev_dependencies:\n  test: any\n', ''),
          );
      expect(await host.run(), isTrue);
      expect(
        await host.run(action: CCAnalyzerBootstrapAction.uninstall),
        isTrue,
      );
      expect(host.file('analysis_options.yaml').existsSync(), isFalse);
      expect(
        host.file('pubspec.yaml').readAsStringSync(),
        isNot(contains('dev_dependencies')),
      );
    },
  );

  test('host.enabled false rejects an app installation target', () async {
    host.write('ccrouter.yaml', 'host:\n  enabled: false\n');
    final before = host.snapshot();

    expect(await host.run(), isFalse);

    expect(host.snapshot(), before);
    expect(host.calls, isEmpty);
  });

  test('symlink bootstrap cannot redirect installation writes', () async {
    final outside = Directory(path.join(host.root.path, 'outside'))
      ..createSync();
    host.file(wrapper).parent.createSync(recursive: true);
    Link(host.file(wrapper).path).createSync(outside.path);
    expect(await host.run(), isFalse);
    expect(outside.listSync(), isEmpty);
  });

  test('concurrent authored edit during verification is preserved', () async {
    host.onCompile = () {
      host
          .file('pubspec.yaml')
          .writeAsStringSync(
            '${host.file('pubspec.yaml').readAsStringSync()}# concurrent edit\n',
          );
    };
    expect(await host.run(), isFalse);
    expect(
      host.file('pubspec.yaml').readAsStringSync(),
      contains('# concurrent edit'),
    );
    expect(host.file('$wrapper/.ccrouter-analyzer.json').existsSync(), isFalse);
  });

  test(
    'Workspace installs target only one Host and rollback shared Pub state',
    () async {
      host.makeWorkspace();
      final other = File(path.join(host.root.path, 'other', 'pubspec.yaml'));
      other.parent.createSync();
      other.writeAsStringSync('name: other\n');
      final before = host.snapshot();
      host.failAt = 'Host pub';
      expect(await host.run(), isFalse);
      expect(host.snapshot(), before);
      host.failAt = null;
      expect(await host.run(), isTrue);
      expect(other.readAsStringSync(), 'name: other\n');
      expect(
        File(path.join(host.root.path, 'pubspec.yaml')).readAsStringSync(),
        isNot(contains('sample_ccrouter_analyzer')),
      );
    },
  );

  test(
    'new Host options retain implicitly inherited Workspace rules',
    () async {
      host.makeWorkspace();
      host.file('analysis_options.yaml').deleteSync();
      File(
        path.join(host.root.path, 'analysis_options.yaml'),
      ).writeAsStringSync('linter:\n  rules:\n    - avoid_print\n');
      expect(await host.run(), isTrue);
      expect(
        host.file('analysis_options.yaml').readAsStringSync(),
        contains('../analysis_options.yaml'),
      );
      expect(
        await host.run(action: CCAnalyzerBootstrapAction.uninstall),
        isTrue,
      );
      expect(host.file('analysis_options.yaml').existsSync(), isFalse);
    },
  );

  test(
    'empty plugin list, repeated uninstall and same-version upgrade are reversible',
    () async {
      host.write('analysis_options.yaml', 'analyzer:\n  plugins: []\n');
      expect(await host.run(), isTrue);
      final before = host.snapshot();
      final calls = host.calls.length;
      expect(await host.run(action: CCAnalyzerBootstrapAction.upgrade), isTrue);
      expect(host.snapshot(), before);
      expect(host.calls.length, calls);
      expect(
        await host.run(action: CCAnalyzerBootstrapAction.uninstall),
        isTrue,
      );
      expect(
        host.file('analysis_options.yaml').readAsStringSync(),
        contains('plugins: []'),
      );
      expect(
        await host.run(action: CCAnalyzerBootstrapAction.uninstall),
        isTrue,
      );
    },
  );

  test('incompatible SDK constraint fails before tool execution', () async {
    host.write(
      'pubspec.yaml',
      host
          .file('pubspec.yaml')
          .readAsStringSync()
          .replaceFirst('^3.10.0', '">=4.0.0"'),
    );
    expect(await host.run(), isFalse);
    expect(host.calls, isEmpty);
  });

  test(
    'upgrade refuses newly conflicting inherited plugins without writes',
    () async {
      expect(await host.run(), isTrue);
      host.write(
        'parent_options.yaml',
        'analyzer:\n  plugins: [another_plugin]\n',
      );
      host.write(
        'analysis_options.yaml',
        'include: parent_options.yaml\n${host.file('analysis_options.yaml').readAsStringSync()}',
      );
      final before = host.snapshot();
      final calls = host.calls.length;
      expect(
        await host.run(
          action: CCAnalyzerBootstrapAction.upgrade,
          version: '1.1.0',
        ),
        isFalse,
      );
      expect(host.snapshot(), before);
      expect(host.calls.length, calls);
    },
  );

  test(
    'dry-run upgrade and uninstall never mutate a managed installation',
    () async {
      expect(await host.run(), isTrue);
      final before = host.snapshot();
      final calls = host.calls.length;
      expect(
        await host.run(
          action: CCAnalyzerBootstrapAction.upgrade,
          version: '1.1.0',
          dryRun: true,
        ),
        isTrue,
      );
      expect(
        await host.run(
          action: CCAnalyzerBootstrapAction.uninstall,
          dryRun: true,
        ),
        isTrue,
      );
      expect(host.snapshot(), before);
      expect(host.calls.length, calls);
    },
  );

  test(
    'CLI process rejects a concurrently locked Pub owner before network work',
    () async {
      final file = host.file('.dart_tool/ccrouter/analyzer/operation.lock');
      file.parent.createSync(recursive: true);
      final lock = file.openSync(mode: FileMode.append)
        ..lockSync(FileLock.exclusive);
      try {
        final result = await Process.run(Platform.resolvedExecutable, [
          '--packages=${path.absolute('.dart_tool/package_config.json')}',
          path.absolute('packages/ccrouter_generator/bin/ccrouter.dart'),
          'analyzer',
          'install',
          host.host.path,
          '--version',
          '1.0.0',
        ]);
        expect(result.exitCode, 1);
        expect(
          '${result.stdout}',
          isNot(contains('resolve isolated bootstrap')),
        );
        expect(
          host.file('$wrapper/.ccrouter-analyzer.json').existsSync(),
          isFalse,
        );
      } finally {
        lock.unlockSync();
        lock.closeSync();
      }
    },
  );

  test(
    'interrupted transaction blocks subsequent writes and preserves recovery bytes',
    () async {
      host.write(
        '.dart_tool/ccrouter/analyzer/transactions/interrupted/originals.json',
        '{"recover":"me"}',
      );
      final before = host.snapshot();
      expect(await host.run(), isFalse);
      expect(host.snapshot(), before);
      expect(
        host
            .file(
              '.dart_tool/ccrouter/analyzer/transactions/interrupted/originals.json',
            )
            .readAsStringSync(),
        '{"recover":"me"}',
      );
    },
  );

  test(
    'unreadable Pub result restores other files and retains recovery journal',
    () async {
      final original = host.file('pubspec.yaml').readAsStringSync();
      host.onHostPub = () {
        host.file('pubspec.lock').deleteSync();
        Link(
          host.file('pubspec.lock').path,
        ).createSync(host.file('pubspec.yaml').path);
      };
      expect(await host.run(), isFalse);
      expect(host.file('pubspec.yaml').readAsStringSync(), original);
      expect(Link(host.file('pubspec.lock').path).existsSync(), isTrue);
      expect(
        host.file('$wrapper/.ccrouter-analyzer.json').existsSync(),
        isFalse,
      );
      expect(
        Directory(
          host.file('.dart_tool/ccrouter/analyzer/transactions').path,
        ).listSync(),
        isNotEmpty,
      );
    },
  );

  test(
    'rollback conflict preserves user edit and restores remaining files',
    () async {
      final originalLock = host.file('pubspec.lock').readAsStringSync();
      host.failAt = 'Host pub';
      host.onHostPub = () =>
          host.write('pubspec.yaml', '# concurrent user edit\n');
      expect(await host.run(), isFalse);
      expect(
        host.file('pubspec.yaml').readAsStringSync(),
        '# concurrent user edit\n',
      );
      expect(host.file('pubspec.lock').readAsStringSync(), originalLock);
      expect(
        host.file('$wrapper/.ccrouter-analyzer.json').existsSync(),
        isFalse,
      );
      expect(
        Directory(
          host.file('.dart_tool/ccrouter/analyzer/transactions').path,
        ).listSync(),
        isNotEmpty,
      );
    },
  );
}

const wrapper = 'tools/ccrouter_analyzer_host';

class _Host {
  _Host()
    : root = Directory.systemTemp.createTempSync('ccrouter-install-test-') {
    host = root;
    write('pubspec.yaml', '''# application configuration
name: sample
environment:
  sdk: ^3.10.0
dependencies:
  flutter:
    sdk: flutter
  ccrouter: any
dev_dependencies:
  test: any
''');
    write('.metadata', 'project_type: app\n');
    write(
      'analysis_options.yaml',
      '# keep this comment\nanalyzer:\n  errors:\n    unused_local_variable: warning\n',
    );
    write('pubspec.lock', '# original resolution\n');
    write(
      '.dart_tool/package_config.json',
      '{"configVersion":2,"packages":[]}\n',
    );
  }
  final Directory root;
  late Directory host;
  final calls = <String>[];
  String? failAt;
  String? failVersion;
  void Function()? onCompile;
  void Function()? onHostPub;

  File file(String relative) => File(path.join(host.path, relative));
  void write(String relative, String content) {
    final target = file(relative);
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(content);
  }

  void makeWorkspace() {
    final app = Directory(path.join(root.path, 'app'))..createSync();
    for (final entity in root.listSync().whereType<File>().toList()) {
      entity.renameSync(path.join(app.path, path.basename(entity.path)));
    }
    host = app;
    write(
      'pubspec.yaml',
      '${file('pubspec.yaml').readAsStringSync()}resolution: workspace\n',
    );
    File(
      path.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: workspace\nworkspace: [app]\n');
    File(
      path.join(root.path, 'pubspec.lock'),
    ).writeAsStringSync('# workspace resolution\n');
  }

  Map<String, String> snapshot() => {
    for (final file
        in root.listSync(recursive: true, followLinks: false).whereType<File>())
      if (!file.path.contains(
        '${path.separator}.dart_tool${path.separator}ccrouter${path.separator}',
      ))
        path.relative(file.path, from: root.path): base64Encode(
          file.readAsBytesSync(),
        ),
  };

  Future<bool> run({
    CCAnalyzerBootstrapAction action = CCAnalyzerBootstrapAction.install,
    String? source,
    String? version = '1.0.0',
    String? url,
    String? ref,
    bool dryRun = false,
  }) => runAnalyzerBootstrapCommand(
    CCAnalyzerBootstrapRequest(
      action: action,
      hostRoot: host.path,
      source: source,
      version: source == 'git' && version == '1.0.0' ? null : version,
      url: url,
      ref: ref,
      dryRun: dryRun,
    ),
    processRunner: process,
  );

  Future<ProcessResult> process(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    Map<String, String>? environment,
  }) async {
    final command = '${path.basename(executable)} ${arguments.join(' ')}';
    calls.add(command);
    if (path.basename(executable).startsWith('flutter')) {
      expect(environment?['CCROUTER_PUB_HOOK_DISABLE'], '1');
      final configRoot = host == root ? host : root;
      File(
        path.join(configRoot.path, 'pubspec.lock'),
      ).writeAsStringSync('# changed Pub state\n');
      final enabled = file(
        'pubspec.yaml',
      ).readAsStringSync().contains('sample_ccrouter_analyzer');
      File(
        path.join(configRoot.path, '.dart_tool', 'package_config.json'),
      ).writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            if (enabled)
              {
                'name': 'sample_ccrouter_analyzer',
                'rootUri': Directory(file(wrapper).path).uri.toString(),
                'packageUri': 'lib/',
              },
          ],
        }),
      );
      onHostPub?.call();
      return ProcessResult(0, failAt == 'Host pub' ? 1 : 0, '', '');
    }
    if (failAt != null && arguments.join(' ').contains(failAt!))
      return ProcessResult(0, 1, '', 'injected failure');
    final manifest = File(path.join(workingDirectory, 'pubspec.yaml'));
    if (arguments.first == 'pub' && !arguments.contains('--enforce-lockfile')) {
      final text = manifest.readAsStringSync();
      final ref = RegExp(r'ref: ([a-f0-9]{40})').firstMatch(text)?.group(1);
      final version = ref != null
          ? '0.1.0'
          : RegExp(
              r'ccrouter_analyzer_plugin: "([^"]+)"',
            ).firstMatch(text)!.group(1)!.replaceFirst('^', '');
      if (version == failVersion)
        return ProcessResult(0, 1, '', 'candidate failed');
      final url = RegExp(r'url: "([^"]+)"').firstMatch(text)?.group(1);
      File(path.join(workingDirectory, 'pubspec.lock')).writeAsStringSync(
        '''packages:
  analyzer:
    source: hosted
    version: "8.4.0"
  analyzer_plugin:
    source: hosted
    version: "0.13.10"
  ccrouter_analyzer_plugin:
    source: ${ref == null ? 'hosted' : 'git'}
    version: "$version"
    description:
      name: ccrouter_analyzer_plugin
      url: ${jsonEncode(url ?? 'https://pub.dev')}
      path: packages/ccrouter_analyzer_plugin
      ref: $ref
      resolved-ref: $ref
''',
      );
    }
    if (arguments.first == 'compile') onCompile?.call();
    return ProcessResult(0, 0, '', '');
  }
}
