import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reentrant_lifecycle_regression_test.dart' show ProbeAdapter;
import 'navigation_test.dart' show BackendEventNavigationAdapter;

final class _FailingChild extends ProbeAdapter
    implements
        CCNavigationAdapterCapabilitySource,
        CCNavigationPredictiveBackSource {
  _FailingChild(super.hostId, {super.onBind, super.onUnbind});
  @override
  CCNavigationAdapterCapabilities get capabilities =>
      const CCNavigationAdapterCapabilities(supportsPredictiveBack: true);
  @override
  void Function() addPredictiveBackListener(
    CCPredictiveBackEventListener listener,
  ) {
    throw StateError('predictive binding failed');
  }
}

final class _SnapshotAdapter extends ProbeAdapter
    implements CCNavigationBackendSnapshotSource {
  _SnapshotAdapter(super.hostId, this.onRead);
  final void Function() onRead;
  @override
  List<CCInitialBackendEntrySnapshot> readInitialBackendEntries() {
    onRead();
    return const [];
  }
}

final class _RollbackAdapter extends ProbeAdapter
    implements CCNavigationBackendSnapshotSource, CCNavigationPopGuardBinding {
  _RollbackAdapter(this.failure, this.onClear) : super('review.main');
  final Object failure;
  final void Function() onClear;
  @override
  List<CCInitialBackendEntrySnapshot> readInitialBackendEntries() =>
      throw failure;
  @override
  void bindPopGuardEvaluator(CCPopGuardEvaluator? evaluator) {
    if (evaluator == null) onClear();
  }
}

final class _Backend implements CCRouterAppBackend {
  _Backend(this.navigationAdapter, {this.onReadCatalog, this.onDispose});
  @override
  final CCNavigationAdapter navigationAdapter;
  @override
  final host = CCNavigationHost(id: 'review.main');
  final _catalog = CCFlutterRouteCatalog(const [], componentVersions: const {});
  final void Function()? onReadCatalog;
  final Future<void> Function()? onDispose;
  @override
  CCFlutterRouteCatalog get routeCatalog {
    onReadCatalog?.call();
    return _catalog;
  }

  int disposeCalls = 0;
  @override
  Future<void> dispose() async {
    disposeCalls++;
    await onDispose?.call();
  }
}

void main() {
  tearDown(CCRouterHost.shutdown);

  testWidgets(
    'managed rejection protects an Adapter attached through HostBinding',
    (tester) async {
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(components: const []),
      );
      final adapter = ProbeAdapter('review.main');
      CCRouterHostBinding.attachNavigationAdapter(adapter);
      final alias = _Backend(adapter);
      await tester.pumpWidget(
        CCRouterApp.managed(backend: alias, child: const SizedBox()),
      );
      expect(tester.takeException(), isA<CCNavigationAdapterError>());
      expect(CCRouter.isInitialized, isTrue);
      expect(adapter.disposeCalls, 0);
      expect(alias.disposeCalls, 0);
      await tester.pumpWidget(const SizedBox());
      await CCRouterHost.shutdown();
      expect(adapter.disposeCalls, 1);
      await alias.dispose();
    },
  );

  for (final stage in ['catalog', 'initialize', 'bind', 'snapshot']) {
    testWidgets('shutdown during $stage releases provisional ownership once', (
      tester,
    ) async {
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(components: const []),
      );
      late Future<void> stopping;
      void stop() => stopping = CCRouterHost.shutdown();
      final adapter = stage == 'snapshot'
          ? _SnapshotAdapter('review.main', stop)
          : ProbeAdapter(
              'review.main',
              onInitialize: stage == 'initialize' ? stop : null,
              onBind: stage == 'bind' ? stop : null,
            );
      final backend = _Backend(
        adapter,
        onReadCatalog: stage == 'catalog' ? stop : null,
      );
      await tester.pumpWidget(
        CCRouterApp.managed(backend: backend, child: const SizedBox()),
      );
      expect(
        tester.takeException(),
        stage == 'catalog'
            ? isA<CCNavigationAdapterError>()
            : isA<CCRouteCancelledError>(),
      );
      await stopping;
      expect(CCRouter.isInitialized, isFalse);
      expect(adapter.disposeCalls, 1);
      expect(backend.disposeCalls, 1);
      expect(adapter.listeners, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await CCRouterHost.shutdown();
      expect(adapter.disposeCalls, 1);
      expect(backend.disposeCalls, 1);

      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(components: const []),
      );
      final replacement = _Backend(ProbeAdapter('review.main'));
      await tester.pumpWidget(
        CCRouterApp.managed(backend: replacement, child: const SizedBox()),
      );
      expect(tester.takeException(), isNull);
      expect(CCRouter.isInitialized, isTrue);
      await tester.pumpWidget(const SizedBox());
      await CCRouterHost.shutdown();
      expect(replacement.disposeCalls, 1);
    });
  }

  test(
    'direct HostBinding reserves cleanup before synchronous shutdown',
    () async {
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(components: const []),
      );
      late Future<void> stopping;
      var backendDisposals = 0;
      final adapter = ProbeAdapter(
        'review.main',
        onInitialize: () {
          stopping = CCRouterHost.shutdown();
        },
      );
      expect(
        () => CCRouterHostBinding.attachNavigationAdapter(
          adapter,
          disposeBackend: () async {
            backendDisposals++;
          },
        ),
        throwsA(isA<CCRouteCancelledError>()),
      );
      await stopping;
      expect(adapter.disposeCalls, 1);
      expect(backendDisposals, 1);
      await CCRouterHost.shutdown();
      expect(adapter.disposeCalls, 1);
      expect(backendDisposals, 1);
    },
  );

  testWidgets(
    'shutdown from attachment rollback preserves the original failure',
    (tester) async {
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(components: const []),
      );
      Future<void>? stopping;
      final failure = StateError('initial snapshot rejected');
      final adapter = _RollbackAdapter(
        failure,
        () => stopping ??= CCRouterHost.shutdown(),
      );
      final backend = _Backend(adapter);
      await tester.pumpWidget(
        CCRouterApp.managed(backend: backend, child: const SizedBox()),
      );
      expect(tester.takeException(), same(failure));
      await stopping;
      expect(adapter.disposeCalls, 1);
      expect(backend.disposeCalls, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Adapter aliases remain protected until Backend cleanup completes',
    (tester) async {
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(components: const []),
      );
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final adapter = ProbeAdapter('review.main');
      final active = _Backend(adapter, onDispose: () => release.future);
      await tester.pumpWidget(
        CCRouterApp.managed(backend: active, child: const SizedBox()),
      );
      await tester.pumpWidget(const SizedBox());
      final stopping = CCRouterHost.shutdown();
      await tester.pump();
      expect(active.disposeCalls, 1);
      final alias = _Backend(adapter);
      await tester.pumpWidget(
        CCRouterApp.managed(backend: alias, child: const SizedBox()),
      );
      expect(tester.takeException(), isA<CCNavigationAdapterError>());
      expect(adapter.disposeCalls, 1);
      expect(alias.disposeCalls, 0);
      release.complete();
      await stopping;
      await tester.pumpWidget(const SizedBox());
      await alias.dispose();
      expect(adapter.disposeCalls, 1);
      expect(active.disposeCalls, 1);
    },
  );

  test('failed dynamic Host binding retires published Runtime ownership', () {
    final aggregate = CCMultiHostNavigationAdapter(
      defaultHostId: 'main',
      adapters: {'main': ProbeAdapter('main')},
    );
    final runtime = CCRouterRuntime.forTesting(navigationAdapter: aggregate)
      ..initialize();
    addTearDown(runtime.dispose);
    late CCNavigationHostLifetime lifetime;
    late _FailingChild child;
    child = _FailingChild(
      'aux',
      onBind: () {
        lifetime = runtime.captureNavigationHostLifetime('aux');
        for (final listener in child.listeners.toList()) {
          listener(
            CCNavigationBackendEvent(
              kind: CCNavigationBackendEventKind.push,
              timestamp: DateTime.now(),
              backendEntryId: 'foreign.aux',
              owner: CCBackendEntryOwner.foreign,
              hostId: 'aux',
              location: '/foreign',
            ),
          );
        }
      },
    );
    expect(() => aggregate.registerHost('aux', child), throwsStateError);
    expect(aggregate.registeredHostIds, {'main'});
    expect(child.disposeCalls, 1);
    expect(
      (lifetime.isActive, runtime.activeBackendEntries.length),
      (false, 0),
    );
    aggregate.registerHost('aux', BackendEventNavigationAdapter());
    final replacement = runtime.captureNavigationHostLifetime('aux');
    expect(replacement.isActive, isTrue);
    expect(lifetime.isActive, isFalse);
  });

  test(
    'failed binding detach precedes a replacement installed by unsubscribe',
    () {
      final aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'main',
        adapters: {'main': ProbeAdapter('main')},
      );
      final runtime = CCRouterRuntime.forTesting(navigationAdapter: aggregate)
        ..initialize();
      addTearDown(runtime.dispose);
      late CCNavigationHostLifetime old;
      CCNavigationHostLifetime? replacement;
      final child = _FailingChild(
        'aux',
        onBind: () {
          old = runtime.captureNavigationHostLifetime('aux');
        },
        onUnbind: () {
          aggregate.registerHost('aux', BackendEventNavigationAdapter());
          replacement = runtime.captureNavigationHostLifetime('aux');
        },
      );
      expect(() => aggregate.registerHost('aux', child), throwsStateError);
      expect(old.isActive, isFalse);
      expect(replacement!.isActive, isTrue);
      expect(aggregate.registeredHostIds, {'main', 'aux'});
      expect(child.disposeCalls, 1);
    },
  );

  test(
    'multi-Host rejects stale child events without reviving removed Entries',
    () {
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
        backendEntryId: 'foreign.stale',
        owner: CCBackendEntryOwner.foreign,
        sequence: 1,
      );
      child.emit(
        CCNavigationBackendEventKind.pop,
        backendEntryId: 'foreign.stale',
        owner: CCBackendEntryOwner.foreign,
        sequence: 2,
      );
      expect(runtime.activeBackendEntries, isEmpty);
      final observations = runtime.runtimeHealth.backendEventCount;
      child.emit(
        CCNavigationBackendEventKind.push,
        backendEntryId: 'foreign.stale',
        owner: CCBackendEntryOwner.foreign,
        sequence: 1,
      );
      expect(runtime.activeBackendEntries, isEmpty);
      expect(runtime.runtimeHealth.backendEventCount, observations);
    },
  );

  test('multi-Host preserves child sequence gaps for Runtime diagnostics', () {
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
      backendEntryId: 'foreign.first',
      owner: CCBackendEntryOwner.foreign,
      sequence: 1,
    );
    child.emit(
      CCNavigationBackendEventKind.push,
      backendEntryId: 'foreign.gap',
      owner: CCBackendEntryOwner.foreign,
      sequence: 3,
    );
    expect(runtime.desynchronizedBackendHosts, {'main'});
  });

  test(
    'child sequences coexist with aggregate events and reset on replacement',
    () {
      final child = BackendEventNavigationAdapter();
      final aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'main',
        adapters: {'main': ProbeAdapter('main'), 'aux': child},
      );
      final runtime = CCRouterRuntime.forTesting(navigationAdapter: aggregate)
        ..initialize();
      addTearDown(runtime.dispose);
      void emit(BackendEventNavigationAdapter adapter, int? sequence) =>
          adapter.emit(
            CCNavigationBackendEventKind.push,
            backendEntryId: 'foreign.$sequence',
            owner: CCBackendEntryOwner.foreign,
            sequence: sequence,
          );
      emit(child, 10);
      aggregate.setActiveOutlets(hostId: 'aux', outlets: const ['root']);
      emit(child, null);
      emit(child, 11);
      expect(runtime.desynchronizedBackendHosts, isEmpty);
      emit(child, 13);
      expect(runtime.desynchronizedBackendHosts, {'aux'});
      aggregate.unregisterHost('aux');
      expect(runtime.desynchronizedBackendHosts, isEmpty);
      final next = BackendEventNavigationAdapter();
      aggregate.registerHost('aux', next);
      emit(next, 1);
      expect(runtime.activeBackendEntries.single.hostId, 'aux');
      expect(runtime.desynchronizedBackendHosts, isEmpty);
    },
  );
}
