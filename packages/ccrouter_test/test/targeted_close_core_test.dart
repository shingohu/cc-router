import 'dart:async';

import 'package:ccrouter/ccrouter_host.dart' as host;
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:test/test.dart';

import 'navigation_test.dart' as fixture;

final class _Resource implements CCDisposable {
  int disposeCount = 0;
  @override
  Future<void> dispose() async => disposeCount++;
}

final class _LegacyAdapter implements CCNavigationAdapter {
  final delegate = CCMemoryNavigationAdapter();
  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) => delegate.initialize(routes, shells: shells);
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
}

/// Models a backend that commits the exact removal before reporting failure.
final class _MutatingThrowingTargetedAdapter
    implements CCNavigationAdapter, CCNavigationTargetedCloseAdapter {
  final delegate = CCMemoryNavigationAdapter();

  @override
  void initialize(
    List<CCNavigationRoute> routes, {
    List<CCNavigationShell> shells = const [],
  }) => delegate.initialize(routes, shells: shells);

  @override
  Future<Object?> navigate(CCNavigationRequest request) =>
      delegate.navigate(request);

  @override
  Future<CCRouteCloseOutcome> closeNavigation({
    required String navigationId,
    required String hostId,
    required String navigatorOutlet,
    Object? result,
  }) async {
    final outcome = await delegate.closeNavigation(
      navigationId: navigationId,
      hostId: hostId,
      navigatorOutlet: navigatorOutlet,
      result: result,
    );
    if (outcome.status == CCRouteCloseStatus.closed) {
      throw const CCNavigationAdapterError(
        'Synthetic failure after targeted close commit.',
      );
    }
    return outcome;
  }

  @override
  Future<bool> maybePop({Object? result}) => delegate.maybePop(result: result);

  @override
  void pop({Object? result}) => delegate.pop(result: result);

  @override
  bool canPop() => delegate.canPop();

  @override
  void dispose() => delegate.dispose();
}

CCRouteIntent<String> _intent(
  String value, {
  String routeId = 'orders.detail',
}) => fixture.TestIntent<String>(routeId, fixture.RouteArgs(value));

CCRouterRuntime _runtime({
  CCNavigationAdapter? adapter,
  void Function(CCRegistry)? register,
  List<CCGlobalPopGuard> guards = const [],
}) {
  final runtime = CCRouterRuntime.forTesting(
    navigationAdapter: adapter ?? CCMemoryNavigationAdapter(),
    globalPopGuards: guards,
    components: [
      fixture.routeComponent(
        'orders',
        register ?? (r) => r.registerRoute(fixture.pathRoute()),
      ),
    ],
  );
  runtime.initialize();
  addTearDown(runtime.dispose);
  return runtime;
}

CCRouteEntryHandle _handle(
  CCRouterRuntime runtime,
  CCRouteEntrySnapshot entry,
) => runtime.routeEntryHandleForNavigation(entry.navigationId)!;

void main() {
  test(
    'duplicate route instances close only selected result and Scope once',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = _runtime(
        adapter: adapter,
        register: (r) {
          r.registerRoute(fixture.pathRoute());
          r.registerService<_Resource>(
            CCServiceProvider(
              scope: CCServiceScope.route,
              factory: (_) => _Resource(),
            ),
          );
        },
      );
      final first = runtime.pushRoute(_intent('1'));
      await Future<void>.delayed(Duration.zero);
      final a = runtime.activeRouteEntries.single;
      final resourceA = runtime.serviceForRoute<_Resource>(
        navigationId: a.navigationId,
      );
      var bCompleted = false;
      final second = runtime.pushRoute(_intent('1')).then((value) {
        bCompleted = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      final b = runtime.activeRouteEntries.last;
      final resourceB = runtime.serviceForRoute<_Resource>(
        navigationId: b.navigationId,
      );
      final outcomes = await Future.wait([
        runtime.closeRoute(_handle(runtime, a), result: 'A'),
        runtime.closeRoute(_handle(runtime, a), result: 'again'),
      ]);
      expect(outcomes.map((o) => o.status), [
        CCRouteCloseStatus.closed,
        CCRouteCloseStatus.notFound,
      ]);
      expect(await first, 'A');
      await Future<void>.delayed(Duration.zero);
      expect(bCompleted, isFalse);
      expect(resourceA.disposeCount, 1);
      expect(resourceB.disposeCount, 0);
      expect(runtime.activeRouteEntries.single.routeEntryId, b.routeEntryId);
      expect(adapter.stack.single.navigationId, b.navigationId);
      expect(
        (await runtime.closeRoute(_handle(runtime, b), result: 'B')).status,
        CCRouteCloseStatus.closed,
      );
      expect(await second, 'B');
      await Future<void>.delayed(Duration.zero);
      expect(resourceA.disposeCount, 1);
      expect(resourceB.disposeCount, 1);
    },
  );

  test(
    'guard-triggered Runtime invalidation never reaches the adapter',
    () async {
      late CCRouterRuntime runtime;
      Future<void>? shutdown;
      runtime = _runtime(
        guards: [
          CCGlobalPopGuard(
            id: 'app.shutdown',
            guard: fixture.TestPopGuard('shutdown', [], (_) {
              shutdown = runtime.dispose();
              return const CCPopAllow();
            }),
          ),
        ],
      );
      final pending = runtime.pushRoute(_intent('1'));
      unawaited(pending.catchError((_) => null));
      await Future<void>.delayed(Duration.zero);
      final outcome = await runtime.closeRoute(
        _handle(runtime, runtime.activeRouteEntries.single),
      );
      expect(outcome.status, CCRouteCloseStatus.notFound);
      await shutdown;
      expect(runtime.activeRouteEntries, isEmpty);
    },
  );

  test(
    'multi-Host optional capability delegates to the owning inactive child',
    () async {
      final left = CCMemoryNavigationAdapter();
      final right = CCMemoryNavigationAdapter();
      final adapter = host.CCMultiHostNavigationAdapter(
        defaultHostId: 'left',
        adapters: {'left': left, 'right': right},
      );
      final runtime = _runtime(adapter: adapter);
      final first = runtime.pushRoute(_intent('1'));
      await Future<void>.delayed(Duration.zero);
      final a = runtime.activeRouteEntries.single;
      adapter.activateHost('right');
      final second = runtime.pushRoute(_intent('2'));
      await Future<void>.delayed(Duration.zero);
      final b = runtime.activeRouteEntries.last;
      expect(
        (await runtime.closeRoute(_handle(runtime, a), result: 'left')).status,
        CCRouteCloseStatus.closed,
      );
      expect(await first, 'left');
      expect(left.stack, isEmpty);
      expect(right.stack.single.navigationId, b.navigationId);
      expect(adapter.activeHostId, 'right');
      await runtime.closeRoute(_handle(runtime, b));
      await second;
    },
  );

  test('wrong result is rejected before backend or Scope mutation', () async {
    final adapter = CCMemoryNavigationAdapter();
    final runtime = _runtime(adapter: adapter);
    final pending = runtime.pushRoute(_intent('1'));
    await Future<void>.delayed(Duration.zero);
    final handle = _handle(runtime, runtime.activeRouteEntries.single);
    await expectLater(
      runtime.closeRoute(handle, result: 42),
      throwsA(isA<CCRouteResultTypeError>()),
    );
    expect(adapter.stack, hasLength(1));
    expect(runtime.activeRouteEntries, hasLength(1));
    await runtime.closeRoute(handle, result: 'valid');
    expect(await pending, 'valid');
  });

  test(
    'guards receive covered target identity and denial preserves both entries',
    () async {
      final calls = <String>[];
      final runtime = _runtime(
        guards: [
          CCGlobalPopGuard(
            id: 'app.guard',
            guard: fixture.TestPopGuard(
              'global',
              calls,
              (c) => c.entry.lifecycleState == CCRouteEntryLifecycleState.hidden
                  ? const CCPopDeny(code: 'covered')
                  : const CCPopAllow(),
            ),
          ),
        ],
      );
      final first = runtime.pushRoute(_intent('1'));
      await Future<void>.delayed(Duration.zero);
      final a = runtime.activeRouteEntries.single;
      final second = runtime.pushRoute(_intent('2'));
      await Future<void>.delayed(Duration.zero);
      final outcome = await runtime.closeRoute(_handle(runtime, a));
      expect(outcome.status, CCRouteCloseStatus.guardDenied);
      expect(outcome.guardDeniedCode, 'covered');
      expect(runtime.activeRouteEntries, hasLength(2));
      expect(calls, ['global:orders.detail:business']);
      await runtime.closeRoute(
        _handle(runtime, runtime.activeRouteEntries.last),
      );
      await second;
      await runtime.closeRoute(_handle(runtime, a));
      await first;
    },
  );

  test('route-local guard denial is target-specific', () async {
    final calls = <String>[];
    final runtime = _runtime(
      register: (r) {
        r.registerRoutePopGuard(
          'orders.local',
          fixture.TestPopGuard(
            'local',
            calls,
            (_) => const CCPopDeny(code: 'dirty'),
          ),
        );
        r.registerRoute(fixture.pathRoute(popGuardIds: ['orders.local']));
      },
    );
    final pending = runtime.pushRoute(_intent('1'));
    unawaited(pending.catchError((_) => null));
    await Future<void>.delayed(Duration.zero);
    final outcome = await runtime.closeRoute(
      _handle(runtime, runtime.activeRouteEntries.single),
    );
    expect(outcome.status, CCRouteCloseStatus.guardDenied);
    expect(outcome.guardDeniedCode, 'dirty');
    expect(calls, ['local:orders.detail:business']);
  });

  test(
    'forged and prior Runtime handles never target same-route current entry',
    () async {
      final old = _runtime();
      final p1 = old.pushRoute(_intent('1'));
      await Future<void>.delayed(Duration.zero);
      final handle = _handle(old, old.activeRouteEntries.single);
      await old.closeRoute(handle);
      await p1;
      final current = _runtime();
      final p2 = current.pushRoute(_intent('1'));
      await Future<void>.delayed(Duration.zero);
      final currentHandle = _handle(current, current.activeRouteEntries.single);
      expect(
        (await current.closeRoute(handle)).status,
        CCRouteCloseStatus.notFound,
      );
      expect(
        (await current.closeRoute(
          CCRouteEntryHandle(currentHandle.routeEntryId),
        )).status,
        CCRouteCloseStatus.notFound,
      );
      expect(current.activeRouteEntries, hasLength(1));
      await current.closeRoute(currentHandle);
      await p2;
    },
  );

  test(
    'legacy adapter is source compatible and explicitly unsupported without Pop fallback',
    () async {
      final adapter = _LegacyAdapter();
      final runtime = _runtime(adapter: adapter);
      final p = runtime.pushRoute(_intent('1'));
      unawaited(p.catchError((_) => null));
      await Future<void>.delayed(Duration.zero);
      expect(
        (await runtime.closeRoute(
          _handle(runtime, runtime.activeRouteEntries.single),
        )).status,
        CCRouteCloseStatus.unsupported,
      );
      expect(adapter.delegate.stack, hasLength(1));
    },
  );

  test(
    'a targeted-close failure after backend mutation still converges Runtime cleanup',
    () async {
      final adapter = _MutatingThrowingTargetedAdapter();
      final runtime = _runtime(adapter: adapter);
      final pending = runtime.pushRoute(_intent('1'));
      await Future<void>.delayed(Duration.zero);
      final handle = _handle(runtime, runtime.activeRouteEntries.single);

      await expectLater(
        runtime.closeRoute(handle, result: 'committed'),
        throwsA(isA<CCNavigationAdapterError>()),
      );
      expect(await pending, 'committed');
      await Future<void>.delayed(Duration.zero);
      expect(runtime.activeRouteEntries, isEmpty);
      expect(adapter.delegate.stack, isEmpty);
    },
  );

  test(
    'closing inactive Host and Outlet preserves the active partition',
    () async {
      final adapter = CCMemoryNavigationAdapter();
      final runtime = _runtime(
        adapter: adapter,
        register: (r) {
          r.registerRoute(
            fixture.pathRoute(
              routeId: 'orders.left',
              path: '/left/:value',
              placement: const CCRoutePlacement(
                hostId: 'left',
                navigatorOutlet: 'detail',
              ),
            ),
          );
          r.registerRoute(
            fixture.pathRoute(
              routeId: 'orders.right',
              path: '/right/:value',
              placement: const CCRoutePlacement(
                hostId: 'right',
                navigatorOutlet: 'root',
              ),
            ),
          );
        },
      );
      final left = runtime.pushRoute(_intent('1', routeId: 'orders.left'));
      await Future<void>.delayed(Duration.zero);
      final a = runtime.activeRouteEntries.single;
      final right = runtime.pushRoute(_intent('2', routeId: 'orders.right'));
      await Future<void>.delayed(Duration.zero);
      final b = runtime.activeRouteEntries.last;
      expect(
        (await runtime.closeRoute(_handle(runtime, a), result: 'left')).status,
        CCRouteCloseStatus.closed,
      );
      expect(await left, 'left');
      expect(adapter.stack.single.hostId, 'right');
      expect(runtime.activeRouteEntries.single.routeEntryId, b.routeEntryId);
      await runtime.closeRoute(_handle(runtime, b));
      await right;
    },
  );
}
