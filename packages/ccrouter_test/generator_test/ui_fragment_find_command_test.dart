@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ccrouter_generator/src/package_workspace.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late _Fixture fixture;
  setUp(() => fixture = _Fixture());
  tearDown(() => fixture.root.deleteSync(recursive: true));

  test(
    'UI lookup and existing usage use exact portable locations and alias',
    () async {
      fixture.publish();
      final before = fixture.snapshot();
      final result = await fixture.find('consumer_component');
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        '${result.stdout}',
        allOf([
          contains('UI Fragment orders.card (component: orders)'),
          contains('package:ui_find_contracts/src/card.dart:10:1'),
          contains('package:ui_find_contracts/src/renderer.dart:20:1'),
          contains(
            'Public import: package:ui_find_contracts/ui_find_contracts.dart',
          ),
          contains('Owner dependency: satisfied'),
          contains('UI dependency: satisfied'),
          contains('consumer_component.ui.api.g.dart'),
          contains('Generated Client: ConsumerComponentFragments.summary'),
          contains('active: isActive'),
        ]),
      );
      expect(fixture.snapshot(), before);
    },
  );

  test(
    'missing usage reports required edge and never invents a Client alias',
    () async {
      fixture.publish(consumed: false, requiredOwner: false);
      final result = await fixture.find('consumer_component');
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        '${result.stdout}',
        allOf(
          contains('Owner dependency: missing'),
          contains('optionalDependencies is insufficient'),
          contains('UI dependency: missing'),
          contains('CCUIFragmentDependency<CardContract>'),
          contains("alias: 'chooseUniqueAlias'"),
          contains('Generated Client: available after'),
          isNot(contains('ConsumerComponentFragments.summary')),
        ),
      );
    },
  );

  test('legacy alias metadata defers the callable member', () async {
    fixture.publish(alias: false);
    final result = await fixture.find('consumer_component');
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      '${result.stdout}',
      contains('old metadata without alias must be regenerated'),
    );
    expect(
      '${result.stdout}',
      isNot(contains('Generated Client: ConsumerComponentFragments.')),
    );
  });

  test(
    'a missing public DTO proof withholds the entire dependency recipe',
    () async {
      fixture.publish(publicShape: false);
      final result = await fixture.find('consumer_component');
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        '${result.stdout}',
        contains('Public import: unavailable for the complete UI schema'),
      );
      expect('${result.stdout}', isNot(contains('Add to uiDependencies')));
    },
  );

  test(
    'same-owner usage points to a local Widget and unknown consumers fail',
    () async {
      fixture.publish();
      final local = await fixture.find('orders');
      expect(local.exitCode, 0, reason: '${local.stderr}');
      expect('${local.stdout}', contains('Use the ordinary local Widget'));
      expect('${local.stdout}', isNot(contains('Add to uiDependencies')));
      final unknown = await fixture.find('missing');
      expect(unknown.exitCode, 1);
      expect('${unknown.stderr}', contains('was not found uniquely'));
    },
  );

  test('missing Renderer and ambiguous UI IDs are explicit', () async {
    fixture.publish(renderer: false);
    final missing = await fixture.find('consumer_component');
    expect(missing.exitCode, 0, reason: '${missing.stderr}');
    expect(
      '${missing.stdout}',
      contains('Renderer: missing in the selected dependency closure'),
    );
    fixture.publish(duplicate: true);
    final ambiguous = await fixture.find('consumer_component');
    expect(ambiguous.exitCode, 1);
    expect(
      '${ambiguous.stderr}',
      contains('requires one unique capability match'),
    );
  });
}

final class _Fixture {
  _Fixture() {
    root = Directory.systemTemp.createTempSync('ccrouter-ui-find-');
    child = Directory(p.join(root.path, 'contracts'))..createSync();
    File(
      p.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: ui_find_host\n');
    File(
      p.join(child.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: ui_find_contracts\n');
    final tool = Directory(p.join(root.path, '.dart_tool'))..createSync();
    File(p.join(tool.path, 'package_graph.json')).writeAsStringSync(
      jsonEncode({
        'packages': [
          {
            'name': 'ui_find_host',
            'version': '1.0.0',
            'dependencies': ['ui_find_contracts'],
            'devDependencies': [],
          },
          {
            'name': 'ui_find_contracts',
            'version': '1.0.0',
            'dependencies': [],
            'devDependencies': [],
          },
        ],
      }),
    );
    File(p.join(tool.path, 'package_config.json')).writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'ui_find_host',
            'rootUri': '../',
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
          {
            'name': 'ui_find_contracts',
            'rootUri': '../contracts/',
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
        ],
      }),
    );
  }

  late final Directory root;
  late final Directory child;

  void publish({
    bool consumed = true,
    bool requiredOwner = true,
    bool publicShape = true,
    bool alias = true,
    bool renderer = true,
    bool duplicate = false,
  }) {
    final contract = <String, Object?>{
      'id': 'orders.card',
      'componentId': 'orders',
      'version': '1.0.0',
      'declaration': {
        'packageUri': 'package:ui_find_contracts/src/card.dart',
        'symbol': 'CardContract',
        'line': 10,
        'column': 1,
      },
      'publicTypes': [
        for (final name in ['CardContract', 'CardProps', 'CardAction'])
          {
            'package': 'ui_find_contracts',
            'source': 'lib/src/card.dart',
            'symbol': name,
            if (publicShape || name != 'CardProps')
              'publicLibraries': [
                'package:ui_find_contracts/ui_find_contracts.dart',
              ],
          },
      ],
    };
    final childIndex = _write(child, 'ui_find_contracts', [
      {
        'package': 'ui_find_contracts',
        'components': [
          {'id': 'orders'},
        ],
        'uiContracts': [
          contract,
          if (duplicate) {...contract, 'componentId': 'other'},
        ],
        'uiRenderers': [
          if (renderer)
            {
              ...contract,
              'implementation': {
                'packageUri': 'package:ui_find_contracts/src/renderer.dart',
                'symbol': 'renderCard',
                'line': 20,
                'column': 1,
              },
            },
        ],
      },
    ]);
    _write(
      root,
      'ui_find_host',
      [
        {
          'package': 'ui_find_host',
          'components': [
            {
              'id': 'consumer_component',
              'dependencies': [if (requiredOwner) 'orders'],
              'optionalDependencies': ['orders'],
            },
          ],
          'uiRequirements': [
            if (consumed)
              {
                ...contract,
                'consumer': 'consumer_component',
                'versionRange': '^1.0.0',
                if (alias) 'alias': 'summary',
              },
          ],
        },
      ],
      [
        CCPackageIndexDependency(
          name: 'ui_find_contracts',
          version: '1.0.0',
          contentFingerprint: childIndex.contentFingerprint,
        ),
      ],
    );
  }

  Map<String, String> snapshot() => {
    for (final f in root.listSync(recursive: true).whereType<File>())
      f.path: f.readAsStringSync(),
  };

  Future<ProcessResult> find(String consumer) =>
      Process.run(Platform.resolvedExecutable, [
        'run',
        'ccrouter_generator:ccrouter',
        'find',
        'orders.card',
        root.path,
        '--usage',
        consumer,
      ]);
}

CCPackageIndex _write(
  Directory root,
  String name,
  List<Map<String, Object?>> documents, [
  List<CCPackageIndexDependency> dependencies = const [],
]) {
  final index = CCPackageIndex(
    packageName: name,
    packageVersion: '1.0.0',
    contentFingerprint: computeCCPackageFingerprint(
      packageName: name,
      packageVersion: '1.0.0',
      bundleLibrary: null,
      bundleSymbol: null,
      dependencies: dependencies,
      metadata: documents,
    ),
    dependencies: dependencies,
    metadata: documents,
  );
  File(
      p.join(
        root.path,
        'lib',
        'src',
        'ccrouter_generated',
        'metadata',
        'ccrouter_package.json',
      ),
    )
    ..createSync(recursive: true)
    ..writeAsStringSync(index.toJson());
  return index;
}
