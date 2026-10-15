@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:ccrouter_generator/builder.dart';
import 'package:ccrouter_generator/ccrouter_generator.dart';
import 'package:test/test.dart';

const _source = '''
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
const owner = CCComponentId('orders');

@CCRouteContract<String>(
  componentId: owner,
  id: 'orders.detail',
  pattern: CCPathPattern('/orders/:id'),
)
abstract class OrderRouteContract {
  const OrderRouteContract({required this.id, @CCQueryParam() this.tab = 'summary'});
  final int id;
  final String tab;
}

@CCServiceContract(componentId: owner, id: 'orders.reader')
abstract interface class OrderReader {
  Future<String> read(int id);
}
''';

void main() {
  test('领域迁移保持 Route 代码及 Route/Service 契约形状', () async {
    final flat = await _generate('');
    final nested = await _generate('orders/');

    expect(nested.code, flat.code);
    for (final group in ['routes', 'serviceContracts']) {
      final before = (flat.documents[group]![group] as List).single as Map;
      final after = (nested.documents[group]![group] as List).single as Map;
      for (final key in ['id', 'componentId', 'version', 'shapeFingerprint']) {
        expect(before[key], isNotNull, reason: '$group.$key');
        expect(after[key], before[key], reason: '$group.$key');
      }
      expect(nested.documents[group]!['source'], 'lib/src/orders/probe.dart');
    }

    final root = Directory.systemTemp.createTempSync(
      'ccrouter-contract-layout-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    void write(String relative, String content) {
      File('${root.path}/$relative')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', 'name: ccrouter_test\n');
    const api = 'src/ccrouter_generated/ccrouter_test.contracts.api.g.dart';
    const consumer = "export '$api' show OrderRoute;\n";
    write('lib/orders.dart', consumer);
    write(
      'lib/orders_reader.dart',
      "export 'src/probe.dart' show OrderReader;\n",
    );

    for (final entry in {'': flat, 'orders/': nested}.entries) {
      final domain = entry.key;
      write('lib/src/${domain}probe.dart', _source);
      write(
        'lib/src/ccrouter_generated/contract/${domain}probe.route.contract.g.dart',
        entry.value.code,
      );
      // 夹具仅模拟 Builder 后的稳定聚合入口，不修改仓库生成文件。
      write(
        'lib/$api',
        "export 'contract/${domain}probe.route.contract.g.dart' show OrderRoute;\n",
      );
      write(
        'lib/orders_reader.dart',
        "export 'src/${domain}probe.dart' show OrderReader;\n",
      );
      final documents = entry.value.documents.values.toList();
      CCRouteBarrelExportValidator.annotatePublicLibraries(
        documents,
        packageRoots: {'ccrouter_test': root},
      );
      expect(CCRouteBarrelExportValidator.validate(root, documents), isEmpty);
      final route =
          (entry.value.documents['routes']!['routes'] as List).single as Map;
      expect((route['contracts'] as Map)['publicLibraries'], [
        'package:ccrouter_test/orders.dart',
      ]);
      final service =
          (entry.value.documents['serviceContracts']!['serviceContracts']
                      as List)
                  .single
              as Map;
      expect(service['publicLibraries'], [
        'package:ccrouter_test/orders_reader.dart',
      ]);
      expect(File('${root.path}/lib/orders.dart').readAsStringSync(), consumer);
    }

    // 当前公开终点必须在 lib 根目录，内部嵌套支持不能扩张为公开入口嵌套支持。
    write('lib/orders.dart', 'library;\n');
    write('lib/orders/api.dart', "export '../$api' show OrderRoute;\n");
    expect(
      CCRouteBarrelExportValidator.validate(
        root,
        nested.documents.values.toList(),
      ),
      contains(contains('Public route "orders.detail"')),
    );
  });
}

Future<({String code, Map<String, Map<String, Object?>> documents})> _generate(
  String domain,
) async {
  final reader = TestReaderWriter(
    rootPackage: 'ccrouter_test',
    flattenOutput: true,
  );
  await reader.testing.loadIsolateSources();
  final input = AssetId('ccrouter_test', 'lib/src/${domain}probe.dart');
  for (final builder in [
    ccRouteContractBuilder(BuilderOptions.empty),
    ccRouteMetadataBuilder(BuilderOptions.empty),
    ccServiceMetadataBuilder(BuilderOptions.empty),
  ]) {
    await testBuilder(
      builder,
      {'ccrouter_test|${input.path}': _source},
      rootPackage: 'ccrouter_test',
      generateFor: {'ccrouter_test|${input.path}'},
      isInput: (id) => id == input,
      readerWriter: reader,
      flattenOutput: true,
    );
  }
  final documents = <String, Map<String, Object?>>{};
  for (final entry in {
    'route': 'routes',
    'service': 'serviceContracts',
  }.entries) {
    final output = AssetId(
      'ccrouter_test',
      'lib/src/ccrouter_generated/metadata/src/${domain}probe.${entry.key}.json',
    );
    documents[entry.value] =
        jsonDecode(await reader.readAsString(output)) as Map<String, Object?>;
  }
  return (
    code: await reader.readAsString(
      AssetId(
        'ccrouter_test',
        'lib/src/ccrouter_generated/contract/${domain}probe.route.contract.g.dart',
      ),
    ),
    documents: documents,
  );
}
