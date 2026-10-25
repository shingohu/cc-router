import 'dart:async';

import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'navigation_test.dart'
    show
        TestIntent,
        RouteArgs,
        RouteArgsCodec,
        BackendEventNavigationAdapter,
        TestNavigationInterceptor,
        UnidentifiedManagedPopAdapter;

import 'navigation_failure_cleanup_test.dart' show Release, runtimeFor;
import 'reentrant_lifecycle_regression_test.dart'
    show Intent, Resource, ProbeAdapter;

final class _HealthCapabilitiesAdapter extends ProbeAdapter
    implements CCNavigationAdapterCapabilitySource {
  _HealthCapabilitiesAdapter() : super('primary');
  void Function()? onCapabilities;
  @override
  CCNavigationAdapterCapabilities get capabilities {
    onCapabilities?.call();
    return const CCNavigationAdapterCapabilities();
  }

  void emit(CCNavigationBackendEventKind kind) {
    final event = CCNavigationBackendEvent(
      kind: kind,
      timestamp: DateTime.now(),
      backendEntryId: 'entry',
      hostId: 'primary',
      navigatorOutlet: 'root',
      owner: CCBackendEntryOwner.foreign,
    );
    for (final listener in listeners.toList()) {
      listener(event);
    }
  }
}

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
    'release callback invalidates a health snapshot captured during Adapter acceptance',
    () async {
      final adapter = Release();
      final runtime = runtimeFor(adapter, Resource());
      addTearDown(runtime.dispose);
      await runtime.resetRoute(const Intent());
      CCRuntimeHealthSnapshot? before, observed;
      var actual = -1;
      adapter.onDispatch = () {
        before = runtime.runtimeHealth;
      };
      adapter.onRelease = () {
        observed = runtime.runtimeHealth;
        actual = runtime.activeRouteEntries.length;
      };
      await runtime.resetRoute(const Intent());
      expect(before!.activeRouteEntryCount, 1);
      expect(observed!.activeRouteEntryCount, actual);
      expect(observed, isNot(same(before)));
    },
  );

  test(
    'backend reconciliation invalidates health before capability callbacks',
    () async {
      final adapter = _HealthCapabilitiesAdapter();
      final runtime = CCRouterRuntime.forTesting(navigationAdapter: adapter)
        ..initialize();
      addTearDown(runtime.dispose);
      adapter.emit(CCNavigationBackendEventKind.push);
      final before = runtime.runtimeHealth;
      CCRuntimeHealthSnapshot? observed;
      var actual = -1;
      adapter.onCapabilities = () {
        observed = runtime.runtimeHealth;
        actual = runtime.activeBackendEntries.length;
      };
      adapter.emit(CCNavigationBackendEventKind.remove);
      expect(before.activeBackendEntryCount, 1);
      expect(observed!.activeBackendEntryCount, actual);
      expect(observed, isNot(same(before)));
    },
  );

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

  test(
    'runtime health exposes live ownership counts without mutation handles',
    () async {
      final adapter = BackendEventNavigationAdapter();
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        navigationDiagnosticCapacity: 4,
      );
      addTearDown(runtime.dispose);
      runtime.registerRoute<RouteArgs, void>(
        CCRouteDefinition(
          routeId: 'fixture.detail',
          patterns: const [CCPathPattern('/detail/:value', primary: true)],
          codec: const RouteArgsCodec(),
        ),
      );
      runtime.initialize();

      final initial = runtime.runtimeHealth;
      expect(initial.activeRouteEntryCount, 0);
      expect(initial.pendingNavigationCount, 0);
      expect(initial.inFlightNavigationCount, 0);
      expect(initial.observerQueueDepth, 0);
      expect(initial.observerQueueCapacity, greaterThanOrEqualTo(4));

      await runtime.goRoute(
        TestIntent<void>('fixture.detail', const RouteArgs('health')),
      );
      final afterPush = runtime.runtimeHealth;
      expect(afterPush.activeRouteEntryCount, 1);
      expect(afterPush.trackedNavigationHostCount, 1);
      expect(afterPush.routeEntryTransitionCount, greaterThan(0));
      expect(afterPush.navigationEventCount, greaterThan(0));
      expect(afterPush.backendEntryCount, 0);

      adapter.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'foreign.health',
        owner: CCBackendEntryOwner.foreign,
      );
      final afterForeign = runtime.runtimeHealth;
      expect(afterForeign, isNot(same(afterPush)));
      expect(afterForeign.backendEntryCount, 1);
      expect(afterForeign.activeBackendEntryCount, 1);
      expect(afterForeign.unattributedBackendEventCount, 1);
    },
  );

  test(
    'attaching an adapter invalidates health after initial ledger import',
    () {
      final runtime = CCRouterRuntime.forTesting();
      addTearDown(runtime.dispose);
      runtime.initialize();
      final beforeAttach = runtime.runtimeHealth;

      final adapter = BackendEventNavigationAdapter()
        ..initialSnapshot = const [
          CCInitialBackendEntrySnapshot(
            backendEntryId: 'foreign.initial',
            owner: CCBackendEntryOwner.foreign,
            navigatorOutlet: 'root',
          ),
        ];
      runtime.attachNavigationAdapter(adapter);

      final afterAttach = runtime.runtimeHealth;
      expect(afterAttach, isNot(same(beforeAttach)));
      expect(afterAttach.backendEntryCount, 1);
      expect(afterAttach.activeBackendEntryCount, 1);
    },
  );

  test(
    'attachment rollback invalidates health with buffered initial reports',
    () async {
      final runtime = CCRouterRuntime.forTesting()..initialize();
      addTearDown(runtime.dispose);
      final adapter = BackendEventNavigationAdapter();
      addTearDown(adapter.dispose);
      final failure = StateError('initial import failed');
      late CCDiagnosticSnapshot duringAttachment;
      adapter.onReadInitialBackendEntries = () {
        adapter.emit(
          CCNavigationBackendEventKind.push,
          backendEntryId: 'foreign.rejected',
          owner: CCBackendEntryOwner.foreign,
        );
        duringAttachment = runtime.diagnosticSnapshot;
        // Read-time observations remain provisional until snapshot import.
        expect(duringAttachment.runtimeHealth!.backendEntryCount, 0);
        expect(runtime.recentBackendNavigationEvents, isEmpty);
        throw failure;
      };

      expect(
        () => runtime.attachNavigationAdapter(adapter),
        throwsA(same(failure)),
      );
      expect(adapter.listeners, isEmpty);
      expect(runtime.backendEntries, isEmpty);
      await _turn();
      final after = runtime.diagnosticSnapshot;
      expect(after.runtimeHealth!.backendEntryCount, 0);
      expect(after.runtimeHealth!.activeBackendEntryCount, 0);
      expect(after.revision, greaterThan(duringAttachment.revision));
      expect(runtime.diagnosticSnapshot, same(after));

      runtime.attachNavigationAdapter(BackendEventNavigationAdapter());
      expect(runtime.runtimeHealth.backendEntryCount, 0);
    },
  );

  test('Host health counts captured lifetimes and retires detached Hosts', () {
    final adapter = CCMultiHostNavigationAdapter(
      defaultHostId: 'main',
      adapters: {
        'main': CCMemoryNavigationAdapter(),
        'secondary': CCMemoryNavigationAdapter(),
      },
    );
    final runtime = CCRouterRuntime.forTesting(navigationAdapter: adapter)
      ..initialize();
    addTearDown(runtime.dispose);
    expect(adapter.registeredHostIds, hasLength(2));
    final initial = runtime.runtimeHealth;
    expect(initial.trackedNavigationHostCount, 0);
    final main = runtime.captureNavigationHostLifetime('main');
    expect(runtime.runtimeHealth.trackedNavigationHostCount, 1);
    final secondary = runtime.captureNavigationHostLifetime('secondary');
    expect(runtime.runtimeHealth.trackedNavigationHostCount, 2);
    adapter.unregisterHost('secondary');
    expect(secondary.isActive, isFalse);
    expect(main.isActive, isTrue);
    expect(runtime.runtimeHealth.trackedNavigationHostCount, 1);
  });

  test(
    'Aspect-only enqueue invalidates health before the next drain',
    () async {
      final release = Completer<CCNavigationInterceptorDecision>();
      var found = 0;
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: CCMemoryNavigationAdapter(),
        navigationConcurrencyPolicy: CCNavigationConcurrencyPolicy.allow,
        navigationAspects: [
          CCNavigationAspect(id: 'health', onFound: (_) => found++),
        ],
        globalInterceptors: [
          CCGlobalNavigationInterceptor(
            id: 'wait',
            interceptor: TestNavigationInterceptor(
              'wait',
              (_) => release.future,
              [],
            ),
          ),
        ],
      );
      addTearDown(runtime.dispose);
      runtime.registerRoute<RouteArgs, void>(
        CCRouteDefinition(
          routeId: 'fixture.detail',
          patterns: const [CCPathPattern('/detail/:value', primary: true)],
          codec: const RouteArgsCodec(),
        ),
      );
      runtime.initialize();
      runtime.captureNavigationHostLifetime('default');
      final before = runtime.diagnosticSnapshot;
      expect(before.runtimeHealth!.observerQueueDepth, 0);

      final navigation = runtime.goRoute(
        const TestIntent<void>('fixture.detail', RouteArgs('health')),
      );
      final queued = runtime.diagnosticSnapshot;
      await _turn();
      final drained = runtime.diagnosticSnapshot;
      release.complete(const CCNavigationProceed());
      await navigation;

      expect(queued.runtimeHealth!.observerQueueDepth, 1);
      expect(queued.revision, greaterThan(before.revision));
      expect(found, 1);
      expect(drained.runtimeHealth!.observerQueueDepth, 0);
      expect(drained.revision, greaterThan(queued.revision));
    },
  );

  test(
    'uncorrelated managed Pop invalidates health only for a new desync',
    () async {
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: UnidentifiedManagedPopAdapter(),
      );
      addTearDown(runtime.dispose);
      runtime.registerRoute<RouteArgs, void>(
        CCRouteDefinition(
          routeId: 'fixture.detail',
          patterns: const [CCPathPattern('/detail/:value', primary: true)],
          codec: const RouteArgsCodec(),
        ),
      );
      runtime.initialize();
      await runtime.goRoute(
        const TestIntent<void>('fixture.detail', RouteArgs('health')),
      );
      await _turn();
      final before = runtime.diagnosticSnapshot;
      expect(before.runtimeHealth!.desynchronizedBackendHostCount, 0);

      final outcome = await runtime.maybePopOutcomeRoute();

      expect(outcome.removedBackendEntryId, isNull);
      expect(runtime.activeRouteEntries, hasLength(1));
      expect(runtime.desynchronizedBackendHosts, {'window.main'});
      final after = runtime.diagnosticSnapshot;
      expect(after, isNot(same(before)));
      expect(after.revision, greaterThan(before.revision));
      expect(after.runtimeHealth!.desynchronizedBackendHostCount, 1);
      expect(runtime.runtimeHealth, same(after.runtimeHealth));

      await runtime.maybePopOutcomeRoute();
      expect(runtime.diagnosticSnapshot, same(after));
      expect(runtime.activeRouteEntries, hasLength(1));
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
