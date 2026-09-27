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

  Future<String> generateProxy(
    String declarations, {
    bool fails = false,
    String imports = '',
    Map<String, String> additionalAssets = const {},
  }) => _generate(
    reader: reader,
    builder: ccServiceProxyBuilder(BuilderOptions.empty),
    declarations: declarations,
    outputPath: 'lib/src/ccrouter_generated/component/probe.service_api.g.dart',
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
    'proxy builder emits a component caller for sync and async members',
    () async {
      final output = await generateProxy(
        r'''
const paymentId = CCComponentId('payment');
const orderId = CCComponentId('orders');
const payment = CCComponent(
  id: paymentId,
  version: '1.0.0',
  dependencies: [orderId],
  serviceDependencies: [
    CCServiceDependency<OrderSummaryService>(),
  ],
);
''',
        imports: "import 'package:ccrouter_test/order_contracts.dart';",
        additionalAssets: {
          'ccrouter_test|lib/order_contracts.dart': r'''
import 'package:ccrouter/ccrouter.dart';
const orderId = CCComponentId('orders');
enum SummaryStyle { compact, detailed }
final class OrderQuote { const OrderQuote(this.value); final int value; }
@CCServiceContract(componentId: orderId, id: 'orders.summary')
abstract interface class OrderSummaryService {
  String summaryFor(int orderId, [SummaryStyle style = SummaryStyle.compact]);
  Future<OrderQuote> quote({required int orderId, String currency = 'CNY'});
  int get cachedCount;
}
''',
        },
      );

      expect(output, contains('abstract final class PaymentServices'));
      expect(
        output,
        matches(
          RegExp(
            r'static const service_type_\d+\.OrderSummaryService orderSummary',
          ),
        ),
      );
      expect(output, contains('callerComponentId: "payment"'));
      expect(output, contains('methodId: "summaryFor"'));
      expect(output, contains('CCRouterGeneratedServiceBinding.invokeSync'));
      expect(output, contains('CCRouterGeneratedServiceBinding.invoke<'));
      expect(
        output,
        matches(
          RegExp(
            r'service_type_\d+\.Future<service_type_\d+\.OrderQuote> quote',
          ),
        ),
      );
      expect(output, contains('required int orderId'));
      expect(output, contains('String currency = "CNY"'));
      expect(output, contains('int get cachedCount'));
    },
  );

  test(
    'proxy builder preserves bounded generic methods and explicit forwarding',
    () async {
      final output = await generateProxy(
        r'''
const paymentId = CCComponentId('payment');
const orderId = CCComponentId('orders');
const payment = CCComponent(
  id: paymentId,
  version: '1.0.0',
  dependencies: [orderId],
  serviceDependencies: [CCServiceDependency<GenericOrderService>()],
);
''',
        imports: "import 'package:ccrouter_test/order_contracts.dart';",
        additionalAssets: {
          'ccrouter_test|lib/order_contracts.dart': r'''
import 'package:ccrouter/ccrouter.dart';
const orderId = CCComponentId('orders');
sealed class OrderValue { const OrderValue(); }
@CCServiceContract(componentId: orderId, id: 'orders.generic')
abstract interface class GenericOrderService {
  T identity<T extends OrderValue>(T value);
  T create<T extends OrderValue>();
  Future<R?> load<T extends OrderValue, R extends Iterable<T>>(T seed);
}
''',
        },
      );

      expect(
        output,
        matches(
          RegExp(
            r'T identity<T extends service_type_\d+\.OrderValue>\(T value\)',
          ),
        ),
      );
      expect(
        output,
        matches(
          RegExp(r'T create<T extends service_type_\d+\.OrderValue>\(\)'),
        ),
      );
      expect(
        output,
        matches(
          RegExp(
            r'load<T extends service_type_\d+\.OrderValue, R extends Iterable<T>>\(T seed\)',
          ),
        ),
      );
      expect(output, contains('Future<R?>'));
      expect(output, contains('service.identity<T>(value)'));
      expect(output, contains('service.create<T>()'));
      expect(output, contains('service.load<T, R>(seed)'));
      expect(
        output,
        matches(
          RegExp(
            r'CCRouterGeneratedServiceBinding\.invokeSync<\s*service_type_\d+\.GenericOrderService,\s*T\s*>',
          ),
        ),
      );
      expect(
        output,
        matches(
          RegExp(
            r'CCRouterGeneratedServiceBinding\.invoke<\s*service_type_\d+\.GenericOrderService,\s*R\?\s*>',
          ),
        ),
      );
    },
  );

  test('proxy import prefixes avoid generic parameter names', () async {
    final output = await generateProxy(
      r'''
const paymentId = CCComponentId('payment');
const orderId = CCComponentId('orders');
const payment = CCComponent(
  id: paymentId,
  version: '1.0.0',
  dependencies: [orderId],
  serviceDependencies: [CCServiceDependency<GenericOrderService>()],
);
''',
      imports: "import 'package:ccrouter_test/order_contracts.dart';",
      additionalAssets: {
        'ccrouter_test|lib/order_contracts.dart': r'''
import 'package:ccrouter/ccrouter.dart';
const orderId = CCComponentId('orders');
final class OrderValue { const OrderValue(); }
@CCServiceContract(componentId: orderId, id: 'orders.generic')
abstract interface class GenericOrderService {
  service_type_0 preserve<service_type_0 extends OrderValue>(
    service_type_0 value,
  );
}
''',
      },
    );

    expect(
      output,
      contains(
        "import 'package:ccrouter_test/order_contracts.dart' as service_type_1;",
      ),
    );
    expect(
      output,
      contains(
        'service_type_0 preserve<service_type_0 extends service_type_1.OrderValue>',
      ),
    );
  });

  test('proxy builder embeds typed Key and explicit alias', () async {
    final output = await generateProxy(
      r'''
const paymentId = CCComponentId('payment');
const orderId = CCComponentId('orders');
const payment = CCComponent(
  id: paymentId,
  version: '1.0.0',
  dependencies: [orderId],
  serviceDependencies: [
    CCServiceDependency<OrderSummaryService>(
      key: CCServiceKey<OrderSummaryService>('archived'),
      alias: 'archivedOrders',
    ),
  ],
);
''',
      imports: "import 'package:ccrouter_test/order_contracts.dart';",
      additionalAssets: {
        'ccrouter_test|lib/order_contracts.dart': r'''
import 'package:ccrouter/ccrouter.dart';
const orderId = CCComponentId('orders');
@CCServiceContract(componentId: orderId, id: 'orders.summary')
abstract interface class OrderSummaryService { String summaryFor(int id); }
''',
      },
    );

    expect(output, contains('archivedOrders'));
    expect(
      output,
      matches(
        RegExp(
          r'key: const CCServiceKey<service_type_\d+\.OrderSummaryService>\("archived"\)',
        ),
      ),
    );
  });

  test('proxy builder emits nothing without a Service dependency', () async {
    await testBuilder(
      ccServiceProxyBuilder(BuilderOptions.empty),
      {
        'ccrouter_test|lib/src/probe.dart': r'''
import 'package:ccrouter/ccrouter.dart';
const probe = CCComponent(
  id: CCComponentId('probe'),
  version: '1.0.0',
);
''',
      },
      rootPackage: 'ccrouter_test',
      generateFor: {'ccrouter_test|lib/src/probe.dart'},
      isInput: (id) => id == 'ccrouter_test|lib/src/probe.dart',
      readerWriter: reader,
      flattenOutput: true,
    );

    expect(
      await reader.canRead(
        AssetId(
          'ccrouter_test',
          'lib/src/ccrouter_generated/component/probe.service_api.g.dart',
        ),
      ),
      isFalse,
    );
  });

  test(
    'proxy builder rejects an owner missing from required dependencies',
    () async {
      final logs = await generateProxy(
        r'''
const paymentId = CCComponentId('payment');
const payment = CCComponent(
  id: paymentId,
  version: '1.0.0',
  serviceDependencies: [CCServiceDependency<OrderSummaryService>()],
);
''',
        imports: "import 'package:ccrouter_test/order_contracts.dart';",
        additionalAssets: {
          'ccrouter_test|lib/order_contracts.dart': r'''
import 'package:ccrouter/ccrouter.dart';
const orderId = CCComponentId('orders');
@CCServiceContract(componentId: orderId, id: 'orders.summary')
abstract interface class OrderSummaryService { String summaryFor(int id); }
''',
        },
        fails: true,
      );

      expect(logs, contains('Add that owner to CCComponent.dependencies'));
    },
  );

  test('proxy builder rejects a contract imported through src', () async {
    final logs = await generateProxy(
      r'''
const paymentId = CCComponentId('payment');
const orderId = CCComponentId('orders');
const payment = CCComponent(
  id: paymentId,
  version: '1.0.0',
  dependencies: [orderId],
  serviceDependencies: [CCServiceDependency<OrderSummaryService>()],
);
''',
      imports: "import 'package:ccrouter_test/src/order_contract.dart';",
      additionalAssets: {
        'ccrouter_test|lib/src/order_contract.dart': r'''
import 'package:ccrouter/ccrouter.dart';
const orderId = CCComponentId('orders');
@CCServiceContract(componentId: orderId, id: 'orders.summary')
abstract interface class OrderSummaryService { String summaryFor(int id); }
''',
      },
      fails: true,
    );

    expect(logs, contains('explicit public package import'));
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
      expect(contract['methods'], isEmpty);

      final genericContractJson =
          jsonDecode(
                await generateMetadata(r'''
const owner = CCComponentId('orders');
@CCServiceContract(componentId: owner, id: 'orders.generic')
abstract interface class GenericOrderService {
  Future<R?> load<T extends Object, R extends Iterable<T>>(T value);
}
'''),
              )
              as Map;
      final genericContract =
          (genericContractJson['serviceContracts'] as List).single as Map;
      final genericMethod = (genericContract['methods'] as List).single as Map;
      expect(genericMethod['typeParameters'], <String>[
        'T extends Object',
        'R extends Iterable<T>',
      ]);
      expect(genericMethod['returnType'], 'Future<R?>');
      expect(genericMethod['resultType'], 'R?');

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
    'generic contract': (
      "const owner = CCComponentId('orders'); @CCServiceContract(componentId: owner, id: 'orders.summary') abstract interface class Probe<T> { T read(); }",
      'public, abstract, non-generic interface',
    ),
    'stream result': (
      "const owner = CCComponentId('orders'); @CCServiceContract(componentId: owner, id: 'orders.summary') abstract interface class Probe { Stream<int> watch(); }",
      'returns Stream',
    ),
    'future-or result': (
      "const owner = CCComponentId('orders'); @CCServiceContract(componentId: owner, id: 'orders.summary') abstract interface class Probe { FutureOr<int> read(); }",
      'returns FutureOr',
    ),
    'callback parameter': (
      "const owner = CCComponentId('orders'); @CCServiceContract(componentId: owner, id: 'orders.summary') abstract interface class Probe { void listen(void Function() callback); }",
      'callback parameter',
    ),
    'setter': (
      "const owner = CCComponentId('orders'); @CCServiceContract(componentId: owner, id: 'orders.summary') abstract interface class Probe { set value(int value); }",
      'do not support setters',
    ),
    'operator': (
      "const owner = CCComponentId('orders'); @CCServiceContract(componentId: owner, id: 'orders.summary') abstract interface class Probe { Probe operator +(Probe other); }",
      'support named methods only',
    ),
    'contract inheritance': (
      "const owner = CCComponentId('orders'); abstract interface class Base { String read(); } @CCServiceContract(componentId: owner, id: 'orders.summary') abstract interface class Probe implements Base {}",
      'Contract inheritance and mixins are not supported',
    ),
  };
  for (final entry in invalidContracts.entries) {
    test('contract builder rejects ${entry.key}', () async {
      final imports = switch (entry.key) {
        'stream result' || 'future-or result' => "import 'dart:async';",
        _ => '',
      };
      final logs = await _generate(
        reader: reader,
        builder: ccServiceContractBuilder(BuilderOptions.empty),
        declarations: entry.value.$1,
        outputPath:
            'lib/src/ccrouter_generated/contract/probe.service.contract.g.dart',
        fails: true,
        imports: imports,
      );
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
