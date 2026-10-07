import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../skill_bundle_check.dart';

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('ccrouter-skill-test-');
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  void write(String relative, String content) {
    final file = File('${temporary.path}/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void entries() {
    for (final name in skillBundleNames) {
      write('$name/SKILL.md', '# $name');
    }
  }

  test('consumer copy resolves required links without repository docs', () {
    copySkillBundle(Directory('${Directory.current.path}/skills'), temporary);
    expect(checkSkillBundle(temporary), isEmpty);
    expect(Directory('${temporary.path}/docs').existsSync(), isFalse);
  });

  test('installing just the integration Skill is rejected', () {
    write('${skillBundleNames.first}/SKILL.md', '# Integration');
    expect(checkSkillBundle(temporary), contains(contains('Missing required')));
  });

  test('repository-relative references fail even if target exists outside', () {
    entries();
    write('outside.md', 'not part of the distribution');
    final bundle = Directory('${temporary.path}/bundle')..createSync();
    copySkillBundle(temporary, bundle);
    File(
      '${bundle.path}/${skillBundleNames.first}/SKILL.md',
    ).writeAsStringSync('[external](../../outside.md)');
    expect(checkSkillBundle(bundle), contains(contains('escapes bundle')));
  });

  test('missing local references fail and optional remote links pass', () {
    entries();
    write(
      '${skillBundleNames.first}/SKILL.md',
      '[remote](https://example.invalid/design)\n[missing](references/gone.md)',
    );
    final findings = checkSkillBundle(temporary);
    expect(findings, hasLength(1));
    expect(findings.single, contains('missing bundled reference'));
  });

  test('links between bundled Skills are valid', () {
    entries();
    write(
      '${skillBundleNames.first}/SKILL.md',
      '[CLI](../${skillBundleNames.last}/SKILL.md#generate)',
    );
    expect(checkSkillBundle(temporary), isEmpty);
  });

  test('CLI examples cannot invent commands or command-specific flags', () {
    const help = '''Usage:
  ccrouter generate [host-root] [--check]
  ccrouter analyzer status [host-root]
''';
    const prefix =
        'fvm dart run --verbosity=error ccrouter_generator:ccrouter ';
    expect(
      checkSkillCommands('${prefix}analyzer status <host-root>', help),
      contains(contains('Undocumented CLI command: ccrouter generate')),
    );
    expect(
      checkSkillCommands('${prefix}analyzer install <host-root>', help),
      contains(contains('Unknown documented CLI')),
    );
    expect(
      checkSkillCommands('${prefix}analyzer status <host-root> --check', help),
      contains(contains('Unsupported documented flag')),
    );
  });

  test('CLI matrix cannot omit an executable command', () {
    const help = '''Usage:
  ccrouter generate [host-root]
  ccrouter portable prepare [host-root]
''';
    const prefix =
        'fvm dart run --verbosity=error ccrouter_generator:ccrouter ';

    expect(
      checkSkillCommands('${prefix}generate <host-root>', help),
      contains('Undocumented CLI command: ccrouter portable prepare'),
    );
  });

  test('documented CLI matrix matches current executable help', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'packages/ccrouter_generator/bin/ccrouter_generator.dart',
      '--help',
    ], environment: _isolatedEnvironment(temporary));
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      checkSkillCommands(
        File('skills/ccrouter-cli-development/SKILL.md').readAsStringSync(),
        '${result.stdout}',
      ),
      isEmpty,
    );
  });

  test(
    'Host, Route and generic Service examples analyze against actual APIs',
    () async {
      final source = File(
        'skills/ccrouter-integration-development/references/implementation-patterns.md',
      ).readAsStringSync();
      String snippet(String name) {
        final match = RegExp(
          '<!-- verified-example: $name -->\\s*```dart\\n([\\s\\S]*?)```',
        ).firstMatch(source);
        expect(match, isNotNull, reason: 'Missing verified example: $name');
        return match!.group(1)!;
      }

      // Inherit the resolved Workspace graph without entering Demo's legacy
      // Analysis Server Plugin context.
      final fixture = Directory(
        '${Directory.current.path}/.dart_tool',
      ).createTempSync('ccrouter-skill-examples-');
      final processHome = Directory('${temporary.path}/process-home')
        ..createSync(recursive: true);
      try {
        File('${fixture.path}/pubspec.yaml').writeAsStringSync('''
name: ccrouter_skill_examples
publish_to: none
environment:
  sdk: ^3.10.0
dependencies:
  ccrouter: any
  flutter:
    sdk: flutter
''');
        _writeAbsolutePackageConfig(fixture);
        final file = File('${fixture.path}/examples.dart')
          ..writeAsStringSync('''
// ignore_for_file: public_member_api_docs
import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/material.dart';

void startHost(CCComponentManifest ordersManifest,
    CCComponentManifest accountManifest, CCFlutterRouteCatalog applicationRouteCatalog) {
${snippet('host-assembly')}
}

const cartComponentId = CCComponentId('cart');
${snippet('service-contract')}
${snippet('service-implementation')}
${snippet('route-page')}
${snippet('extra-page')}
''');
        final result = await Process.run(
          Platform.resolvedExecutable,
          ['analyze', '--fatal-infos', file.path],
          environment: _isolatedEnvironment(processHome),
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final valid = file.readAsStringSync();
        // Prove this check rejects the two historical example defects rather
        // than silently ignoring the temporary file or missing method bodies.
        for (final invalid in [
          valid.replaceFirst(
            'CCRouter.initialize(hostAssembly: hostAssembly)',
            'CCRouter.initialize(contractBundle: hostAssembly.contractBundle)',
          ),
          valid.replaceFirst(
            '  @override\n  T unwrap<T extends Object>(CartSummaryValue<T> value) => value.value;',
            '',
          ),
        ]) {
          expect(invalid, isNot(valid));
          file.writeAsStringSync(invalid);
          final rejected = await Process.run(
            Platform.resolvedExecutable,
            ['analyze', file.path],
            environment: _isolatedEnvironment(processHome),
          );
          expect(rejected.exitCode, isNot(0), reason: '${rejected.stdout}');
        }
      } finally {
        fixture.deleteSync(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Map<String, String> _isolatedEnvironment(Directory home) => {
  ...Platform.environment,
  'HOME': home.path,
  'USERPROFILE': home.path,
  'APPDATA': '${home.path}/app-data',
  'LOCALAPPDATA': '${home.path}/local-app-data',
  'CCROUTER_HOME': '${home.path}/ccrouter',
  'PUB_CACHE': '${home.path}/pub-cache',
};

void _writeAbsolutePackageConfig(Directory fixture) {
  final source = File('.dart_tool/package_config.json').absolute;
  final document =
      jsonDecode(source.readAsStringSync()) as Map<String, Object?>;
  final packages = document['packages'] as List<Object?>;
  for (final value in packages.whereType<Map<String, Object?>>()) {
    final root = value['rootUri'];
    if (root is String) value['rootUri'] = source.uri.resolve(root).toString();
  }
  final target = File('${fixture.path}/.dart_tool/package_config.json')
    ..createSync(recursive: true);
  target.writeAsStringSync(jsonEncode(document));
}
