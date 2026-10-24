import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'navigation_test.dart'
    show TestIntent, RouteArgs, RouteArgsCodec, BackendEventNavigationAdapter;

final class _Command implements CCCommand<void> {
  const _Command();
}

final class _HeldSink implements CCDiagnosticSink {
  final writes = <Completer<void>>[];

  @override
  Future<void> record(CCDiagnosticEvent event) {
    final write = Completer<void>();
    writes.add(write);
    return write.future;
  }
}

final class _OnDispose implements CCDisposable {
  _OnDispose(this.callback);
  final void Function() callback;

  @override
  void dispose() => callback();
}

void _emit(CCRouterRuntime runtime) => runtime.recordHostToolLifecycleFailure(
  integrationId: 'cache.probe',
  operation: 'probe',
  errorType: 'Probe',
);

Future<void> _turn() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'all seven history totals survive rotation and disabled retention',
    () async {
      Map<String, int>? totals;
      for (final capacity in [1000, 1, 0]) {
        final adapter = BackendEventNavigationAdapter();
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: adapter,
          traceCapacity: capacity,
          navigationDiagnosticCapacity: capacity,
        );
        addTearDown(runtime.dispose);
        runtime.registerCommand<_Command, void>((_, _) {});
        runtime.registerRoute<RouteArgs, void>(
          CCRouteDefinition(
            routeId: 'fixture.detail',
            patterns: const [CCPathPattern('/detail/:value', primary: true)],
            codec: const RouteArgsCodec(),
          ),
        );
        runtime.initialize();
        for (var i = 0; i < 3; i++) {
          await runtime.command(const _Command());
          await runtime.goRoute(
            TestIntent<void>('fixture.detail', RouteArgs('$i')),
          );
          adapter.emit(
            CCNavigationBackendEventKind.push,
            backendEntryId: 'foreign.$i',
            owner: CCBackendEntryOwner.foreign,
          );
          await expectLater(
            runtime.pushRoute(
              const TestIntent<void>('missing', RouteArgs('private')),
            ),
            throwsA(isA<CCRouteNotFoundError>()),
          );
        }
        final histories = runtime.diagnosticSnapshot.histories;
        totals ??= {
          for (final h in histories) h.name: h.retainedCount + h.omittedCount,
        };
        expect(histories, hasLength(7));
        for (final h in histories) {
          final total = totals[h.name]!;
          expect(total, greaterThan(1), reason: h.name);
          expect(
            h.retainedCount,
            total < capacity ? total : capacity,
            reason: h.name,
          );
          expect(h.omittedCount, total - h.retainedCount, reason: h.name);
        }
        await runtime.dispose();
      }
    },
  );

  for (final capacity in [0, 1]) {
    test(
      'idle health is reused and no-Sink commands invalidate at $capacity',
      () async {
        final runtime = CCRouterRuntime.forTesting(traceCapacity: capacity);
        addTearDown(runtime.dispose);
        runtime.registerCommand<_Command, void>((_, _) {});
        runtime.initialize();
        final before = runtime.diagnosticSnapshot;
        expect(runtime.diagnosticSnapshot, same(before));
        expect(runtime.diagnosticDeliverySnapshot, same(before.delivery));
        for (var i = 0; i < 3; i++) {
          await runtime.command(const _Command());
        }
        final after = runtime.diagnosticSnapshot;
        expect(after, isNot(same(before)));
        expect(after.revision, greaterThan(before.revision));
        final traces = after.histories.singleWhere((h) => h.name == 'traces');
        expect(traces.retainedCount, capacity);
        expect(traces.omittedCount, 3 - capacity);
        expect(after.sinkConfigured, isFalse);
        expect(after.delivery.deliveredEventCount, 0);
        expect(runtime.diagnosticSnapshot, same(after));
        final other = CCRouterRuntime.forTesting();
        addTearDown(other.dispose);
        expect(other.diagnosticSnapshot.runtimeId, isNot(after.runtimeId));
        expect(other.diagnosticSnapshot, isNot(same(after)));
      },
    );
  }

  for (final failLate in [false, true]) {
    test(
      'delivery changes invalidate health including late failure=$failLate',
      () async {
        final sink = _HeldSink();
        final runtime = CCRouterRuntime.forTesting(
          diagnostics: CCDiagnosticsConfig(
            sink: sink,
            queueCapacity: 1,
            defaultEnabled: false,
            policies: const [
              CCDiagnosticCategoryPolicy(
                category: CCDiagnosticCategory.initialization,
                minimumLevel: CCDiagnosticLevel.error,
              ),
            ],
          ),
        );
        addTearDown(runtime.dispose);
        // Filter successful construction to isolate each delivery transition.
        final idle = runtime.diagnosticSnapshot;
        _emit(runtime);
        final queued = runtime.diagnosticSnapshot;
        expect(queued.delivery.queuedEventCount, 1);
        expect(queued.delivery.peakQueueDepth, 1);
        expect(runtime.diagnosticSnapshot, same(queued));
        await _turn();
        final writing = runtime.diagnosticSnapshot;
        expect(writing.revision, queued.revision);
        expect(writing.delivery.inFlightWriteCount, 1);
        expect(writing.delivery.queuedEventCount, 0);
        expect(writing, isNot(same(queued)));
        sink.writes.single.complete();
        await _turn();
        final succeeded = runtime.diagnosticSnapshot;
        expect(succeeded.revision, writing.revision);
        expect(succeeded.delivery.deliveredEventCount, 1);
        expect(succeeded.delivery.inFlightWriteCount, 0);
        expect(runtime.diagnosticSnapshot, same(succeeded));
        _emit(runtime);
        await _turn();
        _emit(runtime);
        _emit(runtime);
        final overflow = runtime.diagnosticSnapshot;
        expect(overflow.delivery.queuedEventCount, 1);
        expect(overflow.delivery.droppedEventCount, 1);
        await runtime.dispose();
        final closed = runtime.diagnosticSnapshot;
        expect(closed.delivery.isClosed, isTrue);
        expect(closed.delivery.queuedEventCount, 0);
        expect(closed.delivery.droppedEventCount, 2);
        if (failLate) {
          sink.writes.last.completeError(StateError('late write'));
        } else {
          sink.writes.last.complete();
        }
        await _turn();
        final late = runtime.diagnosticSnapshot;
        expect(late.revision, closed.revision);
        expect(late.delivery.failedEventCount, failLate ? 1 : 0);
        expect(late.delivery.deliveredEventCount, failLate ? 1 : 2);
        expect(late.delivery.inFlightWriteCount, 0);
        expect(late, isNot(same(closed)));
        expect(runtime.diagnosticSnapshot, same(late));
        expect(idle.delivery.isClosed, isFalse);
        expect(idle.delivery.peakQueueDepth, 0);
      },
    );
  }

  test('shutdown invalidates a snapshot read after delivery closes', () async {
    final runtime = CCRouterRuntime.forTesting();
    addTearDown(runtime.dispose);
    runtime.initialize();
    await expectLater(
      runtime.pushRoute(
        const TestIntent<void>('missing', RouteArgs('private')),
      ),
      throwsA(isA<CCRouteNotFoundError>()),
    );
    CCDiagnosticSnapshot? duringCleanup;
    runtime.appScope.own(
      _OnDispose(() {
        duringCleanup = runtime.diagnosticSnapshot;
      }),
    );
    await runtime.dispose();
    final during = duringCleanup!;
    expect(during.delivery.isClosed, isTrue);
    expect(
      during.histories.singleWhere((h) => h.name == 'failures').retainedCount,
      1,
    );
    final after = runtime.diagnosticSnapshot;
    expect(after, isNot(same(during)));
    expect(after.revision, greaterThan(during.revision));
    for (final history in after.histories.where((h) => h.name != 'traces')) {
      expect(history.retainedCount, 0, reason: history.name);
      final previous = during.histories.singleWhere(
        (h) => h.name == history.name,
      );
      expect(
        history.omittedCount,
        previous.omittedCount + previous.retainedCount,
      );
    }
    expect(runtime.diagnosticSnapshot, same(after));
  });
}
