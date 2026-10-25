import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'navigation_test.dart' show BackendEventNavigationAdapter;
import 'reentrant_lifecycle_regression_test.dart' show ProbeAdapter;

void main() {
  test('same Host nested events preserve both backend pushes', () async {
    final child = BackendEventNavigationAdapter();
    final aggregate = CCMultiHostNavigationAdapter(
      defaultHostId: 'main',
      adapters: {'main': child},
    );
    var once = true;
    aggregate.addBackendEventListener((e) {
      if (once && e.kind == CCNavigationBackendEventKind.push) {
        once = false;
        child.emit(
          CCNavigationBackendEventKind.push,
          backendEntryId: 'B',
          owner: CCBackendEntryOwner.foreign,
          sequence: 2,
        );
      }
    });
    final runtime = CCRouterRuntime.forTesting(navigationAdapter: aggregate)
      ..initialize();
    addTearDown(runtime.dispose);
    child.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'A',
      owner: CCBackendEntryOwner.foreign,
      sequence: 1,
    );
    expect(runtime.activeBackendEntries, hasLength(2));
  });
  test('duplicate operation IDs do not create phantom sequence gaps', () {
    final child = BackendEventNavigationAdapter();
    final aggregate = CCMultiHostNavigationAdapter(
      defaultHostId: 'main',
      adapters: {'main': child},
    );
    final runtime = CCRouterRuntime.forTesting(navigationAdapter: aggregate)
      ..initialize();
    addTearDown(runtime.dispose);
    child.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'A',
      backendOperationId: 'same',
      owner: CCBackendEntryOwner.foreign,
      sequence: 1,
    );
    child.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'A',
      backendOperationId: 'same',
      owner: CCBackendEntryOwner.foreign,
      sequence: 2,
    );
    child.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'B',
      backendOperationId: 'new',
      owner: CCBackendEntryOwner.foreign,
      sequence: 3,
    );
    expect(runtime.desynchronizedBackendHosts, isEmpty);
  });
  test('aggregate Outlet callback cannot hide the preceding child push', () {
    final child = BackendEventNavigationAdapter();
    final aggregate = CCMultiHostNavigationAdapter(
      defaultHostId: 'main',
      adapters: {'main': child},
    );
    aggregate.addBackendEventListener((event) {
      if (event.kind == CCNavigationBackendEventKind.push) {
        aggregate.setActiveOutlets(hostId: 'main', outlets: const ['root']);
      }
    });
    final runtime = CCRouterRuntime.forTesting(navigationAdapter: aggregate)
      ..initialize();
    addTearDown(runtime.dispose);
    child.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'A',
      owner: CCBackendEntryOwner.foreign,
      sequence: 1,
    );
    expect(runtime.activeBackendEntries, hasLength(1));
  });
  test('control normal child pushes preserve both Entries', () {
    final child = BackendEventNavigationAdapter();
    final aggregate = CCMultiHostNavigationAdapter(
      defaultHostId: 'main',
      adapters: {'main': child},
    );
    final runtime = CCRouterRuntime.forTesting(navigationAdapter: aggregate)
      ..initialize();
    addTearDown(runtime.dispose);
    for (var i = 1; i <= 2; i++)
      child.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: '$i',
        owner: CCBackendEntryOwner.foreign,
        sequence: i,
      );
    expect(runtime.activeBackendEntries, hasLength(2));
    expect(runtime.desynchronizedBackendHosts, isEmpty);
  });
  test('control identical replay sequence does not create a gap', () {
    final child = BackendEventNavigationAdapter();
    final aggregate = CCMultiHostNavigationAdapter(
      defaultHostId: 'main',
      adapters: {'main': child},
    );
    final runtime = CCRouterRuntime.forTesting(navigationAdapter: aggregate)
      ..initialize();
    addTearDown(runtime.dispose);
    child.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'A',
      backendOperationId: 'same',
      owner: CCBackendEntryOwner.foreign,
      sequence: 1,
    );
    child.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'A',
      backendOperationId: 'same',
      owner: CCBackendEntryOwner.foreign,
      sequence: 1,
    );
    child.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'B',
      backendOperationId: 'new',
      owner: CCBackendEntryOwner.foreign,
      sequence: 2,
    );
    expect(runtime.activeBackendEntries, hasLength(2));
    expect(runtime.desynchronizedBackendHosts, isEmpty);
  });
  for (final multiHost in [false, true]) {
    for (final scenario in [
      'duplicateNewer',
      'staleOperation',
      'realGapDuplicate',
      'unsequenced',
    ]) {
      test(
        '$scenario keeps stream and operation identity independent multiHost=$multiHost',
        () {
          final child = BackendEventNavigationAdapter(
            visibilityObservationSupported: true,
          );
          final CCNavigationAdapter adapter = multiHost
              ? CCMultiHostNavigationAdapter(
                  defaultHostId: 'main',
                  adapters: {'main': child},
                )
              : child;
          final runtime = CCRouterRuntime.forTesting(navigationAdapter: adapter)
            ..initialize();
          addTearDown(runtime.dispose);
          void emit(
            String entry,
            String operation,
            int? sequence, [
            CCNavigationBackendEventKind kind =
                CCNavigationBackendEventKind.push,
          ]) {
            child.emit(
              kind,
              backendEntryId: entry,
              backendOperationId: operation,
              sequence: sequence,
              owner: CCBackendEntryOwner.foreign,
            );
          }

          switch (scenario) {
            case 'duplicateNewer':
              emit('A', 'X', 1);
              emit('A', 'X', 2);
              emit('B', 'Y', 3);
              expect(runtime.activeBackendEntries, hasLength(2));
              expect(runtime.recentBackendNavigationEvents, hasLength(2));
              expect(runtime.desynchronizedBackendHosts, isEmpty);
            case 'staleOperation':
              emit('A', 'X', 2);
              emit('stale', 'Y', 1);
              emit('B', 'Y', 3);
              expect(runtime.activeBackendEntries, hasLength(2));
              expect(
                runtime.activeBackendEntries.any(
                  (entry) => entry.backendEntryId.contains('stale'),
                ),
                isFalse,
              );
              expect(runtime.desynchronizedBackendHosts, isEmpty);
            case 'realGapDuplicate':
              emit('A', 'X', 1);
              emit('A', 'top', 2, CCNavigationBackendEventKind.topChanged);
              expect(
                runtime.activeBackendEntries.single.visibilityState,
                CCBackendEntryVisibilityState.visible,
              );
              final cached = runtime.runtimeHealth;
              expect(cached.desynchronizedBackendHostCount, 0);
              emit('A', 'X', 4);
              expect(runtime.recentBackendNavigationEvents, hasLength(2));
              expect(runtime.runtimeHealth.desynchronizedBackendHostCount, 1);
              expect(
                runtime.activeBackendEntries.single.visibilityState,
                CCBackendEntryVisibilityState.unknown,
              );
            case 'unsequenced':
              emit('A', 'X', null);
              emit('A', 'X', null);
              emit('B', 'Y', 1);
              expect(runtime.activeBackendEntries, hasLength(2));
              expect(runtime.desynchronizedBackendHosts, isEmpty);
          }
        },
      );
    }
  }

  test('duplicate child operation advances past aggregate Outlet sequence', () {
    final child = BackendEventNavigationAdapter();
    final aggregate = CCMultiHostNavigationAdapter(
      defaultHostId: 'main',
      adapters: {'main': child},
    );
    final runtime = CCRouterRuntime.forTesting(navigationAdapter: aggregate)
      ..initialize();
    addTearDown(runtime.dispose);
    child.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'A',
      backendOperationId: 'X',
      sequence: 1,
    );
    child.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'A',
      backendOperationId: 'X',
      sequence: 2,
    );
    aggregate.setActiveOutlets(hostId: 'main', outlets: ['root']);
    child.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'B',
      backendOperationId: 'Y',
      sequence: 3,
    );
    expect(runtime.activeBackendEntries, hasLength(2));
    expect(runtime.desynchronizedBackendHosts, isEmpty);
  });

  for (final terminal in ['unsubscribe', 'dispose', 'detach']) {
    test('queued nested events respect $terminal', () {
      final child = BackendEventNavigationAdapter();
      final aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'main',
        adapters: {'main': child, 'aux': BackendEventNavigationAdapter()},
      )..initialize(const []);
      addTearDown(aggregate.dispose);
      final received = <String>[];
      var once = true;
      late void Function() remove;
      aggregate.addBackendEventListener((event) {
        if (!once || event.kind != CCNavigationBackendEventKind.push) return;
        once = false;
        child.emit(
          CCNavigationBackendEventKind.push,
          backendEntryId: 'B',
          sequence: 2,
        );
        switch (terminal) {
          case 'unsubscribe':
            remove();
          case 'dispose':
            aggregate.dispose();
          case 'detach':
            aggregate.unregisterHost('main', replacementActiveHostId: 'aux');
        }
      });
      remove = aggregate.addBackendEventListener((event) {
        if (event.kind == CCNavigationBackendEventKind.push)
          received.add(event.backendEntryId!);
      });
      child.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'A',
        sequence: 1,
      );
      expect(received, isEmpty);
    });
  }

  test('FIFO preserves listener snapshots and both event orderings', () {
    final child = BackendEventNavigationAdapter();
    final aggregate = CCMultiHostNavigationAdapter(
      defaultHostId: 'main',
      adapters: {'main': child},
    )..initialize(const []);
    addTearDown(aggregate.dispose);
    final order = <String>[];
    var once = true;
    aggregate.addBackendEventListener((event) {
      order.add('first:${event.sequence}');
      if (!once) return;
      once = false;
      child.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'B',
        sequence: 2,
      );
      aggregate.addBackendEventListener(
        (event) => order.add('late:${event.sequence}'),
      );
    });
    aggregate.addBackendEventListener(
      (event) => order.add('second:${event.sequence}'),
    );
    child.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'A',
      sequence: 1,
    );
    expect(order, ['first:1', 'second:1', 'first:2', 'second:2']);
  });
  for (final replaceInCleanup in [false, true]) {
    test(
      'cross-Host nested detach keeps replacement events replaceInCleanup=$replaceInCleanup',
      () {
        late CCMultiHostNavigationAdapter aggregate;
        final main = ProbeAdapter('main');
        final replacement = ProbeAdapter('aux');
        void emit(ProbeAdapter adapter, String id) {
          for (final listener in adapter.listeners.toList()) {
            listener(
              CCNavigationBackendEvent(
                kind: CCNavigationBackendEventKind.push,
                timestamp: DateTime.now(),
                backendEntryId: id,
                hostId: adapter.hostId,
                owner: CCBackendEntryOwner.foreign,
                sequence: 1,
              ),
            );
          }
        }

        void replace() {
          aggregate.registerHost('aux', replacement);
          emit(replacement, 'replacement');
        }

        final old = ProbeAdapter(
          'aux',
          onUnbind: replaceInCleanup ? replace : null,
        );
        aggregate = CCMultiHostNavigationAdapter(
          defaultHostId: 'main',
          adapters: {'main': main, 'aux': old},
        );
        var once = true;
        aggregate.addBackendEventListener((event) {
          if (!once ||
              event.kind != CCNavigationBackendEventKind.push ||
              event.hostId != 'main')
            return;
          once = false;
          emit(old, 'queued-retired');
          aggregate.unregisterHost('aux');
          if (!replaceInCleanup) replace();
        });
        final runtime = CCRouterRuntime.forTesting(navigationAdapter: aggregate)
          ..initialize();
        addTearDown(runtime.dispose);
        emit(main, 'live');
        expect(runtime.activeBackendEntries, hasLength(2));
        expect(runtime.activeBackendEntries.map((entry) => entry.hostId), [
          'main',
          'aux',
        ]);
        expect(
          runtime.activeBackendEntries.last.backendEntryId,
          endsWith('-entry-replacement'),
        );
        expect(runtime.desynchronizedBackendHosts, isEmpty);
        expect(old.disposeCalls, 1);
        expect(replacement.disposeCalls, 0);
        expect(
          runtime.recentBackendNavigationEvents.map((event) => event.kind),
          [
            CCNavigationBackendEventKind.hostDetached,
            CCNavigationBackendEventKind.push,
            CCNavigationBackendEventKind.push,
          ],
        );
      },
    );
  }
}
