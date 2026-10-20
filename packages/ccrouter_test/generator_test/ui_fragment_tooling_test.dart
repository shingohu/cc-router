@TestOn('vm')
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:ccrouter_generator/builder.dart';
import 'package:ccrouter_generator/src/barrel_validator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../ccrouter_generator/bin/src/ui_fragment_scaffold.dart';

void main() {
  late Directory root;
  late Directory contracts;
  late Directory owner;
  setUp(() {
    root = Directory(
      Directory.systemTemp
          .createTempSync('ccrouter-ui-tooling-')
          .resolveSymbolicLinksSync(),
    );
    contracts = Directory(p.join(root.path, 'contracts'))..createSync();
    owner = Directory(p.join(root.path, 'owner'))..createSync();
    File(
      p.join(contracts.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: ccrouter_test\n');
    File(
      p.join(owner.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: ui_owner\n');
    File(p.join(contracts.path, 'lib', 'owner.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
const orderComponentId = CCComponentId('orders');
''');
  });
  tearDown(() => root.deleteSync(recursive: true));

  UIFragmentScaffoldPlan plan({
    String name = 'OrderSummary',
    String source = 'lib/owner.dart',
  }) => planUIFragmentScaffold(
    name: name,
    contractsRoot: contracts,
    ownerSource: source,
    ownerSymbol: 'orderComponentId',
    id: 'orders.summary',
    rendererRoot: owner,
  );

  test(
    'preview has no writes and CLI execution rejects duplicate targets',
    () async {
      final args = [
        'create',
        'ui-fragment',
        'OrderSummary',
        contracts.path,
        '--owner-source',
        'lib/owner.dart',
        '--owner-symbol',
        'orderComponentId',
        '--id',
        'orders.summary',
        '--renderer-root',
        owner.path,
      ];
      final before = _snapshot(root);
      final preview = await _run([...args, '--dry-run']);
      expect(preview.exitCode, 0, reason: '${preview.stderr}');
      expect('${preview.stdout}', contains('UI Fragment preview (no writes)'));
      expect('${preview.stdout}', contains('componentId: orderComponentId'));
      expect(_snapshot(root), before);
      final created = await _run(args);
      expect(created.exitCode, 0, reason: '${created.stderr}');
      expect('${created.stdout}', contains('ccrouter find orders.summary'));
      expect(
        File(p.join(contracts.path, 'pubspec.yaml')).readAsStringSync(),
        'name: ccrouter_test\n',
      );
      final bytes = _snapshot(root);
      final duplicate = await _run(args);
      expect(duplicate.exitCode, 1);
      expect('${duplicate.stderr}', contains('Refusing to overwrite'));
      expect(_snapshot(root), bytes);
    },
  );

  test('all targets are checked before any source is written', () {
    final conflict =
        File(
            p.join(
              owner.path,
              'lib',
              'src',
              'order_summary_fragment_renderer.dart',
            ),
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('// authored');
    final before = _snapshot(root);
    expect(() => plan(), throwsA(isA<Exception>()));
    expect(conflict.readAsStringSync(), '// authored');
    expect(_snapshot(root), before);
  });

  test('execution cannot overwrite a target created after preview', () async {
    final pending = plan();
    final target = pending.files.keys.last;
    target.parent.createSync(recursive: true);
    target.writeAsStringSync('// concurrent author');
    await expectLater(pending.write(), throwsA(isA<FileSystemException>()));
    expect(target.readAsStringSync(), '// concurrent author');
    expect(pending.files.keys.first.existsSync(), isFalse);
  });

  test(
    'invalid names, traversal, unknown owners and linked parents are rejected',
    () async {
      final before = _snapshot(root);
      expect(() => plan(name: '../Bad'), throwsA(isA<Exception>()));
      expect(() => plan(name: 'Default'), throwsA(isA<Exception>()));
      expect(() => plan(name: 'ToString'), throwsA(isA<Exception>()));
      expect(() => plan(source: '../owner.dart'), throwsA(isA<Exception>()));
      File(
        p.join(contracts.path, 'lib', 'owner.dart'),
      ).writeAsStringSync('const other = 1;');
      expect(() => plan(), throwsA(isA<Exception>()));
      File(
        p.join(contracts.path, 'lib', 'owner.dart'),
      ).writeAsStringSync(before['contracts/lib/owner.dart']!);
      if (!Platform.isWindows) {
        Link(p.join(owner.path, 'lib')).createSync(contracts.path);
        expect(() => plan(), throwsA(isA<Exception>()));
        Link(p.join(owner.path, 'lib')).deleteSync();
      }
      expect(_snapshot(root), before);
    },
  );

  test('scaffold and printed Consumer steps pass the real UI Builders', () async {
    final pending = plan();
    final consumerSteps = pending.nextSteps
        .split('  3. Consumer pubspec:')
        .last
        .split('  4. Actual Host pubspec:')
        .first;
    final imports = RegExp(
      r"import '[^']+';",
    ).allMatches(consumerSteps).map((match) => match.group(0)!).join('\n');
    final dependency = RegExp(
      r'Add to uiDependencies: (.*)\.',
    ).firstMatch(consumerSteps)!.group(1)!;
    final sources = <String, String>{
      'ccrouter_test|lib/owner.dart': File(
        p.join(contracts.path, 'lib', 'owner.dart'),
      ).readAsStringSync(),
      for (final entry in pending.files.entries)
        'ccrouter_test|${p.relative(entry.key.path, from: p.isWithin(contracts.path, entry.key.path) ? contracts.path : owner.path)}':
            entry.value,
      'ccrouter_test|lib/src/consumer.dart':
          '''
import 'package:ccrouter/ccrouter.dart';
$imports
const component = CCComponent(
  id: CCComponentId('consumer'), version: '1.0.0',
  dependencies: [orderComponentId], uiDependencies: [$dependency]);
''',
    };
    final reader = TestReaderWriter(
      rootPackage: 'ccrouter_test',
      flattenOutput: true,
    );
    await reader.testing.loadIsolateSources();
    final logs = <String>[];
    await testBuilder(
      ccUIFragmentMetadataBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'ccrouter_test',
      readerWriter: reader,
      flattenOutput: true,
      generateFor: {
        'ccrouter_test|lib/src/order_summary_fragment.dart',
        'ccrouter_test|lib/src/order_summary_fragment_renderer.dart',
        'ccrouter_test|lib/src/consumer.dart',
      },
      isInput: (id) => sources.containsKey(id.toString()),
      onLog: (log) => logs.add(log.message),
    );
    final contract =
        jsonDecode(
              await reader.readAsString(
                AssetId(
                  'ccrouter_test',
                  'lib/src/ccrouter_generated/metadata/order_summary_fragment.ui.json',
                ),
              ),
            )
            as Map;
    final renderer =
        jsonDecode(
              await reader.readAsString(
                AssetId(
                  'ccrouter_test',
                  'lib/src/ccrouter_generated/metadata/order_summary_fragment_renderer.ui.json',
                ),
              ),
            )
            as Map;
    expect(
      (contract['uiContracts'] as List).single['componentId'],
      'orders',
      reason: logs.join('\n'),
    );
    expect(
      (renderer['uiRenderers'] as List).single['function'],
      'renderOrderSummary',
    );
    final consumer =
        jsonDecode(
              await reader.readAsString(
                AssetId(
                  'ccrouter_test',
                  'lib/src/ccrouter_generated/metadata/consumer.ui.json',
                ),
              ),
            )
            as Map;
    final requirement = (consumer['uiRequirements'] as List).single as Map;
    expect(requirement['componentId'], 'orders');
    expect(requirement['consumer'], 'consumer');
    expect(requirement['alias'], 'orderSummary');
    await pending.write();
    final docs = [contract.cast<String, Object?>()];
    CCRouteBarrelExportValidator.annotatePublicLibraries(
      docs,
      packageRoots: {'ccrouter_test': contracts},
    );
    final types =
        (docs.single['uiContracts'] as List).single['publicTypes'] as List;
    for (final type in types) {
      expect(type['publicLibraries'], [
        'package:ccrouter_test/order_summary_fragment.dart',
      ]);
    }
  });

  test('UI import proofs honor hide, conditional exports and repeated show', () async {
    await plan().write();
    final barrel = File(
      p.join(contracts.path, 'lib', 'order_summary_fragment.dart'),
    );
    for (final directive in [
      "export 'src/order_summary_fragment.dart' show OrderSummaryProps hide OrderSummaryProps;",
      "export 'src/order_summary_fragment.dart' show OrderSummaryProps show OrderSummaryAction;",
      "export 'src/order_summary_fragment.dart' if (dart.library.io) 'other.dart' show OrderSummaryProps;",
      "export 'src/order_summary_fragment.dart' show OrderSummaryProps; export 'other.dart' show OrderSummaryProps;",
      "export 'src/order_summary_fragment.dart' show OrderSummaryProps; class OrderSummaryProps {}",
      "export 'src/order_summary_fragment.dart' show OrderSummaryProps; export 'other.dart';",
    ]) {
      barrel.writeAsStringSync(directive);
      final docs = <Map<String, Object?>>[
        {
          'package': 'ccrouter_test',
          'source': 'lib/src/order_summary_fragment.dart',
          'uiContracts': [
            {
              'publicTypes': [
                {
                  'package': 'ccrouter_test',
                  'source': 'lib/src/order_summary_fragment.dart',
                  'symbol': 'OrderSummaryProps',
                  'publicLibraries': ['stale'],
                },
              ],
            },
          ],
        },
      ];
      CCRouteBarrelExportValidator.annotatePublicLibraries(
        docs,
        packageRoots: {'ccrouter_test': contracts},
      );
      expect(
        (docs.single['uiContracts'] as List).single['publicTypes'].single,
        isNot(contains('publicLibraries')),
        reason: directive,
      );
    }
  });
  test('UI proof deferral preserves existing Service public-library facts', () {
    File(p.join(contracts.path, 'lib', 'src', 'reader.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('abstract interface class Reader {}');
    File(
      p.join(contracts.path, 'lib', 'src', 'other.dart'),
    ).writeAsStringSync('class Other {}');
    File(p.join(contracts.path, 'lib', 'reader.dart')).writeAsStringSync(
      "export 'src/reader.dart' show Reader; export 'src/other.dart';",
    );
    final docs = <Map<String, Object?>>[
      {
        'package': 'ccrouter_test',
        'source': 'lib/src/reader.dart',
        'serviceContracts': [
          {
            'declaration': {'symbol': 'Reader'},
          },
        ],
        'uiContracts': [
          {
            'publicTypes': [
              {
                'package': 'ccrouter_test',
                'source': 'lib/src/reader.dart',
                'symbol': 'Reader',
              },
            ],
          },
        ],
      },
    ];
    CCRouteBarrelExportValidator.annotatePublicLibraries(
      docs,
      packageRoots: {'ccrouter_test': contracts},
    );
    expect(
      (docs.single['serviceContracts'] as List).single['publicLibraries'],
      ['package:ccrouter_test/reader.dart'],
    );
    expect(
      (docs.single['uiContracts'] as List).single['publicTypes'].single,
      isNot(contains('publicLibraries')),
    );
  });
}

Map<String, String> _snapshot(Directory root) => {
  for (final file
      in root.listSync(recursive: true, followLinks: false).whereType<File>())
    p.relative(file.path, from: root.path).replaceAll(p.separator, '/'): file
        .readAsStringSync(),
};

Future<ProcessResult> _run(List<String> args) => Process.run(
  Platform.resolvedExecutable,
  ['run', 'ccrouter_generator:ccrouter', ...args],
);
