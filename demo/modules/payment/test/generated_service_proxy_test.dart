import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_generated.dart' show CCServiceToken;
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';
import 'package:demo_payment/src/ccrouter_generated/demo_payment_component.api.g.dart';
import 'package:flutter_test/flutter_test.dart';

final class _OrderSummaryServiceFake implements OrderSummaryService {
  _OrderSummaryServiceFake([this.source]);

  final Stream<String>? source;
  CCCancellationToken? streamCancellation;
  int _invocationCount = 0;

  @override
  Stream<String> watchSummary(
    int orderId, {
    required CCCancellationToken cancellation,
  }) {
    streamCancellation = cancellation;
    return source ?? Stream.value(summaryFor(orderId));
  }

  @override
  int get invocationCount => _invocationCount;

  @override
  Future<String> loadSummary(int orderId) async => summaryFor(orderId);

  @override
  Future<T> loadValue<T extends Object>(OrderSummaryValue<T> value) async {
    return value.value;
  }

  @override
  String summaryFor(int orderId) {
    _invocationCount++;
    return 'order:$orderId';
  }

  @override
  T unwrap<T extends Object>(OrderSummaryValue<T> value) => value.value;
}

final class _OrderRegistrar implements CCComponentRegistrar {
  const _OrderRegistrar([this.service]);

  final _OrderSummaryServiceFake? service;

  @override
  void register(CCRegistry registry) {
    registry.registerService<OrderSummaryService>(
      CCServiceProvider(
        contractToken: const CCServiceToken<OrderSummaryService>(
          'demo_order.summary',
        ),
        scope: CCServiceScope.session,
        factory: (_) => service ?? _OrderSummaryServiceFake(),
      ),
    );
  }
}

final class _EmptyRegistrar implements CCComponentRegistrar {
  const _EmptyRegistrar();

  @override
  void register(CCRegistry registry) {}
}

void main() {
  test(
    'real generated Stream Proxy delivers early snapshots and links cancellation',
    () async {
      final release = Completer<void>();
      var cancels = 0;
      final source = StreamController<String>(
        onCancel: () {
          cancels++;
          return release.future;
        },
      );
      final service = _OrderSummaryServiceFake(source.stream);
      final host = CCRouterTestHost(
        components: [
          CCComponentManifest(
            id: 'demo_order_component',
            version: '1.0.0',
            registrar: _OrderRegistrar(service),
          ),
          const CCComponentManifest(
            id: 'demo_payment_component',
            version: '1.0.0',
            dependencies: ['demo_order_component'],
            registrar: _EmptyRegistrar(),
          ),
        ],
      );
      addTearDown(host.dispose);
      host.initialize();
      await host.run(() async {
        CCRouter.openSession(accountId: 'stream');
        final cancellation = CCCancellationToken();
        final stream = DemoPaymentServices.orderSummary.watchSummary(
          1,
          cancellation: cancellation,
        );
        expect(service.streamCancellation, isNull);
        final events = <Object>[];
        final done = Completer<void>();
        stream.listen(events.add, onError: events.add, onDone: done.complete);
        await Future<void>.delayed(Duration.zero);
        source.add('first');
        await Future<void>.delayed(Duration.zero);
        expect(events, ['first']);
        source.add('second');
        await Future<void>.delayed(Duration.zero);
        final original = StateError('original');
        source.addError(original);
        await Future<void>.delayed(Duration.zero);
        expect(events, ['first', 'second', same(original)]);
        cancellation.cancel();
        expect(service.streamCancellation!.isCancelled, isTrue);
        source.add('late');
        var closed = false;
        final closing = CCRouter.closeSession().then((_) {
          closed = true;
        });
        await Future<void>.delayed(Duration.zero);
        expect(closed, isFalse);
        release.complete();
        await closing;
        await done.future;
        expect(events, [
          'first',
          'second',
          same(original),
          isA<CCInvocationCancelledError>(),
        ]);
        expect(cancels, 1);
        expect(CCRouter.recentTraces.single.status, 'cancelled');
        await source.close();
      });
    },
  );

  test(
    'generated component Proxy invokes sync, async, getter, and Trace',
    () async {
      final host = CCRouterTestHost(
        components: const [
          CCComponentManifest(
            id: 'demo_order_component',
            version: '1.0.0',
            registrar: _OrderRegistrar(),
          ),
          CCComponentManifest(
            id: 'demo_payment_component',
            version: '1.0.0',
            dependencies: ['demo_order_component'],
            registrar: _EmptyRegistrar(),
          ),
        ],
      );
      addTearDown(host.dispose);
      host.initialize();

      await host.run(() async {
        expect(
          () => DemoPaymentServices.orderSummary.summaryFor(1),
          throwsA(isA<CCServiceScopeUnavailableError>()),
        );
        CCRouter.openSession(accountId: 'first');
        expect(DemoPaymentServices.orderSummary.summaryFor(12), 'order:12');
        expect(
          await DemoPaymentServices.orderSummary.loadSummary(34),
          'order:34',
        );
        expect(
          DemoPaymentServices.orderSummary.unwrap<String>(
            const OrderSummaryValue<String>('typed'),
          ),
          'typed',
        );
        expect(
          await DemoPaymentServices.orderSummary.loadValue<int>(
            const OrderSummaryValue<int>(42),
          ),
          42,
        );
        expect(DemoPaymentServices.orderSummary.invocationCount, 2);

        await CCRouter.closeSession();
        CCRouter.openSession(accountId: 'second');
        expect(DemoPaymentServices.orderSummary.summaryFor(56), 'order:56');
        expect(DemoPaymentServices.orderSummary.invocationCount, 1);

        final traces = CCRouter.recentTraces
            .where((trace) => trace.operation == 'service')
            .toList(growable: false);
        expect(traces, hasLength(7));
        expect(traces.map((trace) => trace.context.callerComponentId).toSet(), {
          'demo_payment_component',
        });
        expect(traces.map((trace) => trace.context.targetComponentId).toSet(), {
          'demo_order_component',
        });
        expect(
          traces.map((trace) => trace.target),
          containsAll(<String>[
            'demo_order.summary.summaryFor',
            'demo_order.summary.loadSummary',
            'demo_order.summary.unwrap',
            'demo_order.summary.loadValue',
            'demo_order.summary.invocationCount',
          ]),
        );
      });
    },
  );
}
