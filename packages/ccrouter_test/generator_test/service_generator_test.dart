@TestOn('vm')
library;

import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:ccrouter_generator/builder.dart';
import 'package:test/test.dart';

void main() {
  late TestReaderWriter reader;

  setUp(() async {
    reader = TestReaderWriter(
      rootPackage: 'ccrouter_test',
      flattenOutput: true,
    );
    await reader.testing.loadIsolateSources();
  });

  Future<String> generateContract(String declarations, {bool fails = false}) =>
      _generate(
        reader: reader,
        builder: ccServiceContractBuilder(BuilderOptions.empty),
        declarations: declarations,
        outputPath:
            'lib/src/ccrouter_generated/contract/probe.service.contract.g.dart',
        fails: fails,
      );

  Future<String> generateService(
    String declarations, {
    bool fails = false,
    String imports = '',
    Map<String, String> additionalAssets = const {},
  }) => _generate(
    reader: reader,
    builder: ccServiceBuilder(BuilderOptions.empty),
    declarations: declarations,
    outputPath: 'lib/src/ccrouter_generated/service/probe.service.g.dart',
    fails: fails,
    imports: imports,
    additionalAssets: additionalAssets,
  );

  Future<String> generateMetadata(
    String declarations, {
    bool fails = false,
    String imports = '',
    Map<String, String> additionalAssets = const {},
  }) => _generate(
    reader: reader,
    builder: ccServiceMetadataBuilder(BuilderOptions.empty),
    declarations: declarations,
    outputPath: 'lib/src/ccrouter_generated/metadata/src/probe.service.json',
    fails: fails,
    imports: imports,
    additionalAssets: additionalAssets,
  );

  test('contract builder emits a typed owner-only Token', () async {
    final output = await generateContract(r'''
const owner = CCComponentId('orders');
@CCServiceContract(
  componentId: owner,
  id: 'orders.summary',
  description: 'Formats an order summary.',
)
abstract interface class OrderSummaryService {
  String summaryFor(int orderId);
}
''');

    expect(output, contains('const orderSummaryServiceToken ='));
    expect(
      output,
      contains('CCServiceToken<service_contract.OrderSummaryService>'),
    );
    expect(output, contains('"orders.summary"'));
  });

  test('service builder infers one directly implemented contract', () async {
    final output = await generateService(
      r'''
@CCService(
  key: 'primary',
  scope: CCServiceScope.session,
  creationPolicy: CCServiceCreationPolicy.newInstance,
  isDefault: true,
)
final class OrderSummaryServiceImpl implements OrderSummaryService {
  const OrderSummaryServiceImpl();
  @override
  String summaryFor(int orderId) => '$orderId';
}
''',
      imports: "import 'package:ccrouter_test/order_contract.dart';",
      additionalAssets: {
        'ccrouter_test|lib/order_contract.dart': r'''
import 'package:ccrouter/ccrouter.dart';
const orderComponentId = CCComponentId('orders');
@CCServiceContract(componentId: orderComponentId, id: 'orders.summary')
abstract interface class OrderSummaryService {
  String summaryFor(int orderId);
}
''',
      },
    );

    expect(
      output,
      contains('registry.registerService<service_type_0.OrderSummaryService>'),
    );
    expect(output, contains('const service_source.OrderSummaryServiceImpl()'));
    expect(
      output,
      contains('CCServiceToken<service_type_0.OrderSummaryService>'),
    );
    expect(output, contains('contractToken: const CCServiceToken'));
    expect(
      output,
      contains('CCServiceKey<service_type_0.OrderSummaryService>'),
    );
    expect(output, contains('scope: CCServiceScope.session'));
    expect(
      output,
      contains('creationPolicy: CCServiceCreationPolicy.newInstance'),
    );
    expect(output, contains('isDefault: true'));
  });

  test('service builder emits an internal type-local Provider', () async {
    final output = await generateService(r'''
@CCService(id: 'orders.cache')
final class OrderCache {
  OrderCache();
}
''');

    expect(
      output,
      contains('registry.registerService<service_source.OrderCache>'),
    );
    expect(output, contains('factory: (_) => service_source.OrderCache()'));
    expect(output, isNot(contains('contractToken:')));
  });

  test(
    'service metadata records contracts and ownerless implementations',
    () async {
      final contractJson =
          jsonDecode(
                await generateMetadata(r'''
const owner = CCComponentId('orders');
@CCServiceContract(componentId: owner, id: 'orders.summary')
abstract interface class OrderSummaryService {}
'''),
              )
              as Map;
      final contract = (contractJson['serviceContracts'] as List).single as Map;
      expect(contract['id'], 'orders.summary');
      expect(contract['componentId'], 'orders');
      expect((contract['token'] as Map)['symbol'], 'orderSummaryServiceToken');

      final implementationJson =
          jsonDecode(
                await generateMetadata(r'''
@CCService(id: 'orders.cache', scope: CCServiceScope.route)
final class OrderCache { const OrderCache(); }
'''),
              )
              as Map;
      final implementation =
          (implementationJson['serviceImplementations'] as List).single as Map;
      expect(implementation['id'], 'orders.cache');
      expect(implementation['componentId'], isNull);
      expect(implementation['scope'], 'route');
      expect(
        implementation['registration'],
        'ccrouterRegisterOrderCacheService',
      );
    },
  );

  final invalidContracts = <String, (String, String)>{
    'concrete declaration': (
      "const owner = CCComponentId('orders'); @CCServiceContract(componentId: owner, id: 'orders.summary') final class Probe {}",
      'public, abstract, non-generic interface',
    ),
    'invalid ID': (
      "const owner = CCComponentId('orders'); @CCServiceContract(componentId: owner, id: 'Orders Summary') abstract interface class Probe {}",
      'Service contract ID',
    ),
  };
  for (final entry in invalidContracts.entries) {
    test('contract builder rejects ${entry.key}', () async {
      final logs = await generateContract(entry.value.$1, fails: true);
      expect(logs, contains(entry.value.$2));
    });
  }

  final invalidServices = <String, (String, String)>{
    'missing identity': (
      '@CCService() final class Probe { const Probe(); }',
      'must declare id',
    ),
    'parameterized constructor': (
      "@CCService(id: 'probe.service') final class Probe { const Probe(this.value); final int value; }",
      'zero-argument generative constructor',
    ),
    'private implementation': (
      "@CCService(id: 'probe.service') final class _Probe { const _Probe(); }",
      'public, concrete, non-generic class',
    ),
    'invalid Key': (
      "@CCService(id: 'probe.service', key: 'Primary Key') final class Probe { const Probe(); }",
      'Service Key',
    ),
  };
  for (final entry in invalidServices.entries) {
    test('service builder rejects ${entry.key}', () async {
      final logs = await generateService(entry.value.$1, fails: true);
      expect(logs, contains(entry.value.$2));
    });
  }

  test(
    'service builder rejects multiple directly implemented contracts',
    () async {
      final logs = await generateService(
        r'''
@CCService()
final class Probe implements FirstService, SecondService {
  const Probe();
}
''',
        imports: "import 'package:ccrouter_test/order_contract.dart';",
        additionalAssets: {
          'ccrouter_test|lib/order_contract.dart': r'''
import 'package:ccrouter/ccrouter.dart';
const orderComponentId = CCComponentId('orders');
@CCServiceContract(componentId: orderComponentId, id: 'orders.first')
abstract interface class FirstService {}
@CCServiceContract(componentId: orderComponentId, id: 'orders.second')
abstract interface class SecondService {}
''',
        },
        fails: true,
      );
      expect(logs, contains('directly implements multiple'));
    },
  );

  test('service builder rejects an id beside an inferred contract', () async {
    final logs = await generateService(
      r'''
@CCService(id: 'orders.other')
final class Probe implements OrderSummaryService { const Probe(); }
''',
      imports: "import 'package:ccrouter_test/order_contract.dart';",
      additionalAssets: {
        'ccrouter_test|lib/order_contract.dart': r'''
import 'package:ccrouter/ccrouter.dart';
const orderComponentId = CCComponentId('orders');
@CCServiceContract(componentId: orderComponentId, id: 'orders.summary')
abstract interface class OrderSummaryService {}
''',
      },
      fails: true,
    );
    expect(logs, contains('omit id'));
  });

  test(
    'service builder does not infer an indirectly inherited contract',
    () async {
      final logs = await generateService(
        r'''
abstract base class BaseSummary implements OrderSummaryService {}
@CCService()
final class Probe extends BaseSummary { Probe(); }
''',
        imports: "import 'package:ccrouter_test/order_contract.dart';",
        additionalAssets: {
          'ccrouter_test|lib/order_contract.dart': r'''
import 'package:ccrouter/ccrouter.dart';
const orderComponentId = CCComponentId('orders');
@CCServiceContract(componentId: orderComponentId, id: 'orders.summary')
abstract interface class OrderSummaryService {}
''',
        },
        fails: true,
      );
      expect(logs, contains('inherits Service contract'));
      expect(logs, contains('directly'));
    },
  );

  test(
    'service builder rejects direct and indirect contracts together',
    () async {
      final logs = await generateService(
        r'''
abstract base class BaseSummary implements LegacySummaryService {}
@CCService()
final class Probe extends BaseSummary implements OrderSummaryService {
  Probe();
}
''',
        imports: "import 'package:ccrouter_test/order_contract.dart';",
        additionalAssets: {
          'ccrouter_test|lib/order_contract.dart': r'''
import 'package:ccrouter/ccrouter.dart';
const orderComponentId = CCComponentId('orders');
@CCServiceContract(componentId: orderComponentId, id: 'orders.summary')
abstract interface class OrderSummaryService {}
@CCServiceContract(componentId: orderComponentId, id: 'orders.legacy')
abstract interface class LegacySummaryService {}
''',
        },
        fails: true,
      );
      expect(logs, contains('inherits Service contract LegacySummaryService'));
      expect(logs, contains('automatic binding is unambiguous'));
    },
  );
}

Future<String> _generate({
  required TestReaderWriter reader,
  required Builder builder,
  required String declarations,
  required String outputPath,
  required bool fails,
  String imports = '',
  Map<String, String> additionalAssets = const {},
}) async {
  final logs = <String>[];
  const sourcePath = 'lib/src/probe.dart';
  await testBuilder(
    builder,
    {
      ...additionalAssets,
      'ccrouter_test|$sourcePath':
          "import 'package:ccrouter/ccrouter.dart';\n$imports\n$declarations",
    },
    rootPackage: 'ccrouter_test',
    generateFor: {'ccrouter_test|$sourcePath'},
    isInput: (id) => id == 'ccrouter_test|$sourcePath',
    readerWriter: reader,
    flattenOutput: true,
    onLog: (log) => logs.add(log.message),
  );
  final output = AssetId('ccrouter_test', outputPath);
  if (fails) {
    expect(await reader.canRead(output), isFalse);
    return logs.join('\n');
  }
  return reader.readAsString(output);
}
