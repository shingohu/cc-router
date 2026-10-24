import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

import 'managed_cross_lifecycle_regression_test.dart' as fixture;

class LinkPolicy implements CCNavigationInterceptor {
  final decision = Completer<CCNavigationInterceptorDecision>();
  bool entered = false;
  CCCancellationToken? cancellation;

  @override
  FutureOr<CCNavigationInterceptorDecision> intercept(
    CCNavigationInterceptorContext context,
  ) {
    if (context.request.uri.path == '/detail/A') {
      entered = true;
      cancellation = context.cancellation;
      return decision.future;
    }
    return const CCNavigationProceed();
  }
}

CCRouteDefinition<String, String> linkDefinition(bool home) =>
    CCRouteDefinition(
      routeId: home ? 'probe.home' : 'probe.detail',
      patterns: [CCPathPattern(home ? '/' : '/detail/:id', primary: true)],
      codec: const fixture.Codec(),
      deepLink: CCDeepLinkPolicy.enabled,
    );

class LinkRegistrar implements CCComponentRegistrar {
  @override
  void register(CCRegistry registry) {
    registry.registerRoute(linkDefinition(true));
    registry.registerRoute(linkDefinition(false));
  }
}

class CallbackPolicy implements CCNavigationInterceptor {
  CallbackPolicy(this.callback);
  final FutureOr<CCNavigationInterceptorDecision> Function(
    CCNavigationInterceptorContext,
  )
  callback;
  @override
  FutureOr<CCNavigationInterceptorDecision> intercept(
    CCNavigationInterceptorContext context,
  ) => callback(context);
}

class RecoveryPolicy implements CCNavigationFailurePolicy {
  final decision = Completer<CCNavigationFailureDecision>();
  int calls = 0;
  @override
  Future<CCNavigationFailureDecision> onFailure(
    CCNavigationFailureContext context,
  ) {
    calls++;
    return decision.future;
  }
}

CCFlutterRouteCatalog linkCatalog() => CCFlutterRouteCatalog(
  [
    for (final def in [linkDefinition(true), linkDefinition(false)])
      CCFlutterRouteDestination.fromDefinition(
        definition: def,
        builder: (v) => Scaffold(body: Text(v.path['id'] ?? 'home')),
      ),
  ],
  componentVersions: {'probe': '1.0.0'},
);

Future<CCManagedRouterBackend> mountLinks(
  WidgetTester tester,
  CCNavigationInterceptor policy, {
  String initialLocation = '/',
  CCNavigationFailurePolicy? failurePolicy,
}) async {
  CCRouterHost.initialize(
    hostAssembly: CCHostAssembly.fromComponents(
      components: [
        CCComponentManifest(
          id: 'probe',
          version: '1.0.0',
          registrar: LinkRegistrar(),
        ),
      ],
    ),
    globalInterceptors: [
      CCGlobalNavigationInterceptor(id: 'probe.policy', interceptor: policy),
    ],
    deepLinkIngressPolicy: CCDeepLinkIngressPolicy(allowRelativePaths: true),
    navigationFailurePolicy: failurePolicy,
  );
  final backend = CCManagedRouterBackend(
    initialLocation: initialLocation,
    routeCatalog: CCFlutterRouteCatalog(
      [
        for (final def in [linkDefinition(true), linkDefinition(false)])
          CCFlutterRouteDestination.fromDefinition(
            definition: def,
            builder: (v) => Scaffold(body: Text(v.path['id'] ?? 'home')),
          ),
      ],
      componentVersions: {'probe': '1.0.0'},
    ),
  );
  await tester.pumpWidget(
    CCRouterApp.managed(
      backend: backend,
      child: MaterialApp.router(routerConfig: backend.routerConfig),
    ),
  );
  await tester.pumpAndSettle();
  return backend;
}

Future<void> platformLocation(
  WidgetTester tester,
  CCManagedRouterBackend backend,
  String path,
) async {
  await (backend.routerConfig.routeInformationProvider!
          as PlatformRouteInformationProvider)
      .didPushRouteInformation(RouteInformation(uri: Uri.parse(path)));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(CCRouterHost.shutdown);

  testWidgets(
    'concurrent maybePop preserves actual result and unique receipt',
    (tester) async {
      final h = await fixture.mount(tester);
      final result = CCRouter.navigator.push(const fixture.Intent('A'));
      await tester.pumpAndSettle();
      final nativeResult = ModalRoute.of(h.contexts['A']!)!.popped;
      final first = CCRouter.navigator.maybePopOutcome(result: 'first');
      final second = CCRouter.navigator.maybePopOutcome(result: 'second');
      final outcomes = await Future.wait([first, second]);
      await tester.pumpAndSettle();
      expect(await nativeResult, 'first');
      expect(await result, 'first');
      expect(h.backend.adapter.requests, hasLength(1));
      expect(
        outcomes.where(
          (o) => o.removedEntryOwner == CCPopRemovedEntryOwner.managed,
        ),
        hasLength(1),
      );
    },
  );

  testWidgets('independent Outlets preserve concurrent results', (
    tester,
  ) async {
    final h = await fixture.mount(tester, panes: true);
    final results = <String, Future<String?>>{};
    for (final side in ['left', 'right']) {
      fixture.ignore(
        CCRouter.navigator.push(fixture.PaneIntent(side, '$side-1')),
      );
      await tester.pumpAndSettle();
      results[side] = CCRouter.navigator.push(
        fixture.PaneIntent(side, '$side-2'),
      );
      await tester.pumpAndSettle();
    }
    final outcomes = await Future.wait([
      for (final side in ['left', 'right'])
        CCRouter.navigator.maybePopOutcome(
          context: h.contexts['$side-2'],
          result: side,
        ),
    ]);
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      final side = ['left', 'right'][i];
      expect(await results[side], side);
      expect(outcomes[i].removedEntryOwner, CCPopRemovedEntryOwner.managed);
      expect(outcomes[i].navigatorOutlet, side);
      expect(h.resources['$side-2']!.disposals, 1);
      expect(h.resources['$side-1']!.disposals, 0);
    }
  });

  for (final interruption in ['pop', 'push', 'close', 'unmount']) {
    testWidgets('waiting maybePop cannot claim $interruption removal', (
      tester,
    ) async {
      final h = await fixture.mount(tester);
      final result = CCRouter.navigator.push(const fixture.Intent('A'));
      await tester.pumpAndSettle();
      final handle = CCRouter.routeEntryHandleOf(h.contexts['A']!)!;
      final route = ModalRoute.of(h.contexts['A']!)!;
      final gate = Completer<bool>();
      var entered = false;
      Future<bool> waitForInterruption() {
        entered = true;
        return gate.future;
      }

      // Exercise Flutter's real asynchronous willPop boundary deterministically.
      // ignore: deprecated_member_use
      route.addScopedWillPopCallback(waitForInterruption);
      final pending = CCRouter.navigator.maybePopOutcome(result: 'waiting');
      await tester.pump();
      expect(entered, isTrue);
      switch (interruption) {
        case 'pop':
          CCRouter.navigator.pop(result: 'explicit');
        case 'push':
          fixture.ignore(CCRouter.navigator.push(const fixture.Intent('B')));
        case 'close':
          await CCRouter.navigator.close(handle, result: 'explicit');
        case 'unmount':
          h.showRoot.value = false;
          await tester.pump();
      }
      await tester.pump();
      gate.complete(true);
      final outcome = await pending;
      await tester.pumpAndSettle();
      expect(outcome.removedEntryOwner, CCPopRemovedEntryOwner.none);
      if (interruption == 'pop' || interruption == 'close') {
        expect(await result, 'explicit');
      } else {
        fixture.ignore(result);
        expect(
          CCRouter.activeRouteEntries.any(
            (e) => e.routeEntryId == handle.routeEntryId,
          ),
          isTrue,
        );
      }
    });
  }

  for (final native in [false, true]) {
    testWidgets('LocalHistory precedes deny Guard (native=$native)', (
      tester,
    ) async {
      final guard = fixture.Guard();
      final h = await fixture.mount(tester, panes: true, guard: guard);
      for (final id in ['L1', 'L2']) {
        fixture.ignore(CCRouter.navigator.push(fixture.PaneIntent('left', id)));
        await tester.pumpAndSettle();
      }
      final context = h.contexts['L2']!;
      final handle = CCRouter.routeEntryHandleOf(context);
      var removed = 0;
      ModalRoute.of(
        context,
      )!.addLocalHistoryEntry(LocalHistoryEntry(onRemove: () => removed++));
      await tester.pumpAndSettle();
      guard.seen.clear();
      if (native) {
        expect(await Navigator.of(context).maybePop(), isTrue);
      } else {
        final outcome = await CCRouter.navigator.maybePopOutcome(
          context: context,
        );
        expect(outcome.removedEntryOwner, CCPopRemovedEntryOwner.none);
        expect(outcome.guardDeniedCode, isNull);
      }
      await tester.pumpAndSettle();
      expect(removed, 1);
      expect(CCRouter.routeEntryHandleOf(context), same(handle));
      expect(h.resources['L2']!.disposals, 0);
      expect(guard.seen, isEmpty);
      expect(
        (await CCRouter.navigator.maybePopOutcome(
          context: context,
        )).guardDeniedCode,
        'left_locked',
      );
    });
  }

  testWidgets('Shell exit gives its result only to the selected branch', (
    tester,
  ) async {
    final h = await fixture.mount(tester, shell: true);
    final left = CCRouter.navigator.push(
      const fixture.PaneIntent('left', 'L1'),
    );
    await tester.pumpAndSettle();
    final right = CCRouter.navigator.push(
      const fixture.PaneIntent('right', 'R1'),
    );
    await tester.pumpAndSettle();
    h.backend.host.navigatorKey.currentState!.pop('right-result');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(await left, isNull);
    expect(await right, 'right-result');
    for (final id in ['L1', 'R1']) {
      expect(find.text('probe-$id', skipOffstage: false), findsOneWidget);
      expect(h.resources[id]!.disposals, 0);
    }
    await tester.pumpAndSettle();
    for (final id in ['L1', 'R1']) {
      expect(h.resources[id]!.disposals, 1);
    }
  });

  for (final shutdown in [false, true]) {
    testWidgets(
      'pending willPop ends on renderer teardown (shutdown=$shutdown)',
      (tester) async {
        final h = await fixture.mount(tester);
        fixture.ignore(CCRouter.navigator.push(const fixture.Intent('A')));
        await tester.pumpAndSettle();
        final route = ModalRoute.of(h.contexts['A']!)!;
        final gate = Completer<bool>();
        // ignore: deprecated_member_use
        route.addScopedWillPopCallback(() => gate.future);
        var completed = false;
        final pending = CCRouter.navigator.maybePopOutcome().whenComplete(() {
          completed = true;
        });
        fixture.ignore(pending);
        await tester.pump();
        if (shutdown) {
          await CCRouterHost.shutdown();
        } else {
          h.showRoot.value = false;
        }
        await tester.pumpAndSettle();
        final completedBeforeUserCode = completed;
        gate.complete(true);
        await tester.pumpAndSettle();
        await pending;
        expect(completedBeforeUserCode, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Shell receipt identifies its actual selected child at Pop', (
    tester,
  ) async {
    final h = await fixture.mount(tester, shell: true);
    final left = CCRouter.navigator.push(
      const fixture.PaneIntent('left', 'L1'),
    );
    await tester.pumpAndSettle();
    final shellRoute = ModalRoute.of(Navigator.of(h.contexts['L1']!).context)!;
    final gate = Completer<bool>();
    // ignore: deprecated_member_use
    shellRoute.addScopedWillPopCallback(() => gate.future);
    final pending = CCRouter.navigator.maybePopOutcome(result: 'selected');
    await tester.pump();
    final right = CCRouter.navigator.push(
      const fixture.PaneIntent('right', 'R1'),
    );
    await tester.pumpAndSettle();
    final rightEntry = CCRouter.activeBackendEntries.singleWhere(
      (entry) => entry.routeId == 'probe.right',
    );
    gate.complete(true);
    final outcome = await pending;
    await tester.pumpAndSettle();
    expect(outcome.removedBackendEntryId, rightEntry.backendEntryId);
    expect(await left, isNull);
    expect(await right, 'selected');
    expect(tester.takeException(), isNull);
  });

  for (final native in [false, true]) {
    testWidgets('Shell exit retains content and child Scope (native=$native)', (
      tester,
    ) async {
      final h = await fixture.mount(tester, shell: true);
      final result = CCRouter.navigator.push(
        const fixture.PaneIntent('left', 'L1'),
      );
      await tester.pumpAndSettle();
      final resource = h.resources['L1']!;
      final shellRoute = ModalRoute.of(
        Navigator.of(h.contexts['L1']!).context,
      )!;
      if (native) {
        h.backend.host.navigatorKey.currentState!.pop('closed');
      } else {
        await CCRouter.navigator.maybePopOutcome(result: 'closed');
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(await result, 'closed');
      expect(shellRoute.animation!.status, AnimationStatus.reverse);
      expect(find.text('probe-L1', skipOffstage: false), findsOneWidget);
      expect(resource.disposals, 0);
      expect(
        CCRouter.routeService<fixture.Resource>(h.contexts['L1']!),
        same(resource),
      );
      await tester.pumpAndSettle();
      expect(resource.disposals, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('LocalHistory removed during wait cannot bypass denied exit', (
    tester,
  ) async {
    final guard = fixture.Guard();
    final h = await fixture.mount(tester, panes: true, guard: guard);
    for (final id in ['L1', 'L2']) {
      fixture.ignore(CCRouter.navigator.push(fixture.PaneIntent('left', id)));
      await tester.pumpAndSettle();
    }
    final context = h.contexts['L2']!;
    final history = LocalHistoryEntry(onRemove: () {});
    ModalRoute.of(context)!.addLocalHistoryEntry(history);
    await tester.pumpAndSettle();
    final pending = CCRouter.navigator.maybePopOutcome(context: context);
    history.remove();
    final outcome = await pending;
    await tester.pumpAndSettle();
    expect(outcome.removedEntryOwner, CCPopRemovedEntryOwner.none);
    expect(h.resources['L2']!.disposals, 0);
    expect(find.text('probe-L2'), findsOneWidget);
    expect(guard.seen, contains('probe.left'));
  });

  for (final action in ['push', 'reenter', 'unmount', 'shutdown']) {
    testWidgets('Shell exit remains bounded when interrupted by $action', (
      tester,
    ) async {
      final h = await fixture.mount(tester, shell: true);
      fixture.ignore(
        CCRouter.navigator.push(const fixture.PaneIntent('left', 'L1')),
      );
      await tester.pumpAndSettle();
      final resource = h.resources['L1']!;
      await CCRouter.navigator.maybePopOutcome();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(resource.disposals, 0);
      switch (action) {
        case 'push':
          fixture.ignore(CCRouter.navigator.push(const fixture.Intent('A')));
        case 'reenter':
          fixture.ignore(
            CCRouter.navigator.push(const fixture.PaneIntent('left', 'L2')),
          );
        case 'unmount':
          h.showRoot.value = false;
        case 'shutdown':
          await CCRouterHost.shutdown();
      }
      await tester.pumpAndSettle();
      expect(resource.disposals, 1);
      if (action == 'reenter') {
        expect(find.text('probe-L2'), findsOneWidget);
        expect(h.resources['L2']!.disposals, 0);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'completed Shell exit releases old Routes while Adapter stays alive',
    (tester) async {
      final h = await fixture.mount(tester, shell: true);
      fixture.ignore(
        CCRouter.navigator.push(const fixture.PaneIntent('left', 'L1')),
      );
      await tester.pumpAndSettle();
      final old = WeakReference(ModalRoute.of(h.contexts['L1']!)!);
      await CCRouter.navigator.maybePopOutcome();
      await tester.pumpAndSettle();
      h.contexts.remove('L1');
      await tester.runAsync(
        () => forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20)),
      );
      expect(old.target, isNull);
      expect(h.backend.adapter.requests, hasLength(1));
    },
  );

  for (final initial in ['/', '/detail/A']) {
    testWidgets('new location supersedes old policy (initial=$initial)', (
      tester,
    ) async {
      final policy = LinkPolicy();
      final backend = await mountLinks(
        tester,
        policy,
        initialLocation: initial,
      );
      if (initial == '/') await platformLocation(tester, backend, '/detail/A');
      expect(policy.entered, isTrue);
      await platformLocation(tester, backend, '/detail/B');
      expect(backend.adapter.requests.single.uri.path, '/detail/B');
      policy.decision.complete(const CCNavigationProceed());
      await tester.pumpAndSettle();
      expect(backend.adapter.requests.single.uri.path, '/detail/B');
      expect(policy.cancellation!.isCancelled, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('same-current location still cancels the old policy', (
    tester,
  ) async {
    final policy = LinkPolicy();
    final backend = await mountLinks(tester, policy);
    await platformLocation(tester, backend, '/detail/A');
    await platformLocation(tester, backend, '/');
    policy.decision.complete(const CCNavigationProceed());
    await tester.pumpAndSettle();
    expect(backend.adapter.requests.single.uri.path, '/');
    expect(policy.cancellation!.isCancelled, isTrue);
  });

  testWidgets('new location cancels an old Failure Policy recovery', (
    tester,
  ) async {
    final recovery = RecoveryPolicy();
    final backend = await mountLinks(
      tester,
      CallbackPolicy((_) => const CCNavigationProceed()),
      failurePolicy: recovery,
    );
    await platformLocation(tester, backend, '/missing');
    expect(recovery.calls, 1);
    await platformLocation(tester, backend, '/detail/B');
    recovery.decision.complete(
      CCNavigationFailureRedirect.toUri(Uri.parse('/detail/A')),
    );
    await tester.pumpAndSettle();
    expect(backend.adapter.requests.single.uri.path, '/detail/B');
    expect(recovery.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late interceptor redirect and cancellation errors stay fenced', (
    tester,
  ) async {
    final gate = Completer<CCNavigationInterceptorDecision>();
    final backend = await mountLinks(
      tester,
      CallbackPolicy((context) {
        if (context.request.uri.path != '/detail/A') {
          return const CCNavigationProceed();
        }
        context.cancellation.addListener(() => throw StateError('cleanup'));
        return gate.future;
      }),
    );
    await platformLocation(tester, backend, '/detail/A');
    await platformLocation(tester, backend, '/detail/B');
    gate.complete(CCNavigationRedirect.toUri(Uri.parse('/detail/C')));
    await tester.pumpAndSettle();
    expect(backend.adapter.requests.single.uri.path, '/detail/B');
    expect(tester.takeException(), isNull);
  });

  testWidgets('platform ingress cancellation remains isolated per Host', (
    tester,
  ) async {
    final policy = LinkPolicy();
    CCRouterHost.initialize(
      hostAssembly: CCHostAssembly.fromComponents(
        components: [
          CCComponentManifest(
            id: 'probe',
            version: '1.0.0',
            registrar: LinkRegistrar(),
          ),
        ],
        routeCatalog: linkCatalog(),
      ),
      globalInterceptors: [
        CCGlobalNavigationInterceptor(id: 'probe.policy', interceptor: policy),
      ],
      deepLinkIngressPolicy: CCDeepLinkIngressPolicy(allowRelativePaths: true),
    );
    final aggregate = CCManagedMultiHostBackend.managed(
      defaultHostId: 'primary',
      hostFactories: {
        for (final id in ['primary', 'secondary'])
          id: (config) => CCManagedRouterBackend(
            routeCatalog: config.catalog,
            host: CCNavigationHost(id: config.hostId),
          ),
      },
    );
    await tester.pumpWidget(
      CCRouterApp.managed(
        backend: aggregate,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              for (final id in ['primary', 'secondary'])
                Expanded(
                  child: MaterialApp.router(
                    routerConfig: aggregate.routerConfigFor(id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final primary = aggregate.backendFor('primary');
    final secondary = aggregate.backendFor('secondary');
    await platformLocation(tester, primary, '/detail/A');
    await platformLocation(tester, secondary, '/detail/B');
    expect(policy.cancellation!.isCancelled, isFalse);
    policy.decision.complete(const CCNavigationProceed());
    await tester.pumpAndSettle();
    expect(primary.adapter.requests.single.uri.path, '/detail/A');
    expect(secondary.adapter.requests.single.uri.path, '/detail/B');
    expect(tester.takeException(), isNull);
  });

  for (final resume in [false, true]) {
    testWidgets('new location cancels deferred replay (resuming=$resume)', (
      tester,
    ) async {
      var calls = 0;
      final gate = Completer<CCNavigationInterceptorDecision>();
      final backend = await mountLinks(
        tester,
        CallbackPolicy((context) {
          if (context.request.uri.path != '/detail/A')
            return const CCNavigationProceed();
          return calls++ == 0 ? const CCNavigationDefer() : gate.future;
        }),
      );
      await platformLocation(tester, backend, '/detail/A');
      final pendingId = CCRouter.pendingNavigations.single.navigationId;
      Future<Object?>? replay;
      if (resume) {
        replay = CCRouter.resumePendingNavigation(pendingId);
        fixture.ignore(replay);
        await tester.pumpAndSettle();
      }
      await platformLocation(tester, backend, '/detail/B');
      expect(CCRouter.pendingNavigations, isEmpty);
      gate.complete(const CCNavigationProceed());
      await tester.pumpAndSettle();
      if (resume)
        await expectLater(replay, throwsA(isA<CCRouteCancelledError>()));
      else
        await expectLater(
          CCRouter.resumePendingNavigation(pendingId),
          throwsA(isA<CCNavigationPendingNotFoundError>()),
        );
      expect(backend.adapter.requests.single.uri.path, '/detail/B');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'shutdown cancels a never-completing platform policy without another frame',
    (tester) async {
      final policy = LinkPolicy();
      final backend = await mountLinks(tester, policy);
      await platformLocation(tester, backend, '/detail/A');
      await CCRouterHost.shutdown();
      expect(policy.cancellation!.isCancelled, isTrue);
      policy.decision.completeError(StateError('late policy failure'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
