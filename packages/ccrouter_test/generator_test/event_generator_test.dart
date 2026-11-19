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

  for (final type in [
    'async.Future<void>',
    'async.FutureOr<void>',
    'async.Future<void>?',
    'Completion',
  ]) {
    test('subscriber generator accepts resolved $type', () async {
      final output = await _generate(
        reader,
        ccEventBuilder(BuilderOptions.empty),
        '''
import 'dart:async' as async;
typedef Completion = async.Future<void>;
@CCEventContract(id: 'orders.created')
final class OrderCreatedEvent implements CCEvent { const OrderCreatedEvent(); }
@CCEventSubscription(id: 'analytics.orders-created')
$type trackOrder(OrderCreatedEvent event) => throw StateError('test');
''',
        'lib/src/ccrouter_generated/event/probe.event.g.dart',
      );
      expect(output, contains('event_source.trackOrder'));
    });
  }
  for (final type in ['async.Future<int>', 'BadCompletion']) {
    test('subscriber generator rejects resolved $type', () async {
      final logs = await _generate(
        reader,
        ccEventBuilder(BuilderOptions.empty),
        '''
import 'dart:async' as async;
typedef BadCompletion = async.Future<int>;
@CCEventContract(id: 'orders.created')
final class OrderCreatedEvent implements CCEvent { const OrderCreatedEvent(); }
@CCEventSubscription(id: 'analytics.orders-created')
$type trackOrder(OrderCreatedEvent event) => throw StateError('test');
''',
        'lib/src/ccrouter_generated/event/probe.event.g.dart',
        fails: true,
      );
      expect(logs, contains('void'));
    });
  }

  test('subscriber builder emits stable typed registration', () async {
    final output = await _generate(
      reader,
      ccEventBuilder(BuilderOptions.empty),
      r'''
@CCEventContract(id: 'orders.created')
final class OrderCreatedEvent implements CCEvent {
  const OrderCreatedEvent(this.orderId);
  final int orderId;
}
@CCEventSubscription(id: 'analytics.orders-created')
Future<void> trackOrder(
  OrderCreatedEvent event,
  CCInvocationContext context,
) async {}
''',
      'lib/src/ccrouter_generated/event/probe.event.g.dart',
    );

    expect(
      output,
      contains('registerEventSubscriber<event_source.OrderCreatedEvent>'),
    );
    expect(output, contains('eventId: "orders.created"'));
    expect(output, contains('event_source.trackOrder'));
    expect(output, contains('required String subscriberId'));
  });

  test('one-parameter subscriber is adapted to registry signature', () async {
    final output = await _generate(
      reader,
      ccEventBuilder(BuilderOptions.empty),
      r'''
@CCEventContract(id: 'orders.created')
final class OrderCreatedEvent implements CCEvent {
  const OrderCreatedEvent();
}
@CCEventSubscription()
void refreshOrders(OrderCreatedEvent event) {}
''',
      'lib/src/ccrouter_generated/event/probe.event.g.dart',
    );

    expect(output, contains('(event, _) => event_source.refreshOrders(event)'));
  });

  test(
    'metadata contains portable contract and subscriber locations',
    () async {
      final output = await _generate(
        reader,
        ccEventMetadataBuilder(BuilderOptions.empty),
        r'''
@CCEventContract(id: 'orders.created', description: 'Order was created.')
final class OrderCreatedEvent implements CCEvent {
  const OrderCreatedEvent(this.orderId);
  final int orderId;
}
@CCEventSubscription(id: 'analytics.orders-created')
void trackOrder(OrderCreatedEvent event) {}
''',
        'lib/src/ccrouter_generated/metadata/src/probe.event.json',
      );
      final metadata = jsonDecode(output) as Map<String, dynamic>;
      expect(metadata['eventContracts'], hasLength(1));
      expect(metadata['eventSubscriptions'], hasLength(1));
      expect(metadata['eventContracts'][0]['version'], '0.1.0');
      expect(metadata['eventContracts'][0].containsKey('alias'), isFalse);
      expect(
        metadata['eventContracts'][0]['shapeFingerprint'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect(
        metadata['eventContracts'][0]['declaration']['packageUri'],
        'package:ccrouter_test/src/probe.dart',
      );
      expect(
        metadata['eventSubscriptions'][0]['implementation']['symbol'],
        'trackOrder',
      );
    },
  );

  test('mutable payload fields fail generation', () async {
    final logs = await _generate(
      reader,
      ccEventMetadataBuilder(BuilderOptions.empty),
      r'''
@CCEventContract(id: 'orders.created')
final class OrderCreatedEvent implements CCEvent {
  OrderCreatedEvent(this.orderId);
  int orderId;
}
''',
      'lib/src/ccrouter_generated/metadata/src/probe.event.json',
      fails: true,
    );
    expect(logs, contains('must be final'));
  });

  test(
    'Event Contract alias overrides the generated Owner publication member',
    () async {
      final output = await _generate(
        reader,
        ccEventMetadataBuilder(BuilderOptions.empty),
        r'''
@CCEventContract(id: 'orders.created', alias: 'publishCreated')
final class OrderCreatedEvent implements CCEvent {
  const OrderCreatedEvent();
}
''',
        'lib/src/ccrouter_generated/metadata/src/probe.event.json',
      );
      final metadata = jsonDecode(output) as Map<String, dynamic>;
      expect(metadata['eventContracts'][0]['alias'], 'publishCreated');
    },
  );

  test('Event Contract rejects a generated Object member name', () async {
    final logs = await _generate(
      reader,
      ccEventMetadataBuilder(BuilderOptions.empty),
      r'''
@CCEventContract(id: 'orders.created', alias: 'toString')
final class OrderCreatedEvent implements CCEvent {
  const OrderCreatedEvent();
}
''',
      'lib/src/ccrouter_generated/metadata/src/probe.event.json',
      fails: true,
    );
    expect(logs, contains('alias "toString"'));
  });

  test(
    'Event alias changes the Contract fingerprint while omission stays stable',
    () async {
      Future<Map> contract(String? alias) async {
        final output = await _generate(
          reader,
          ccEventMetadataBuilder(BuilderOptions.empty),
          '''
@CCEventContract(id: 'orders.created'${alias == null ? '' : ", alias: '$alias'"})
final class OrderCreatedEvent implements CCEvent {
  const OrderCreatedEvent();
}
''',
          'lib/src/ccrouter_generated/metadata/src/probe.event.json',
        );
        return (jsonDecode(output)['eventContracts'] as List).single as Map;
      }

      final implicit = await contract(null);
      expect(
        implicit['shapeFingerprint'],
        '99e7c491a7c427b3e11322bb356458a6113f9305dfc43f23befbb3187b6ba883',
      );
      final explicit = await contract('publishCreated');
      expect(explicit['alias'], 'publishCreated');
      expect(explicit['shapeFingerprint'], isNot(implicit['shapeFingerprint']));
      expect(
        (await contract(null))['shapeFingerprint'],
        implicit['shapeFingerprint'],
      );
    },
  );

  test('imported Event aliases are validated on the Subscriber path', () async {
    final logs = await _generate(
      reader,
      ccEventMetadataBuilder(BuilderOptions.empty),
      '''import 'package:ccrouter_test/shared_event.dart';
@CCEventSubscription()
void observe(SharedEvent event) {}
''',
      'lib/src/ccrouter_generated/metadata/src/probe.event.json',
      fails: true,
      additionalAssets: {
        'ccrouter_test|lib/shared_event.dart': '''
import 'package:ccrouter/ccrouter.dart';
@CCEventContract(id: 'owner.shared', alias: 'toString')
final class SharedEvent implements CCEvent { const SharedEvent(); }
''',
      },
    );
    expect(logs, contains('alias "toString"'));
  });

  test('subscriber business result fails generation', () async {
    final logs = await _generate(
      reader,
      ccEventBuilder(BuilderOptions.empty),
      r'''
@CCEventContract(id: 'orders.created')
final class OrderCreatedEvent implements CCEvent {
  const OrderCreatedEvent();
}
@CCEventSubscription()
int trackOrder(OrderCreatedEvent event) => 1;
''',
      'lib/src/ccrouter_generated/event/probe.event.g.dart',
      fails: true,
    );
    expect(logs, contains('must return void'));
  });

  test(
    'duplicate Event annotations cannot silently select the first alias',
    () async {
      for (final imported in [false, true]) {
        const contract = '''
@CCEventContract(id: 'owner.first', alias: 'publishFirst')
@CCEventContract(id: 'owner.second', alias: 'publishSecond')
final class SharedEvent implements CCEvent { const SharedEvent(); }
''';
        final logs = await _generate(
          reader,
          ccEventMetadataBuilder(BuilderOptions.empty),
          imported
              ? "import 'package:ccrouter_test/shared_event.dart';\n@CCEventSubscription()\nvoid observe(SharedEvent event) {}"
              : contract,
          'lib/src/ccrouter_generated/metadata/src/probe.event.json',
          fails: true,
          additionalAssets: imported
              ? {
                  'ccrouter_test|lib/shared_event.dart':
                      "import 'package:ccrouter/ccrouter.dart';\n$contract",
                }
              : const {},
        );
        expect(logs, contains('exactly one CCEventContract'));
      }
    },
  );

  test('invalid stable ID fails generation', () async {
    final logs = await _generate(
      reader,
      ccEventMetadataBuilder(BuilderOptions.empty),
      r'''
@CCEventContract(id: 'Orders Created')
final class OrderCreatedEvent implements CCEvent {
  const OrderCreatedEvent();
}
''',
      'lib/src/ccrouter_generated/metadata/src/probe.event.json',
      fails: true,
    );
    expect(logs, contains('Event ID "Orders Created" is invalid'));
  });

  test('annotated Event cannot bypass its generated owner Client', () async {
    final logs = await _generate(
      reader,
      ccEventMetadataBuilder(BuilderOptions.empty),
      r'''
@CCEventContract(id: 'orders.created')
final class OrderCreatedEvent implements CCEvent {
  const OrderCreatedEvent();
}
Future<void> bypass() => CCRouter.event(const OrderCreatedEvent());
''',
      'lib/src/ccrouter_generated/metadata/src/probe.event.json',
      fails: true,
    );
    expect(logs, contains('must use its generated owner Client'));
  });
}

Future<String> _generate(
  TestReaderWriter reader,
  Builder builder,
  String declarations,
  String outputPath, {
  bool fails = false,
  Map<String, String> additionalAssets = const {},
}) async {
  final logs = <String>[];
  const sourcePath = 'lib/src/probe.dart';
  await testBuilder(
    builder,
    {
      ...additionalAssets,
      'ccrouter_test|$sourcePath':
          "import 'package:ccrouter/ccrouter.dart';\n$declarations",
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
