import 'dart:async';

import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

// Deterministic external callback and async handoff lifecycle regressions.
class ProbeAdapter
    implements
        CCNavigationAdapter,
        CCNavigationAdapterHostBinding,
        CCNavigationBackendEventSource {
  ProbeAdapter(
    this.hostId, {
    this.onInitialize,
    this.onBind,
    this.onUnbind,
    this.onNavigate,
    this.navigationResult,
  });

  @override
  final String hostId;
  final void Function()? onInitialize;
  final void Function()? onBind;
  final void Function()? onUnbind;
  final void Function()? onNavigate;
  final Future<Object?>? navigationResult;
  int listenerRemovals = 0;
  final delegate = CCMemoryNavigationAdapter();
  final listeners = <CCNavigationBackendEventListener>{};
  int disposeCalls = 0;

  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) {
    delegate.initialize(routes, shells: shells);
    onInitialize?.call();
  }

  @override
  void Function() addBackendEventListener(
    CCNavigationBackendEventListener listener,
  ) {
    listeners.add(listener);
    onBind?.call();
    return () {
      listenerRemovals++;
      listeners.remove(listener);
      onUnbind?.call();
    };
  }

  @override
  Future<Object?> navigate(CCNavigationRequest request) {
    if (onNavigate != null) {
      onNavigate!();
      return navigationResult ?? Future<Object?>.value();
    }
    return delegate.navigate(request);
  }

  @override
  Future<bool> maybePop({Object? result}) => delegate.maybePop(result: result);
  @override
  void pop({Object? result}) => delegate.pop(result: result);
  @override
  bool canPop() => delegate.canPop();
  @override
  void dispose() {
    disposeCalls++;
    listeners.clear();
    delegate.dispose();
  }
}

class Codec implements CCRouteCodec<String> {
  const Codec();
  @override
  String decode(CCRouteCodecValues input) => input.path['id']!;
  @override
  CCRouteCodecValues encode(String arguments) =>
      CCRouteCodecValues(path: {'id': arguments});
}

class Intent implements CCRouteIntent<void> {
  const Intent();
  @override
  String get routeId => 'probe.detail';
  @override
  String get arguments => 'A';
}

class Registrar implements CCComponentRegistrar {
  Registrar({this.extra});
  final void Function(CCRegistry)? extra;

  @override
  void register(CCRegistry registry) {
    extra?.call(registry);
    registry.registerRoute(
      CCRouteDefinition<String, void>(
        routeId: 'probe.detail',
        patterns: [CCPathPattern('/detail/:id', primary: true)],
        codec: const Codec(),
      ),
    );
  }
}

class Resource implements CCDisposable {
  int disposeCalls = 0;
  @override
  void dispose() => disposeCalls++;
}

const serviceToken = CCServiceToken<Resource>('probe.resource');

void main() {
  for (final disposeDuringDelivery in [false, true]) {
    test(
      'detach delivery retains old ownership until publication ends ($disposeDuringDelivery)',
      () {
        final primary = ProbeAdapter('primary');
        final old = ProbeAdapter('aux');
        final rejected = ProbeAdapter('aux');
        final aggregate = CCMultiHostNavigationAdapter(
          defaultHostId: 'primary',
          adapters: {'primary': primary, 'aux': old},
        );
        aggregate.initialize(const []);
        var delivered = 0;
        Object? reuseFailure;
        Object? conflictFailure;
        int? disposalsDuringDelivery;
        var callbackReturned = false;
        aggregate.addBackendEventListener((event) {
          if (event.kind != CCNavigationBackendEventKind.hostDetached) return;
          delivered++;
          try {
            aggregate.registerHost('aux', old);
          } catch (error) {
            reuseFailure = error;
          }
          disposalsDuringDelivery = old.disposeCalls;
          try {
            aggregate.registerHost('aux', rejected);
          } catch (error) {
            conflictFailure = error;
          }
          if (disposeDuringDelivery) aggregate.dispose();
          callbackReturned = true;
        });
        aggregate.unregisterHost('aux');
        expect(delivered, 1);
        expect(callbackReturned, isTrue);
        expect(reuseFailure, isA<CCNavigationAdapterError>());
        expect(conflictFailure, isA<CCNavigationAdapterError>());
        expect(disposalsDuringDelivery, 0);
        expect(rejected.disposeCalls, 1);
        expect(old.disposeCalls, 1);
        expect(old.listenerRemovals, 1);
        if (!disposeDuringDelivery) {
          final replacement = ProbeAdapter('aux');
          aggregate.registerHost('aux', replacement);
          aggregate.dispose();
          expect(replacement.disposeCalls, 1);
        }
        expect(primary.disposeCalls, 1);
      },
    );
  }

  test(
    'unsubscribe reentry cannot detach a freshly navigated replacement',
    () async {
      late CCMultiHostNavigationAdapter aggregate;
      late CCRouterRuntime runtime;
      final replacement = ProbeAdapter('aux');
      Future<void>? navigation;
      var replaceOnce = true;
      final old = ProbeAdapter(
        'aux',
        onUnbind: () {
          if (!replaceOnce) return;
          replaceOnce = false;
          aggregate.registerHost('aux', replacement);
          navigation = runtime.goRoute(
            const Intent(),
            placementOverride: const CCRoutePlacement(hostId: 'aux'),
          );
        },
      );
      aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'primary',
        adapters: {'primary': ProbeAdapter('primary'), 'aux': old},
      );
      runtime = CCRouterRuntime.forTesting(
        navigationAdapter: aggregate,
        components: [
          CCComponentManifest(
            id: 'probe',
            version: '1.0.0',
            registrar: Registrar(),
          ),
        ],
      );
      runtime.initialize();
      addTearDown(runtime.dispose);
      aggregate.unregisterHost('aux');
      await navigation;
      expect(runtime.activeRouteEntries.single.hostId, 'aux');
      expect(replacement.delegate.stack, hasLength(1));
      expect(old.disposeCalls, 1);
      expect(replacement.disposeCalls, 0);
    },
  );

  test('pre-initialization registration binds each Adapter once', () {
    final primary = ProbeAdapter('primary');
    final aux = ProbeAdapter('aux');
    final aggregate = CCMultiHostNavigationAdapter(
      defaultHostId: 'primary',
      adapters: {'primary': primary},
    );
    aggregate.registerHost('aux', aux);
    aggregate.initialize(const []);
    expect(aux.listeners, hasLength(1));
    aggregate.dispose();
    expect(aux.listenerRemovals, 1);
    expect(aux.disposeCalls, 1);
    expect(primary.disposeCalls, 1);
  });

  test(
    'initial configuration rejects recursive setup without losing ownership',
    () {
      late CCMultiHostNavigationAdapter aggregate;
      final rejected = ProbeAdapter('aux');
      final primary = ProbeAdapter(
        'primary',
        onInitialize: () {
          expect(
            () => aggregate.initialize(const []),
            throwsA(isA<CCNavigationAdapterError>()),
          );
          expect(
            () => aggregate.registerHost('aux', rejected),
            throwsA(isA<CCNavigationAdapterError>()),
          );
        },
      );
      aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'primary',
        adapters: {'primary': primary},
      );
      aggregate.initialize(const []);
      expect(aggregate.registeredHostIds, {'primary'});
      expect(primary.listeners, hasLength(1));
      expect(rejected.disposeCalls, 1);
      aggregate.dispose();
      expect(primary.disposeCalls, 1);
    },
  );

  for (final stop in ['initialize', 'bind']) {
    test('aggregate disposal during $stop releases the pending owner once', () {
      final primary = ProbeAdapter('primary');
      final aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'primary',
        adapters: {'primary': primary},
      );
      aggregate.initialize(const []);
      final rejected = ProbeAdapter(
        'aux',
        onInitialize: stop == 'initialize' ? aggregate.dispose : null,
        onBind: stop == 'bind' ? aggregate.dispose : null,
      );
      expect(
        () => aggregate.registerHost('aux', rejected),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      aggregate.dispose();
      expect(primary.disposeCalls, 1);
      expect(rejected.disposeCalls, 1);
      expect(rejected.listeners, isEmpty);
      expect(rejected.listenerRemovals, stop == 'bind' ? 1 : 0);
      expect(aggregate.registeredHostIds, isEmpty);
    });
  }

  test(
    'reusing a pending or live Adapter never disposes its current owner',
    () {
      final primary = ProbeAdapter('primary');
      final aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'primary',
        adapters: {'primary': primary},
      );
      aggregate.initialize(const []);
      late ProbeAdapter aux;
      aux = ProbeAdapter(
        'aux',
        onInitialize: () {
          expect(
            () => aggregate.registerHost('aux', aux),
            throwsA(isA<CCNavigationAdapterError>()),
          );
          expect(aux.disposeCalls, 0);
        },
      );
      aggregate.registerHost('aux', aux);
      expect(
        () => aggregate.registerHost('aux', aux),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      expect(aux.disposeCalls, 0);
      final duplicate = ProbeAdapter('aux');
      expect(
        () => aggregate.registerHost('aux', duplicate),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      expect(duplicate.disposeCalls, 1);
      aggregate.dispose();
      expect(aux.disposeCalls, 1);
      expect(primary.disposeCalls, 1);
    },
  );

  test('successful binding return cannot revive a replaced registration', () {
    final aggregate = CCMultiHostNavigationAdapter(
      defaultHostId: 'primary',
      adapters: {'primary': ProbeAdapter('primary')},
    );
    aggregate.initialize(const []);
    final replacement = ProbeAdapter('aux');
    final old = ProbeAdapter(
      'aux',
      onBind: () {
        aggregate.unregisterHost('aux');
        aggregate.registerHost('aux', replacement);
      },
    );
    expect(
      () => aggregate.registerHost('aux', old),
      throwsA(isA<CCNavigationAdapterError>()),
    );
    expect(aggregate.registeredHostIds, {'primary', 'aux'});
    expect(old.listenerRemovals, 1);
    expect(old.disposeCalls, 1);
    expect(replacement.listeners, hasLength(1));
    aggregate.activateHost('aux');
    aggregate.dispose();
    expect(replacement.disposeCalls, 1);
  });

  test('uncommitted binding cannot become the replacement active Host', () {
    final aggregate = CCMultiHostNavigationAdapter(
      defaultHostId: 'primary',
      adapters: {'primary': ProbeAdapter('primary')},
    );
    aggregate.initialize(const []);
    final aux = ProbeAdapter(
      'aux',
      onBind: () {
        expect(
          () => aggregate.activateHost('aux'),
          throwsA(isA<CCNavigationAdapterError>()),
        );
        expect(
          () => aggregate.unregisterHost(
            'primary',
            replacementActiveHostId: 'aux',
          ),
          throwsA(isA<CCNavigationAdapterError>()),
        );
      },
    );
    aggregate.registerHost('aux', aux);
    expect(aggregate.activeHostId, 'primary');
    aggregate.activateHost('aux');
    aggregate.dispose();
    expect(aux.disposeCalls, 1);
  });

  test('initialization reentry cannot overwrite an accepted registration', () {
    final primary = ProbeAdapter('primary');
    final aggregate = CCMultiHostNavigationAdapter(
      defaultHostId: 'primary',
      adapters: {'primary': primary},
    );
    aggregate.initialize(const []);
    final inner = ProbeAdapter('aux');
    final outer = ProbeAdapter(
      'aux',
      onInitialize: () => aggregate.registerHost('aux', inner),
    );
    Object? failure;
    try {
      aggregate.registerHost('aux', outer);
    } catch (error) {
      failure = error;
    }
    aggregate.dispose();
    expect(primary.disposeCalls, 1);
    // Both ownership transfers need a terminal path, whatever wins admission.
    expect(inner.disposeCalls, 1, reason: 'accepted inner Adapter leaked');
    expect(outer.disposeCalls, 1);
    expect(failure, isA<CCNavigationAdapterError>());
  });

  test('binding rollback cannot erase a replacement registration', () {
    final aggregate = CCMultiHostNavigationAdapter(
      defaultHostId: 'primary',
      adapters: {'primary': ProbeAdapter('primary')},
    );
    aggregate.initialize(const []);
    final replacement = ProbeAdapter('aux');
    final rejected = ProbeAdapter(
      'aux',
      onBind: () {
        aggregate.unregisterHost('aux');
        aggregate.registerHost('aux', replacement);
        throw StateError('bind failed after replacement');
      },
    );
    expect(() => aggregate.registerHost('aux', rejected), throwsStateError);
    final registered = aggregate.registeredHostIds;
    aggregate.dispose();
    expect(
      registered,
      contains('aux'),
      reason: 'replacement disposeCalls=${replacement.disposeCalls}',
    );
    expect(replacement.disposeCalls, 1);
    expect(rejected.disposeCalls, 1);
    expect(rejected.listeners, isEmpty);
  });

  for (final operation in ['push', 'replace', 'go', 'reset', 'open']) {
    test(
      '$operation consumes late Backend failure after synchronous detach',
      () async {
        late CCMultiHostNavigationAdapter aggregate;
        final result = Completer<Object?>();
        final aux = ProbeAdapter(
          'aux',
          onNavigate: () => aggregate.unregisterHost(
            'aux',
            replacementActiveHostId: 'primary',
          ),
          navigationResult: result.future,
        );
        aggregate = CCMultiHostNavigationAdapter(
          defaultHostId: 'primary',
          adapters: {'primary': ProbeAdapter('primary'), 'aux': aux},
        );
        final runtime = CCRouterRuntime.forTesting(
          navigationAdapter: aggregate,
          components: [
            CCComponentManifest(
              id: 'probe',
              version: '1.0.0',
              registrar: Registrar(),
            ),
          ],
        );
        runtime.initialize();
        addTearDown(runtime.dispose);
        aggregate.activateHost('aux');
        final pending = switch (operation) {
          'push' => runtime.pushRoute(const Intent()),
          'replace' => runtime.replaceRoute(const Intent()),
          'reset' => runtime.resetRoute(const Intent()),
          'open' => runtime.openRoute(Uri.parse('/detail/A')),
          _ => runtime.goRoute(const Intent()),
        };
        await expectLater(pending, throwsA(isA<CCRouteCancelledError>()));
        expect(runtime.activeRouteEntries, isEmpty);
        result.completeError(StateError('late Backend rejection'));
        await Future<void>.delayed(Duration.zero);
        aggregate.activateHost('primary');
        await runtime.goRoute(const Intent());
        expect(runtime.activeRouteEntries.single.hostId, 'primary');
        expect(aux.disposeCalls, 1);
      },
    );
  }

  for (final interruption in ['detach', 'shutdown']) {
    test('old Scope cancellation during commit fences $interruption', () async {
      final aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'primary',
        adapters: {
          'primary': ProbeAdapter('primary'),
          'aux': ProbeAdapter('aux'),
        },
      );
      late CCRouterRuntime runtime;
      Future<void>? closing;
      final resource = Resource();
      runtime = CCRouterRuntime.forTesting(
        navigationAdapter: aggregate,
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
                      context.cancellation.addListener(() {
                        if (interruption == 'detach') {
                          aggregate.unregisterHost(
                            'aux',
                            replacementActiveHostId: 'primary',
                          );
                        } else {
                          closing = runtime.dispose();
                        }
                      });
                      return resource;
                    },
                  ),
                );
              },
            ),
          ),
        ],
      );
      runtime.initialize();
      addTearDown(runtime.dispose);
      aggregate.activateHost('aux');
      await runtime.goRoute(const Intent());
      runtime.serviceForRoute<Resource>(
        navigationId: runtime.activeRouteEntries.single.navigationId,
      );
      await expectLater(
        runtime.goRoute(const Intent()),
        throwsA(isA<CCRouteCancelledError>()),
      );
      await closing;
      expect(runtime.activeRouteEntries, isEmpty);
      await runtime.dispose();
      expect(resource.disposeCalls, 1);
    });
  }

  test(
    'synchronous detach during dispatch cannot commit a retired Entry',
    () async {
      late CCMultiHostNavigationAdapter aggregate;
      final aux = ProbeAdapter(
        'aux',
        onNavigate: () =>
            aggregate.unregisterHost('aux', replacementActiveHostId: 'primary'),
      );
      aggregate = CCMultiHostNavigationAdapter(
        defaultHostId: 'primary',
        adapters: {'primary': ProbeAdapter('primary'), 'aux': aux},
      );
      final runtime = CCRouterRuntime.forTesting(
        navigationAdapter: aggregate,
        components: [
          CCComponentManifest(
            id: 'probe',
            version: '1.0.0',
            registrar: Registrar(),
          ),
        ],
      );
      runtime.initialize();
      addTearDown(runtime.dispose);
      aggregate.activateHost('aux');
      Object? failure;
      try {
        await runtime.goRoute(const Intent());
      } catch (error) {
        failure = error;
      }
      expect(runtime.activeRouteEntries, isEmpty);
      expect(failure, isA<CCRouteCancelledError>());
    },
  );

  test(
    'synchronous shutdown during dispatch cannot recreate an Entry',
    () async {
      late CCRouterRuntime runtime;
      Future<void>? shutdown;
      final adapter = ProbeAdapter(
        'default',
        onNavigate: () => shutdown = runtime.dispose(),
      );
      runtime = CCRouterRuntime.forTesting(
        navigationAdapter: adapter,
        components: [
          CCComponentManifest(
            id: 'probe',
            version: '1.0.0',
            registrar: Registrar(),
          ),
        ],
      );
      runtime.initialize();
      addTearDown(runtime.dispose);
      Object? failure;
      try {
        await runtime.goRoute(const Intent());
      } catch (error) {
        failure = error;
      }
      await shutdown;
      expect(runtime.activeRouteEntries, isEmpty);
      expect(failure, isA<CCRouteCancelledError>());
    },
  );

  for (final interruption in ['caller', 'session', 'shutdown']) {
    test(
      'unstarted Service method stays cancelled after $interruption',
      () async {
        final resource = Resource();
        final provider = CCServiceProvider<Resource>(
          contractToken: serviceToken,
          scope: interruption == 'session'
              ? CCServiceScope.session
              : CCServiceScope.app,
          factory: (_) => resource,
        );
        final runtime = CCRouterRuntime.forTesting();
        runtime.registerService(provider);
        runtime.initialize();
        addTearDown(runtime.dispose);
        if (interruption == 'session')
          runtime.openSession(accountId: 'account-a');
        final cancellation = CCCancellationToken();
        var calls = 0;
        bool? cancelledAtCall;
        final pending = runtime.invokeService<Resource, int>(
          contractToken: serviceToken,
          methodId: 'write',
          cancellation: cancellation,
          call: (service, context) {
            calls++;
            cancelledAtCall = context.cancellation.isCancelled;
            return 1;
          },
        );
        final observed = pending.then<Object?>(
          (v) => v,
          onError: (Object e) => e,
        );
        final Future<void>? closing;
        switch (interruption) {
          case 'session':
            closing = runtime.closeSession();
          case 'shutdown':
            closing = runtime.dispose();
          default:
            cancellation.cancel();
            closing = null;
        }
        final outcome = await observed;
        await closing;
        expect(
          calls,
          0,
          reason:
              'business method started after cancellation; '
              'cancelledAtCall=$cancelledAtCall, outcome=$outcome',
        );
        expect(outcome, isA<CCInvocationCancelledError>());
        await runtime.dispose();
        expect(resource.disposeCalls, 1);
      },
    );
  }

  test(
    'cancellation after ready lookup affects only the unentered caller',
    () async {
      final runtime = CCRouterRuntime.forTesting();
      addTearDown(runtime.dispose);
      var initializations = 0;
      var calls = 0;
      runtime.registerService(
        CCServiceProvider<Resource>(
          contractToken: serviceToken,
          factory: (_) => Resource(),
          initializer: (_, _) => initializations++,
        ),
      );
      runtime.initialize();
      await runtime.serviceAsync<Resource>(contractToken: serviceToken);
      Future<int> invoke(CCCancellationToken token) =>
          runtime.invokeService<Resource, int>(
            contractToken: serviceToken,
            methodId: 'write',
            cancellation: token,
            call: (_, _) => ++calls,
          );
      final cancelled = CCCancellationToken();
      final first = invoke(cancelled);
      final second = invoke(CCCancellationToken());
      cancelled.cancel();
      await expectLater(first, throwsA(isA<CCInvocationCancelledError>()));
      expect(await second, 1);
      expect(calls, 1);
      expect(initializations, 1);
    },
  );
}
