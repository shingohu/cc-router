import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'navigation_test.dart' show BackendEventNavigationAdapter;

void main() {
  for (final reenter in [false, true]) {
    test(
      'terminal backpressure reserves FIFO capacity reenter=$reenter',
      () async {
        final adapter = BackendEventNavigationAdapter();
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: adapter,
          navigationDiagnosticCapacity: 0,
        )..initialize();
        addTearDown(runtime.dispose);
        final capacity = runtime.runtimeHealth.observerQueueCapacity;
        final observed = <String>[];
        var nested = false;
        int? nestedDepth;
        void emit(String id) => adapter.emit(
          CCNavigationBackendEventKind.pop,
          backendOperationId: id,
        );
        runtime.addBackendNavigationListener((event) {
          observed.add(event.backendOperationId!);
          if (reenter && !nested) {
            nested = true;
            emit('nested');
            nestedDepth = runtime.runtimeHealth.observerQueueDepth;
          }
        });
        for (var i = 0; i <= capacity; i++) {
          emit('$i');
        }
        expect(
          runtime.runtimeHealth.observerQueueDepth,
          lessThanOrEqualTo(capacity),
        );
        if (reenter) expect(nestedDepth, lessThanOrEqualTo(capacity));
        await Future<void>.delayed(Duration.zero);
        expect(observed, [
          for (var i = 0; i <= capacity; i++) '$i',
          if (reenter) 'nested',
        ]);
        expect(runtime.runtimeHealth.observerQueueDepth, 0);
      },
    );
  }

  test(
    'backpressure preserves FIFO for every listener during nested fan-out',
    () async {
      final adapter = BackendEventNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        navigationDiagnosticCapacity: 0,
      )..initialize();
      addTearDown(runtime.dispose);
      final capacity = runtime.runtimeHealth.observerQueueCapacity;
      final first = <String>[];
      final second = <String>[];
      var nested = false;
      void emit(String id) => adapter.emit(
        CCNavigationBackendEventKind.pop,
        backendOperationId: id,
      );
      runtime.addBackendNavigationListener((event) {
        first.add(event.backendOperationId!);
        if (!nested) {
          nested = true;
          emit('nested');
        }
      });
      runtime.addBackendNavigationListener((event) {
        second.add(event.backendOperationId!);
      });
      for (var i = 0; i <= capacity; i++) {
        emit('$i');
      }
      await Future<void>.delayed(Duration.zero);
      final expected = [for (var i = 0; i <= capacity; i++) '$i', 'nested'];
      expect(first, expected);
      expect(second, expected);
      expect(runtime.runtimeHealth.observerQueueDepth, 0);
    },
  );

  for (final terminal in ['unsubscribe', 'shutdown', 'throw']) {
    test('nested drain pressure completes once with $terminal', () async {
      final adapter = BackendEventNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        navigationDiagnosticCapacity: 0,
      )..initialize();
      addTearDown(runtime.dispose);
      final capacity = runtime.runtimeHealth.observerQueueCapacity;
      final first = <String>[];
      final second = <String>[];
      Future<void>? shutdown;
      var nested = false;
      void emit(String id) => adapter.emit(
        CCNavigationBackendEventKind.pop,
        backendOperationId: id,
      );
      late void Function() removeSecond;
      runtime.addBackendNavigationListener((event) {
        first.add(event.backendOperationId!);
        if (!nested) {
          nested = true;
          for (var i = 0; i <= capacity; i++) {
            emit('nested-$i');
          }
          switch (terminal) {
            case 'unsubscribe':
              removeSecond();
            case 'shutdown':
              shutdown = runtime.dispose();
            case 'throw':
              throw StateError('isolated observer failure');
          }
        }
      });
      removeSecond = runtime.addBackendNavigationListener((event) {
        second.add(event.backendOperationId!);
      });
      for (var i = 0; i < capacity; i++) {
        emit('$i');
      }
      // The first event-loop drain is active while nested events overflow.
      await Future<void>.delayed(Duration.zero);
      await shutdown;
      await Future<void>.delayed(Duration.zero);
      final expected = [
        for (var i = 0; i < capacity; i++) '$i',
        for (var i = 0; i <= capacity; i++) 'nested-$i',
      ];
      expect(first, expected);
      expect(
        second,
        terminal == 'unsubscribe'
            ? expected.take(capacity + 1).toList()
            : expected,
      );
      expect(runtime.runtimeHealth.observerQueueDepth, 0);
      expect(first.toSet(), hasLength(first.length));
    });
  }

  test(
    'repeated backpressure invalidates health before synchronous delivery',
    () async {
      final adapter = BackendEventNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        navigationDiagnosticCapacity: 0,
      )..initialize();
      addTearDown(runtime.dispose);
      final capacity = runtime.runtimeHealth.observerQueueCapacity;
      CCRuntimeHealthSnapshot? before, during;
      runtime.addBackendNavigationListener((_) {
        // The incoming terminal event must already own its queue slot, keeping
        // health and FIFO stable throughout a synchronous callback.
        during = runtime.runtimeHealth;
      });
      for (var i = 0; i < capacity + 2; i++) {
        before = runtime.runtimeHealth;
        adapter.emit(
          CCNavigationBackendEventKind.pop,
          backendOperationId: '$i',
        );
      }
      expect(before!.observerQueueDepth, capacity);
      expect(during!.observerQueueDepth, capacity);
      expect(runtime.runtimeHealth.observerQueueDepth, capacity);
      await runtime.dispose();
      expect(runtime.runtimeHealth.observerQueueDepth, 0);
    },
  );
}
