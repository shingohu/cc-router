import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'managed_navigation_partition_regression_test.dart' as partition;
import 'managed_cross_lifecycle_regression_test.dart' as fixture;
import 'managed_operation_ownership_regression_test.dart' as links;

Future<Object?> outcome(Future<void> future) =>
    future.then<Object?>((_) => null, onError: (Object e, StackTrace _) => e);

final class Owned implements CCDisposable {
  int disposals = 0;
  @override
  void dispose() {
    disposals++;
  }
}

final class Ping implements CCCommand<int> {}

final class FailureCounter implements CCNavigationFailurePolicy {
  int calls = 0;
  @override
  CCNavigationFailureDecision onFailure(CCNavigationFailureContext context) {
    calls++;
    return const CCNavigationFailureRedirect.toIntent(fixture.Intent('B'));
  }
}

final class ServiceRegistrar implements CCComponentRegistrar {
  ServiceRegistrar(this.factory);
  final Owned Function() factory;
  @override
  void register(CCRegistry registry) {
    registry.registerService(
      CCServiceProvider<Owned>(
        scope: CCServiceScope.session,
        factory: (_) => factory(),
      ),
    );
  }
}

Future<CCManagedRouterBackend> replacePrimary(
  WidgetTester tester,
  CCManagedMultiHostBackend aggregate,
) async {
  aggregate.adapter.unregisterHost(
    'primary',
    replacementActiveHostId: 'secondary',
  );
  final replacement = CCManagedRouterBackend(
    routeCatalog: aggregate.routeCatalog,
    host: CCNavigationHost(
      id: 'primary',
      navigatorKeys: {'detail': GlobalKey<NavigatorState>()},
    ),
    shellBindings: [
      CCManagedShellBinding(
        shellId: 'probe.shell',
        builder: (_, shell) => shell.navigatorFor('detail'),
      ),
    ],
  );
  aggregate.adapter.registerHost('primary', replacement.navigationAdapter);
  addTearDown(replacement.dispose);
  await tester.pumpWidget(
    CCRouterApp.managed(
      backend: aggregate,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            Expanded(
              child: MaterialApp.router(routerConfig: replacement.routerConfig),
            ),
            Expanded(
              child: MaterialApp.router(
                routerConfig: aggregate.routerConfigFor('secondary'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  aggregate.adapter.activateHost('primary');
  return replacement;
}

void main() {
  tearDown(CCRouterHost.shutdown);
  test(
    'same logical Host gets disjoint Managed backend operation identities',
    () async {
      final allIds = <String>{};
      for (var generation = 0; generation < 4; generation++) {
        final adapter = CCManagedNavigationAdapter(
          catalog: CCFlutterRouteCatalog([]),
          host: CCNavigationHost(id: 'reused'),
        );
        addTearDown(adapter.dispose);
        adapter.initialize(const []);
        final events = <CCNavigationBackendEvent>[];
        adapter.addBackendEventListener(events.add);
        final handle = adapter.foreignRouteBridge.push();
        adapter.foreignRouteBridge.pop(handle);
        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(2));
        for (final event in events) {
          expect(
            allIds.add(event.backendOperationId!),
            isTrue,
            reason: 'generation $generation',
          );
        }
      }
    },
  );
  for (final concurrency in [
    CCNavigationConcurrencyPolicy.singleFlight,
    CCNavigationConcurrencyPolicy.rejectDuplicate,
  ]) {
    testWidgets(
      'visited redirect Host removal releases initial $concurrency gate immediately',
      (tester) async {
        final gate = Completer<CCNavigationInterceptorDecision>();
        var initialCalls = 0;
        final aggregate = await partition.mountMulti(
          tester,
          concurrency: concurrency,
          interceptor: links.CallbackPolicy((context) {
            if (context.request.uri.path == '/detail/A') {
              initialCalls++;
              return initialCalls == 1
                  ? const CCNavigationRedirect.toIntent(
                      partition.PartitionIntent('explicit', 'B'),
                    )
                  : const CCNavigationProceed();
            }
            return context.request.uri.path == '/explicit/B'
                ? gate.future
                : const CCNavigationProceed();
          }),
        );
        final first = outcome(CCRouter.navigator.go(const fixture.Intent('A')));
        await tester.pump();
        aggregate.adapter.unregisterHost('secondary');
        // Deliberately do not pump between detach and retry.
        final retry = outcome(CCRouter.navigator.go(const fixture.Intent('A')));
        await tester.pumpAndSettle();
        expect(await first, isA<CCRouteCancelledError>());
        expect(await retry, isNull);
        expect(initialCalls, 2);
        expect(
          aggregate.backendFor('primary').adapter.requests.single.uri.path,
          '/detail/A',
        );
        gate.complete(const CCNavigationProceed());
        await tester.pumpAndSettle();
      },
    );
  }
  for (final operation in [
    'go',
    'reset',
    'push',
    'replace',
    'open',
    'notification',
  ]) {
    testWidgets('$operation ends before late policy after Host removal', (
      tester,
    ) async {
      final gate = Completer<CCNavigationInterceptorDecision>();
      final failures = FailureCounter();
      CCCancellationToken? policyToken;
      final aggregate = await partition.mountMulti(
        tester,
        failurePolicy: failures,
        interceptor: links.CallbackPolicy((context) {
          if (context.request.uri.path != '/detail/A')
            return const CCNavigationProceed();
          policyToken = context.cancellation;
          return gate.future;
        }),
      );
      final Future<void> pending = switch (operation) {
        'go' => CCRouter.navigator.go(const fixture.Intent('A')),
        'reset' => CCRouter.navigator.reset(const fixture.Intent('A')),
        'push' => CCRouter.navigator.push(const fixture.Intent('A')),
        'replace' => CCRouter.navigator.replace(const fixture.Intent('A')),
        'open' => CCRouter.navigator.open(Uri.parse('/detail/A')),
        _ => CCDeepLinkIngress.fromNotification(Uri.parse('/detail/A')),
      };
      var ended = false;
      final old = outcome(pending).then((result) {
        ended = true;
        return result;
      });
      await tester.pump();
      expect(policyToken, isNotNull);
      final replacement = await replacePrimary(tester, aggregate);
      expect(
        ended,
        isTrue,
        reason: 'Host removal cannot wait for cooperative user code',
      );
      expect(await old, isA<CCRouteCancelledError>());
      expect(policyToken!.isCancelled, isTrue);
      expect(
        failures.calls,
        0,
        reason:
            'terminal owner cancellation cannot recover into the replacement',
      );
      await CCRouter.navigator.go(const fixture.Intent('C'));
      await tester.pumpAndSettle();
      final identity = CCRouter.activeRouteEntries
          .singleWhere((entry) => entry.hostId == 'primary')
          .routeEntryId;
      gate.completeError(StateError('late policy failure'));
      await tester.pumpAndSettle();
      expect(replacement.adapter.requests.single.uri.path, '/detail/C');
      expect(
        CCRouter.activeRouteEntries
            .singleWhere((entry) => entry.hostId == 'primary')
            .routeEntryId,
        identity,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'an explicit initial target does not bind the active unrelated Host',
    (tester) async {
      final gate = Completer<CCNavigationInterceptorDecision>();
      final aggregate = await partition.mountMulti(
        tester,
        interceptor: links.CallbackPolicy(
          (context) => context.request.uri.path == '/explicit/A'
              ? gate.future
              : const CCNavigationProceed(),
        ),
      );
      final pending = outcome(
        CCRouter.navigator.go(const partition.PartitionIntent('explicit', 'A')),
      );
      await tester.pump();
      aggregate.adapter.unregisterHost(
        'primary',
        replacementActiveHostId: 'secondary',
      );
      gate.complete(const CCNavigationProceed());
      await tester.pumpAndSettle();
      expect(await pending, isNull);
      expect(
        aggregate.backendFor('secondary').adapter.requests.single.uri.path,
        '/explicit/A',
      );
    },
  );

  for (final reentrant in [false, true]) {
    test('public Session service cleanup (reentrant=$reentrant)', () async {
      late Owned instance;
      Future<void>? closing;
      CCRouterHost.initialize(
        hostAssembly: CCHostAssembly.fromComponents(
          components: [
            CCComponentManifest(
              id: 'probe',
              version: '1.0.0',
              registrar: ServiceRegistrar(() {
                instance = Owned();
                if (reentrant) closing = CCRouter.closeSession();
                return instance;
              }),
            ),
          ],
        ),
      );
      CCRouter.openSession(accountId: 'probe-account');
      if (reentrant) {
        expect(
          () => CCRouter.service<Owned>(),
          throwsA(isA<CCScopeClosedError>()),
        );
      } else {
        CCRouter.service<Owned>();
        closing = CCRouter.closeSession();
      }
      await closing;
      await CCRouterHost.shutdown();
      debugPrint(
        'public service: reentrant=$reentrant, disposals=${instance.disposals}',
      );
      expect(instance.disposals, 1);
    });
  }
  for (final reentrant in [false, true]) {
    for (final scope in [CCServiceScope.app, CCServiceScope.session]) {
      test(
        'factory resource cleanup (scope=${scope.name}, reentrant=$reentrant)',
        () async {
          final runtime = CCRouterRuntime.forTesting();
          addTearDown(runtime.dispose);
          late Owned instance;
          Future<void>? closing;
          runtime.registerService(
            CCServiceProvider<Owned>(
              scope: scope,
              factory: (_) {
                instance = Owned();
                if (reentrant)
                  closing = scope == CCServiceScope.session
                      ? runtime.closeSession()
                      : runtime.dispose();
                return instance;
              },
            ),
          );
          runtime.initialize();
          runtime.openSession(accountId: 'probe-account');
          if (reentrant) {
            expect(
              () => runtime.service<Owned>(),
              throwsA(
                scope == CCServiceScope.session
                    ? isA<CCScopeClosedError>()
                    : isA<CCInvocationCancelledError>(),
              ),
            );
          } else {
            runtime.service<Owned>();
            closing ??= scope == CCServiceScope.session
                ? runtime.closeSession()
                : runtime.dispose();
          }
          await closing;
          await runtime.dispose();
          debugPrint(
            'factory: scope=${scope.name}, reentrant=$reentrant, disposals=${instance.disposals}',
          );
          expect(
            instance.disposals,
            1,
            reason:
                'a successfully returned owned resource must not be abandoned',
          );
        },
      );
    }
  }

  for (final throwsListener in [false, true]) {
    test(
      'Command timeout preserves error when listener throws=$throwsListener',
      () async {
        final runtime = CCRouterRuntime.forTesting();
        addTearDown(runtime.dispose);
        final lateResult = Completer<int>();
        var notifications = 0;
        runtime.registerCommand<Ping, int>((_, context) {
          context.cancellation.addListener(() {
            notifications++;
            if (throwsListener) throw StateError('cleanup listener');
          });
          return lateResult.future;
        });
        runtime.initialize();
        var timeoutTimers = 0;
        // Test timeout cancellation after Handler entry, independently of JIT
        // startup or suite load. Advance the real timeout callback to the next
        // event turn while leaving ample wall-clock time for initial admission.
        final pending = runZoned(
          () => runtime.command(Ping(), timeout: const Duration(hours: 1)),
          zoneSpecification: ZoneSpecification(
            createTimer: (_, parent, zone, duration, callback) {
              if (duration > Duration.zero) {
                timeoutTimers++;
                return parent.createTimer(zone, Duration.zero, callback);
              }
              return parent.createTimer(zone, duration, callback);
            },
          ),
        );
        final result = await pending.then<Object?>(
          (value) => value,
          onError: (Object error, StackTrace _) => error,
        );
        lateResult.completeError(StateError('late handler failure'));
        await Future<void>.delayed(Duration.zero);
        expect(timeoutTimers, 1);
        expect(notifications, 1);
        expect(runtime.recentTraces.single.status, 'timedOut');
        debugPrint(
          'timeout: throwing=$throwsListener, result=${result.runtimeType}, trace=${runtime.recentTraces.single.status}',
        );
        expect(result, isA<CCInvocationTimeoutError>());
      },
    );
  }

  testWidgets('deferred request cannot be resurrected in replacement Host', (
    tester,
  ) async {
    var defer = true;
    final aggregate = await partition.mountMulti(
      tester,
      interceptor: links.CallbackPolicy(
        (context) => context.request.uri.path == '/detail/A' && defer
            ? const CCNavigationDefer()
            : const CCNavigationProceed(),
      ),
    );
    final old = outcome(CCRouter.navigator.go(const fixture.Intent('A')));
    await tester.pump();
    final id = CCRouter.pendingNavigations.single.navigationId;
    final replacement = await replacePrimary(tester, aggregate);
    defer = false;
    final resumed = outcome(CCRouter.resumePendingNavigation(id));
    await tester.pumpAndSettle();
    await resumed;
    final result = await old;
    debugPrint(
      'defer replacement: old=${result.runtimeType}, path=${replacement.adapter.requests.single.uri.path}',
    );
    expect(replacement.adapter.requests.single.uri.path, '/');
    expect(result, isA<CCRouterError>());
  });

  for (final remove in [false, true]) {
    testWidgets(
      'control: ${remove ? 'removed Host without replacement fails' : 'focus change preserves live Host'}',
      (tester) async {
        final gate = Completer<CCNavigationInterceptorDecision>();
        final aggregate = await partition.mountMulti(
          tester,
          interceptor: links.CallbackPolicy(
            (context) => context.request.uri.path == '/detail/A'
                ? gate.future
                : const CCNavigationProceed(),
          ),
        );
        final old = outcome(CCRouter.navigator.go(const fixture.Intent('A')));
        await tester.pump();
        if (remove) {
          aggregate.adapter.unregisterHost(
            'primary',
            replacementActiveHostId: 'secondary',
          );
        } else {
          aggregate.adapter.activateHost('secondary');
        }
        gate.complete(const CCNavigationProceed());
        await tester.pumpAndSettle();
        final result = await old;
        debugPrint('control: remove=$remove, old=${result.runtimeType}');
        expect(
          aggregate.backendFor('secondary').adapter.requests.single.uri.path,
          '/',
        );
        if (remove) {
          expect(result, isA<CCRouteCancelledError>());
        } else {
          expect(result, isNull);
          expect(
            aggregate.backendFor('primary').adapter.requests.single.uri.path,
            '/detail/A',
          );
        }
      },
    );
  }
  for (final redirect in [false, true]) {
    testWidgets(
      'old ${redirect ? 'redirect' : 'proceed'} cannot enter replacement Host',
      (tester) async {
        final gate = Completer<CCNavigationInterceptorDecision>();
        final aggregate = await partition.mountMulti(
          tester,
          interceptor: links.CallbackPolicy(
            (context) => context.request.uri.path == '/detail/A'
                ? gate.future
                : const CCNavigationProceed(),
          ),
        );
        final old = outcome(CCRouter.navigator.go(const fixture.Intent('A')));
        await tester.pump();
        final replacement = await replacePrimary(tester, aggregate);
        gate.complete(
          redirect
              ? const CCNavigationRedirect.toIntent(fixture.Intent('B'))
              : const CCNavigationProceed(),
        );
        await tester.pumpAndSettle();
        final result = await old;
        expect(
          replacement.adapter.requests.map((r) => r.uri.path),
          ['/'],
          reason:
              'terminated Host must not transfer pending work to a new instance',
        );
        expect(result, isA<CCRouterError>());
      },
    );
  }

  testWidgets('old recovery cannot enter replacement Host', (tester) async {
    final policy = links.RecoveryPolicy();
    final aggregate = await partition.mountMulti(
      tester,
      failurePolicy: policy,
      interceptor: links.CallbackPolicy(
        (context) => context.request.uri.path == '/detail/A'
            ? const CCNavigationCancel(code: 'probe')
            : const CCNavigationProceed(),
      ),
    );
    final old = outcome(CCRouter.navigator.go(const fixture.Intent('A')));
    await tester.pump();
    expect(policy.calls, 1);
    final replacement = await replacePrimary(tester, aggregate);
    policy.decision.complete(
      const CCNavigationFailureRedirect.toIntent(fixture.Intent('B')),
    );
    await tester.pumpAndSettle();
    final result = await old;
    expect(replacement.adapter.requests.map((r) => r.uri.path), ['/']);
    expect(result, isA<CCRouterError>());
  });

  for (final concurrency in [
    CCNavigationConcurrencyPolicy.singleFlight,
    CCNavigationConcurrencyPolicy.rejectDuplicate,
  ]) {
    testWidgets('control: same live Host honors ${concurrency.name}', (
      tester,
    ) async {
      final gate = Completer<CCNavigationInterceptorDecision>();
      var calls = 0;
      final aggregate = await partition.mountMulti(
        tester,
        concurrency: concurrency,
        interceptor: links.CallbackPolicy((context) {
          if (context.request.uri.path != '/detail/A')
            return const CCNavigationProceed();
          calls++;
          return gate.future;
        }),
      );
      final first = outcome(CCRouter.navigator.go(const fixture.Intent('A')));
      await tester.pump();
      final second = outcome(CCRouter.navigator.go(const fixture.Intent('A')));
      await tester.pump();
      gate.complete(const CCNavigationProceed());
      await tester.pumpAndSettle();
      expect(await first, isNull);
      final secondResult = await second;
      expect(calls, 1);
      expect(
        secondResult,
        concurrency == CCNavigationConcurrencyPolicy.singleFlight
            ? isNull
            : isA<CCNavigationDuplicateError>(),
      );
      expect(
        aggregate.backendFor('primary').adapter.requests.single.uri.path,
        '/detail/A',
      );
    });

    testWidgets('new Host request does not share old ${concurrency.name} gate', (
      tester,
    ) async {
      final gate = Completer<CCNavigationInterceptorDecision>();
      var calls = 0;
      final aggregate = await partition.mountMulti(
        tester,
        concurrency: concurrency,
        interceptor: links.CallbackPolicy((context) {
          if (context.request.uri.path != '/detail/A')
            return const CCNavigationProceed();
          calls++;
          return calls == 1 ? gate.future : const CCNavigationProceed();
        }),
      );
      final old = outcome(CCRouter.navigator.go(const fixture.Intent('A')));
      await tester.pump();
      final replacement = await replacePrimary(tester, aggregate);
      final fresh = outcome(CCRouter.navigator.go(const fixture.Intent('A')));
      await tester.pumpAndSettle();
      final independentChecks = calls;
      gate.complete(const CCNavigationCancel(code: 'old_request'));
      await tester.pumpAndSettle();
      final freshResult = await fresh;
      await old;
      debugPrint(
        'replacement gate: policy=${concurrency.name}, calls=$independentChecks, fresh=${freshResult.runtimeType}, path=${replacement.adapter.requests.single.uri.path}',
      );
      expect(
        independentChecks,
        2,
        reason: 'new lifecycle must run its own admission policy',
      );
      expect(freshResult, isNull);
      expect(replacement.adapter.requests.single.uri.path, '/detail/A');
    });
  }
}
