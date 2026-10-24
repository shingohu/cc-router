import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'support/managed_test_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _OrderArguments {
  const _OrderArguments(this.id);

  final String id;
}

final class _OrderCodec implements CCRouteCodec<_OrderArguments> {
  const _OrderCodec();

  @override
  _OrderArguments decode(CCRouteCodecValues input) =>
      _OrderArguments(input.path['id']!);

  @override
  CCRouteCodecValues encode(_OrderArguments arguments) =>
      CCRouteCodecValues(path: {'id': arguments.id});
}

final class _OrderIntent<R> implements CCRouteIntent<R> {
  const _OrderIntent(this.arguments);

  @override
  String get routeId => 'orders.detail';

  @override
  final _OrderArguments arguments;
}

final class _SimpleOrdersRegistrar implements CCComponentRegistrar {
  const _SimpleOrdersRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerRoute<_OrderArguments, String>(
      CCRouteDefinition<_OrderArguments, String>(
        routeId: 'orders.detail',
        patterns: [const CCPathPattern('/orders/:id', primary: true)],
        codec: const _OrderCodec(),
      ),
    );
  }
}

final class _GuardedOrdersRegistrar implements CCComponentRegistrar {
  _GuardedOrdersRegistrar(this.allowPop, this.triggers);

  final ValueNotifier<bool> allowPop;
  final List<CCPopTrigger> triggers;

  @override
  void register(CCRegistry registry) {
    registry.registerRoutePopGuard(
      'orders.system-back',
      _SystemBackPopGuard(allowPop, triggers),
    );
    registry.registerRoute<_OrderArguments, String>(
      CCRouteDefinition<_OrderArguments, String>(
        routeId: 'orders.detail',
        patterns: [const CCPathPattern('/orders/:id', primary: true)],
        codec: const _OrderCodec(),
        popGuardIds: const ['orders.system-back'],
      ),
    );
  }
}

final class _SystemBackPopGuard implements CCPopGuard {
  _SystemBackPopGuard(this.allowPop, this.triggers);

  final ValueNotifier<bool> allowPop;
  final List<CCPopTrigger> triggers;

  @override
  CCPopGuardDecision evaluate(CCPopGuardContext context) {
    triggers.add(context.trigger);
    return allowPop.value
        ? const CCPopAllow()
        : const CCPopDeny(code: 'unsaved_changes');
  }
}

final class _OrdersRegistrar implements CCComponentRegistrar {
  const _OrdersRegistrar();

  @override
  void register(CCRegistry registry) {
    registry.registerShell(
      CCShellDefinition(
        shellId: 'tabs',
        type: CCShellType.statefulBranches,
        outlets: const ['home', 'settings'],
        initialOutlet: 'home',
      ),
    );
    registry.registerRoute<_OrderArguments, void>(
      CCRouteDefinition<_OrderArguments, void>(
        routeId: 'orders.detail',
        patterns: [
          const CCPathPattern('/settings/orders/:id', primary: true),
          const CCUriPattern('https://example.com/settings/orders/:id'),
        ],
        codec: const _OrderCodec(),
        deepLink: CCDeepLinkPolicy.enabled,
        placement: const CCRoutePlacement(
          shellId: 'tabs',
          navigatorOutlet: 'settings',
        ),
      ),
    );
  }
}

CCRouteDefinition<_OrderArguments, String> _simpleDefinition() =>
    CCRouteDefinition(
      routeId: 'orders.detail',
      patterns: [const CCPathPattern('/orders/:id', primary: true)],
      codec: const _OrderCodec(),
    );

Iterable<CCRouteEntrySnapshot> get _orders => CCRouter.activeRouteEntries.where(
  (entry) => entry.routeId == 'orders.detail',
);

Future<CCManagedRouterBackend> _mountOrders(
  WidgetTester tester, {
  required Widget Function(CCRouteCodecValues) builder,
  CCComponentRegistrar registrar = const _SimpleOrdersRegistrar(),
  CCNavigationHost? host,
}) async {
  CCRouterHost.initialize(
    hostAssembly: CCHostAssembly.fromComponents(
      components: [
        CCComponentManifest(
          id: 'orders',
          version: '1.0.0',
          registrar: WithTestHome(registrar),
        ),
      ],
    ),
  );
  final backend = CCManagedRouterBackend(
    host: host,
    routeCatalog: CCFlutterRouteCatalog(
      [
        testHomeDestination(),
        CCFlutterRouteDestination.fromDefinition(
          definition: _simpleDefinition(),
          builder: builder,
        ),
      ],
      componentVersions: const {'orders': '1.0.0'},
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

void main() {
  tearDown(CCRouterHost.shutdown);

  testWidgets(
    'foreign routes and local history never remove a managed Route Entry',
    (tester) async {
      final host = CCNavigationHost(id: 'window.main');
      final scaffoldKey = GlobalKey<ScaffoldState>();
      await _mountOrders(
        tester,
        host: host,
        builder: (values) => Scaffold(
          key: scaffoldKey,
          body: Text(
            'order:${values.path['id']}',
            key: const ValueKey('managed-order'),
          ),
        ),
      );

      final managedResult = CCRouter.navigator.push<String>(
        const _OrderIntent<String>(_OrderArguments('42')),
      );
      await tester.pumpAndSettle();
      final managedEntryId = _orders.single.routeEntryId;
      final managedBackendEntries = CCRouter.activeBackendEntries.where(
        (entry) => entry.owner == CCBackendEntryOwner.managed,
      );
      expect(managedBackendEntries, isNotEmpty);
      expect(
        managedBackendEntries.every((entry) => entry.hostId == host.id),
        isTrue,
      );
      final managedPushEvent = CCRouter.recentBackendNavigationEvents.lastWhere(
        (event) => event.routeId == 'orders.detail',
      );
      expect(managedPushEvent.hostId, host.id);
      expect(managedPushEvent.placement.hostId, host.id);
      final managedContext = tester.element(
        find.byKey(const ValueKey('managed-order')),
      );

      void expectManagedEntryAlive({
        CCRouteEntryLifecycleState state = CCRouteEntryLifecycleState.visible,
      }) {
        expect(_orders, hasLength(1));
        expect(_orders.single.routeEntryId, managedEntryId);
        expect(_orders.single.lifecycleState, state);
      }

      final dialog = showDialog<void>(
        context: managedContext,
        builder: (context) => AlertDialog(
          key: const ValueKey('foreign-dialog'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('close-dialog'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expectManagedEntryAlive(state: CCRouteEntryLifecycleState.hidden);
      await tester.tap(find.text('close-dialog'));
      await tester.pumpAndSettle();
      await dialog;
      expectManagedEntryAlive();

      final modal = showModalBottomSheet<void>(
        context: managedContext,
        builder: (context) => TextButton(
          key: const ValueKey('foreign-modal'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('close-modal'),
        ),
      );
      await tester.pumpAndSettle();
      expectManagedEntryAlive(state: CCRouteEntryLifecycleState.hidden);
      await tester.tap(find.text('close-modal'));
      await tester.pumpAndSettle();
      await modal;
      expectManagedEntryAlive();

      final bottomSheet = scaffoldKey.currentState!.showBottomSheet(
        (_) =>
            const SizedBox(key: ValueKey('foreign-local-history'), height: 80),
      );
      await tester.pumpAndSettle();
      expectManagedEntryAlive();
      final localHistoryPop = await CCRouter.navigator.maybePopOutcome();
      expect(localHistoryPop.handled, isTrue);
      expect(localHistoryPop.removedEntryOwner, CCPopRemovedEntryOwner.none);
      await tester.pumpAndSettle();
      await bottomSheet.closed;
      expect(find.byKey(const ValueKey('foreign-local-history')), findsNothing);
      expectManagedEntryAlive();

      final foreignRoute = Navigator.of(managedContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Text('foreign-page', key: ValueKey('foreign-page')),
        ),
      );
      await tester.pumpAndSettle();
      expectManagedEntryAlive(state: CCRouteEntryLifecycleState.hidden);
      Navigator.of(
        tester.element(find.byKey(const ValueKey('foreign-page'))),
      ).pop();
      await tester.pumpAndSettle();
      await foreignRoute;
      expectManagedEntryAlive();

      final secondForeignRoute = Navigator.of(managedContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Text('foreign-page-2', key: ValueKey('foreign-page-2')),
        ),
      );
      await tester.pumpAndSettle();
      expectManagedEntryAlive(state: CCRouteEntryLifecycleState.hidden);
      CCRouter.navigator.pop();
      await tester.pumpAndSettle();
      await secondForeignRoute;
      expectManagedEntryAlive();

      Navigator.of(managedContext).pop<String>('managed-result');
      await tester.pumpAndSettle();
      expect(await managedResult, 'managed-result');
      expect(_orders, isEmpty);
      expect(
        CCRouter.recentBackendNavigationEvents.where(
          (event) => event.routeId == null,
        ),
        isNotEmpty,
      );
    },
  );

  testWidgets(
    'a rejected Pop keeps the managed Route Entry and pending result alive',
    (tester) async {
      final allowPop = ValueNotifier(false);
      addTearDown(allowPop.dispose);
      await _mountOrders(
        tester,
        builder: (values) => ValueListenableBuilder<bool>(
          valueListenable: allowPop,
          builder: (_, canPop, _) => PopScope<String>(
            canPop: canPop,
            child: Text(
              'order:${values.path['id']}',
              key: const ValueKey('guarded-order'),
            ),
          ),
        ),
      );

      final managedResult = CCRouter.navigator.push<String>(
        const _OrderIntent<String>(_OrderArguments('guarded')),
      );
      await tester.pumpAndSettle();
      final managedEntryId = _orders.single.routeEntryId;
      expect(find.byKey(const ValueKey('guarded-order')), findsOneWidget);

      final declined = await CCRouter.navigator.maybePopOutcome<String>(
        result: 'rejected',
      );
      // PopScope consumes the request even though it refuses to remove the
      // route. Ownership and result availability carry the rejection detail.
      expect(declined.handled, isTrue);
      expect(declined.removedEntryOwner, CCPopRemovedEntryOwner.none);
      expect(_orders, hasLength(1));
      expect(_orders.single.routeEntryId, managedEntryId);
      expect(_orders.single.lifecycleState, CCRouteEntryLifecycleState.visible);
      expect(find.byKey(const ValueKey('guarded-order')), findsOneWidget);

      allowPop.value = true;
      await tester.pump();
      final accepted = await CCRouter.navigator.maybePopOutcome<String>(
        result: 'accepted',
      );
      await tester.pumpAndSettle();
      expect(accepted.handled, isTrue);
      expect(accepted.removedEntryOwner, CCPopRemovedEntryOwner.managed);
      expect(accepted.removedEntryOwner, CCPopRemovedEntryOwner.managed);
      expect(await managedResult, 'accepted');
      expect(_orders, isEmpty);
    },
  );

  testWidgets('an external system Pop closes a managed go route entry', (
    tester,
  ) async {
    await _mountOrders(
      tester,
      builder: (values) => Text(
        'order:${values.path['id']}',
        key: const ValueKey('go-managed-order'),
      ),
    );
    await CCRouter.navigator.go(
      const _OrderIntent<void>(_OrderArguments('42')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('go-managed-order')), findsOneWidget);
    expect(_orders, hasLength(1));

    final context = tester.element(
      find.byKey(const ValueKey('go-managed-order')),
    );
    Navigator.of(context).pop<void>();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('go-managed-order')), findsNothing);
    expect(_orders, isEmpty);
  });

  testWidgets(
    'Managed system back evaluates the Runtime PopGuard before removal',
    (tester) async {
      final allowPop = ValueNotifier(false);
      final triggers = <CCPopTrigger>[];
      addTearDown(allowPop.dispose);
      final backend = await _mountOrders(
        tester,
        registrar: _GuardedOrdersRegistrar(allowPop, triggers),
        builder: (values) => Text(
          'order:${values.path['id']}',
          key: const ValueKey('system-guarded-order'),
        ),
      );

      final result = CCRouter.navigator.push<String>(
        const _OrderIntent<String>(_OrderArguments('system-guard')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('system-guarded-order')),
        findsOneWidget,
      );

      final denied = await backend.routerConfig.routerDelegate.popRoute();
      await tester.pumpAndSettle();
      expect(denied, isTrue);
      expect(triggers, [CCPopTrigger.system]);
      expect(_orders, hasLength(1));
      expect(
        find.byKey(const ValueKey('system-guarded-order')),
        findsOneWidget,
      );

      allowPop.value = true;
      final accepted = await backend.routerConfig.routerDelegate.popRoute();
      await tester.pumpAndSettle();
      expect(accepted, isTrue);
      expect(triggers, [CCPopTrigger.system, CCPopTrigger.system]);
      expect(await result, isNull);
      expect(_orders, isEmpty);
    },
  );

  for (final useForm in [false, true]) {
    testWidgets(
      'system PopGuard allow preserves local ${useForm ? 'Form' : 'PopScope'} refusal and result',
      (tester) async {
        final allowFrameworkPop = ValueNotifier(true);
        final allowLocalPop = ValueNotifier(false);
        final triggers = <CCPopTrigger>[];
        final localResults = <bool>[];
        addTearDown(allowFrameworkPop.dispose);
        addTearDown(allowLocalPop.dispose);
        final backend = await _mountOrders(
          tester,
          registrar: _GuardedOrdersRegistrar(allowFrameworkPop, triggers),
          builder: (_) => ValueListenableBuilder<bool>(
            valueListenable: allowLocalPop,
            builder: (_, canPop, _) {
              const child = Text('unsaved editor');
              return useForm
                  ? Form(
                      canPop: canPop,
                      onPopInvokedWithResult: (didPop, _) =>
                          localResults.add(didPop),
                      child: child,
                    )
                  : PopScope<Object?>(
                      canPop: canPop,
                      onPopInvokedWithResult: (didPop, _) =>
                          localResults.add(didPop),
                      child: child,
                    );
            },
          ),
        );
        var resultCompleted = false;
        final result = CCRouter.navigator
            .push<String>(
              const _OrderIntent<String>(_OrderArguments('unsaved')),
            )
            .then((value) {
              resultCompleted = true;
              return value;
            });
        await tester.pumpAndSettle();
        final entryId = _orders.single.routeEntryId;

        expect(await backend.routerConfig.routerDelegate.popRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('unsaved editor'), findsOneWidget);
        expect(_orders.single.routeEntryId, entryId);
        expect(resultCompleted, isFalse);
        expect(triggers, [CCPopTrigger.system]);
        expect(localResults, [false]);

        allowLocalPop.value = true;
        await tester.pump();
        final navigator = Navigator.of(
          tester.element(find.text('unsaved editor')),
        );
        expect(await navigator.maybePop<String>('saved'), isTrue);
        await tester.pumpAndSettle();
        expect(await result, 'saved');
        expect(_orders, isEmpty);
        expect(triggers, [CCPopTrigger.system, CCPopTrigger.system]);
        expect(localResults.where((didPop) => didPop), hasLength(1));
      },
    );
  }

  testWidgets(
    'dynamic open pushes on Managed and completes before its later Pop',
    (tester) async {
      await _mountOrders(
        tester,
        builder: (values) => Text(
          'open-order:${values.path['id']}',
          key: const ValueKey('open-managed-order'),
        ),
      );

      expect(CCRouter.activeBackendEntries, hasLength(1));

      await CCRouter.navigator.open(Uri.parse('/orders/42'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('open-managed-order')), findsOneWidget);
      expect(CCRouter.navigator.canPop(), isTrue);
      expect(_orders, hasLength(1));
      expect(_orders.single.lifecycleState, CCRouteEntryLifecycleState.visible);

      CCRouter.navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(_orders, isEmpty);
    },
  );

  testWidgets('replace recreates the same route with updated parameters', (
    tester,
  ) async {
    await _mountOrders(
      tester,
      builder: (values) => Text(
        'replace-order:${values.path['id']}',
        key: ValueKey('replace-order-${values.path['id']}'),
      ),
    );

    final firstResult = CCRouter.navigator.push<String>(
      const _OrderIntent<String>(_OrderArguments('1')),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('replace-order-1')), findsOneWidget);

    final replacementResult = CCRouter.navigator.replace<String>(
      const _OrderIntent<String>(_OrderArguments('2')),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const ValueKey('replace-order-1')), findsNothing);
    expect(find.byKey(const ValueKey('replace-order-2')), findsOneWidget);
    expect(_orders, hasLength(1));
    expect(_orders.single.address.routePattern, '/orders/:id');

    CCRouter.navigator.pop(result: 'done');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(await firstResult.timeout(const Duration(seconds: 2)), isNull);
    expect(await replacementResult.timeout(const Duration(seconds: 2)), 'done');
    expect(_orders, isEmpty);
  });

  testWidgets('Runtime dispose terminates a pending typed Push result', (
    tester,
  ) async {
    final backend = await _mountOrders(
      tester,
      builder: (values) => Text(
        'dispose-order:${values.path['id']}',
        key: const ValueKey('dispose-order'),
      ),
    );

    final pending = CCRouter.navigator.push<String>(
      const _OrderIntent<String>(_OrderArguments('42')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dispose-order')), findsOneWidget);

    final completion = expectLater(
      pending,
      throwsA(
        isA<CCNavigationAdapterError>().having(
          (error) => error.message,
          'message',
          contains('navigation ended before'),
        ),
      ),
    );
    await tester.runAsync(
      () => CCRouterHost.shutdown().timeout(const Duration(seconds: 2)),
    );

    await tester.runAsync(() => completion.timeout(const Duration(seconds: 2)));
    expect(CCRouter.isInitialized, isFalse);
    expect(
      () => backend.adapter.canPop(),
      throwsA(isA<CCNavigationAdapterError>()),
    );
  });

  testWidgets(
    'external ingress reaches the bound StatefulShell branch with metadata',
    (tester) async {
      final homeKey = GlobalKey<NavigatorState>();
      final settingsKey = GlobalKey<NavigatorState>();
      const placement = CCRoutePlacement(
        shellId: 'tabs',
        navigatorOutlet: 'home',
      );
      final detail = CCRouteDefinition<_OrderArguments, void>(
        routeId: 'orders.detail',
        patterns: [
          const CCPathPattern('/settings/orders/:id', primary: true),
          const CCUriPattern('https://example.com/settings/orders/:id'),
        ],
        codec: const _OrderCodec(),
        deepLink: CCDeepLinkPolicy.enabled,
        placement: const CCRoutePlacement(
          shellId: 'tabs',
          navigatorOutlet: 'settings',
        ),
      );
      CCRouterHost.initialize(
        deepLinkIngressPolicy: CCDeepLinkIngressPolicy(
          allowedAuthorities: [
            CCDeepLinkAuthorityRule(scheme: 'https', host: 'example.com'),
          ],
        ),
        hostAssembly: CCHostAssembly.fromComponents(
          components: [
            CCComponentManifest(
              id: 'orders',
              version: '1.0.0',
              registrar: const WithTestHome(
                _OrdersRegistrar(),
                placement: placement,
              ),
            ),
          ],
        ),
      );
      final backend = CCManagedRouterBackend(
        host: CCNavigationHost(
          navigatorKeys: {'home': homeKey, 'settings': settingsKey},
        ),
        routeCatalog: CCFlutterRouteCatalog(
          [
            testHomeDestination(placement: placement),
            CCFlutterRouteDestination.fromDefinition(
              definition: detail,
              builder: (values) => Text(
                'order:${values.path['id']}',
                key: const ValueKey('order-detail'),
              ),
            ),
          ],
          componentVersions: const {'orders': '1.0.0'},
        ),
        shellBindings: [
          CCManagedShellBinding(
            shellId: 'tabs',
            builder: (_, shell) => IndexedStack(
              index: shell.activeOutlet == 'home' ? 0 : 1,
              children: [
                shell.navigatorFor('home'),
                shell.navigatorFor('settings'),
              ],
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        CCRouterApp.managed(
          backend: backend,
          child: MaterialApp.router(routerConfig: backend.routerConfig),
        ),
      );
      await tester.pumpAndSettle();

      const source = CCNavigationSource.deepLink('initial_location.orders');
      await CCDeepLinkIngress.fromPlatform(
        Uri.parse('https://example.com/settings/orders/42'),
        mode: CCDeepLinkOpenMode.go,
        source: source,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('order-detail')), findsOneWidget);
      expect(find.text('order:42'), findsOneWidget);
      expect(
        backend.routerConfig.routerDelegate.currentConfiguration!.uri.path,
        '/settings/orders/42',
      );
      expect(backend.adapter.requests, hasLength(2));
      expect(
        backend.adapter.requests.last.origin,
        CCNavigationOrigin.externalPlatform,
      );
      expect(backend.adapter.requests.last.source, same(source));
      expect(backend.adapter.requests.last.openMode, CCDeepLinkOpenMode.go);
      expect(backend.adapter.requests.last.routeId, 'orders.detail');
      expect(
        backend.adapter.requests.last.placement.navigatorOutlet,
        'settings',
      );
      expect(settingsKey.currentState, isNotNull);
      expect(homeKey.currentState, isNotNull);
      final backendEvents = CCRouter.recentBackendNavigationEvents;
      expect(backendEvents, isNotEmpty);
      expect(
        backendEvents.any(
          (event) =>
              event.routeId == 'orders.detail' &&
              event.origin == CCNavigationOrigin.externalPlatform &&
              event.source == source,
        ),
        isTrue,
      );
    },
  );

  testWidgets('external ingress rejects a route disabled for deep links', (
    tester,
  ) async {
    final definition = CCRouteDefinition<_OrderArguments, void>(
      routeId: 'internal',
      patterns: [const CCPathPattern('/internal/:id', primary: true)],
      codec: const _OrderCodec(),
    );
    CCRouterHost.initialize(
      deepLinkIngressPolicy: CCDeepLinkIngressPolicy(allowRelativePaths: true),
      hostAssembly: CCHostAssembly.fromComponents(
        components: [
          CCComponentManifest(
            id: 'internal',
            version: '1.0.0',
            registrar: WithTestHome(_DisabledRouteRegistrar()),
          ),
        ],
      ),
    );
    final backend = CCManagedRouterBackend(
      routeCatalog: CCFlutterRouteCatalog(
        [
          testHomeDestination(),
          CCFlutterRouteDestination.fromDefinition(
            definition: definition,
            builder: (values) => Text('internal:${values.path['id']}'),
          ),
        ],
        componentVersions: const {'internal': '1.0.0'},
      ),
    );
    await tester.pumpWidget(
      CCRouterApp.managed(
        backend: backend,
        child: MaterialApp.router(routerConfig: backend.routerConfig),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      CCDeepLinkIngress.fromNotification(
        Uri.parse('/internal/7'),
        source: const CCNavigationSource.notification('order_ready'),
      ),
      throwsA(isA<CCDeepLinkRejectedError>()),
    );
    expect(
      backend.routerConfig.routerDelegate.currentConfiguration!.uri.path,
      '/',
    );
    expect(find.text('home'), findsOneWidget);
  });
}

final class _DisabledRouteRegistrar implements CCComponentRegistrar {
  @override
  void register(CCRegistry registry) {
    registry.registerRoute<_OrderArguments, void>(
      CCRouteDefinition<_OrderArguments, void>(
        routeId: 'internal',
        patterns: [const CCPathPattern('/internal/:id', primary: true)],
        codec: const _OrderCodec(),
      ),
    );
  }
}
