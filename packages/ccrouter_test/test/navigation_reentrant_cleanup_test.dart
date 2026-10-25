import 'dart:async';

import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reentrant_lifecycle_regression_test.dart'
    show ProbeAdapter, Intent, Registrar, Resource;

class _ReusableAdapter extends ProbeAdapter {
  _ReusableAdapter(super.hostId, {super.onUnbind});
  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) {}
}

final class _ExitAdapter extends ProbeAdapter
    implements CCNavigationRouteExitBinding {
  _ExitAdapter(this.onExit, {String hostId = 'primary'}) : super(hostId);
  final void Function() onExit;
  final exits = <void Function()>[];
  int removals = 0;
  bool completeSynchronously = false;
  void Function()? onRemove;
  @override
  void Function()? addRouteExitListener({
    required String navigationId,
    required String hostId,
    required void Function() onExited,
  }) {
    exits.add(onExited);
    if (completeSynchronously) onExited();
    onExit();
    return () {
      exits.remove(onExited);
      removals++;
      onRemove?.call();
    };
  }
}

final class _ReleaseAdapter extends ProbeAdapter
    implements CCNavigationManagedEntryReleaseSink {
  _ReleaseAdapter(this.onRelease) : super('primary');
  final void Function() onRelease;
  @override
  void releaseManagedNavigation(String navigationId) => onRelease();
}

final class _HeldResource extends Resource {
  final released = Completer<void>();
  @override
  Future<void> dispose() {
    super.dispose();
    return released.future;
  }
}

final class _CleanupAdapter extends _ReusableAdapter
    implements CCNavigationPopGuardBinding {
  _CleanupAdapter(super.hostId, {super.onUnbind});
  void Function()? onClear;
  void Function()? onDispose;
  @override
  void bindPopGuardEvaluator(CCPopGuardEvaluator? evaluator) {
    if (evaluator == null) onClear?.call();
  }

  @override
  void dispose() {
    super.dispose();
    onDispose?.call();
  }
}

final class _UnboundCleanupAdapter
    implements
        CCNavigationAdapter,
        CCNavigationBackendEventSource,
        CCNavigationPopGuardBinding {
  _UnboundCleanupAdapter({void Function()? onUnbind})
    : delegate = _CleanupAdapter('aux', onUnbind: onUnbind);
  final _CleanupAdapter delegate;
  int get disposeCalls => delegate.disposeCalls;
  Set<CCNavigationBackendEventListener> get listeners => delegate.listeners;
  set onClear(void Function()? callback) => delegate.onClear = callback;
  set onDispose(void Function()? callback) => delegate.onDispose = callback;
  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) {}
  @override
  Future<Object?> navigate(CCNavigationRequest request) =>
      delegate.navigate(request);
  @override
  Future<bool> maybePop({Object? result}) => delegate.maybePop(result: result);
  @override
  void pop({Object? result}) => delegate.pop(result: result);
  @override
  bool canPop() => delegate.canPop();
  @override
  void dispose() => delegate.dispose();
  @override
  void Function() addBackendEventListener(
    CCNavigationBackendEventListener listener,
  ) => delegate.addBackendEventListener(listener);
  @override
  void bindPopGuardEvaluator(CCPopGuardEvaluator? evaluator) =>
      delegate.bindPopGuardEvaluator(evaluator);
}

final class _PredictiveAdapter extends _ReusableAdapter
    implements
        CCNavigationAdapterCapabilitySource,
        CCNavigationPredictiveBackSource {
  _PredictiveAdapter(super.hostId);
  final predictive = <CCPredictiveBackEventListener>{};
  @override
  CCNavigationAdapterCapabilities get capabilities =>
      const CCNavigationAdapterCapabilities(supportsPredictiveBack: true);
  @override
  void Function() addPredictiveBackListener(
    CCPredictiveBackEventListener listener,
  ) {
    predictive.add(listener);
    return () => predictive.remove(listener);
  }

  void emitPredictive() {
    for (final listener in predictive.toList()) {
      listener(
        CCPredictiveBackEvent(
          phase: CCPredictiveBackPhase.committed,
          timestamp: DateTime.now(),
        ),
      );
    }
  }
}

CCRouterRuntime _runtimeWithResource(
  CCNavigationAdapter adapter,
  Resource resource, {
  void Function()? onScopeCancelled,
}) => CCRouterRuntime.forTesting(
  navigationAdapter: adapter,
  components: [
    CCComponentManifest(
      id: 'probe',
      version: '1.0.0',
      registrar: Registrar(
        extra: (registry) {
          registry.registerService<Resource>(
            CCServiceProvider(
              scope: CCServiceScope.route,
              factory: (context) {
                if (onScopeCancelled != null)
                  context.cancellation.addListener(onScopeCancelled);
                return resource;
              },
            ),
          );
        },
      ),
    ),
  ],
)..initialize();

void _emitPush(ProbeAdapter adapter, String id) {
  for (final listener in adapter.listeners.toList()) {
    listener(
      CCNavigationBackendEvent(
        kind: CCNavigationBackendEventKind.push,
        timestamp: DateTime.now(),
        hostId: adapter.hostId,
        backendEntryId: id,
        owner: CCBackendEntryOwner.foreign,
        sequence: 1,
      ),
    );
  }
}

void main() {
  test('retired child event cannot resume fanout after detach', () async {
    final old = ProbeAdapter('aux');
    final aggregate = CCMultiHostNavigationAdapter(
      defaultHostId: 'primary',
      adapters: {'primary': ProbeAdapter('primary'), 'aux': old},
    );
    var armed = true;
    aggregate.addBackendEventListener((event) {
      if (!armed || event.kind != CCNavigationBackendEventKind.push) return;
      armed = false;
      aggregate.unregisterHost('aux');
      aggregate.registerHost('aux', ProbeAdapter('aux'));
    });
    final runtime = CCRouterRuntime.forTesting(navigationAdapter: aggregate)
      ..initialize();
    addTearDown(runtime.dispose);
    for (final listener in old.listeners.toList()) {
      listener(
        CCNavigationBackendEvent(
          kind: CCNavigationBackendEventKind.push,
          timestamp: DateTime.now(),
          hostId: 'aux',
          backendEntryId: 'retired.foreign',
          owner: CCBackendEntryOwner.foreign,
          sequence: 1,
        ),
      );
    }
    expect(
      runtime.activeBackendEntries,
      isEmpty,
      reason:
          'the push belongs to the retired registration, not the replacement',
    );
  });

  test('unsubscribe cannot transfer still-owned Adapter to replacement', () {
    late CCMultiHostNavigationAdapter aggregate;
    late ProbeAdapter old;
    Object? rejected;
    var once = true;
    old = _ReusableAdapter(
      'aux',
      onUnbind: () {
        if (!once) return;
        once = false;
        try {
          aggregate.registerHost('aux', old);
        } catch (error) {
          rejected = error;
        }
      },
    );
    aggregate = CCMultiHostNavigationAdapter(
      defaultHostId: 'primary',
      adapters: {'primary': ProbeAdapter('primary'), 'aux': old},
    )..initialize(const []);
    addTearDown(aggregate.dispose);
    aggregate.unregisterHost('aux');
    expect(rejected, isA<CCNavigationAdapterError>());
    expect(aggregate.registeredHostIds, {'primary'});
    expect(old.disposeCalls, 1);
  });

  test(
    'shutdown during exit subscription cannot leave route Scope alive',
    () async {
      late CCRouterRuntime runtime;
      Future<void>? shutdown;
      var armed = false;
      final adapter = _ExitAdapter(() {
        if (armed) shutdown = runtime.dispose();
      });
      final resource = Resource();
      runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          CCComponentManifest(
            id: 'probe',
            version: '1.0.0',
            registrar: Registrar(
              extra: (registry) {
                registry.registerService<Resource>(
                  CCServiceProvider(
                    scope: CCServiceScope.route,
                    factory: (_) => resource,
                  ),
                );
              },
            ),
          ),
        ],
      )..initialize();
      addTearDown(() async {
        for (final exit in adapter.exits.toList()) {
          exit();
        }
        await runtime.dispose();
      });
      await runtime.goRoute(const Intent());
      runtime.serviceForRoute<Resource>(
        navigationId: runtime.activeRouteEntries.single.navigationId,
      );
      armed = true;
      try {
        await runtime.goRoute(const Intent());
      } catch (_) {}
      await shutdown;
      expect(
        resource.disposeCalls,
        1,
        reason:
            'shutdown must close a removed Route even if exit subscription reenters shutdown',
      );
      expect(adapter.exits, isEmpty);
    },
  );
  for (final phase in ['unbind', 'clearGuard', 'dispose']) {
    for (final fails in [false, true]) {
      for (final destination in ['aux', 'other']) {
        test('Adapter stays owned during $phase ($fails, $destination)', () {
          late CCMultiHostNavigationAdapter aggregate;
          late _UnboundCleanupAdapter old;
          Object? rejected;
          var once = true;
          final failure = StateError('cleanup failed');
          void attemptReuse() {
            if (!once) return;
            once = false;
            try {
              aggregate.registerHost(destination, old);
            } catch (error) {
              rejected = error;
            }
            if (fails) throw failure;
          }

          old = _UnboundCleanupAdapter(
            onUnbind: phase == 'unbind' ? attemptReuse : null,
          );
          aggregate = CCMultiHostNavigationAdapter(
            defaultHostId: 'primary',
            adapters: {'primary': ProbeAdapter('primary'), 'aux': old},
          )..initialize(const []);
          addTearDown(aggregate.dispose);
          if (phase == 'clearGuard') old.onClear = attemptReuse;
          if (phase == 'dispose') old.onDispose = attemptReuse;
          if (fails) {
            expect(
              () => aggregate.unregisterHost('aux'),
              throwsA(same(failure)),
            );
          } else {
            aggregate.unregisterHost('aux');
          }
          expect(rejected, isA<CCNavigationAdapterError>());
          expect(old.disposeCalls, 1);
          expect(old.listeners, isEmpty);
          expect(aggregate.registeredHostIds, {'primary'});
          final fresh = ProbeAdapter('aux');
          aggregate.registerHost('aux', fresh);
          expect(fresh.disposeCalls, 0);
          aggregate.dispose();
          expect(fresh.disposeCalls, 1);
          expect(old.disposeCalls, 1);
        });
      }
    }
  }

  for (final source in ['backend', 'predictive', 'outlets']) {
    for (final retirement in ['detach', 'replace', 'dispose']) {
      test('$source fanout stops at reentrant $retirement', () {
        final old = _PredictiveAdapter('aux');
        final aggregate = CCMultiHostNavigationAdapter(
          defaultHostId: 'primary',
          adapters: {'primary': ProbeAdapter('primary'), 'aux': old},
        )..initialize(const []);
        addTearDown(aggregate.dispose);
        var armed = true;
        var deliveries = 0;
        void retire() {
          if (!armed) return;
          armed = false;
          if (retirement == 'dispose') {
            aggregate.dispose();
            return;
          }
          aggregate.unregisterHost('aux');
          if (retirement == 'replace')
            aggregate.registerHost('aux', _PredictiveAdapter('aux'));
        }

        if (source == 'predictive') {
          aggregate.addPredictiveBackListener((_) => retire());
          aggregate.addPredictiveBackListener((_) => deliveries++);
          old.emitPredictive();
        } else {
          final kind = source == 'backend'
              ? CCNavigationBackendEventKind.push
              : CCNavigationBackendEventKind.outletsChanged;
          aggregate.addBackendEventListener((event) {
            if (event.kind == kind) retire();
          });
          aggregate.addBackendEventListener((event) {
            if (event.kind == kind) deliveries++;
          });
          if (source == 'backend')
            _emitPush(old, 'retired');
          else
            aggregate.setActiveOutlets(hostId: 'aux', outlets: const ['root']);
        }
        expect(deliveries, 0);
        expect(old.disposeCalls, 1);
      });
    }
  }

  test(
    'replacement event sequence is accepted after stale fanout is stopped',
    () async {
      final old = ProbeAdapter('aux');
      final replacement = ProbeAdapter('aux');
      final aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'primary',
        adapters: {'primary': ProbeAdapter('primary'), 'aux': old},
      );
      var armed = true;
      aggregate.addBackendEventListener((event) {
        if (!armed || event.kind != CCNavigationBackendEventKind.push) return;
        armed = false;
        aggregate.unregisterHost('aux');
        aggregate.registerHost('aux', replacement);
        _emitPush(replacement, 'replacement');
      });
      final runtime = CCRouterRuntime.forTesting(navigationAdapter: aggregate)
        ..initialize();
      addTearDown(runtime.dispose);
      _emitPush(old, 'retired');
      expect(runtime.activeBackendEntries, hasLength(1));
      expect(
        runtime.activeBackendEntries.single.backendEntryId,
        endsWith('-entry-replacement'),
      );
      expect(runtime.desynchronizedBackendHosts, isEmpty);
    },
  );

  test('observer errors do not suppress a live child event', () {
    final child = _PredictiveAdapter('primary');
    final aggregate = CCMultiHostNavigationAdapter(
      defaultHostId: 'primary',
      adapters: {'primary': child},
    )..initialize(const []);
    addTearDown(aggregate.dispose);
    var backend = 0;
    var predictive = 0;
    aggregate.addBackendEventListener(
      (_) => throw StateError('observer failed'),
    );
    aggregate.addBackendEventListener((_) => backend++);
    aggregate.addPredictiveBackListener(
      (_) => throw StateError('observer failed'),
    );
    aggregate.addPredictiveBackListener((_) => predictive++);
    _emitPush(child, 'live');
    child.emitPredictive();
    expect((backend, predictive), (1, 1));
  });

  for (final boundary in ['subscription', 'scopeCancellation', 'releaseSink']) {
    test('shutdown joins asynchronous Scope cleanup from $boundary', () async {
      late CCRouterRuntime runtime;
      Future<void>? shutdown;
      var armed = false;
      final resource = _HeldResource();
      final adapter = boundary != 'subscription'
          ? _ReleaseAdapter(() {
              if (armed && boundary == 'releaseSink')
                shutdown ??= runtime.dispose();
            })
          : _ExitAdapter(() {
              if (armed && boundary == 'subscription')
                shutdown ??= runtime.dispose();
            });
      runtime = _runtimeWithResource(
        adapter,
        resource,
        onScopeCancelled: boundary == 'scopeCancellation'
            ? () {
                if (armed) shutdown ??= runtime.dispose();
              }
            : null,
      );
      addTearDown(() async {
        if (!resource.released.isCompleted) resource.released.complete();
        if (adapter is _ExitAdapter)
          for (final exit in adapter.exits.toList()) {
            exit();
          }
        await runtime.dispose();
      });
      await runtime.goRoute(const Intent());
      final id = runtime.activeRouteEntries.single.navigationId;
      runtime.serviceForRoute<Resource>(navigationId: id);
      armed = true;
      await expectLater(
        runtime.goRoute(const Intent()),
        throwsA(isA<CCRouteCancelledError>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(shutdown, isNotNull);
      expect(resource.disposeCalls, 1);
      var finished = false;
      shutdown!.then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      resource.released.complete();
      await shutdown!.timeout(const Duration(seconds: 2));
      expect(finished, isTrue);
      expect(resource.disposeCalls, 1);
      expect(runtime.runtimeHealth.exitingRouteEntryCount, 0);
      if (adapter is _ExitAdapter) {
        expect(adapter.exits, isEmpty);
        expect(adapter.removals, 1);
      }
    });
  }

  for (final timing in ['duringSubscription', 'afterSubscription']) {
    test('Host detach releases outgoing Scope $timing', () async {
      late CCMultiHostNavigationAdapter aggregate;
      var armed = false;
      final child = _ExitAdapter(() {
        if (armed && timing == 'duringSubscription') {
          aggregate.unregisterHost('aux', replacementActiveHostId: 'primary');
        }
      }, hostId: 'aux');
      aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'aux',
        adapters: {'primary': ProbeAdapter('primary'), 'aux': child},
      );
      final resource = Resource();
      final runtime = _runtimeWithResource(aggregate, resource);
      addTearDown(runtime.dispose);
      await runtime.goRoute(const Intent());
      runtime.serviceForRoute<Resource>(
        navigationId: runtime.activeRouteEntries.single.navigationId,
      );
      armed = true;
      if (timing == 'duringSubscription') {
        await expectLater(
          runtime.goRoute(const Intent()),
          throwsA(isA<CCRouteCancelledError>()),
        );
      } else {
        await runtime.goRoute(const Intent());
        expect(resource.disposeCalls, 0);
        aggregate.unregisterHost('aux', replacementActiveHostId: 'primary');
      }
      await Future<void>.delayed(Duration.zero);
      expect(resource.disposeCalls, 1);
      expect(child.exits, isEmpty);
      expect(child.removals, 1);
      expect(runtime.runtimeHealth.exitingRouteEntryCount, 0);
    });
  }

  test(
    'synchronous exit and reentrant remover unsubscribe exactly once',
    () async {
      late CCRouterRuntime runtime;
      Future<void>? shutdown;
      final child = _ExitAdapter(() {})..completeSynchronously = true;
      final resource = Resource();
      runtime = _runtimeWithResource(child, resource);
      addTearDown(runtime.dispose);
      await runtime.goRoute(const Intent());
      runtime.serviceForRoute<Resource>(
        navigationId: runtime.activeRouteEntries.single.navigationId,
      );
      child.onRemove = () {
        shutdown ??= runtime.dispose();
      };
      try {
        await runtime.goRoute(const Intent());
      } on CCRouteCancelledError {
        /* Shutdown owns final cleanup. */
      }
      await Future<void>.delayed(Duration.zero);
      expect(shutdown, isNotNull);
      await shutdown!.timeout(const Duration(seconds: 2));
      expect(resource.disposeCalls, 1);
      expect(child.removals, 1);
      expect(child.exits, isEmpty);
    },
  );
}
