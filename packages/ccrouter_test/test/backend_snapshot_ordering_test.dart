import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'navigation_test.dart' show BackendEventNavigationAdapter;

void main() {
  for (final aggregate in [false, true]) {
    test('initial snapshot rejects stale event aggregate=$aggregate', () async {
      final child =
          BackendEventNavigationAdapter(visibilityObservationSupported: true)
            ..initialSnapshot = [
              const CCInitialBackendEntrySnapshot(
                backendEntryId: 'A',
                owner: CCBackendEntryOwner.foreign,
                navigatorOutlet: 'root',
                hostId: 'default',
                sequence: 10,
                visibilityState: CCBackendEntryVisibilityState.hidden,
              ),
              const CCInitialBackendEntrySnapshot(
                backendEntryId: 'B',
                owner: CCBackendEntryOwner.foreign,
                navigatorOutlet: 'root',
                hostId: 'default',
                sequence: 10,
                visibilityState: CCBackendEntryVisibilityState.visible,
              ),
            ];
      final CCNavigationAdapter adapter = aggregate
          ? CCMultiHostNavigationAdapter(
              defaultHostId: 'main',
              adapters: {'main': child},
            )
          : child;
      final runtime = CCRouterRuntime.forTesting(navigationAdapter: adapter)
        ..initialize();
      addTearDown(runtime.dispose);
      child.emit(
        CCNavigationBackendEventKind.topChanged,
        backendEntryId: 'A',
        sequence: 9,
      );
      final visible = runtime.activeBackendEntries.singleWhere(
        (entry) =>
            entry.visibilityState == CCBackendEntryVisibilityState.visible,
      );
      expect(visible.backendEntryId, endsWith('B'));
    });
  }
  for (final aggregate in [false, true]) {
    test(
      'snapshot import cannot overwrite a newer observed top aggregate=$aggregate',
      () {
        final child =
            BackendEventNavigationAdapter(visibilityObservationSupported: true)
              ..initialSnapshot = [
                const CCInitialBackendEntrySnapshot(
                  backendEntryId: 'A',
                  owner: CCBackendEntryOwner.foreign,
                  navigatorOutlet: 'root',
                  hostId: 'default',
                  sequence: 10,
                  visibilityState: CCBackendEntryVisibilityState.visible,
                ),
                const CCInitialBackendEntrySnapshot(
                  backendEntryId: 'B',
                  owner: CCBackendEntryOwner.foreign,
                  navigatorOutlet: 'root',
                  hostId: 'default',
                  sequence: 10,
                  visibilityState: CCBackendEntryVisibilityState.hidden,
                ),
              ];
        child.onReadInitialBackendEntries = () => child.emit(
          CCNavigationBackendEventKind.topChanged,
          backendEntryId: 'B',
          sequence: 11,
        );
        final CCNavigationAdapter adapter = aggregate
            ? CCMultiHostNavigationAdapter(
                defaultHostId: 'main',
                adapters: {'main': child},
              )
            : child;
        final runtime = CCRouterRuntime.forTesting(navigationAdapter: adapter)
          ..initialize();
        addTearDown(runtime.dispose);
        final visible = runtime.activeBackendEntries.singleWhere(
          (entry) =>
              entry.visibilityState == CCBackendEntryVisibilityState.visible,
        );
        expect(visible.backendEntryId, endsWith('B'));
      },
    );
  }
  for (final aggregate in [false, true]) {
    for (final versioned in [false, true]) {
      for (final duringRead in [false, true]) {
        test(
          'snapshot replay fallback aggregate=$aggregate versioned=$versioned duringRead=$duringRead',
          () async {
            final child =
                BackendEventNavigationAdapter(
                    visibilityObservationSupported: true,
                  )
                  ..initialSnapshot = [
                    CCInitialBackendEntrySnapshot(
                      backendEntryId: 'A',
                      owner: CCBackendEntryOwner.foreign,
                      navigatorOutlet: 'root',
                      hostId: 'default',
                      sequence: versioned ? 3 : null,
                      visibilityState: CCBackendEntryVisibilityState.visible,
                    ),
                    CCInitialBackendEntrySnapshot(
                      backendEntryId: 'B',
                      owner: CCBackendEntryOwner.foreign,
                      navigatorOutlet: 'root',
                      hostId: 'default',
                      sequence: versioned ? 10 : null,
                      visibilityState: CCBackendEntryVisibilityState.hidden,
                    ),
                    CCInitialBackendEntrySnapshot(
                      backendEntryId: 'other',
                      owner: CCBackendEntryOwner.foreign,
                      navigatorOutlet: 'other',
                      hostId: 'default',
                      sequence: versioned ? 8 : null,
                      visibilityState: CCBackendEntryVisibilityState.visible,
                    ),
                  ];
            void top(String id, int sequence, {String? operation}) =>
                child.emit(
                  CCNavigationBackendEventKind.topChanged,
                  backendEntryId: id,
                  backendOperationId: operation,
                  sequence: versioned ? sequence : null,
                );
            if (duringRead)
              child.onReadInitialBackendEntries = () {
                if (versioned) top('A', 9, operation: 'same');
                top('B', 20, operation: 'same');
              };
            final CCNavigationAdapter adapter = aggregate
                ? CCMultiHostNavigationAdapter(
                    defaultHostId: 'main',
                    adapters: {'main': child},
                  )
                : child;
            final runtime = CCRouterRuntime.forTesting(
              navigationAdapter: adapter,
            )..initialize();
            addTearDown(runtime.dispose);
            if (!duringRead) {
              if (versioned) top('A', 9, operation: 'same');
              top('B', 20, operation: 'same');
            }
            expect(runtime.desynchronizedBackendHosts, isEmpty);
            final entries = runtime.activeBackendEntries;
            expect(
              entries
                  .where(
                    (entry) =>
                        entry.navigatorOutlet == 'root' &&
                        entry.visibilityState ==
                            CCBackendEntryVisibilityState.visible,
                  )
                  .single
                  .backendEntryId,
              endsWith('B'),
            );
            expect(
              entries
                  .singleWhere((entry) => entry.navigatorOutlet == 'other')
                  .visibilityState,
              CCBackendEntryVisibilityState.visible,
            );
            expect(runtime.recentBackendNavigationEvents, hasLength(1));
            // Real post-bootstrap event loss still marks desynchronization.
            top('A', 22);
            expect(
              runtime.desynchronizedBackendHosts,
              versioned ? isNotEmpty : isEmpty,
            );
          },
        );
      }
    }

    test(
      'snapshot replay preserves removal and replace aggregate=$aggregate',
      () async {
        final child =
            BackendEventNavigationAdapter(visibilityObservationSupported: true)
              ..initialSnapshot = const [
                CCInitialBackendEntrySnapshot(
                  backendEntryId: 'A',
                  owner: CCBackendEntryOwner.foreign,
                  navigatorOutlet: 'root',
                  hostId: 'default',
                  sequence: 10,
                  visibilityState: CCBackendEntryVisibilityState.visible,
                ),
              ];
        child.onReadInitialBackendEntries = () {
          child.emit(
            CCNavigationBackendEventKind.replace,
            backendEntryId: 'B',
            previousBackendEntryId: 'A',
            sequence: 11,
          );
          child.emit(
            CCNavigationBackendEventKind.topChanged,
            backendEntryId: 'B',
            sequence: 12,
          );
          child.emit(
            CCNavigationBackendEventKind.remove,
            backendEntryId: 'B',
            sequence: 13,
          );
        };
        final CCNavigationAdapter adapter = aggregate
            ? CCMultiHostNavigationAdapter(
                defaultHostId: 'main',
                adapters: {'main': child},
              )
            : child;
        final runtime = CCRouterRuntime.forTesting(navigationAdapter: adapter)
          ..initialize();
        addTearDown(runtime.dispose);
        expect(runtime.activeBackendEntries, isEmpty);
        expect(runtime.recentBackendNavigationEvents, hasLength(3));
        expect(runtime.desynchronizedBackendHosts, isEmpty);
      },
    );
  }

  test(
    'aggregate-generated events coexist with child snapshot versions and Host replacement',
    () async {
      BackendEventNavigationAdapter child() =>
          BackendEventNavigationAdapter(visibilityObservationSupported: true)
            ..initialSnapshot = const [
              CCInitialBackendEntrySnapshot(
                backendEntryId: 'A',
                owner: CCBackendEntryOwner.foreign,
                navigatorOutlet: 'root',
                hostId: 'default',
                sequence: 100,
              ),
            ];
      final first = child();
      final aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'main',
        adapters: {'main': first, 'aux': BackendEventNavigationAdapter()},
      );
      final runtime = CCRouterRuntime.forTesting(navigationAdapter: aggregate)
        ..initialize();
      addTearDown(runtime.dispose);
      aggregate.setActiveOutlets(hostId: 'main', outlets: const ['root']);
      first.emit(
        CCNavigationBackendEventKind.topChanged,
        backendEntryId: 'A',
        sequence: 101,
      );
      expect(runtime.desynchronizedBackendHosts, isEmpty);
      first.emit(
        CCNavigationBackendEventKind.topChanged,
        backendEntryId: 'A',
        sequence: 103,
      );
      expect(runtime.desynchronizedBackendHosts, contains('main'));
      aggregate.unregisterHost('main', replacementActiveHostId: 'aux');
      final second = BackendEventNavigationAdapter(
        visibilityObservationSupported: true,
      );
      aggregate.registerHost('main', second);
      second.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'A',
        sequence: 1,
      );
      second.emit(
        CCNavigationBackendEventKind.topChanged,
        backendEntryId: 'A',
        sequence: 2,
      );
      expect(runtime.desynchronizedBackendHosts, isEmpty);
      expect(
        runtime.activeBackendEntries.single.visibilityState,
        CCBackendEntryVisibilityState.visible,
      );
    },
  );
  test(
    'snapshot child and aggregate Outlet events preserve FIFO under listener reentry',
    () async {
      final child =
          BackendEventNavigationAdapter(visibilityObservationSupported: true)
            ..initialSnapshot = const [
              CCInitialBackendEntrySnapshot(
                backendEntryId: 'A',
                owner: CCBackendEntryOwner.foreign,
                navigatorOutlet: 'root',
                hostId: 'default',
                sequence: 10,
                visibilityState: CCBackendEntryVisibilityState.visible,
              ),
              CCInitialBackendEntrySnapshot(
                backendEntryId: 'B',
                owner: CCBackendEntryOwner.foreign,
                navigatorOutlet: 'root',
                hostId: 'default',
                sequence: 10,
                visibilityState: CCBackendEntryVisibilityState.hidden,
              ),
            ];
      final aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'main',
        adapters: {'main': child},
      );
      var nested = false;
      final delivered = <CCNavigationBackendEventKind>[];
      aggregate.addBackendEventListener((event) {
        delivered.add(event.kind);
        if (!nested && event.kind == CCNavigationBackendEventKind.topChanged) {
          nested = true;
          child.emit(
            CCNavigationBackendEventKind.topChanged,
            backendEntryId: 'B',
            sequence: 13,
          );
        }
      });
      child.onReadInitialBackendEntries = () {
        expect(
          aggregate.readInitialBackendEntries,
          throwsA(isA<CCNavigationAdapterError>()),
        );
        child.emit(
          CCNavigationBackendEventKind.topChanged,
          backendEntryId: 'B',
          sequence: 11,
        );
        aggregate.setActiveOutlets(hostId: 'main', outlets: const ['root']);
        child.emit(
          CCNavigationBackendEventKind.topChanged,
          backendEntryId: 'A',
          sequence: 12,
        );
      };
      final runtime = CCRouterRuntime.forTesting(navigationAdapter: aggregate)
        ..initialize();
      addTearDown(runtime.dispose);
      expect(delivered, [
        CCNavigationBackendEventKind.topChanged,
        CCNavigationBackendEventKind.outletsChanged,
        CCNavigationBackendEventKind.topChanged,
        CCNavigationBackendEventKind.topChanged,
      ]);
      expect(
        runtime.recentBackendNavigationEvents.map((event) => event.kind),
        delivered,
      );
      expect(runtime.desynchronizedBackendHosts, isEmpty);
      expect(
        runtime.activeBackendEntries
            .singleWhere(
              (entry) =>
                  entry.visibilityState ==
                  CCBackendEntryVisibilityState.visible,
            )
            .backendEntryId,
        endsWith('B'),
      );
    },
  );
}
