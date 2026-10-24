import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Args {
  _Args(this.path, {this.extra});
  final Map<String, String> path;
  final Object? extra;
}

final class _Codec implements CCRouteCodec<_Args> {
  const _Codec({this.requiresExtra = false, this.pathKeys = const []});
  final bool requiresExtra;
  final List<String> pathKeys;
  @override
  _Args decode(CCRouteCodecValues input) {
    if (requiresExtra && input.extra == null) {
      throw const CCRouteParameterError('Parent requires process-local Extra.');
    }
    return _Args({
      for (final key in pathKeys)
        if (input.path.containsKey(key)) key: input.path[key]!,
    }, extra: input.extra);
  }

  @override
  CCRouteCodecValues encode(_Args arguments) =>
      CCRouteCodecValues(path: arguments.path, extra: arguments.extra);
}

final class _Intent implements CCRouteIntent<String> {
  _Intent(this.routeId, {Map<String, String> path = const {}})
    : arguments = _Args(path);
  @override
  final String routeId;
  @override
  final _Args arguments;
}

List<CCRouteDefinition<_Args, String>> _definitions() => [
  for (final record in [
    (id: 'tree.root', path: '/', parent: null),
    (id: 'tree.group', path: '/group/:group', parent: null),
    (id: 'tree.parent', path: '/group/:group/parent/:id', parent: 'tree.group'),
    (
      id: 'tree.child',
      path: '/group/:group/parent/:id/child/:item',
      parent: 'tree.parent',
    ),
    (id: 'tree.extra', path: '/editor/:id', parent: null),
    (id: 'tree.editor', path: '/editor/:id/child', parent: 'tree.extra'),
    (id: 'tree.missing', path: '/missing', parent: 'tree.parent'),
  ])
    CCRouteDefinition(
      routeId: record.id,
      patterns: [CCPathPattern(record.path, primary: true)],
      codec: _Codec(
        requiresExtra: record.id == 'tree.extra',
        pathKeys: [
          for (final segment in record.path.split('/'))
            if (segment.startsWith(':')) segment.substring(1),
        ],
      ),
      deepLink: record.id == 'tree.child'
          ? CCDeepLinkPolicy.enabled
          : CCDeepLinkPolicy.disabled,
      placement: CCRoutePlacement(parentRouteId: record.parent),
    ),
];

final class _Resource implements CCDisposable {
  int disposed = 0;
  @override
  void dispose() => disposed++;
}

final class _Registrar implements CCComponentRegistrar {
  @override
  void register(CCRegistry registry) {
    for (final route in _definitions()) {
      registry.registerRoute(route);
    }
    registry.registerService<_Resource>(
      CCServiceProvider(
        scope: CCServiceScope.route,
        factory: (_) => _Resource(),
      ),
    );
  }
}

final class _Interceptor implements CCNavigationInterceptor {
  _Interceptor(this.callback);
  final FutureOr<CCNavigationInterceptorDecision> Function(
    CCNavigationInterceptorContext,
  )
  callback;
  @override
  FutureOr<CCNavigationInterceptorDecision> intercept(
    CCNavigationInterceptorContext context,
  ) => callback(context);
}

final class _DenyPop implements CCPopGuard {
  @override
  CCPopGuardDecision evaluate(CCPopGuardContext context) =>
      const CCPopDeny(code: 'parent_locked');
}

Future<
  ({
    CCManagedRouterBackend backend,
    Map<String, _Resource> resources,
    CCManagedMultiHostBackend? multiHost,
  })
>
_mount(
  WidgetTester tester, {
  _Interceptor? interceptor,
  bool allowLinks = false,
  bool overridePlatform = false,
  bool renderRouter = true,
  bool multipleHosts = false,
  bool denyPop = false,
}) async {
  final resources = <String, _Resource>{};
  final catalog = CCFlutterRouteCatalog(
    [
      for (final route in _definitions())
        CCFlutterRouteDestination.fromDefinition(
          definition: route,
          builder: (_) => Builder(
            builder: (context) {
              resources[route.routeId] = CCRouter.routeService<_Resource>(
                context,
              );
              return Material(child: Text(route.routeId));
            },
          ),
        ),
    ],
    componentVersions: const {'tree': '1.0.0'},
  );
  CCRouterHost.initialize(
    hostAssembly: CCHostAssembly.fromComponents(
      components: [
        CCComponentManifest(
          id: 'tree',
          version: '1.0.0',
          registrar: _Registrar(),
        ),
      ],
      routeCatalog: catalog,
    ),
    deepLinkIngressPolicy: CCDeepLinkIngressPolicy(
      allowRelativePaths: allowLinks,
    ),
    globalPopGuards: [
      if (denyPop) CCGlobalPopGuard(id: 'tree.guard', guard: _DenyPop()),
    ],
    globalInterceptors: [
      if (interceptor != null)
        CCGlobalNavigationInterceptor(
          id: 'tree.policy',
          interceptor: interceptor,
        ),
    ],
  );
  CCManagedRouterBackend createBackend(CCFlutterRouteCatalog resolved) =>
      CCManagedRouterBackend(
        overridePlatformDefaultLocation: overridePlatform,
        routeCatalog: resolved,
      );
  late final CCManagedRouterBackend backend;
  final aggregate = multipleHosts
      ? CCManagedMultiHostBackend.managed(
          defaultHostId: 'default',
          hostFactories: {
            'default': (config) => backend = createBackend(config.catalog),
            'secondary': (config) => CCManagedRouterBackend(
              routeCatalog: config.catalog,
              host: CCNavigationHost(id: config.hostId),
              initializeFromRouteInformation: false,
            ),
          },
        )
      : null;
  if (!multipleHosts) backend = createBackend(catalog);
  await tester.pumpWidget(
    CCRouterApp.managed(
      backend: aggregate ?? backend,
      child: renderRouter
          ? MaterialApp.router(routerConfig: backend.routerConfig)
          : const SizedBox.shrink(),
    ),
  );
  await tester.pumpAndSettle();
  return (backend: backend, resources: resources, multiHost: aggregate);
}

_Intent _child() =>
    _Intent('tree.child', path: {'group': 'a/b', 'id': '42', 'item': '7'});

void main() {
  tearDown(CCRouterHost.shutdown);

  testWidgets(
    'canonical parent plan owns independent Scopes and exact identities',
    (tester) async {
      final harness = await _mount(tester);
      await CCRouter.navigator.go(_child());
      await tester.pumpAndSettle();
      expect(CCRouter.activeRouteEntries.map((e) => e.routeId), [
        'tree.group',
        'tree.parent',
        'tree.child',
      ]);
      expect(harness.backend.adapter.requests.map((r) => r.uri.pathSegments), [
        ['group', 'a/b'],
        ['group', 'a/b', 'parent', '42'],
        ['group', 'a/b', 'parent', '42', 'child', '7'],
      ]);
      expect(
        harness.backend.adapter.requests.every((r) => r.parentStack.isEmpty),
        isTrue,
      );
      final leaf = CCRouter.activeRouteEntries.last.routeEntryId;
      // Reveal and construct the parent's Route Service before covering it again.
      await CCRouter.navigator.maybePop();
      await tester.pumpAndSettle();
      final parentResource = harness.resources['tree.parent']!;
      final parent = CCRouter.routeEntryHandleOf(
        tester.element(find.text('tree.parent')),
      )!;
      final result = CCRouter.navigator.push(_child());
      String? returnedResult;
      unawaited(
        result.then<void>(
          (value) => returnedResult = value,
          onError: (Object error) {},
        ),
      );
      await tester.pumpAndSettle();
      final coveredLeaf = CCRouter.activeRouteEntries.last.routeEntryId;
      expect(coveredLeaf, isNot(same(leaf)));
      expect(
        (await CCRouter.navigator.close(parent)).status,
        CCRouteCloseStatus.closed,
      );
      await tester.pumpAndSettle();
      expect(parentResource.disposed, 1);
      expect(CCRouter.activeRouteEntries.last.routeEntryId, same(coveredLeaf));
      expect(find.text('tree.child'), findsOneWidget);
      CCRouter.navigator.pop(result: 'done');
      await tester.pumpAndSettle();
      expect(returnedResult, 'done');
      expect(find.text('tree.group'), findsOneWidget);
    },
  );

  for (final routeId in ['tree.missing', 'tree.editor']) {
    testWidgets('unreconstructible $routeId leaves the existing stack intact', (
      tester,
    ) async {
      final harness = await _mount(tester);
      final before = CCRouter.activeRouteEntries.single.routeEntryId;
      await expectLater(
        CCRouter.navigator.go(_Intent(routeId, path: {'id': '42'})),
        throwsA(isA<CCRouteParameterError>()),
      );
      await tester.pumpAndSettle();
      expect(CCRouter.activeRouteEntries.single.routeEntryId, same(before));
      expect(harness.backend.adapter.requests.single.routeId, 'tree.root');
      expect(harness.resources['tree.root']!.disposed, 0);
    });
  }

  testWidgets(
    'ancestor policy cancels atomically before leaf policy or allocation',
    (tester) async {
      final seen = <String>[];
      final harness = await _mount(
        tester,
        interceptor: _Interceptor((context) {
          seen.add(context.request.routeId);
          return context.request.routeId == 'tree.parent'
              ? const CCNavigationCancel(code: 'parent_denied')
              : const CCNavigationProceed();
        }),
      );
      seen.clear();
      final before = CCRouter.activeRouteEntries.single.routeEntryId;
      await expectLater(
        CCRouter.navigator.reset(_child()),
        throwsA(isA<CCRouteCancelledError>()),
      );
      expect(seen, ['tree.group', 'tree.parent']);
      expect(CCRouter.activeRouteEntries.single.routeEntryId, same(before));
      expect(harness.backend.adapter.requests.single.routeId, 'tree.root');
    },
  );

  testWidgets(
    'browser route information rebuilds the complete parent hierarchy',
    (tester) async {
      final harness = await _mount(tester, allowLinks: true);
      await harness.backend.routerConfig.routerDelegate.setNewRoutePath(
        CCManagedRouteConfiguration(
          uri: Uri.parse('/group/a/parent/42/child/7'),
          trustedHistory: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(CCRouter.activeRouteEntries.map((e) => e.routeId), [
        'tree.group',
        'tree.parent',
        'tree.child',
      ]);
      await CCRouter.navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('tree.parent'), findsOneWidget);
      expect(
        harness
            .backend
            .routerConfig
            .routerDelegate
            .currentConfiguration!
            .uri
            .path,
        '/group/a/parent/42',
      );
    },
  );

  testWidgets(
    'MultiHost reconstructs only the selected child and preserves its sibling',
    (tester) async {
      final harness = await _mount(tester, multipleHosts: true);
      final primary = CCRouter.activeRouteEntries.single.routeEntryId;
      harness.multiHost!.adapter.activateHost('secondary');
      await CCRouter.navigator.go(_child());
      await tester.pumpAndSettle();
      expect(harness.backend.adapter.requests.single.routeId, 'tree.root');
      expect(
        harness.multiHost!
            .backendFor('secondary')
            .adapter
            .requests
            .map((r) => r.routeId),
        ['tree.group', 'tree.parent', 'tree.child'],
      );
      expect(CCRouter.activeRouteEntries.first.routeEntryId, same(primary));
      expect(
        CCRouter.activeRouteEntries
            .skip(1)
            .every((e) => e.hostId == 'secondary'),
        isTrue,
      );
      expect(harness.resources['tree.root']!.disposed, 0);
    },
  );

  testWidgets('scoped foreign ownership is independent of the active Host', (
    tester,
  ) async {
    final harness = await _mount(tester, multipleHosts: true, denyPop: true);
    await CCRouter.navigator.go(_child());
    await tester.pumpAndSettle();
    final context = tester.element(find.text('tree.child'));
    final handle = CCRouter.routeEntryHandleOf(context);
    final popup = showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('foreign-primary-popup')),
    );
    await tester.pumpAndSettle();
    harness.multiHost!.adapter.activateHost('secondary');
    final outcome = await CCRouter.navigator.maybePopOutcome(context: context);
    await tester.pumpAndSettle();
    expect(outcome.removedEntryOwner, CCPopRemovedEntryOwner.foreign);
    expect(outcome.hostId, 'default');
    expect(outcome.guardDeniedCode, isNull);
    await popup;
    expect(CCRouter.routeEntryHandleOf(context), same(handle));
    expect(
      (await CCRouter.navigator.maybePopOutcome(
        context: context,
      )).guardDeniedCode,
      'parent_locked',
    );
    expect(harness.multiHost!.adapter.activeHostId, 'secondary');
    expect(
      harness.multiHost!.backendFor('secondary').adapter.requests,
      isEmpty,
    );
  });

  testWidgets(
    'ancestor redirect discards the old plan and resolves a new target',
    (tester) async {
      await _mount(
        tester,
        interceptor: _Interceptor(
          (context) => context.request.routeId == 'tree.parent'
              ? CCNavigationRedirect.toIntent(_Intent('tree.root'))
              : const CCNavigationProceed(),
        ),
      );
      await CCRouter.navigator.go(_child());
      await tester.pumpAndSettle();
      expect(CCRouter.activeRouteEntries.map((e) => e.routeId), ['tree.root']);
      expect(find.text('tree.child'), findsNothing);
    },
  );

  testWidgets(
    'deferred ancestor resumes the leaf with one freshly validated chain',
    (tester) async {
      var deferred = true;
      await _mount(
        tester,
        interceptor: _Interceptor(
          (context) => deferred && context.request.routeId == 'tree.parent'
              ? const CCNavigationDefer(code: 'parent_wait')
              : const CCNavigationProceed(),
        ),
      );
      final pending = CCRouter.navigator.go(_child());
      await tester.pumpAndSettle();
      expect(CCRouter.activeRouteEntries.single.routeId, 'tree.root');
      expect(CCRouter.pendingNavigations.single.routeId, 'tree.child');
      deferred = false;
      await CCRouter.resumePendingNavigation(
        CCRouter.pendingNavigations.single.navigationId,
      );
      await pending;
      await tester.pumpAndSettle();
      expect(CCRouter.activeRouteEntries.map((e) => e.routeId), [
        'tree.group',
        'tree.parent',
        'tree.child',
      ]);
      expect(CCRouter.pendingNavigations, isEmpty);
    },
  );

  testWidgets(
    'shutdown fences a late ancestor policy before Backend mutation',
    (tester) async {
      final decision = Completer<CCNavigationInterceptorDecision>();
      final entered = Completer<void>();
      final harness = await _mount(
        tester,
        interceptor: _Interceptor((context) {
          if (context.request.routeId != 'tree.parent')
            return const CCNavigationProceed();
          entered.complete();
          return decision.future;
        }),
      );
      final pending = CCRouter.navigator.go(_child());
      final cancelled = expectLater(
        pending,
        throwsA(isA<CCRouteCancelledError>()),
      );
      await tester.pumpAndSettle();
      expect(entered.isCompleted, isTrue);
      await CCRouterHost.shutdown();
      await cancelled;
      decision.complete(const CCNavigationProceed());
      await tester.pumpAndSettle();
      expect(harness.backend.adapter.requests, isEmpty);
      expect(harness.resources['tree.root']!.disposed, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('platform startup stays external across ancestor interception', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/group/a/parent/42/child/7';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final seen = <CCNavigationOrigin>[];
    await _mount(
      tester,
      allowLinks: true,
      interceptor: _Interceptor((context) {
        seen.add(context.request.origin);
        return const CCNavigationProceed();
      }),
    );
    expect(find.text('tree.child'), findsOneWidget);
    expect(seen, List.filled(3, CCNavigationOrigin.externalPlatform));
    expect(
      CCRouter.activeRouteEntries.every(
        (e) => e.origin == CCNavigationOrigin.externalPlatform,
      ),
      isTrue,
    );
  });

  testWidgets('Host can explicitly override a non-root platform startup URI', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/group/a/parent/42/child/7';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    await _mount(tester, overridePlatform: true);
    expect(find.text('tree.root'), findsOneWidget);
    expect(
      CCRouter.activeRouteEntries.single.origin,
      CCNavigationOrigin.internal,
    );
  });

  testWidgets(
    'default platform startup cannot bypass the Host ingress deny policy',
    (tester) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue =
          '/group/a/parent/42/child/7';
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      final harness = await _mount(tester, renderRouter: false);
      await expectLater(
        harness.backend.routerConfig.routerDelegate.setInitialRoutePath(
          CCManagedRouteConfiguration(
            uri: Uri.parse('/group/a/parent/42/child/7'),
            trustedHistory: false,
          ),
        ),
        throwsA(isA<CCDeepLinkIngressRejectedError>()),
      );
      expect(CCRouter.activeRouteEntries, isEmpty);
      expect(find.text('tree.child'), findsNothing);
    },
  );
}
