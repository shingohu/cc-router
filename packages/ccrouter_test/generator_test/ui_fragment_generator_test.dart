@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:ccrouter_generator/builder.dart';
import 'package:ccrouter_generator/src/barrel_validator.dart';
import 'package:ccrouter_generator/src/ui_fragment_workspace.dart';
import 'package:test/test.dart';

const _source = '''
import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_ui/ccrouter_ui.dart';
import 'package:flutter/widgets.dart';
const owner = CCComponentId('orders');
final class Props {
  const Props({required this.orderId});
  final int orderId;
}
enum Action { openDetails }
@CCUIFragmentContract<Props, Action>(componentId: owner, id: 'orders.summary', version: '1.0.0')
abstract final class Summary {}
''';

Future<({String output, String logs})> _generate(
  String source, {
  bool metadata = true,
  Map<String, String> additionalSources = const {},
}) async {
  final reader = TestReaderWriter(
    rootPackage: 'ccrouter_test',
    flattenOutput: true,
  );
  await reader.testing.loadIsolateSources();
  final logs = <String>[];
  await testBuilder(
    metadata
        ? ccUIFragmentMetadataBuilder(BuilderOptions.empty)
        : ccUIFragmentBuilder(BuilderOptions.empty),
    {'ccrouter_test|lib/src/ui_probe.dart': source, ...additionalSources},
    rootPackage: 'ccrouter_test',
    generateFor: {'ccrouter_test|lib/src/ui_probe.dart'},
    isInput: (id) => id == 'ccrouter_test|lib/src/ui_probe.dart',
    readerWriter: reader,
    flattenOutput: true,
    onLog: (log) => logs.add(log.message),
  );
  final output = AssetId(
    'ccrouter_test',
    metadata
        ? 'lib/src/ccrouter_generated/metadata/ui_probe.ui.json'
        : 'lib/src/ccrouter_generated/ui/ui_probe.ui.g.dart',
  );
  return (
    output: await reader.canRead(output)
        ? await reader.readAsString(output)
        : '',
    logs: logs.join('\n'),
  );
}

void main() {
  test('UI marker and DTOs require explicit public Contract exposure', () {
    final root = Directory.systemTemp.createTempSync('ccrouter-ui-barrel-');
    addTearDown(() => root.deleteSync(recursive: true));
    final lib = Directory('${root.path}/lib')..createSync();
    File(
      '${lib.path}/contract.dart',
    ).writeAsStringSync('class Marker {}\nclass Props {}');
    final barrel = File('${lib.path}/public.dart')
      ..writeAsStringSync("export 'contract.dart' show Marker;");
    final documents = <Map<String, Object?>>[
      {
        'package': 'contracts',
        'source': 'lib/contract.dart',
        'uiContracts': [
          {
            'id': 'orders.summary',
            'publicTypes': [
              {
                'package': 'contracts',
                'source': 'lib/contract.dart',
                'symbol': 'Marker',
              },
              {
                'package': 'contracts',
                'source': 'lib/contract.dart',
                'symbol': 'Props',
              },
            ],
          },
        ],
      },
    ];
    expect(
      CCRouteBarrelExportValidator.validate(
        root,
        documents,
        packageRoots: {'contracts': root},
      ),
      contains(contains('Props')),
    );
    barrel.writeAsStringSync("export 'contract.dart' show Marker, Props;");
    expect(
      CCRouteBarrelExportValidator.validate(
        root,
        documents,
        packageRoots: {'contracts': root},
      ),
      isEmpty,
    );
  });
  test('no UI declaration emits nothing', () async {
    expect((await _generate('const value = 1;')).output, isEmpty);
  });
  test('shape includes DTO fields and enum values', () async {
    String fingerprint(String json) =>
        ((jsonDecode(json) as Map)['uiContracts'] as List)
                .single['shapeFingerprint']
            as String;
    final original = (await _generate(_source)).output;
    expect(original, isNotEmpty);
    expect(
      fingerprint(
        (await _generate(
          _source.replaceAll('int orderId', 'String orderId'),
        )).output,
      ),
      isNot(fingerprint(original)),
    );
    expect(
      fingerprint(
        (await _generate(
          _source.replaceAll('openDetails }', 'openDetails, retry }'),
        )).output,
      ),
      isNot(fingerprint(original)),
    );
    expect(
      fingerprint((await _generate(_source)).output),
      fingerprint(original),
    );
  });
  test('effective const defaults participate in the fingerprint', () async {
    final source = _source.replaceFirst(
      'required this.orderId',
      'this.orderId = defaultId',
    );
    final first =
        jsonDecode((await _generate('$source\nconst defaultId = 1;')).output)
            as Map;
    final second =
        jsonDecode((await _generate('$source\nconst defaultId = 2;')).output)
            as Map;
    expect(
      (first['uiContracts'] as List).single['shapeFingerprint'],
      isNot((second['uiContracts'] as List).single['shapeFingerprint']),
    );
  });
  test('effective field initializers participate in the fingerprint', () async {
    final source = _source
        .replaceFirst('const Props({required this.orderId});', 'const Props();')
        .replaceFirst('final int orderId;', 'final int orderId = defaultId;');
    String fingerprint(String output) =>
        (jsonDecode(output)['uiContracts'] as List).single['shapeFingerprint']
            as String;
    final first = fingerprint(
      (await _generate('$source\nconst defaultId = 1;')).output,
    );
    final changed = fingerprint(
      (await _generate('$source\nconst defaultId = 2;')).output,
    );
    final equivalent = fingerprint(
      (await _generate('$source\nconst defaultId = 1 + 0;')).output,
    );
    expect(changed, isNot(first));
    expect(equivalent, first);
  });
  test(
    'nested imported defaults and named DTO constructors remain supported',
    () async {
      final source =
          "import 'package:ccrouter_test/src/ui_defaults.dart';\n" +
          _source
              .replaceFirst(
                'const Props({required this.orderId});',
                'const Props({required this.orderId}); '
                    'const Props.named({this.orderId = 7});',
              )
              .replaceFirst(
                'final int orderId;',
                'final int orderId; '
                    'final Nested settings = const Nested(value: defaultId); '
                    'final Kind kind = Kind.first; final int? optional = null;',
              ) +
          '\nenum Kind { first, second }\n'
              'final class Nested { const Nested({required this.value}); final int value; }';
      Future<String> fingerprint(String value) async {
        final result = await _generate(
          source,
          additionalSources: {
            'ccrouter_test|lib/src/ui_defaults.dart':
                'const defaultId = $value;',
          },
        );
        expect(result.output, isNotEmpty, reason: result.logs);
        return (jsonDecode(result.output)['uiContracts'] as List)
                .single['shapeFingerprint']
            as String;
      }

      final first = await fingerprint('1');
      expect(await fingerprint('2'), isNot(first));
      expect(await fingerprint('1 + 0'), first);
    },
  );
  for (final constructor in [
    'const Props() : orderId = 1;',
    'const Props({int orderId = 1}) : orderId = orderId * 2;',
    'const Props({required int orderId}) : orderId = orderId;',
    'const Props() : this.named(1); const Props.named(this.orderId);',
  ]) {
    test('rejects unmodeled DTO construction: $constructor', () async {
      final result = await _generate(
        _source.replaceFirst(
          'const Props({required this.orderId});',
          constructor,
        ),
      );
      expect(result.output, isEmpty);
      expect(result.logs, contains('UI DTO constructors'));
    });
  }
  for (final declaration in [
    'enum Action { openDetails; Widget get content => const SizedBox(); }',
    'enum Action { openDetails; Widget content() => const SizedBox(); }',
    'enum Action { openDetails; set content(Widget value) {} }',
    'enum Action { openDetails; static const label = "open"; }',
    'mixin Behavior { Widget get content => const SizedBox(); } '
        'enum Action with Behavior { openDetails }',
    'abstract interface class Behavior {} '
        'enum Action implements Behavior { openDetails }',
    'enum Action { openDetails; const Action(); }',
  ]) {
    test('rejects enhanced UI enum: $declaration', () async {
      final result = await _generate(
        _source.replaceFirst('enum Action { openDetails }', declaration),
      );
      expect(result.output, isEmpty);
      expect(result.logs, contains('UI v1 enums must be plain'));
    });
  }
  test('nested DTO enum uses the same plain-enum boundary', () async {
    final result = await _generate(
      _source.replaceFirst('final int orderId;', 'final Kind orderId;') +
          '\nenum Kind { value; Widget get content => const SizedBox(); }',
    );
    expect(result.output, isEmpty);
    expect(result.logs, contains('UI v1 enums must be plain'));
  });
  for (final type in [
    'Widget',
    'BuildContext',
    'Axis',
    'TextDirection',
    'Future<int>',
    'Stream<int>',
    'void Function()',
    'List<int>',
    'dynamic',
  ]) {
    test('rejects unsupported Props field $type', () async {
      final result = await _generate(
        _source.replaceAll('int orderId', '$type orderId'),
      );
      expect(result.output, isEmpty);
      expect(result.logs, contains('UI DTO'));
    });
  }
  test('Action enum cannot originate from Flutter', () async {
    final result = await _generate(
      _source.replaceFirst('<Props, Action>', '<Props, Axis>'),
    );
    expect(result.output, isEmpty);
    expect(result.logs, contains('UI DTO enums'));
  });
  test('consumer generation uses isolated typed Widget Client', () async {
    final result = await _generate('''$_source
const component = CCComponent(id: CCComponentId('account'), version: '1.0.0',
  dependencies: [owner], uiDependencies: [
    CCUIFragmentDependency<Summary>(alias: 'summary', versionRange: '^1.0.0')]);
''', metadata: false);
    expect(result.output, contains('class AccountFragments'));
    expect(result.output, contains('CCUIGeneratedFragment<'));
    expect(result.output, isNot(contains('CCRouterRuntime')));
    expect(result.output, isNot(contains('registerRoute')));
  });
  test('missing required owner fails generation', () async {
    final result = await _generate('''$_source
const component = CCComponent(id: CCComponentId('account'), version: '1.0.0',
  uiDependencies: [CCUIFragmentDependency<Summary>(alias: 'summary', versionRange: '^1.0.0')]);
''');
    expect(result.output, isEmpty);
    expect(result.logs, contains('dependencyMissing'));
  });
  test('Renderer signature must match exact schema', () async {
    final result = await _generate('''$_source
@CCUIFragmentRenderer(Summary)
Widget render(CCUIFragmentRenderInput<String, Action> input) => const SizedBox();
''');
    expect(result.output, isEmpty);
    expect(result.logs, contains('rendererSignatureMismatch'));
  });
  test('Host validation rejects missing or foreign-owner Renderer', () {
    final contract = {
      'componentId': 'orders',
      'id': 'orders.summary',
      'version': '1.0.0',
      'shapeFingerprint': 'shape',
    };
    final documents = <Map<String, Object?>>[
      {
        'package': 'contracts',
        'uiSchemaVersion': 1,
        'uiContracts': [contract],
      },
      {
        'package': 'a',
        'components': [
          {
            'id': 'account',
            'dependencies': ['orders'],
          },
        ],
        'uiRequirements': [
          {...contract, 'consumer': 'account', 'versionRange': '^1.0.0'},
        ],
      },
    ];
    expect(validateUIFragmentWorkspace(documents, host: false), isEmpty);
    expect(
      validateUIFragmentWorkspace(documents, host: true),
      contains(contains('missingImplementation')),
    );
    documents.add({
      'package': 'evil',
      'uiRenderers': [contract],
    });
    expect(
      validateUIFragmentWorkspace(documents, host: true),
      contains(contains('ownerMismatch')),
    );
  });
}
