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
}) async {
  final logs = <String>[];
  const sourcePath = 'lib/src/probe.dart';
  await testBuilder(
    builder,
    {
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
