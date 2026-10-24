import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

const _primary = 'host.primary';
const _secondary = 'host.secondary';
const _left = 'pane.left';
const _right = 'pane.right';

final class _Codec implements CCRouteCodec<String> {
  const _Codec();
  @override
  String decode(CCRouteCodecValues input) => input.path['value'] ?? 'home';
  @override
  CCRouteCodecValues encode(String arguments) =>
      CCRouteCodecValues(path: {'value': arguments});
}

final class _Intent implements CCRouteIntent<String> {
  const _Intent(this.arguments, {this.routeId = 'probe.detail'});
  @override
  final String arguments;
  @override
  final String routeId;
}

final _definitions = [
  CCRouteDefinition<String, String>(
    routeId: 'probe.home',
    patterns: [CCPathPattern('/', primary: true)],
    codec: const _Codec(),
  ),
  CCRouteDefinition<String, String>(
    routeId: 'probe.detail',
    patterns: [CCPathPattern('/detail/:value', primary: true)],
    codec: const _Codec(),
  ),
  CCRouteDefinition<String, String>(
    routeId: 'probe.fixed',
    patterns: [CCPathPattern('/fixed/:value', primary: true)],
    codec: const _Codec(),
    placement: const CCRoutePlacement(hostId: _primary, navigatorOutlet: _left),
  ),
];

final class _Registrar implements CCComponentRegistrar {
  const _Registrar();
  @override
  void register(CCRegistry registry) {
    for (final route in _definitions) {
      registry.registerRoute(route);
    }
  }
}

final class _Interceptor implements CCNavigationInterceptor {
  _Interceptor(this.decide);
  final FutureOr<CCNavigationInterceptorDecision> Function() decide;
  @override
  FutureOr<CCNavigationInterceptorDecision> intercept(
    CCNavigationInterceptorContext context,
  ) => context.request.routeId == 'probe.detail'
      ? decide()
      : const CCNavigationProceed();
}

final class _Guard implements CCPopGuard {
  bool deny = true;
  @override
  CCPopGuardDecision evaluate(CCPopGuardContext context) =>
      deny ? const CCPopDeny(code: 'test-deny') : const CCPopAllow();
}

/// Captures only clients and weak references, never a live page Context.
final class _Harness {
  _Harness({
    bool includeDefaultHost = false,
    CCNavigationInterceptor? interceptor,
    CCPopGuard? guard,
  }) {
    catalog = CCFlutterRouteCatalog(
      [
        for (final definition in _definitions)
          CCFlutterRouteDestination.fromDefinition(
            definition: definition,
            builder: (values) => Builder(
              builder: (context) {
                final value = values.path['value'] ?? 'home';
                pageContexts[value] = WeakReference(context);
                return Material(child: Text('page-$value'));
              },
            ),
          ),
      ],
      componentVersions: const {'probe': '1.0.0'},
    );
    CCRouterHost.initialize(
      hostAssembly: CCHostAssembly.fromComponents(
        components: const [
          CCComponentManifest(
            id: 'probe',
            version: '1.0.0',
            registrar: _Registrar(),
          ),
        ],
        routeCatalog: catalog,
      ),
      globalInterceptors: [
        if (interceptor != null)
          CCGlobalNavigationInterceptor(
            id: 'test.policy',
            interceptor: interceptor,
          ),
      ],
      globalPopGuards: [
        if (guard != null) CCGlobalPopGuard(id: 'test.guard', guard: guard),
      ],
    );
    aggregate = CCManagedMultiHostBackend.managed(
      defaultHostId: _primary,
      hostFactories: {
        for (final id in [
          _primary,
          _secondary,
          if (includeDefaultHost) 'default',
        ])
          id: (configuration) => createBackend(configuration.hostId),
      },
    );
    for (final id in aggregate.hostIds) {
      children[id] = aggregate.backendFor(id);
    }
  }

  late final CCFlutterRouteCatalog catalog;
  late final CCManagedMultiHostBackend aggregate;
  final children = <String, CCManagedRouterBackend>{};
  final clients = <String, CCNavigator>{};
  final pageContexts = <String, WeakReference<BuildContext>>{};
  bool renderSecondary = true;

  CCManagedRouterBackend createBackend(String id) => CCManagedRouterBackend(
    routeCatalog: CCRouterHostBinding.routeCatalog,
    host: CCNavigationHost(
      id: id,
      navigatorKeys: {
        _left: GlobalKey<NavigatorState>(),
        _right: GlobalKey<NavigatorState>(),
      },
    ),
    overridePlatformDefaultLocation: true,
  );

  Widget app() => CCRouterApp.managed(
    backend: aggregate,
    child: MaterialApp(
      home: Row(
        children: [
          for (final id in children.keys)
            if (id != _secondary || renderSecondary)
              Expanded(
                child: id == _primary
                    ? surface(id)
                    : CCRouterApp(host: children[id]!.host, child: surface(id)),
              ),
        ],
      ),
    ),
  );

  Widget surface(String id) => Column(
    children: [
      Expanded(child: Router.withConfig(config: children[id]!.routerConfig)),
      for (final outlet in [_left, _right])
        Expanded(
          child: CCManagedOutlet(
            backend: children[id]!,
            outlet: outlet,
            baseBuilder: (context) {
              clients['$id/$outlet'] = CCRouter.navigatorOf(context);
              return Material(child: Text('base-$id-$outlet'));
            },
          ),
        ),
    ],
  );
}

void _ignore(Future<Object?> future) {
  unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
}

Matcher get _retired => isA<CCRouteCancelledError>().having(
  (error) => error.code,
  'code',
  'host_detached',
);

void main() {
  tearDown(CCRouterHost.shutdown);

  testWidgets('a real Host named default stays bound while another is active', (
    tester,
  ) async {
    final gate = Completer<CCNavigationInterceptorDecision>();
    final h = _Harness(
      includeDefaultHost: true,
      interceptor: _Interceptor(() => gate.future),
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final client = h.clients['default/$_right']!;
    h.aggregate.adapter.activateHost(_secondary);
    final result = client.push(const _Intent('literal-default'));
    _ignore(result);
    await tester.pumpAndSettle();
    h.aggregate.adapter.activateHost(_primary);
    gate.complete(const CCNavigationProceed());
    await tester.pumpAndSettle();
    expect(CCRouter.activeRouteEntries.last.hostId, 'default');
    expect(CCRouter.activeRouteEntries.last.placement.navigatorOutlet, _right);
    client.pop(result: 'done');
    await tester.pumpAndSettle();
    expect(await result, 'done');
  });

  for (final host in [_primary, _secondary]) {
    for (final outlet in [_left, _right]) {
      testWidgets('bound push/pop ignores focus: $host/$outlet', (
        tester,
      ) async {
        final h = _Harness();
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
        final client = h.clients['$host/$outlet']!;
        final ready = Completer<void>();
        final result = ready.future.then(
          (_) => client.push(const _Intent('delayed')),
        );
        h.aggregate.adapter.activateHost(
          host == _primary ? _secondary : _primary,
        );
        ready.complete();
        await tester.pumpAndSettle();
        final entry = CCRouter.activeRouteEntries.last;
        expect(entry.hostId, host);
        expect(entry.placement.navigatorOutlet, outlet);
        expect(client.canPop(), isTrue);
        client.pop(result: 'done');
        await tester.pumpAndSettle();
        expect(await result, 'done');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('all bound operations share placement and typed results', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final client = h.clients['$_secondary/$_right']!;
    // Global/default navigation still targets primary root.
    final global = CCRouter.navigator.push(const _Intent('global'));
    await tester.pumpAndSettle();
    expect(CCRouter.activeRouteEntries.last.hostId, _primary);
    expect(CCRouter.activeRouteEntries.last.placement.navigatorOutlet, 'root');
    CCRouter.navigator.pop(result: 'global-done');
    await tester.pumpAndSettle();
    expect(await global, 'global-done');

    final first = client.push(const _Intent('first'));
    _ignore(first);
    await tester.pumpAndSettle();
    final replaced = client.replace(const _Intent('replaced'));
    await tester.pumpAndSettle();
    final maybe = client.maybePop(result: 'replace-done');
    await tester.pumpAndSettle();
    expect(await maybe, isTrue);
    expect(await replaced, 'replace-done');

    for (final mode in ['go', 'reset', 'open']) {
      final completion = switch (mode) {
        'go' => client.go(_Intent(mode)),
        'reset' => client.reset(_Intent(mode)),
        _ => client.open(Uri.parse('/detail/$mode')),
      };
      await tester.pumpAndSettle();
      await completion;
      final entry = CCRouter.activeRouteEntries.lastWhere(
        (entry) => entry.routeId == 'probe.detail',
      );
      expect(entry.hostId, _secondary);
      expect(entry.placement.navigatorOutlet, _right);
    }
    final outcome = client.maybePopOutcome(result: 'open-done');
    await tester.pumpAndSettle();
    expect((await outcome).handled, isTrue);

    final closing = client.push(const _Intent('closing'));
    await tester.pumpAndSettle();
    final handle = CCRouter.routeEntryHandleOf(
      h.pageContexts['closing']!.target!,
    )!;
    expect(
      (await client.close(handle, result: 'closed')).status,
      CCRouteCloseStatus.closed,
    );
    await tester.pumpAndSettle();
    expect(await closing, 'closed');
    expect(tester.takeException(), isNull);
  });

  for (final defer in [false, true]) {
    testWidgets('bound target survives async policy and resume: defer=$defer', (
      tester,
    ) async {
      var allow = false;
      final gate = Completer<CCNavigationInterceptorDecision>();
      final h = _Harness(
        interceptor: _Interceptor(() {
          if (allow) return const CCNavigationProceed();
          return defer ? const CCNavigationDefer() : gate.future;
        }),
      );
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      final client = h.clients['$_secondary/$_right']!;
      final result = client.push(const _Intent('policy'));
      await tester.pumpAndSettle();
      h.aggregate.adapter.activateHost(_primary);
      allow = true;
      Future<Object?>? resume;
      if (defer) {
        resume = CCRouter.resumePendingNavigation(
          CCRouter.pendingNavigations.single.navigationId,
        );
      } else {
        gate.complete(const CCNavigationProceed());
      }
      await tester.pumpAndSettle();
      expect(CCRouter.activeRouteEntries.last.hostId, _secondary);
      expect(
        CCRouter.activeRouteEntries.last.placement.navigatorOutlet,
        _right,
      );
      client.pop(result: 'policy-done');
      await tester.pumpAndSettle();
      expect(await result, 'policy-done');
      if (resume != null) expect(await resume, 'policy-done');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('bound Back respects root popup, LocalHistory and PopGuard', (
    tester,
  ) async {
    final guard = _Guard();
    final h = _Harness(guard: guard);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final client = h.clients['$_secondary/$_right']!;
    final result = client.push(const _Intent('guarded'));
    await tester.pumpAndSettle();
    final context = h.pageContexts['guarded']!.target!;
    var historyRemoved = false;
    ModalRoute.of(context)!.addLocalHistoryEntry(
      LocalHistoryEntry(onRemove: () => historyRemoved = true),
    );
    final history = client.maybePop();
    await tester.pumpAndSettle();
    expect(await history, isTrue);
    expect(historyRemoved, isTrue);
    final popup = DialogRoute<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('foreign-popup')),
    );
    unawaited(
      h.children[_secondary]!.host.navigatorKey.currentState!.push(popup),
    );
    await tester.pumpAndSettle();
    h.aggregate.adapter.activateHost(_primary);
    final dismiss = client.maybePopOutcome();
    await tester.pumpAndSettle();
    final outcome = await dismiss;
    expect(outcome.handled, isTrue);
    expect(outcome.navigatorOutlet, 'root');
    expect(find.text('foreign-popup'), findsNothing);
    final denied = client.maybePop();
    await tester.pumpAndSettle();
    expect(await denied, isTrue); // handled by the denial, without removal
    expect(find.text('page-guarded'), findsOneWidget);
    guard.deny = false;
    client.pop(result: 'allowed');
    await tester.pumpAndSettle();
    expect(await result, 'allowed');
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit destination wins; conflicting Context is rejected', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final client = h.clients['$_secondary/$_right']!;
    final fixed = client.push(const _Intent('fixed', routeId: 'probe.fixed'));
    await tester.pumpAndSettle();
    expect(CCRouter.activeRouteEntries.last.hostId, _primary);
    expect(CCRouter.activeRouteEntries.last.placement.navigatorOutlet, _left);
    final fixedContext = h.pageContexts['fixed']!.target!;
    expect(
      () => client.push(const _Intent('wrong'), context: fixedContext),
      throwsA(isA<CCNavigationOutletResolutionError>()),
    );
    expect(
      () => client.pop(context: fixedContext),
      throwsA(isA<CCNavigationOutletResolutionError>()),
    );
    final sameClient = CCRouter.navigatorOf(fixedContext);
    expect(sameClient.canPop(context: fixedContext), isTrue);
    sameClient.pop(result: 'fixed-done', context: fixedContext);
    await tester.pumpAndSettle();
    expect(await fixed, 'fixed-done');
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-ID replacement permanently retires every old operation', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final stale = h.clients['$_secondary/$_right']!;
    h.renderSecondary = false;
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    h.aggregate.adapter.unregisterHost(_secondary);
    final replacement = h.createBackend(_secondary);
    addTearDown(replacement.dispose);
    h.aggregate.adapter.registerHost(_secondary, replacement.adapter);
    h.children[_secondary] = replacement;
    h.renderSecondary = true;
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    for (final operation in <Object? Function()>[
      () => stale.push(const _Intent('stale')),
      () => stale.replace(const _Intent('stale')),
      () => stale.go(const _Intent('stale')),
      () => stale.reset(const _Intent('stale')),
      () => stale.open(Uri.parse('/detail/stale')),
      () => stale.pop(),
      () => stale.maybePop(),
      () => stale.maybePopOutcome(),
      () => stale.canPop(),
    ]) {
      expect(operation, throwsA(_retired));
    }
    final fresh = h.clients['$_secondary/$_right']!;
    final result = fresh.push(const _Intent('fresh'));
    await tester.pumpAndSettle();
    final handle = CCRouter.activeRouteEntries.last.handle!;
    expect(() => stale.close(handle), throwsA(_retired));
    expect(CCRouter.activeRouteEntries.last.hostId, _secondary);
    fresh.pop(result: 'fresh-done');
    await tester.pumpAndSettle();
    expect(await result, 'fresh-done');
    expect(
      replacement.adapter.requests.any((r) => r.uri.path.contains('stale')),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('retained client does not retain removed page Context', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final initial = h.clients['$_secondary/$_right']!;
    final result = initial.push(const _Intent('collectable'));
    await tester.pumpAndSettle();
    final (client, contextRef) = _capture(h);
    client.pop(result: 'done');
    await tester.pumpAndSettle();
    expect(await result, 'done');
    await tester.runAsync(() async {
      await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
    });
    expect(contextRef.target, isNull);
    // A client belongs to the Host registration, not the removed page.
    final next = client.push(const _Intent('still-live'));
    await tester.pumpAndSettle();
    client.pop(result: 'next-done');
    await tester.pumpAndSettle();
    expect(await next, 'next-done');

    await tester.pumpWidget(const SizedBox.shrink());
    await CCRouterHost.shutdown();
    expect(() => client.canPop(), throwsA(_retired));
    // A new Runtime, even with the same IDs, cannot revive the client.
    final replacement = _Harness();
    await tester.pumpWidget(replacement.app());
    await tester.pumpAndSettle();
    expect(
      () => client.push(const _Intent('wrong-runtime')),
      throwsA(_retired),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('retained client releases ended Runtime, Adapter and Navigator', (
    tester,
  ) async {
    final (client, references) = await _retireIsolatedClient(tester);
    await tester.runAsync(() async {
      await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
    });
    for (final reference in references) {
      expect(reference.target, isNull);
    }
    expect(() => client.canPop(), throwsA(_retired));
  });

  testWidgets(
    'navigatorOf rejects a Context outside the registered Navigator',
    (tester) async {
      final h = _Harness();
      BuildContext? outer;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            outer = context;
            return h.app();
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(() => CCRouter.navigatorOf(outer!), throwsFlutterError);
      final unregistered = tester.element(find.byType(Row).first);
      expect(
        () => CCRouter.navigatorOf(unregistered),
        throwsA(isA<CCNavigationOutletResolutionError>()),
      );
    },
  );
}

(CCNavigator, WeakReference<BuildContext>) _capture(_Harness harness) {
  final context = harness.pageContexts['collectable']!.target!;
  return (CCRouter.navigatorOf(context), WeakReference(context));
}

Future<(CCNavigator, List<WeakReference<Object>>)> _retireIsolatedClient(
  WidgetTester tester,
) async {
  final host = CCNavigationHost(
    id: _primary,
    navigatorKeys: {_left: GlobalKey<NavigatorState>()},
  );
  final adapter = CCManagedNavigationAdapter(
    catalog: CCFlutterRouteCatalog(const []),
    host: host,
  );
  final testHost = CCRouterTestHost(navigationAdapter: adapter);
  testHost.initialize();
  final pageKey = GlobalKey();
  // Only acquisition runs in the overlay. Scheduling Flutter frames there
  // would itself retain the test Runtime in Flutter's frame callback Zones.
  await tester.pumpWidget(
    CCRouterApp(
      host: host,
      child: MaterialApp(
        home: Navigator(
          key: host.navigatorKey,
          onGenerateRoute: (_) =>
              MaterialPageRoute<void>(builder: (_) => SizedBox(key: pageKey)),
        ),
      ),
    ),
  );
  final client = testHost.run(
    () => CCRouter.navigatorOf(pageKey.currentContext!),
  );
  final references = <WeakReference<Object>>[
    WeakReference(testHost.runtime),
    WeakReference(adapter),
    WeakReference(host.navigatorKey.currentState!),
  ];
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await testHost.dispose();
  return (client, references);
}
