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
    {'ccrouter_test|lib/src/ui_probe.dart': source},
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
