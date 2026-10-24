import 'dart:async';
import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_test/ccrouter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

final class Resource implements CCDisposable {
  int disposals = 0;
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

final class Codec implements CCRouteCodec<String> {
  const Codec();
  @override
  String decode(CCRouteCodecValues input) => input.path['id'] ?? 'home';
  @override
  CCRouteCodecValues encode(String id) => id == 'home'
      ? CCRouteCodecValues()
      : CCRouteCodecValues(path: {'id': id});
}

CCRouteDefinition<String, String> definition(bool home) => CCRouteDefinition(
  routeId: home ? 'probe.home' : 'probe.detail',
  patterns: [CCPathPattern(home ? '/' : '/detail/:id', primary: true)],
  codec: const Codec(),
);

final class Registrar implements CCComponentRegistrar {
  const Registrar({this.includeShell = false});
  final bool includeShell;

  @override
  void register(CCRegistry registry) {
    registry.registerRoute(definition(true));
    registry.registerRoute(definition(false));
    registry.registerRoute(paneDefinition('left', shell: includeShell));
    registry.registerRoute(paneDefinition('right', shell: includeShell));
    if (includeShell) {
      registry.registerShell(
        CCShellDefinition(
          shellId: 'probe.shell',
          type: CCShellType.statefulBranches,
          outlets: const ['left', 'right'],
          initialOutlet: 'left',
        ),
      );
    }
    registry.registerService<Resource>(
      CCServiceProvider(
        scope: CCServiceScope.route,
        factory: (_) => Resource(),
      ),
    );
  }
}

CCRouteDefinition<String, String> paneDefinition(
  String side, {
  bool shell = false,
}) => CCRouteDefinition(
  routeId: 'probe.$side',
  patterns: [CCPathPattern('/$side/:id', primary: true)],
  codec: const Codec(),
  placement: CCRoutePlacement(
    shellId: shell ? 'probe.shell' : null,
    navigatorOutlet: side,
  ),
);

final class PaneIntent implements CCRouteIntent<String> {
  const PaneIntent(this.side, this.id);
  final String side;
  final String id;
  @override
  String get routeId => 'probe.$side';
  @override
  Object get arguments => id;
}

final class Guard implements CCPopGuard {
  final seen = <String>[];
  @override
  CCPopGuardDecision evaluate(CCPopGuardContext context) {
    seen.add(context.entry.routeId);
    return context.entry.routeId == 'probe.left'
        ? const CCPopDeny(code: 'left_locked')
        : const CCPopAllow();
  }
}

final class Intent implements CCRouteIntent<String> {
  const Intent(this.id);
  final String id;
  @override
  String get routeId => id == 'home' ? 'probe.home' : 'probe.detail';
  @override
  Object get arguments => id;
}

final class Harness {
  final contexts = <String, BuildContext>{};
  final resources = <String, Resource>{};
  final showPanes = ValueNotifier<bool>(true);
  final showRoot = ValueNotifier<bool>(true);
  final reversePanes = ValueNotifier<bool>(false);
  late final CCManagedRouterBackend backend;
}

Future<Harness> mount(
  WidgetTester tester, {
  bool panes = false,
  bool shell = false,
  Guard? guard,
}) async {
  CCRouterHost.initialize(
    hostAssembly: CCHostAssembly.fromComponents(
      components: [
        CCComponentManifest(
          id: 'probe',
          version: '1.0.0',
          registrar: Registrar(includeShell: shell),
        ),
      ],
    ),
    globalPopGuards: guard == null
        ? []
        : [CCGlobalPopGuard(id: 'probe.guard', guard: guard)],
  );
  final h = Harness();
  addTearDown(h.showPanes.dispose);
  addTearDown(h.showRoot.dispose);
  addTearDown(h.reversePanes.dispose);
  h.backend = CCManagedRouterBackend(
    routeCatalog: CCFlutterRouteCatalog(
      [
        for (final def in [
          definition(true),
          definition(false),
          paneDefinition('left', shell: shell),
          paneDefinition('right', shell: shell),
        ])
          CCFlutterRouteDestination.fromDefinition(
            definition: def,
            builder: (values) => Builder(
              builder: (context) {
                final id = values.path['id'] ?? 'home';
                h.contexts[id] = context;
                ModalRoute.of(context);
                h.resources[id] = CCRouter.routeService<Resource>(context);
                return Scaffold(
                  appBar: AppBar(title: Text('title-$id')),
                  body: Text('probe-$id'),
                );
              },
            ),
          ),
      ],
      componentVersions: const {'probe': '1.0.0'},
    ),
    host: CCNavigationHost(
      id: 'default',
      navigatorKeys: {
        'left': GlobalKey<NavigatorState>(),
        'right': GlobalKey<NavigatorState>(),
      },
    ),
    shellBindings: [
      if (shell)
        CCManagedShellBinding(
          shellId: 'probe.shell',
          builder: (_, scope) => ValueListenableBuilder<bool>(
            valueListenable: h.showPanes,
            builder: (_, show, _) => show
                ? Row(
                    children: [
                      for (final side in ['left', 'right'])
                        Expanded(child: scope.navigatorFor(side)),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ),
    ],
  );
  await tester.pumpWidget(
    CCRouterApp.managed(
      backend: h.backend,
      child: MaterialApp.router(
        theme: ThemeData(platform: TargetPlatform.iOS),
        routerConfig: h.backend.routerConfig,
        builder: panes
            ? (_, child) => ValueListenableBuilder<bool>(
                valueListenable: h.showPanes,
                builder: (_, show, _) => ValueListenableBuilder<bool>(
                  valueListenable: h.reversePanes,
                  builder: (_, reverse, _) => Row(
                    children: [
                      Expanded(child: child!),
                      if (show)
                        for (final side
                            in reverse ? ['right', 'left'] : ['left', 'right'])
                          Expanded(
                            child: CCManagedOutlet(
                              backend: h.backend,
                              outlet: side,
                            ),
                          ),
                    ],
                  ),
                ),
              )
            : (_, child) => ValueListenableBuilder<bool>(
                valueListenable: h.showRoot,
                builder: (_, show, _) =>
                    show ? child! : const SizedBox.shrink(),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

void ignore(Future<Object?> result) {
  unawaited(result.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
}

WeakReference<Route<dynamic>> pushWeakPopup(BuildContext context) {
  final route = DialogRoute<void>(
    context: context,
    builder: (_) => const AlertDialog(content: Text('weak-popup')),
  );
  unawaited(Navigator.of(context).push(route));
  return WeakReference<Route<dynamic>>(route);
}

void main() {
  tearDown(CCRouterHost.shutdown);
  testWidgets(
    'same-frame pane reparent preserves live popup and native Guard',
    (tester) async {
      final h = await mount(tester, panes: true, guard: Guard());
      for (final intent in [
        const PaneIntent('left', 'L1'),
        const PaneIntent('left', 'L2'),
        const PaneIntent('right', 'R1'),
      ]) {
        ignore(CCRouter.navigator.push(intent));
        await tester.pumpAndSettle();
      }
      final route = ModalRoute.of(h.contexts['L2']!)! as PageRoute<Object?>;
      final handle = CCRouter.routeEntryHandleOf(h.contexts['L2']!)!;
      final popup = DialogRoute<void>(
        context: h.contexts['L2']!,
        builder: (_) => const AlertDialog(content: Text('moving-popup')),
      );
      unawaited(Navigator.of(h.contexts['L2']!).push(popup));
      await tester.pumpAndSettle();
      h.reversePanes.value = true;
      await tester.pumpAndSettle();
      expect(find.text('moving-popup'), findsOneWidget);
      expect(
        CCRouter.activeBackendEntries.where(
          (entry) => entry.owner == CCBackendEntryOwner.foreign,
        ),
        hasLength(1),
      );
      popup.navigator!.pop();
      await tester.pumpAndSettle();
      expect(ModalRoute.of(h.contexts['L2']!), same(route));
      expect(CCRouter.routeEntryHandleOf(h.contexts['L2']!), same(handle));
      expect(route.popGestureEnabled, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Shell renderer remount preserves both retained branch identities',
    (tester) async {
      final h = await mount(tester, shell: true, guard: Guard());
      final result = CCRouter.navigator.push(const PaneIntent('left', 'L1'));
      ignore(result);
      await tester.pumpAndSettle();
      final handle = CCRouter.routeEntryHandleOf(h.contexts['L1']!)!;
      final leftResource = h.resources['L1']!;
      ignore(CCRouter.navigator.push(const PaneIntent('right', 'R1')));
      await tester.pumpAndSettle();
      final rightHandle = CCRouter.routeEntryHandleOf(h.contexts['R1']!)!;
      final rightResource = h.resources['R1']!;
      pushWeakPopup(h.contexts['L1']!);
      await tester.pumpAndSettle();
      h.showPanes.value = false;
      await tester.pumpAndSettle();
      expect(leftResource.disposals, 0);
      expect(rightResource.disposals, 0);
      h.showPanes.value = true;
      await tester.pumpAndSettle();
      expect(CCRouter.routeEntryHandleOf(h.contexts['L1']!), same(handle));
      expect(CCRouter.routeEntryHandleOf(h.contexts['R1']!), same(rightHandle));
      expect(h.resources['L1'], same(leftResource));
      expect(h.resources['R1'], same(rightResource));
      expect(
        CCRouter.activeBackendEntries.where(
          (entry) => entry.owner == CCBackendEntryOwner.foreign,
        ),
        isEmpty,
      );
      Navigator.of(h.contexts['L1']!).pop('shell-done');
      await tester.pumpAndSettle();
      expect(await result, 'shell-done');
      expect(leftResource.disposals, 1);
      expect(rightResource.disposals, 0);
      expect(CCRouter.routeEntryHandleOf(h.contexts['R1']!), same(rightHandle));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('live Adapter releases old Routes after renderer remount', (
    tester,
  ) async {
    final h = await mount(tester, panes: true, guard: Guard());
    ignore(CCRouter.navigator.push(const PaneIntent('left', 'L1')));
    await tester.pumpAndSettle();
    final managed = WeakReference(ModalRoute.of(h.contexts['L1']!)!);
    final foreign = pushWeakPopup(h.contexts['L1']!);
    await tester.pumpAndSettle();
    h.showPanes.value = false;
    await tester.pumpAndSettle();
    h.showPanes.value = true;
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20)),
    );
    expect(managed.target, isNull);
    expect(foreign.target, isNull);
    expect(
      h.backend.adapter.requests.where(
        (request) => request.routeId == 'probe.left',
      ),
      hasLength(1),
    );
  });

  testWidgets('native Back and predictive policy stay in an inactive Host', (
    tester,
  ) async {
    final contexts = <String, BuildContext>{};
    final guard = Guard();
    final catalog = CCFlutterRouteCatalog(
      [
        for (final def in [
          definition(true),
          definition(false),
          paneDefinition('left'),
          paneDefinition('right'),
        ])
          CCFlutterRouteDestination.fromDefinition(
            definition: def,
            builder: (values) => Builder(
              builder: (context) {
                final id = values.path['id'] ?? 'home';
                contexts[id] = context;
                return Scaffold(
                  appBar: AppBar(title: Text('multi-$id')),
                  body: Text('body-$id'),
                );
              },
            ),
          ),
      ],
      componentVersions: const {'probe': '1.0.0'},
    );
    CCRouterHost.initialize(
      hostAssembly: CCHostAssembly.fromComponents(
        components: [
          CCComponentManifest(
            id: 'probe',
            version: '1.0.0',
            registrar: Registrar(),
          ),
        ],
        routeCatalog: catalog,
      ),
      globalPopGuards: [CCGlobalPopGuard(id: 'probe.guard', guard: guard)],
    );
    final aggregate = CCManagedMultiHostBackend.managed(
      defaultHostId: 'primary',
      hostFactories: {
        for (final id in ['primary', 'secondary'])
          id: (config) => CCManagedRouterBackend(
            routeCatalog: config.catalog,
            host: CCNavigationHost(
              id: config.hostId,
              navigatorKeys: {
                'left': GlobalKey<NavigatorState>(),
                'right': GlobalKey<NavigatorState>(),
              },
            ),
            enablePredictiveBack: true,
            initializeFromRouteInformation: config.isDefaultHost,
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
                  child: Builder(
                    builder: (_) {
                      final app = MaterialApp.router(
                        theme: ThemeData(platform: TargetPlatform.iOS),
                        routerConfig: aggregate.routerConfigFor(id),
                        builder: (_, root) => Row(
                          children: [
                            Expanded(child: root!),
                            for (final side in ['left', 'right'])
                              Expanded(
                                child: CCManagedOutlet(
                                  backend: aggregate.backendFor(id),
                                  outlet: side,
                                ),
                              ),
                          ],
                        ),
                      );
                      return id == 'primary'
                          ? app
                          : CCRouterApp(
                              host: aggregate.hostFor(id),
                              child: app,
                            );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final id in ['L1', 'L2']) {
      ignore(CCRouter.navigator.push(PaneIntent('left', id)));
      await tester.pumpAndSettle();
    }
    aggregate.adapter.activateHost('secondary');
    ignore(CCRouter.navigator.push(const PaneIntent('right', 'R1')));
    await tester.pumpAndSettle();
    aggregate.adapter.setActiveOutlets(hostId: 'primary', outlets: ['left']);
    aggregate.adapter.setActiveOutlets(hostId: 'secondary', outlets: ['right']);
    await tester.pumpAndSettle();
    guard.seen.clear();
    final route = ModalRoute.of(contexts['L2']!)! as PageRoute<Object?>;
    expect(route.popGestureEnabled, isFalse);
    expect(
      aggregate
          .backendFor('primary')
          .adapter
          .predictiveBackBridge!
          .evaluateStart(),
      isA<CCPopDeny>(),
    );
    final appBar = find.ancestor(
      of: find.text('multi-L2'),
      matching: find.byType(AppBar),
    );
    tester
        .widget<IconButton>(
          find.descendant(of: appBar, matching: find.byType(IconButton)),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(guard.seen, isNotEmpty);
    expect(guard.seen, everyElement('probe.left'));
    expect(aggregate.adapter.activeHostId, 'secondary');
    expect(
      aggregate
          .backendFor('primary')
          .adapter
          .requests
          .where((entry) => entry.routeId == 'probe.left'),
      hasLength(2),
    );
    expect(aggregate.backendFor('secondary').adapter.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'repeated pane remount preserves Scope, result and exact identity',
    (tester) async {
      final h = await mount(tester, panes: true, guard: Guard());
      ignore(CCRouter.navigator.push(const PaneIntent('right', 'R0')));
      await tester.pumpAndSettle();
      final result = CCRouter.navigator.push(const PaneIntent('right', 'R1'));
      ignore(result);
      await tester.pumpAndSettle();
      final handle = CCRouter.routeEntryHandleOf(h.contexts['R1']!)!;
      final resource = h.resources['R1']!;
      var completed = false;
      unawaited(result.then((_) => completed = true));
      for (var i = 0; i < 4; i++) {
        unawaited(
          Navigator.of(h.contexts['R1']!).push(
            DialogRoute<void>(
              context: h.contexts['R1']!,
              builder: (_) =>
                  const AlertDialog(content: Text('retiring-popup')),
            ),
          ),
        );
        await tester.pump();
        h.showPanes.value = false;
        await tester.pumpAndSettle();
        expect(resource.disposals, 0);
        expect(completed, isFalse);
        expect(
          CCRouter.activeBackendEntries.where(
            (entry) => entry.owner == CCBackendEntryOwner.foreign,
          ),
          isEmpty,
        );
        h.showPanes.value = true;
        await tester.pumpAndSettle();
        expect(CCRouter.routeEntryHandleOf(h.contexts['R1']!), same(handle));
        expect(h.resources['R1'], same(resource));
        expect(
          CCRouter.activeBackendEntries.where(
            (entry) => entry.owner == CCBackendEntryOwner.foreign,
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      }
      final appBar = find.ancestor(
        of: find.text('title-R1'),
        matching: find.byType(AppBar),
      );
      tester
          .widget<IconButton>(
            find.descendant(of: appBar, matching: find.byType(IconButton)),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(resource.disposals, 1);
    },
  );

  testWidgets('root renderer remount also preserves its logical Entry', (
    tester,
  ) async {
    final h = await mount(tester);
    final result = CCRouter.navigator.push(const Intent('A'));
    ignore(result);
    await tester.pumpAndSettle();
    final handle = CCRouter.routeEntryHandleOf(h.contexts['A']!)!;
    final resource = h.resources['A']!;
    unawaited(
      Navigator.of(h.contexts['A']!).push(
        DialogRoute<void>(
          context: h.contexts['A']!,
          builder: (_) => const AlertDialog(content: Text('root-popup')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    h.showRoot.value = false;
    await tester.pumpAndSettle();
    expect(resource.disposals, 0);
    expect(
      CCRouter.activeBackendEntries.where(
        (entry) => entry.owner == CCBackendEntryOwner.foreign,
      ),
      isEmpty,
    );
    h.showRoot.value = true;
    await tester.pumpAndSettle();
    expect(CCRouter.routeEntryHandleOf(h.contexts['A']!), same(handle));
    expect(h.resources['A'], same(resource));
    Navigator.of(h.contexts['A']!).pop('remounted');
    await tester.pumpAndSettle();
    expect(await result, 'remounted');
    expect(resource.disposals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('native Pop then shutdown closes Scope without another frame', (
    tester,
  ) async {
    final h = await mount(tester);
    final result = CCRouter.navigator.push(const Intent('A'));
    ignore(result);
    await tester.pumpAndSettle();
    final resource = h.resources['A']!;
    Navigator.of(h.contexts['A']!).pop('done');
    await tester.pump();
    expect(await result, 'done');
    expect(resource.disposals, 0);
    await CCRouterHost.shutdown();
    expect(resource.disposals, 1);
    await tester.pumpAndSettle();
    expect(resource.disposals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Outlet unmount retires its foreign ledger before remount', (
    tester,
  ) async {
    final h = await mount(tester, panes: true);
    ignore(CCRouter.navigator.push(const PaneIntent('left', 'L1')));
    await tester.pumpAndSettle();
    final handle = CCRouter.routeEntryHandleOf(h.contexts['L1']!)!;
    final popup = DialogRoute<void>(
      context: h.contexts['L1']!,
      builder: (_) => const AlertDialog(content: Text('local-popup')),
    );
    unawaited(Navigator.of(h.contexts['L1']!).push(popup));
    await tester.pumpAndSettle();
    h.showPanes.value = false;
    await tester.pumpAndSettle();
    h.showPanes.value = true;
    await tester.pumpAndSettle();
    final staleForeign = CCRouter.activeBackendEntries
        .where((e) => e.owner == CCBackendEntryOwner.foreign)
        .length;
    expect(
      (await CCRouter.navigator.close(handle)).status,
      CCRouteCloseStatus.closed,
    );
    await tester.pumpAndSettle();
    ignore(CCRouter.navigator.push(const PaneIntent('left', 'L2')));
    await tester.pumpAndSettle();
    final navigator = h.backend.host.navigatorKeyFor('left').currentState!;
    expect(
      staleForeign,
      0,
      reason: 'disposed foreign popup must not stay active',
    );
    expect(navigator.widget.pages, hasLength(1));
    expect(navigator.canPop(), isFalse);
  });
  testWidgets('ordinary maybePop leaves backend synchronization healthy', (
    tester,
  ) async {
    final backend = CCManagedRouterBackend(
      routeCatalog: CCFlutterRouteCatalog(
        [
          for (final def in [
            definition(true),
            definition(false),
            paneDefinition('left'),
            paneDefinition('right'),
          ])
            CCFlutterRouteDestination.fromDefinition(
              definition: def,
              builder: (_) => const Text('sync-probe'),
            ),
        ],
        componentVersions: const {'probe': '1.0.0'},
      ),
      host: CCNavigationHost(
        navigatorKeys: {
          'left': GlobalKey<NavigatorState>(),
          'right': GlobalKey<NavigatorState>(),
        },
      ),
    );
    final host = CCRouterTestHost(
      components: [
        CCComponentManifest(
          id: 'probe',
          version: '1.0.0',
          registrar: Registrar(),
        ),
      ],
      navigationAdapter: backend.adapter,
    );
    host.initialize();
    addTearDown(host.dispose);
    addTearDown(backend.dispose);
    await host.run(() async {
      await tester.pumpWidget(
        CCRouterApp(
          host: backend.host,
          child: MaterialApp.router(routerConfig: backend.routerConfig),
        ),
      );
      await tester.pumpAndSettle();
      ignore(CCRouter.navigator.push<String>(const Intent('A')));
      await tester.pumpAndSettle();
      final outcome = await CCRouter.navigator.maybePopOutcome();
      await tester.pumpAndSettle();
      expect(outcome.removedEntryOwner, CCPopRemovedEntryOwner.managed);
      expect(host.runtime.desynchronizedBackendHosts, isEmpty);
      expect(backend.adapter.requests, hasLength(1));
    });
  });
  testWidgets('Back follows the sole visible pane after folding', (
    tester,
  ) async {
    final h = await mount(tester, panes: true);
    for (final intent in [
      const PaneIntent('left', 'L1'),
      const PaneIntent('left', 'L2'),
      const PaneIntent('right', 'R1'),
    ]) {
      ignore(CCRouter.navigator.push(intent));
      await tester.pumpAndSettle();
    }
    h.backend.adapter.updateVisibleOutlets(['left']);
    await tester.pumpAndSettle();
    final outcome = await CCRouter.navigator.maybePopOutcome();
    await tester.pumpAndSettle();
    expect(outcome.removedEntryOwner, CCPopRemovedEntryOwner.managed);
    expect(
      h.backend.adapter.requests.where(
        (r) => r.placement.navigatorOutlet == 'left',
      ),
      hasLength(1),
    );
  });
  testWidgets(
    'iOS gesture checks its own pane guard rather than focused pane',
    (tester) async {
      final guard = Guard();
      final h = await mount(tester, panes: true, guard: guard);
      for (final intent in [
        const PaneIntent('left', 'L1'),
        const PaneIntent('left', 'L2'),
        const PaneIntent('right', 'R1'),
      ]) {
        ignore(CCRouter.navigator.push(intent));
        await tester.pumpAndSettle();
      }
      h.backend.adapter.updateVisibleOutlets(['left', 'right']);
      await tester.pumpAndSettle();
      guard.seen.clear();
      final left = ModalRoute.of(h.contexts['L2']!)! as PageRoute<Object?>;
      final enabled = left.popGestureEnabled;
      expect(
        enabled,
        isFalse,
        reason: 'left is guarded even while right is focused',
      );
      expect(guard.seen, everyElement('probe.left'));
    },
  );
  testWidgets('native local Back cannot bypass the non-focused pane guard', (
    tester,
  ) async {
    final guard = Guard();
    final h = await mount(tester, panes: true, guard: guard);
    for (final intent in [
      const PaneIntent('left', 'L1'),
      const PaneIntent('left', 'L2'),
      const PaneIntent('right', 'R1'),
    ]) {
      ignore(CCRouter.navigator.push(intent));
      await tester.pumpAndSettle();
    }
    h.backend.adapter.updateVisibleOutlets(['left', 'right']);
    await tester.pumpAndSettle();
    guard.seen.clear();
    final appBar = find.ancestor(
      of: find.text('title-L2'),
      matching: find.byType(AppBar),
    );
    tester
        .widget<IconButton>(
          find.descendant(of: appBar, matching: find.byType(IconButton)),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    final errors = <Object>[];
    Object? error;
    while ((error = tester.takeException()) != null) {
      errors.add(error!);
    }
    expect(
      h.backend.adapter.requests.where(
        (r) => r.placement.navigatorOutlet == 'left',
      ),
      hasLength(2),
      reason: 'left_locked must preserve its exact page',
    );
  });
  for (final followup in [
    'pop',
    'push',
    'replace',
    'go',
    'reset',
    'close',
    'popup',
  ]) {
    testWidgets('business Pop interrupted by $followup stays consistent', (
      tester,
    ) async {
      final h = await mount(tester);
      final a = CCRouter.navigator.push<String>(const Intent('A'));
      ignore(a);
      await tester.pumpAndSettle();
      final aHandle = CCRouter.routeEntryHandleOf(h.contexts['A']!)!;
      final b = CCRouter.navigator.push<String>(const Intent('B'));
      ignore(b);
      await tester.pumpAndSettle();
      final bResource = h.resources['B']!;
      CCRouter.navigator.pop(result: 'B-done');
      switch (followup) {
        case 'pop':
          CCRouter.navigator.pop(result: 'A-done');
        case 'push':
          ignore(CCRouter.navigator.push<String>(const Intent('C')));
        case 'replace':
          ignore(CCRouter.navigator.replace<String>(const Intent('C')));
        case 'go':
          await CCRouter.navigator.go(const Intent('C'));
        case 'reset':
          await CCRouter.navigator.reset(const Intent('C'));
        case 'close':
          await CCRouter.navigator.close(aHandle, result: 'A-done');
        case 'popup':
          unawaited(
            showDialog<void>(
              context: h.contexts['A']!,
              builder: (_) => const AlertDialog(content: Text('probe-popup')),
            ),
          );
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.takeException(), isNull);
      expect(bResource.disposals, 0);
      expect(await b, 'B-done');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(bResource.disposals, 1);
      expect(
        h.backend.adapter.requests.map((r) => r.navigationId),
        CCRouter.activeRouteEntries.map((r) => r.navigationId),
      );
    });
  }
  for (final action in [
    'business',
    'direct',
    'system',
    'gesture',
    'go',
    'reset',
    'replace',
  ]) {
    testWidgets('Scope remains live through $action outgoing animation', (
      tester,
    ) async {
      final h = await mount(tester);
      final result = CCRouter.navigator.push<String>(const Intent('A'));
      ignore(result);
      await tester.pumpAndSettle();
      final resource = h.resources['A']!;
      final route = ModalRoute.of(h.contexts['A']!)!;
      switch (action) {
        case 'business':
          CCRouter.navigator.pop(result: 'done');
        case 'direct':
          Navigator.of(h.contexts['A']!).pop('done');
        case 'system':
          await tester.binding.handlePopRoute();
        case 'gesture':
          await tester.flingFrom(
            const Offset(1, 300),
            const Offset(500, 0),
            1000,
          );
        case 'go':
          await CCRouter.navigator.go(const Intent('B'));
        case 'reset':
          await CCRouter.navigator.reset(const Intent('B'));
        case 'replace':
          ignore(CCRouter.navigator.replace<String>(const Intent('B')));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(
        tester.takeException(),
        isNull,
        reason: 'outgoing rebuild must still resolve its Route Scope',
      );
      if (route.animation!.value > 0) expect(resource.disposals, 0);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(resource.disposals, 1);
    });
  }
}
